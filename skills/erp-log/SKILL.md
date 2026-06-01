---
name: erp-log
description: Generate Arbisoft ERP project log for a given week (w/weekly) or append a quick daily entry (d/daily). Weekly mode aggregates GitHub activity (openedx org only), Google Calendar meetings, Slack activity, Chrome browsing history, and GitHub project board events, combining them with accumulated daily entries and existing ERP data. Daily mode parses a task description from the user's message and appends it to the ongoing weekly log file. Logs are organized under logs/<Mon, MMM DD to Sun, MMM DD>/ directories. Use when the user asks to "fill ERP log", "generate weekly log", "log today's work", "add daily entry", or similar.
version: 3.0.0
model: haiku
allowed-tools: Bash(gh api:*), Bash(gh auth status:*), Bash(date:*), Bash(sqlite3:*), Bash(cp:*), Bash(ls:*), Bash(mkdir:*), Bash(cat:*), Write, Read, mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_channel, mcp__claude_ai_Slack__slack_read_thread, mcp__claude_ai_Slack__slack_search_channels, mcp__claude_ai_Slack__slack_search_users, mcp__claude_ai_Google_Calendar__list_calendars, mcp__claude_ai_Google_Calendar__list_events
---

# erp-log

Generate a weekly Arbisoft ERP project log, or append a quick daily entry to the ongoing log.

---

## Step 0: Parse Arguments and Route

**Syntax:**
```
/erp-log [d|daily|w|weekly] [ERP_URL] [--week YYYY-MM-DD] [free-form content]
```

