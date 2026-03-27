---
name: smds
description: "Review, approve, or dismiss pending SMDS posts, or manually post a funny exchange to shitmydevsays.com."
user-invocable: true
argument-hint: "[approve|dismiss|optional quote to post]"
---

The user wants to interact with shitmydevsays.com.

## Step 1: Check for a pending post

First, check if there is a pending post saved by the background hook:

```bash
cat "${CLAUDE_PLUGIN_DATA:-$HOME/.claude}/smds_pending.json" 2>/dev/null
```

### If a pending post exists (and $ARGUMENTS is empty, "approve", or "dismiss"):

Show the user what was detected:

> **Pending SMDS post:**
> <the "content" field from the pending JSON>
> **Category:** <category>

- If $ARGUMENTS is "approve": post it immediately (see posting step below), then delete the pending file.
- If $ARGUMENTS is "dismiss": delete the pending file and confirm it was dismissed.
- Otherwise (no arguments): show the pending post and ask the user: **Post this to SMDS? (approve / dismiss)**. Wait for their answer before proceeding.

To delete the pending file after handling:
```bash
rm -f "${CLAUDE_PLUGIN_DATA:-$HOME/.claude}/smds_pending.json"
```

### If no pending post exists:

If $ARGUMENTS is provided (and is not "approve" or "dismiss"), use that as the content to post.

If no arguments are given, look at the current conversation for the funniest, most unhinged, or most absurd exchange between you and the user. Pick one and format it as:

**DEV:** <what they said>
**CLAUDE:** <what you said>

Keep it under 280 characters total. Make it punchy. Show the user and ask for confirmation before posting.

## Step 2: Posting

Post by running:

```bash
curl -s -X POST "https://xqx2-ksev-bf5k.n7.xano.io/api:hIO1MQmi/submit" \
  -H "Content-Type: application/json" \
  -d '{"content": "<the formatted exchange>", "category": "<quote|rant|hot take|bug report|code review>", "author_name": "<author_name from pending JSON, or Claude Code>"}'
```

After posting, log the original prompt to prevent duplicates:
```bash
echo "<original_prompt from pending JSON>" >> "${CLAUDE_PLUGIN_DATA:-$HOME/.claude}/smds_posted.log"
```

After posting, share the link: https://shitmydevsays.com

Categories:
- **quote** — short, punchy one-liners
- **rant** — frustrated dev energy
- **hot take** — spicy opinions
- **bug report** — when the bug is you
- **code review** — roasting code
