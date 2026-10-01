#!/usr/bin/env bash
# Run the harness in the background and wait (for tool environments with command time limits).
# Usage: tools/bgshots.sh <set> [args…]; log in /tmp/gt_shots.log, done-marker /tmp/gt_shots.done
rm -f /tmp/gt_shots.done
( "$(dirname "$0")/shots.sh" "$@" > /tmp/gt_shots.log 2>&1; echo $? > /tmp/gt_shots.done ) &
for i in $(seq 1 56); do sleep 10; [ -f /tmp/gt_shots.done ] && break; done
grep -E "harness|SCRIPT ERROR|at: " /tmp/gt_shots.log | grep -v audio | cut -c1-220
[ -f /tmp/gt_shots.done ] && echo "done rc=$(cat /tmp/gt_shots.done)" || echo "still running"