Parse the first argument (case-insensitive):
- `w` or `weekly` → **Weekly Mode** — go to [Weekly Mode](#weekly-mode) section below
- `d` or `daily`, or **no mode argument given** → **Daily Mode** — go to [Daily Mode](#daily-mode) section below

**Directory naming (used in both modes):**

All files for a week live under:
```
/Users/farhan.khan/MyStuff/Development/Claude_Workspaces/project_logs/logs/<WEEK_DIR>/
```

Where `WEEK_DIR` uses format `Mon, Jun 01 to Sun, Jun 07`:
- `WEEK_START` = Monday of the target week
- `WEEK_END_SUN` = WEEK_START + 6 days (Sunday)
- `WEEK_END_FRI` = WEEK_START + 4 days (Friday)
- `WEEK_DIR` = `Mon, {MMM DD} to Sun, {MMM DD}` — e.g. `Mon, Jun 01 to Sun, Jun 07`
  - Use zero-padded day (`01`, `07`, `25`)
  - Month abbreviation: Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec

Files per directory:
- `erp_log.txt` — accumulated daily entries, refined to final log on weekly run
- `devtools_fill_log.js` — ready-to-paste DevTools submission script

---

## DAILY MODE

### Step D1: Determine Target Date and Week

Parse the user's message for a date reference:
- "yesterday" → yesterday's PKT date
- "on Monday", "last Tuesday" → resolve to the most recent such weekday
- "Jun 1", "June 1st", "2026-05-30" → parse as an absolute date
- No date mentioned → today's PKT date (UTC+5)

Compute:
- `TARGET_DATE` = resolved date (YYYY-MM-DD)
- `WEEK_START` = Monday of the week containing TARGET_DATE
- `WEEK_END_SUN` = WEEK_START + 6 days
- `WEEK_END_FRI` = WEEK_START + 4 days
- `WEEK_DIR` = formatted directory name (see Step 0)
- `LOG_DIR` = `/Users/farhan.khan/MyStuff/Development/Claude_Workspaces/project_logs/logs/<WEEK_DIR>`
- `LOG_FILE` = `<LOG_DIR>/erp_log.txt`

### Step D2: Parse the Task Content

From the user's message (the text after `d`/`daily` and any date reference), extract:

- **Description:** what was worked on — preserve the user's own wording where possible
- **Hours:** time spent — look for patterns like `2.5h`, `2 hours`, `~1.5`, `30 min`, `half an hour`
- **Tag:** infer from the description:

| Signal in description | Tag |
|---|---|
| PR, commit, coding, implemented, built, wrote code | `[Coding]` |
| reviewed, code review, PR review | `[Code Review]` |
| meeting, sync, standup, call, huddle | `[Meeting]` |
| research, investigated, explored, R&D | `[R&D]` |
| tested, QA, testing | `[Testing]` |
| watched, read docs, learning, tutorial | `[Training/Learning]` |
| deployed, deployment | `[Deployment]` |
| wrote docs, documentation | `[Documentation]` |
| debugged, debugging, fixed a bug | `[Debugging]` |

If **hours are not mentioned**, ask: "How long did this take? (e.g. 1.5h)" — do not proceed until hours are known.

If the user describes **multiple tasks** in one message, create one entry per task.

### Step D3: Write to Log File

Create the directory if it doesn't exist:
```bash
mkdir -p "<LOG_DIR>"
```

If `erp_log.txt` does not exist yet, create it with this header:
```
Week: WEEK_START .. WEEK_END_FRI
--- Accumulated daily entries ---
```

Append each entry as one line:
```
TARGET_DATE [TAG] - Description (hours)
```

Example:
```
2026-06-02 [Coding] - Worked on following PR: https://github.com/openedx/repo/pull/123 (2.5)
2026-06-02 [Meeting] - Axim Daily Syncup (0.5)
```

Hours format: bare decimal, no `h` suffix (`0.5`, `2.5`).

### Step D4: Confirm to User

Show what was added:
> "Added to `logs/<WEEK_DIR>/erp_log.txt`:"
> `2026-06-02 [Coding] - Worked on following PR: ... (2.5)`

List all entries if multiple were added.

---

## WEEKLY MODE

### Step 1: Determine Target Week and ERP Log ID

**ERP URL (required):** If the user provides a URL like `https://erp.arbisoft.com/project-logs/update/382332/`, extract the log ID from it immediately:
```
LOG_ID = last path segment of the URL (e.g. "382332")
```
**If the user did NOT provide the ERP URL**, ask for it before proceeding:
> "Please share the ERP log URL (e.g. `https://erp.arbisoft.com/project-logs/update/382332/`) so I can fetch existing entries and generate the DevTools script."

Wait for the URL before continuing. Do not proceed without a LOG_ID.

**Week:** If the user specified `--week YYYY-MM-DD`, a date like "May 22", or "last week", parse that into the Monday of the target week. Otherwise compute the current Monday in PKT (UTC+5):
```bash
date -v-Mon +%Y-%m-%d
```
If today IS Monday, use today.

Store:
- `WEEK_START` = Monday YYYY-MM-DD
- `WEEK_END_FRI` = Friday YYYY-MM-DD
- `WEEK_END_SUN` = Sunday YYYY-MM-DD
- `GH_RANGE` = `YYYY-MM-DD..YYYY-MM-DD` (Mon..Fri, used in GitHub queries)
- `WEEK_DIR` = `Mon, {MMM DD} to Sun, {MMM DD}` (e.g. `Mon, Jun 01 to Sun, Jun 07`)
- `LOG_DIR` = `/Users/farhan.khan/MyStuff/Development/Claude_Workspaces/project_logs/logs/<WEEK_DIR>`

---

### Step 2: Fetch Existing ERP Log Entries (ALWAYS — before any other work)

**This step is mandatory every time, even if the log looks empty.**

The ERP log may already have entries logged by the user. Always fetch them first so they are preserved and not overwritten.

Share the following snippet with the user and ask them to paste the output:

> "Before I start, please paste this into your Chrome DevTools Console on `https://erp.arbisoft.com/project-logs/update/<LOG_ID>/` and share the output:"
>
> ```javascript
> fetch('/api/v1/project-logs/person/get/<LOG_ID>/', {headers:{Accept:'application/json'},credentials:'include'}).then(r=>r.json()).then(d=>console.log(JSON.stringify(d)))
> ```

Wait for the user to paste the JSON response before proceeding.

**Once you receive the JSON, parse the existing entries:**

For each project in `response.projects`, for each task in `project.tasks`, for each day in `task.days`:
- Extract: `date`, `decimal_hours`, `label_option.value` (labelId), `label_option.label` (taskType), `task.description`
- If `label_option` is null, infer labelId from the description (e.g. "sync" / "meeting" / "standup" → 37 Meeting; "PR" / "worked on" → 34 Coding; "reviewed" → 35 Code Review; "R&D" / "explored" → 44 R&D)

Display a clear summary of what is already logged:

```
Already logged in ERP for week of <WEEK_START>:
  Mon 2026-06-01: [Meeting] Axim Sync up + Knowledge Sharing (0.75h)
  ...
  Total already logged: X.Xh
```

Store these as `ERP_ENTRIES` — they will be preserved verbatim in Step 16.

**Deduplication note:** When generating new entries in Steps 3–11, treat both `ERP_ENTRIES` and `ACCUMULATED_ENTRIES` (Step 2.5) as already-present. Do not create a new entry for something already logged.

---

### Step 2.5: Read Accumulated Daily Entries

Check if `<LOG_DIR>/erp_log.txt` exists:
```bash
ls "<LOG_DIR>/erp_log.txt" 2>/dev/null
```

If it exists, read it and parse all lines matching the format:
```
YYYY-MM-DD [TAG] - Description (hours)
```

Display a summary:
```
Accumulated daily entries from log file:
  2026-06-01 [Coding] - Worked on PR #123 (2.5)
  2026-06-02 [Meeting] - Axim Daily Syncup (0.5)
  Total accumulated: X.Xh
```

Store these as `ACCUMULATED_ENTRIES`.

**Deduplication with ERP_ENTRIES:** If an accumulated entry matches an ERP entry (same date + same or similar description), mark it as covered — do not include it again in the final output.

---

### Step 3: Verify GitHub Auth

GitHub username is **`farhan`** (hardcoded — do not resolve dynamically).

```bash
gh auth status
```

If this fails, stop and tell the user: "Run `gh auth login` first."

Set `GH_USER=farhan`.

---

### Step 4: Fetch GitHub Activity (openedx org only)

Run all three queries. The GitHub search API uses UTC dates; since the user is PKT (UTC+5), extend the range by ±1 day to avoid missing boundary items — query `(WEEK_START-1day)..(WEEK_END_FRI+1day)` and then filter to PKT weekdays during classification.

**Authored PRs** (updated this week — catches merges of older PRs):
```bash
gh api -X GET "search/issues" \
  -f q="author:${GH_USER} is:pr updated:${GH_RANGE} org:openedx" \
  --jq '[.items[] | {number,title,html_url,state,created_at,updated_at,closed_at,repository_url,body}]'
```

**Authored PRs created this week** (catches PRs whose last `updated_at` falls AFTER the week due to later CI activity):
```bash
gh api -X GET "search/issues" \
  -f q="author:${GH_USER} is:pr created:${GH_RANGE} org:openedx" \
  --jq '[.items[] | {number,title,html_url,state,created_at,updated_at,closed_at,repository_url,body}]'
```
Merge the two result sets (deduplicate by PR number). PRs that appear only in the `updated:` set but have `created_at` from weeks ago — include them only if `merged_at` or significant commit activity falls within the current week.

**Reviewed PRs** (reviewed but not authored):
```bash
gh api -X GET "search/issues" \
  -f q="reviewed-by:${GH_USER} -author:${GH_USER} is:pr updated:${GH_RANGE} org:openedx" \
  --jq '[.items[] | {number,title,html_url,updated_at,repository_url}]'
```

**Issues commented on** (substantive R&D discussions):
```bash
gh api -X GET "search/issues" \
  -f q="commenter:${GH_USER} is:issue updated:${GH_RANGE} org:openedx" \
  --jq '[.items[] | {number,title,html_url,updated_at,repository_url,body}]'
```

### Detailed PR enrichment (for ALL authored PRs):

For each authored PR, extract `{owner}/{repo}` from `repository_url` (last two path segments) and run:

**PR size and metadata:**
```bash
gh api "repos/{owner}/{repo}/pulls/{number}" \
  --jq '{additions,deletions,changed_files,review_comments,body,title,base_ref_name:.base.ref,head_ref_name:.head.ref,merged_at,draft}'
```

**Commits (title + message for context):**
```bash
gh api "repos/{owner}/{repo}/pulls/{number}/commits" \
  --jq '[.[] | {sha: .sha[0:7], message: .commit.message, author: .commit.author.name, date: .commit.author.date}]'
```

**Review rounds and reviewers:**
```bash
gh api "repos/{owner}/{repo}/pulls/{number}/reviews" \
  --jq '[.[] | {user: .user.login, state, submitted_at}]'
```

**Review comments (inline code discussion):**
```bash
gh api "repos/{owner}/{repo}/pulls/{number}/comments" \
  --jq '[.[] | {user: .user.login, body, path, created_at}]'
```

**Issue/PR conversation comments:**
```bash
gh api "repos/{owner}/{repo}/issues/{number}/comments" \
  --jq '[.[] | {user: .user.login, body, created_at}]'
```

**Linked issues (from PR body — look for "Closes #NNN", "Fixes #NNN", "Resolves #NNN"):**
Parse the PR `body` field for linked issue references. For each found issue number:
```bash
gh api "repos/{owner}/{repo}/issues/{linked_number}" \
  --jq '{number,title,html_url,state,body}'
```

Use all the above to:
- Refine the description beyond just the PR URL (include what the PR actually does)
- Determine if it fixes a spec/ticket (link the issue in the description)
- Identify if it was a multi-day effort (commits span multiple PKT days)

Also fetch size for **reviewed PRs** to calibrate hours:
```bash
gh api "repos/{owner}/{repo}/pulls/{number}" \
  --jq '{additions,deletions,changed_files}'
```

---

### Step 5: Fetch GitHub Project Board Events

Project board URL: `https://github.com/orgs/openedx/projects/55/views/1`

Fetch project items and their status using the GraphQL API:

```bash
gh api graphql -f query='
query {
  organization(login: "openedx") {
    projectV2(number: 55) {
      title
      items(first: 100) {
        nodes {
          id
          updatedAt
          fieldValues(first: 20) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field { ... on ProjectV2SingleSelectField { name } }
              }
              ... on ProjectV2ItemFieldTextValue {
                text
                field { ... on ProjectV2Field { name } }
              }
            }
          }
          content {
            ... on Issue {
              title
              number
              url
              updatedAt
              state
              assignees(first: 5) { nodes { login } }
              labels(first: 5) { nodes { name } }
            }
            ... on PullRequest {
              title
              number
              url
              updatedAt
              state
              assignees(first: 5) { nodes { login } }
            }
          }
        }
      }
    }
  }
}'
```

Filter the results:
- Keep only items where `content.updatedAt` falls within `WEEK_START..WEEK_END_FRI+1day`
- Keep only items assigned to `farhan` OR items where the user's authored/reviewed PRs from Step 4 are linked
- Note the Status field value (e.g. "In Progress", "In Review", "Done") — use it to corroborate what the user was working on

Use board items to:
- Confirm which stories/tickets the week's PRs belong to
- Surface any issue-only work (no PR yet) that should appear as `[R&D]`
- Add issue URL as context in descriptions: `Worked on <PR_URL> (fixes <issue_url>)`

---

### Step 6: Fetch Google Calendar Events

**Primary calendar ID (hardcoded):** `farhan.khan@arbisoft.com`

Fetch events:
```
mcp__claude_ai_Google_Calendar__list_events
  calendarId: farhan.khan@arbisoft.com
  startTime: WEEK_START T00:00:00+05:00
  endTime:   WEEK_END_FRI T23:59:59+05:00
  pageSize:  50
```

**Known recurring meetings (use exact durations below):**

| Calendar event | Tag | ERP description | Duration |
|---|---|---|---|
| "Axim Sync up + Knowledge Sharing" (daily recurring) | `[Meeting]` | `Axim Daily Syncup` | 0.75h (17:00–17:45 PKT) |
| "Axim - Grooming Session + DS" (bi-weekly Wed) | `[Meeting]` | `Team Grooming Session` | 1.0h (16:30–17:30 PKT) |
| "Aximprovements Weekly Sync-up" (Wed after grooming) | `[Meeting]` | `Weekly Aximprovements team sync up meeting with Client` | 0.5h (17:45–18:15 PKT) |
| "Open edX Core Arch Sync" (weekly Tue ~23:30 PKT) | `[Meeting]` | `Open edX Core Arch Sync` | 1.0h |
| Any training / I&AI learning session | `[Training/Learning]` | `Attended <event title>` | actual duration |
| 1:1 or pair session | `[Meeting]` | `1:1 with <person>` | actual duration |
| Other work meeting | `[Meeting]` | `<event title>` | actual duration |
| Out-of-office / leave | skip, note as leave day | | |
| Personal / non-work | skip | | |

Extract duration from event start/end times (round to nearest 0.25h). Calendar duration is authoritative — do NOT use Slack/heuristic estimates for meetings that have a calendar entry.

---

### Step 7: Fetch Slack Activity from #axim-aximprovements-internal

**Known values (hardcoded — skip search if unchanged):**
- Channel ID: `C05NRP1U0CC` (#axim-aximprovements-internal)
- User Slack ID: `UGZM9UKPH` (Muhammad Farhan Khan / farhan.khan@arbisoft.com)

If the channel search ever fails, search `mcp__claude_ai_Slack__slack_search_channels` with query `axim` (not `aximprovements` — the search doesn't match mid-word) and pick `#axim-aximprovements-internal`.

**Search user's messages for the week:**
Use `mcp__claude_ai_Slack__slack_search_public_and_private` with:
```
query: "from:<@UGZM9UKPH> after:<WEEK_START> before:<WEEK_END_FRI+1day>"
```
Use text date strings (`after:2026-05-25`) — NOT Unix timestamps — for the search query.

**Read the channel for meeting signals** (standup bot prompts, grooming invites, sync announcements):
Use `mcp__claude_ai_Slack__slack_read_channel` with channel_id `C05NRP1U0CC`, `limit: 100`.

**IMPORTANT — Unix timestamp calculation for `oldest`/`latest`:**
`slack_read_channel` uses Unix timestamps, not text dates. For 2026 dates:
- 2026-05-25 00:00 UTC = `1779667200`
- Formula: `2026-01-01 = 1767225600`; add `(days_since_jan1) × 86400`
- Jan=31, Feb=28, Mar=31, Apr=30 → May 1 = day 121 → May 25 = day 144 → `1767225600 + 144×86400 = 1779667200`
- Always verify by cross-checking with the text-search results' timestamps.

**For threads the user participated in** that reference a PR/issue URL, optionally call:
`mcp__claude_ai_Slack__slack_read_thread` to get the thread context.

**Search explicitly for 1:1 huddle sessions:**
Slack huddles (started via the huddle button or "let's jump on a call" DMs) do NOT appear on the calendar. Search for them explicitly:

```
mcp__claude_ai_Slack__slack_search_public_and_private
  query: "from:<@UGZM9UKPH> huddle"
  channel_types: "public_channel,private_channel,mpim,im"

mcp__claude_ai_Slack__slack_search_public_and_private
  query: "to:<@UGZM9UKPH> huddle"
  channel_types: "public_channel,private_channel,mpim,im"

mcp__claude_ai_Slack__slack_search_public_and_private
  query: "from:<@UGZM9UKPH> (\"quick call\" OR \"hop on\" OR \"join me\" OR \"let's chat\")"
  channel_types: "public_channel,private_channel,mpim,im"
```

**IMPORTANT — do NOT use `after:`/`before:` date filters on huddle searches.** Slack's date filter silently drops results even when matching messages exist (confirmed: a May 18 huddle was invisible in date-filtered search but appeared in unfiltered search). Instead, run **without date filters** and manually filter results by checking the `Time:` field in each result — keep only messages whose PKT timestamp falls within `WEEK_START..WEEK_END_FRI`.

For each huddle signal found:
- Note the other participant(s) and the approximate time from message timestamp
- Estimate duration: 0.25h for quick syncs (≤15 min), 0.5h default if unknown, longer if the thread suggests a code walkthrough or design discussion
- If a DM thread has substantial back-and-forth (5+ messages in a short window), treat as 0.5h huddle minimum
- Tag as `[Meeting]` — `Huddle with <name>` (or `Quick sync with <name>`)
- **Dedup with Calendar:** If the same huddle also shows up as a calendar event, use the calendar duration

From Slack, extract:
- Standup messages (daily) → `[Meeting]`
- Grooming session threads/mentions → `[Backlog grooming]`
- Weekly client sync mentions → `[Meeting]`
- Huddle / quick-call mentions in any channel or DM → `[Meeting]` — `Huddle with <name>`
- Technical discussions linking to PRs/issues → supporting context only (do NOT create duplicate entries)

**Deduplication with Calendar:** If a meeting already appears in Google Calendar, do NOT create a duplicate entry from Slack — use the calendar's duration as authoritative.

---

### Step 8: Fetch Chrome Browsing History

Chrome history DB is at:
```
~/Library/Application Support/Google/Chrome/Default/History
```

Since Chrome may have a lock on this file, copy it first:
```bash
cp ~/Library/Application\ Support/Google/Chrome/Default/History /tmp/chrome_history_tmp.db
```

Query for work-relevant URLs visited during the week (Chrome stores timestamps as microseconds since 1601-01-01):
```bash
sqlite3 /tmp/chrome_history_tmp.db "
SELECT url, title,
  datetime(last_visit_time/1000000 - 11644473600, 'unixepoch', '+5 hours') as visited_pkt
FROM urls
WHERE visited_pkt >= '<WEEK_START> 00:00:00'
  AND visited_pkt <= '<WEEK_END_FRI> 23:59:59'
  AND (
    url LIKE '%github.com/openedx%'
    OR url LIKE '%github.com/orgs/openedx%'
    OR url LIKE '%docs.openedx.org%'
    OR url LIKE '%discuss.openedx.org%'
    OR url LIKE '%openedx.atlassian.net%'
    OR url LIKE '%erp.arbisoft.com%'
    OR url LIKE '%youtu%'
    OR url LIKE '%developer.mozilla.org%'
    OR url LIKE '%stackoverflow.com%'
    OR url LIKE '%docs.djangoproject.com%'
    OR url LIKE '%docs.python.org%'
    OR url LIKE '%confluence%'
  )
ORDER BY last_visit_time ASC;
"
```

Use browsing history to:
- **Corroborate** GitHub activity: visited PR/issue URLs confirm they were actively worked on that specific day (use for day assignment)
- **Surface learning/research:** YouTube videos, docs, StackOverflow, MDN → `[Training/Learning]` or enrich `[R&D]` descriptions
- **Identify exact working day** for a PR that spans multiple days (the day with the most visits = primary work day)
- **Do NOT create entries for browsing alone** unless it clearly represents distinct research not otherwise captured (e.g., a doc page with no related GitHub issue)

Clean up:
```bash
rm /tmp/chrome_history_tmp.db
```

---

### Step 9: Mine Conversation History

Re-read the current conversation for any activity the user mentioned during the target week:
- PR links or issue links not captured by GitHub search
- Learning resources (YouTube videos, documentation, blog posts) → `[Training/Learning]`
- Explicit mentions of meetings, calls, or sessions
- Any hours the user already noted

Add these as supplementary entries. These are authoritative — prefer them over inferred data.

---

### Step 10: Classify Each Item

Apply these rules in order:

| Signal | Tag | Description template |
|---|---|---|
| GitHub PR authored, active this week | `[Coding]` | `Worked on following PR: <url>` — enrich with what the PR does if commits/body clarify it |
| GitHub PR authored, multiple PRs for same story/issue | `[Coding]` | Group them: `Worked on following PR's\n<url1>\n<url2>` |
| GitHub PR reviewed (not authored) | `[Code Review]` | `Reviewed following PR: <url>` |
| GitHub issue with user's comments | `[R&D]` | `Study the code and brainstorm the solution for this story: <url>` (adapt phrasing to issue title) |
| GitHub project board issue (assigned, no PR) | `[R&D]` | `Investigated and explored solution for: <issue_url>` |
| Google Calendar meeting (standup) | `[Meeting]` | `Axim Daily Syncup` |
| Google Calendar meeting (grooming) | `[Meeting]` | `Team Grooming Session` |
| Google Calendar meeting (weekly sync) | `[Meeting]` | `Weekly Aximprovements team sync up meeting with Client` |
| Google Calendar meeting (other) | `[Meeting]` | `<calendar event title>` |
| Slack daily standup post (no calendar duplicate) | `[Meeting]` | `Axim Daily Syncup` |
| Slack grooming thread/post | `[Backlog grooming]` | `Team Grooming Session` |
| Slack weekly sync post | `[Meeting]` | `Weekly Aximprovements team sync up meeting with Client` |
| Slack huddle / "quick call" / "hop on" in any DM or channel | `[Meeting]` | `Huddle with <name>` |
| Chrome: YouTube/docs/SO visited | `[Training/Learning]` | `Watched/read <topic> for learning: <url>` (only if distinct from existing entries) |
| Conversation: learning resource | `[Training/Learning]` | `Watch <topic> for learning: <url>` |

**Deduplication rules:**
- If a Slack message references the same PR/issue already in GitHub results → merge context, do NOT create a second entry
- If a Calendar event matches a Slack standup/meeting → use Calendar, discard Slack duplicate
- If Chrome history confirms a PR was visited on a specific day → use that for day assignment, do NOT create a new entry
- GitHub project board items already covered by an authored PR → skip the board item as a separate entry; use it only to enrich the PR description
- Anything already present in `ERP_ENTRIES` or `ACCUMULATED_ENTRIES` → do NOT create a duplicate new entry

**Bot/automated PR filtering:**
- PRs titled "chore: Upgrade Python/JS requirements", "build(deps): bump ...", or "chore: pin GitHub Actions workflows to full commit SHAs" are bot-generated.
- If `reviewed-by:farhan` returns a large batch (10+) of these on the same day, they were batch-reviewed as part of an org-wide initiative. Represent the entire batch as **one** `[Code Review]` entry listing 2–3 representative URLs, with 1.5–2.5h depending on how many repos were covered (not 1.5h per PR).
- Individual bot PRs reviewed in isolation (1–2) can be included normally if they are in repos farhan owns.

**WIP / superseded PR handling:**
- If a WIP PR (e.g. `[WIP]` in title, or `draft: true`) was closed WITHOUT merging because its commits were absorbed into a later PR, do NOT create a separate entry for the abandoned PR. Count the work only under the PR that eventually merged or is still open.
- A WIP PR that is still open at week end counts as a normal authored entry at the draft hour rate (2.0h).

**PKT day assignment:**
1. Convert all UTC timestamps to PKT (+5h) before assigning to a weekday.
2. If Chrome history shows the user visited the PR on a specific day, prefer that day.
3. If a PR spans multiple days (created Monday, merged Wednesday), assign the primary coding entry to the merge/last-active day, and optionally split a second entry to an earlier day if hours would exceed the daily cap.

---

### Step 11: Estimate Hours Per Item

| Item type | Hours |
|---|---|
| PR authored, ≤200 LOC | 2.5h (+0.5 if 2+ review rounds) |
| PR authored, 200–600 LOC | 3.5h (+0.5 if 2+ review rounds) |
| PR authored, >600 LOC | 4.0h (+1.0 if 2+ review rounds) |
| PR authored, draft / not merged | 2.0h |
| PR reviewed, ≤200 LOC | 1.5h |
| PR reviewed, 200–600 LOC | 2.0h |
| PR reviewed, >600 LOC | 2.5h |
| Issue commented (1 comment by user) | 1.0h |
| Issue commented (2–3 comments by user) | 2.0h |
| Issue commented (4+ comments by user) | 3.0h |
| GitHub board issue only (no PR) | 1.0–2.0h depending on board status |
| Google Calendar meeting | Use actual event duration (rounded to 0.25h) |
| Daily standup (no calendar event) | 0.5h |
| Grooming session (no calendar event) | 1.5h |
| Weekly client sync (no calendar event) | 0.5h |
| Huddle / quick call (no calendar event, short thread ≤5 msgs) | 0.25h |
| Huddle / quick call (no calendar event, longer thread or code walkthrough) | 0.5h |
| Training/Learning item | 0.5h (or as mentioned by user) |

Round all hours to the nearest 0.1h. If the user explicitly stated hours anywhere (in the conversation, in an `ACCUMULATED_ENTRIES` line, or in a Slack message), use those instead.

For items already in `ERP_ENTRIES`, use the hours already recorded there — do not re-estimate.
For items already in `ACCUMULATED_ENTRIES`, use the hours from those entries — do not re-estimate.

---

### Step 12: Balance Daily Hours

Target: **~8h/day**, max 9.0h, min 6.5h.

1. Sum hours per PKT weekday — include `ERP_ENTRIES`, `ACCUMULATED_ENTRIES`, and new entries.
2. If a day exceeds 9.0h: move the lowest-priority `[Coding]` or `[R&D]` entry to the lightest adjacent weekday (keep `[Meeting]` and `[Code Review]` in place). Do NOT move ERP or accumulated entries.
3. If a day is below 6.5h and there are unassigned GitHub issues or Slack R&D threads, redistribute them here.
4. Always include `[Meeting] - Axim Daily Syncup (0.50)` for every weekday where there is any other activity (standup is a daily constant unless the user is on leave). Skip if a calendar standup event or existing entry already covers it.
5. If a weekday has zero signal across all sources, leave it **blank** in the output and add a note: `(no activity detected — leave or holiday?)`.

---

### Step 13: Render the Output

Format the log exactly as:

```
Week: YYYY-MM-DD .. YYYY-MM-DD
Sources: GitHub (openedx) | Google Calendar | Slack (#aximprovements) | Chrome history | GitHub board (openedx/projects/55) | Accumulated daily entries | Conversation history
GitHub: X authored, Y reviewed, Z issues  |  Calendar: N events  |  Slack: M messages  |  Board: K items  |  Daily entries: D accumulated

--- YYYY-MM-DD (Mon) | X.Xh ---
[Tag] - Description (X.X)
[Tag] - Description (X.X)
...

--- YYYY-MM-DD (Tue) | X.Xh ---
...

--- YYYY-MM-DD (Wed) | X.Xh ---
...

--- YYYY-MM-DD (Thu) | X.Xh ---
...

--- YYYY-MM-DD (Fri) | X.Xh ---
...

Weekly total: XX.Xh
```

Entry ordering within each day:
1. `ERP_ENTRIES` (already in ERP — listed first)
2. `ACCUMULATED_ENTRIES` for that date (daily mode entries)
3. New entries generated from connectors this session

---

### Step 14: Write the Log File

Create the directory if it doesn't exist:
```bash
mkdir -p "<LOG_DIR>"
```

Write the rendered output to:
```
<LOG_DIR>/erp_log.txt
```

i.e. `/Users/farhan.khan/MyStuff/Development/Claude_Workspaces/project_logs/logs/<WEEK_DIR>/erp_log.txt`

**IMPORTANT — hours format:** Use `(0.5)` not `(0.5h)` — bare decimal numbers only, no unit suffix.

Use the Write tool. Confirm the file path to the user after writing.

---

### Step 15: Ask for Adjustments

After writing the file, show the full content in chat and ask:
> "Adjust anything? (e.g., 'move PR #35 to Tuesday', 'add 1h learning on Thursday', 'the grooming was on Wednesday', 'I was on leave Friday')"

If the user requests changes, apply them, rewrite the file, and confirm.

---

### Step 16: Generate DevTools Submission Script

After the log file is finalised, **always** write the script to:
```
<LOG_DIR>/devtools_fill_log.js
```

i.e. `/Users/farhan.khan/MyStuff/Development/Claude_Workspaces/project_logs/logs/<WEEK_DIR>/devtools_fill_log.js`

Never add a date suffix — one file per week directory, overwrite each time.

**Why a file, not chat code:** Copying JS from chat causes smart-quote mangling (`'` → `'`) which breaks JavaScript parsing. Always write to disk — user copies from the file in their editor.

**CRITICAL — ENTRIES must include all three sources:**
The PATCH request replaces all tasks for the project. Therefore the ENTRIES array must contain:
1. All entries from `ERP_ENTRIES` (Step 2) — converted to ENTRIES format, preserving their original date, labelId, hours, and description exactly
2. All entries from `ACCUMULATED_ENTRIES` (Step 2.5) — that are NOT already covered by ERP_ENTRIES
3. All new entries generated in this session — only those NOT already covered by ERP_ENTRIES or ACCUMULATED_ENTRIES

For existing entries where `label_option` was null, infer the labelId from the description as described in Step 2.

**Rules for the JS:**
- Use `var` and regular `function` (no arrow functions on critical lines) — maximises compatibility
- Use double quotes `"` for all strings — single quotes are more prone to curly-quote substitution
- Hardcode `labelId` numbers directly in each entry object (do NOT use a `LABEL_IDS` lookup object with `"Code Review"` as a key — long object keys are where wrapping breaks)
- Label IDs: Meeting=37, R&D=44, Code Review=35, Coding=34, Testing=39, Debugging=40, Documentation=42, Deployment=60
- Hours format: decimal number (e.g. `0.5`, `1.5`, `6.5`)
- `desc` max 120 chars — truncate PR URL lists if needed
- Log ID comes from the ERP portal URL: `https://erp.arbisoft.com/project-logs/update/<LOG_ID>/`
- The DevTools approach uses the browser's existing logged-in session via `document.cookie` — no separate auth needed

**Template:**

```javascript
(async () => {
  var LOG_ID = "<LOG_ID>";
  var BASE = "https://erp.arbisoft.com";

  // ENTRIES = ERP entries (preserved) + accumulated daily entries + new entries this session
  // ERP entries are listed first within each day, then accumulated, then new
  var ENTRIES = [
    // --- From ERP (preserved verbatim) ---
    { date: "YYYY-MM-DD", labelId: 37, taskType: "Meeting",     hours: 0.75, desc: "Axim Sync up + Knowledge Sharing" },
    // --- From accumulated daily entries ---
    { date: "YYYY-MM-DD", labelId: 34, taskType: "Coding",      hours: 2.5,  desc: "Worked on following PR: https://..." },
    // --- New entries added this session ---
    { date: "YYYY-MM-DD", labelId: 35, taskType: "Code Review", hours: 1.5,  desc: "Reviewed following PR: https://..." },
  ];

  var csrf = document.cookie.split("; ").find(function(r) { return r.startsWith("csrftoken="); });
  if (!csrf) { console.error("Not logged in"); return; }
  csrf = csrf.split("=")[1];

  var state = await fetch(BASE + "/api/v1/project-logs/person/get/" + LOG_ID + "/", {
    headers: { "Accept": "application/json" }, credentials: "include"
  }).then(function(r) { return r.json(); });

  var weekEnding = state.week_ending, year = state.year;
  var primary = state.projects[0], projectId = primary.id;
  console.log(state.person_name + " | " + state.week_starting + " to " + weekEnding);

  function toWeekDay(s) {
    var p = s.split("-").map(Number);
    return ["sun","mon","tue","wed","thu","fri","sat"][new Date(Date.UTC(p[0], p[1]-1, p[2])).getUTCDay()];
  }

  function toMoment(hours, we, yr) {
    var base = new Date(we.replace(/^\w+,\s*/, "") + " " + yr + " 19:00:00 UTC");
    var mins = Math.round(hours * 60), ts = new Date(base.getTime() + mins * 60000);
    var h = Math.floor(mins / 60), m = mins % 60;
    return { value: ts.toISOString().replace(/\.\d+Z$/, ".000Z"), display: String(h).padStart(2,"0") + ":" + String(m).padStart(2,"0") };
  }

  var tasks = ENTRIES.map(function(e, i) {
    var wd = toWeekDay(e.date), mins = Math.round(e.hours * 60), h = Math.floor(mins/60), m = mins%60;
    return {
      index: i, description: e.desc.slice(0, 120), week_day: wd,
      days: [{ is_work_from_home: false, week_day: wd, decimal_hours: Math.round(e.hours*10000)/10000,
        logged_time: { hours: h, minutes: m }, hours: h, minutes: m, date: e.date,
        loggedTimeMoment: toMoment(e.hours, weekEnding, year), label: e.labelId,
        label_option: { value: e.labelId, label: e.taskType, category: null, visibleInOtherLogs: e.labelId === 37 }
      }],
      person_week_project: projectId, danger: false
    };
  });

  console.table(ENTRIES.map(function(e) { return { date: e.date, type: e.taskType, hours: e.hours }; }));

  var updatedProjects = state.projects.map(function(p) {
    return p.id === projectId ? Object.assign({}, p, { tasks: tasks }) : p;
  });
  var payload = Object.assign({}, state, { projects: updatedProjects });

  var r = await fetch(BASE + "/api/v1/project-logs/person/person-week-log/save/" + LOG_ID + "/", {
    method: "PATCH", credentials: "include",
    headers: {
      "Accept": "application/json, text/plain, */*",
      "Content-Type": "application/json;charset=UTF-8",
      "X-CSRFToken": csrf, "x-build-version": "true",
      "Origin": BASE, "Referer": BASE + "/project-logs/update/" + LOG_ID + "/"
    },
    body: JSON.stringify(payload)
  });

  if (r.ok) {
    var t = (await r.json()).total_logged_time || {};
    console.log("Done! " + (t.hours || 0) + "h " + (t.minutes || 0) + "m saved. Refresh to review.");
  } else {
    var errText = await r.text();
    console.error("Failed: " + r.status, errText.slice(0, 400));
  }
})();
```

Tell the user:
> "Script written to `logs/<WEEK_DIR>/devtools_fill_log.js`. Open it in VS Code, Cmd+A → Cmd+C, then paste into Chrome DevTools Console on `https://erp.arbisoft.com/project-logs/update/<LOG_ID>/`. This saves a draft — refresh the page to review, then submit manually."

---

## Invocation Examples

```
/erp-log w https://erp.arbisoft.com/project-logs/update/382332/
/erp-log weekly for May 22 https://erp.arbisoft.com/project-logs/update/382332/
/erp-log w --week 2026-05-04 https://erp.arbisoft.com/project-logs/update/382332/
/erp-log w last week
/erp-log w for May 12

/erp-log d Worked on the auth PR, about 2.5 hours
/erp-log d yesterday: attended team grooming session, 1 hour
/erp-log d Reviewed John's PR on the frontend, 1.5h. Also daily standup 0.5h
/erp-log d on Monday: investigated issue #234, 2h
```

The ERP URL is optional for log generation but required for the DevTools JS script (Step 16). Always extract the LOG_ID from it when provided.
