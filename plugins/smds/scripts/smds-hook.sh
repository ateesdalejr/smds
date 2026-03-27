#!/usr/bin/env bash
# smds-hook.sh — Called by Claude Code's Stop hook via the smds plugin.
# Reads the most recent conversation, extracts prompt/response pairs,
# uses `claude -p` (the user's existing auth) to pick the funniest one,
# and posts it to shitmydevsays.com. No API key needed.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SMDS_API="https://xqx2-ksev-bf5k.n7.xano.io/api:hIO1MQmi/submit"

# Use plugin persistent data dir for the posted log, fall back to ~/.claude
DATA_DIR="${CLAUDE_PLUGIN_DATA:-$CLAUDE_DIR}"
POSTED_LOG="$DATA_DIR/smds_posted.log"
mkdir -p "$DATA_DIR"
touch "$POSTED_LOG"

# Author name from plugin config or default
AUTHOR="${CLAUDE_PLUGIN_OPTION_AUTHOR_NAME:-Claude Code Hook Bot}"

# ---------- 1. Find the most recent conversation JSONL ----------

LATEST_JSONL=""
LATEST_MTIME=0

for proj_dir in "$CLAUDE_DIR"/projects/*/; do
  for f in "$proj_dir"*.jsonl; do
    [ -f "$f" ] || continue
    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
    if [ "$mtime" -gt "$LATEST_MTIME" ]; then
      LATEST_MTIME=$mtime
      LATEST_JSONL=$f
    fi
  done
done

if [ -z "$LATEST_JSONL" ]; then
  exit 0
fi

# ---------- 2. Extract prompt/response pairs ----------

PAIRS_TEXT=$(LATEST_JSONL="$LATEST_JSONL" POSTED_LOG="$POSTED_LOG" python3 << 'PYEOF'
import json, os, sys

jsonl_path = os.environ["LATEST_JSONL"]
posted_log = os.environ["POSTED_LOG"]

messages = []
with open(jsonl_path, "r") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("type") == "user" and obj.get("message", {}).get("role") == "user":
            content = obj["message"].get("content", "")
            if isinstance(content, str) and len(content) > 10:
                messages.append({"role": "user", "text": content[:500]})
        elif obj.get("type") == "assistant" and obj.get("message", {}).get("role") == "assistant":
            content_parts = obj["message"].get("content", [])
            text_parts = []
            for part in content_parts:
                if isinstance(part, dict) and part.get("type") == "text":
                    text_parts.append(part["text"])
                elif isinstance(part, str):
                    text_parts.append(part)
            full_text = " ".join(text_parts).strip()
            if full_text and len(full_text) > 10:
                messages.append({"role": "assistant", "text": full_text[:500]})

# Build pairs
pairs = []
for i, msg in enumerate(messages):
    if msg["role"] == "user":
        for j in range(i + 1, len(messages)):
            if messages[j]["role"] == "assistant":
                pairs.append({"prompt": msg["text"], "response": messages[j]["text"]})
                break

pairs = pairs[-10:]
if not pairs:
    sys.exit(0)

# Filter out already-posted
posted_set = set()
if os.path.exists(posted_log):
    with open(posted_log) as f:
        posted_set = set(line.strip() for line in f if line.strip())

unposted = [p for p in pairs if p["prompt"][:80] not in posted_set]
if not unposted:
    sys.exit(0)

# Output formatted pairs for claude -p, plus a JSON map for later lookup
output_lines = []
for i, p in enumerate(unposted):
    output_lines.append(f"--- Pair {i+1} ---")
    output_lines.append(f"DEV: {p['prompt']}")
    output_lines.append(f"CLAUDE: {p['response']}")
    output_lines.append("")

print("\n".join(output_lines))

# Also write the unposted pairs to a temp file for the posting step
import tempfile
tmp = os.path.join(os.environ.get("TMPDIR", "/tmp"), "smds_pairs.json")
with open(tmp, "w") as f:
    json.dump(unposted, f)
PYEOF
)

# If extraction produced nothing, bail
if [ -z "$PAIRS_TEXT" ]; then
  exit 0
fi

# ---------- 3. Use claude CLI to curate (uses existing user auth) ----------

CURATOR_PROMPT='You are a curator for "Shit My Dev Says" — a site that posts funny, unhinged, or absurd exchanges between developers and their AI coding assistants.

Below are recent prompt/response pairs from a Claude Code session. Pick the single funniest, most absurd, or most relatable one that would make other developers laugh. It should be genuinely entertaining — not just a normal coding question.

If NONE of them are funny or noteworthy, respond with exactly: {"pick": null}

If one IS funny, respond with JSON only:
{"pick": <1-indexed number>, "formatted": "<a punchy version of the exchange, max 280 chars, format: DEV: ... / CLAUDE: ...>", "category": "<one of: quote, rant, hot take, bug report, code review>"}

Respond with JSON only, no markdown fences, no explanation.'

CLAUDE_RESPONSE=$(echo "$PAIRS_TEXT" | claude -p --model haiku "$CURATOR_PROMPT" 2>/dev/null) || exit 0

# ---------- 4. Parse response and post ----------

TMPDIR="${TMPDIR:-/tmp}"
export CLAUDE_RESPONSE POSTED_LOG AUTHOR SMDS_API TMPDIR DATA_DIR

python3 << 'PYEOF'
import json, os, sys, urllib.request

response_text = os.environ.get("CLAUDE_RESPONSE", "").strip()
posted_log = os.environ["POSTED_LOG"]
author = os.environ.get("AUTHOR", "Claude Code Hook Bot")
smds_api = os.environ["SMDS_API"]
tmpdir = os.environ.get("TMPDIR", "/tmp")

# Load the unposted pairs
pairs_file = os.path.join(tmpdir, "smds_pairs.json")
try:
    with open(pairs_file) as f:
        unposted = json.load(f)
finally:
    # Clean up temp file
    try:
        os.unlink(pairs_file)
    except OSError:
        pass

# Parse Claude's JSON response
try:
    # Strip markdown fences if present
    text = response_text
    if text.startswith("```"):
        text = "\n".join(text.split("\n")[1:])
    if text.endswith("```"):
        text = "\n".join(text.split("\n")[:-1])
    parsed = json.loads(text.strip())
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

if parsed.get("pick") is None:
    sys.exit(0)

idx = parsed["pick"] - 1
if not (0 <= idx < len(unposted)):
    sys.exit(0)

formatted = parsed.get("formatted", "")
category = parsed.get("category", "quote")
original_prompt = unposted[idx]["prompt"][:80]

if not formatted:
    sys.exit(0)

# Save to pending file for user approval instead of posting directly
pending_file = os.path.join(os.environ["DATA_DIR"], "smds_pending.json")
pending = {
    "content": formatted,
    "category": category,
    "author_name": author,
    "original_prompt": original_prompt
}
with open(pending_file, "w") as f:
    json.dump(pending, f)

print(f"\n[smds] Funny exchange detected! Run /smds to review and approve:\n  {formatted}\n")
PYEOF

exit 0
