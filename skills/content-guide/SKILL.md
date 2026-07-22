---
name: content-guide
description: Guide for generating English content (not code) that follows minimal-wording, hyperlinked, and clean-spacing conventions. Outputs content formatted for the target destination.
argument-hint: [target content to generate]
allowed-tools: Read, WebSearch, WebFetch
---

# Content Guide Skill

This skill generates English content following a strict set of style guidelines. It does not apply to code or technical documentation — only to human-readable written content such as PR comments, PR descriptions, GitHub issues, or Word documents.

---

## Phase 1: Clarify Inputs

If the target content to generate is not clear, ask explicitly before proceeding. Do not assume.

Ask: "What content do you want me to write?"

Then confirm the destination. Common destinations include:

- [GitHub PR comment](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/commenting-on-a-pull-request)
- [GitHub PR description](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests)
- [GitHub Issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/about-issues)
- Word document / Google Doc
- Slack message
- Email

If the destination is not stated, infer the most likely one from context and confirm: "Are you going to post this as a PR comment?"

---

## Phase 2: Apply Content Guidelines

Write the content following these rules:

### Use the least possible wording.
Keep every sentence as short as it can be while remaining complete and grammatically correct. Never use fragments. Never pad with filler phrases like "It is worth noting that" or "As mentioned above."

### Add hyperlinks for references.
Whenever you reference a tool, library, standard, issue, PR, doc, or external concept — embed a hyperlink directly in the text. Do not list URLs separately at the bottom. Example: "This follows the [Conventional Commits](https://www.conventionalcommits.org/) spec."

### Use at most one blank line between sections.
A single blank line is fine for visual separation. Never use two or more consecutive blank lines.

---

## Phase 3: Format for the Destination

Adapt the output format based on the confirmed destination:

- **GitHub PR comment / PR description / Issue** — use [GitHub Flavored Markdown](https://github.github.com/gfm/). Use `**bold**`, `_italic_`, backticks for code, and `[text](url)` for links.
- **Word / Google Doc** — output plain text with natural paragraph breaks. Mention links as readable URLs in parentheses if inline hyperlinking is not possible.
- **Slack** — use Slack's [mrkdwn](https://api.slack.com/reference/surfaces/formatting) format: `*bold*`, `_italic_`, `<url|text>` for links.
- **Email** — use plain prose, no markdown. Embed links as `text (url)`.

---

## Phase 4: Deliver

Output the final content in a code block so the user can copy it cleanly, preceded by a single sentence stating what the content is and where it is formatted for.
