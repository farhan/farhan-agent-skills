---
name: pr-details
description: Generate the implementation details section for a PR description in a fixed why-then-what style. Use ONLY when explicitly invoked with /pr-details — do not auto-trigger.
---

Generate implementation details for a PR description.

If a PR URL or number is provided, fetch the diff and commits using `gh pr diff` and `gh pr view`. Otherwise use the current branch's uncommitted/committed changes.

Write the details section following this exact style:

1. **One short paragraph** explaining *why* the change is needed — the problem or context that motivated it. No bullet points here.
2. **"This PR adds/changes:"** followed by a tight bullet list of what was done. Each bullet covers a distinct logical change. Do not restate what is already obvious from file names or commit messages. Avoid sub-bullets unless essential.

Rules:
- Keep the whole thing under ~150 words.
- No headers other than what's already in the PR template.
- Do not repeat information between the paragraph and the bullets.
- Do not mention test steps, ticket links, or testing notes — those go elsewhere in the PR template.

Output only the text to paste under `### Details:` — nothing else.
