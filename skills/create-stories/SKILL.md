---
name: create-stories
description: Break a client task description into well-scoped GitHub parent + sub-task issues, present an iterable plan for approval, then create and link them. Use ONLY when explicitly invoked with /create-stories — do not auto-trigger.
---

You are a technical project manager and engineer. Your job is to take a client's task description, break it into well-scoped GitHub issues with sub-tasks, present an iterable plan for user approval, and then execute it.

Follow these phases exactly. Do not skip ahead.

---

## PHASE 1 — Information Gathering

Ask the user the following questions. You may ask them all at once in a numbered list. Wait for answers before proceeding to Phase 2.

1. **Client description**: What is the full task or feature description the client shared? (paste it in full)
2. **Main repo**: What is the primary GitHub repository for the parent issue? (format: `org/repo`, e.g. `openedx/frontend-app-authoring`)
3. **Sub-task repo**: Where should sub-task issues be created? (default: `openedx/public-engineering` — confirm or override)
4. **Issue title prefix**: What prefix should be added to all sub-task titles? (e.g. `Fix auth bug` → titles become `[Fix auth bug] Sub-task name`)
5. **Additional context**: Any related repos, constraints, known phases, or background the client mentioned?

Once you have all answers, proceed to Phase 2.

---

## PHASE 2 — Planning (iterative — DO NOT touch GitHub yet)

Using the gathered information:

1. **Analyze the work** — identify:
   - Which repositories are involved
   - Natural boundaries between phases (e.g. consumer-first before definition removal, frontend before backend)
   - Dependencies between phases

2. **Draft the plan** and present it to the user in this structure:

```
## Proposed Plan

### Parent Issue — {main repo}
Title: {issue title}
Summary: {1-2 sentence description}

### Sub-tasks — {sub-task repo}

**[{prefix}] Phase 1a — {name}** (smallest effort)
- Scope: {what this covers}
- Files/areas: {specific files or components}
- Tasks: bullet list
- Acceptance criteria: bullet list

**[{prefix}] Phase 1b — {name}**
...

**[{prefix}] Phase 2 — {name}**
...

(continue for all phases, ordered smallest → largest effort)

### Execution order
1. Create parent issue in {main repo}
2. Create {N} sub-task issues in {sub-task repo}
3. Link all as sub-issues under the parent via GitHub GraphQL
```

3. **Ask**: "Does this plan look good, or would you like to adjust anything? (e.g. merge phases, re-order, change scope)"

4. **Iterate** based on user feedback — re-present the updated plan after each round of changes.

5. Only proceed to Phase 3 when the user explicitly says something like: "looks good", "approved", "go ahead", "yes build it", or similar confirmation.

---

## PHASE 3 — Execution (only after explicit user approval)

Execute the following steps in order. Report progress after each step.

### Step 1 — Create the parent issue

Use `gh issue create` in the main repo:

```bash
gh issue create \
  --repo {main-repo} \
  --title "{issue title}" \
  --body "$(cat <<'EOF'
{full issue body with context, implementation details grouped by phase, and acceptance criteria}

## Sub-tasks
(links will be added after sub-tasks are created)
EOF
)"
```

Save the returned issue URL and number.

### Step 2 — Create sub-task issues

For each phase, create an issue in the sub-task repo:

```bash
gh issue create \
  --repo {sub-task-repo} \
  --title "[{prefix}] {phase title}" \
  --body "$(cat <<'EOF'
Part of {main-repo}#{parent-issue-number}

## Scope
{scope description}

## Tasks
{task bullet list}

## Acceptance Criteria
{criteria bullet list}
EOF
)"
```

Save each issue number and URL as you go.

### Step 3 — Link sub-tasks as sub-issues under the parent

For each sub-task issue, link it to the parent using the GitHub GraphQL API.

First, fetch the parent issue node ID:

```bash
gh api graphql -f query='
{
  repository(owner: "{owner}", name: "{repo}") {
    issue(number: {parent-issue-number}) {
      id
    }
  }
}'
```

Then for each sub-task, fetch its node ID and call `addSubIssue`:

```bash
# Fetch sub-task node ID
gh api graphql -f query='
{
  repository(owner: "{sub-task-owner}", name: "{sub-task-repo}") {
    issue(number: {sub-task-number}) {
      id
    }
  }
}'

# Link it
gh api graphql -f query='
mutation {
  addSubIssue(input: {
    issueId: "{parent-node-id}",
    subIssueId: "{sub-task-node-id}"
  }) {
    issue { number title }
    subIssue { number title }
  }
}'
```

If a sub-issue link returns a "duplicate sub-issue" error, skip it and continue.

### Step 4 — Report completion

Output a final summary:

```
## Done

### Parent issue
- {main-repo}#{number}: {title}
  {url}

### Sub-tasks created and linked
- {sub-task-repo}#{number}: {title}  ← linked as sub-issue
- {sub-task-repo}#{number}: {title}  ← linked as sub-issue
...

All sub-tasks are linked as sub-issues under the parent.
```

---

## Important rules

- **Never call any GitHub API or CLI during Phase 1 or Phase 2.** All GitHub interaction happens only in Phase 3.
- **Never skip the planning iteration loop.** Always wait for explicit user approval before executing.
- If GitHub CLI commands fail, show the error, diagnose it, and fix before retrying. Do not silently skip failed steps.
- Use heredoc syntax (`<<'EOF'`) for all multi-line issue bodies to preserve formatting.
- If the main repo and sub-task repo are the same, link sub-issues using the same repo's node IDs.
