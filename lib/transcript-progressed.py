"""Has an agent transcript progressed past a given moment?

Usage: transcript-progressed.py <transcript.jsonl> <epoch_seconds>
Exit 0 if any entry near the end of the transcript has a timestamp newer
than epoch+1s (the prompt was answered, the badge is stale); exit 1
otherwise, including every failure mode — clearing a badge requires
positive evidence.
"""

import datetime
import json
import sys

TAIL_BYTES = 65536
SLACK_SECONDS = 1


def entry_epoch(line):
    try:
        entry = json.loads(line)
        stamp = entry["timestamp"]
        return datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
    except (ValueError, KeyError, TypeError):
        return None


def main():
    if len(sys.argv) != 3:
        return 1
    path, raw_epoch = sys.argv[1], sys.argv[2]
    try:
        threshold = int(raw_epoch) + SLACK_SECONDS
    except ValueError:
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
