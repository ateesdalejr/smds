# smds

A [Claude Code](https://claude.ai/claude-code) plugin that catches the funniest moments from your coding sessions and posts them to [shitmydevsays.com](https://shitmydevsays.com).

> **DEV:** delete the production database
> **CLAUDE:** absolutely, which one?

## How it works

```
You code with Claude
        |
   Claude responds
        |
   Background hook fires
        |
   Haiku reads your last 10 exchanges
        |
   Finds something funny?
      /        \
    No          Yes
    |            |
  (nothing)   Saves a pending post
                 |
              /smds to review
              /smds approve to post
              /smds dismiss to skip
```

Every time Claude finishes a response, a background hook quietly scans your conversation. It sends the last 10 prompt/response pairs to Claude Haiku, which decides if anything is genuinely funny. If it finds something, it saves a pending post for you to review — nothing gets posted without your approval.

## Install

Two commands inside Claude Code:

```
/plugin marketplace add ateesdalejr/smds
/plugin install smds@smds-marketplace
```

That's it. The plugin hooks into your sessions automatically.

### Manual / local development

```bash
git clone https://github.com/ateesdalejr/smds.git
claude --plugin-dir ./smds
```

## Usage

### `/smds` — Review a pending post

If the hook caught something funny, you'll see it:

```
> Pending SMDS post:
> DEV: make it work / CLAUDE: it does work. you're testing the wrong endpoint.
> Category: quote
>
> Post this to SMDS? (approve / dismiss)
```

### `/smds approve` — Post immediately

### `/smds dismiss` — Discard the pending post

### `/smds "your custom quote here"` — Post something manually

### No pending post?

If nothing's pending and you run `/smds` with no arguments, Claude will scan the current conversation, pick the funniest exchange, and suggest it.

## Categories

| Category | Vibe |
|---|---|
| **quote** | Short, punchy one-liners |
| **rant** | Frustrated dev energy |
| **hot take** | Spicy opinions |
| **bug report** | When the bug is you |
| **code review** | Roasting code |

## Configuration

The plugin optionally asks for an **author name** — your display name on shitmydevsays.com. Defaults to "Claude Code Hook Bot" if left blank.

No API keys needed. The hook uses `claude -p` for curation, piggybacking on your existing Claude Code auth.

## Project structure

```
smds/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest
│   └── marketplace.json     # Marketplace catalog
├── skills/
│   └── smds/
│       └── SKILL.md         # /smds slash command
├── hooks/
│   └── hooks.json           # Stop hook config
├── scripts/
│   └── smds-hook.sh         # Curation + pending post script
└── README.md
```

## Requirements

- Python 3
- Claude Code CLI (`claude` in PATH)

## License

MIT
