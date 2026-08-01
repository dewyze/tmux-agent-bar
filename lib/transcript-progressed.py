"""Has an agent transcript progressed past a given moment?

Usage: transcript-progressed.py <transcript.jsonl> <epoch_seconds>
Exit 0 if any entry near the end of the transcript has a timestamp newer
than epoch+1s (the prompt was answered, the badge is stale); exit 1
otherwise, including every failure mode — clearing a badge requires
positive evidence.
"""

import datetime
import json
import os
import sys

TAIL_BYTES = 65536
SLACK_SECONDS = 1


# Only conversation entries count as evidence a prompt was answered. Real
# transcripts also record checkpoints (file-history-delta), queued messages,
# hook logs (system), and meta/sidechain entries — all of which can land
# during a wait without answering it.
ANSWER_TYPES = {"user", "assistant"}


def entry_epoch(line):
    try:
        entry = json.loads(line)
        if entry.get("type") not in ANSWER_TYPES:
            return None
        if entry.get("isMeta") or entry.get("isSidechain"):
            return None
        stamp = entry["timestamp"]
        parsed = datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=datetime.timezone.utc)
        return parsed.timestamp()
    except (ValueError, KeyError, TypeError, AttributeError):
        return None


def main():
    if len(sys.argv) != 3:
        return 1
    path, raw_epoch = sys.argv[1], sys.argv[2]
    try:
        threshold = int(raw_epoch) + SLACK_SECONDS
    except ValueError:
        return 1
    # @agent_transcript is writable by any process; opening a FIFO here
    # would block a run-shell forever.
    if not os.path.isfile(path):
        return 1
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - TAIL_BYTES))
            tail = f.read().decode("utf-8", errors="replace")
    except OSError:
        return 1
    # Newest first; skip unparseable lines (a partial trailing write must
    # not hide real progress above it).
    for line in reversed(tail.splitlines()):
        epoch = entry_epoch(line)
        if epoch is not None:
            return 0 if epoch > threshold else 1
    return 1


if __name__ == "__main__":
    sys.exit(main())
