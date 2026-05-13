# Team Claude Commands

Shared [Claude Code](https://claude.ai/code) slash commands for the team.

## Available commands

| Command | Description |
|---|---|
| `/commit` | Stage and commit changes following Open edX commit conventions |
| `/pr-details` | Generate implementation details for a PR description |

## Setup

```bash
git clone <repo-url>
cd team-claude-commands
chmod +x install.sh
./install.sh
```

Restart Claude Code. Commands are immediately available as `/commit`, `/pr-details`, etc.

## How it works

`install.sh` creates **symlinks** from `~/.claude/commands/` to this repo's `commands/` directory.
This means pulling the latest changes (`git pull`) automatically updates your commands — no reinstall needed.

## Uninstall

```bash
./uninstall.sh
```

## Adding a new command

1. Create a `commands/<name>.md` file describing what the command should do.
2. Open a PR — once merged, teammates get the update on their next `git pull`.

## Where to put project-specific commands

Commands that are specific to a single repo should live in that repo at `.claude/commands/<name>.md` and be committed there — not here.

## References:
https://github.com/addyosmani/agent-skills/tree/main
