#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/ci/debug-ci.sh [--run ID | --branch NAME | --commit SHA | --failed-latest] [--comment-pr NUMBER]

Examples:
  scripts/ci/debug-ci.sh --failed-latest
  scripts/ci/debug-ci.sh --run 123456789
  scripts/ci/debug-ci.sh --branch main
  scripts/ci/debug-ci.sh --commit abcdef123
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 127
  fi
}

find_lua() {
  if command -v lua >/dev/null 2>&1; then
    printf 'lua'
    return 0
  fi
  if command -v luajit >/dev/null 2>&1; then
    printf 'luajit'
    return 0
  fi
  echo "Missing required command: lua or luajit" >&2
  exit 127
}

json_escape() {
  # jq is intentionally avoided; this helper is only used for simple shell strings.
  printf '%s' "$1" | "$LUA_BIN" -e 'local s=io.read("*a"); s=s:gsub("\\\\","\\\\\\\\"):gsub("\"","\\\""):gsub("\n","\\n"); io.write(s)'
}

run_id=""
comment_pr=""

if [ "$#" -eq 0 ]; then
  set -- --failed-latest
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      run_id="$2"
      shift 2
      ;;
    --branch)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      branch="$2"
      shift 2
      ;;
    --commit)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      commit="$2"
      shift 2
      ;;
    --failed-latest)
      failed_latest=1
      shift
      ;;
    --comment-pr)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      comment_pr="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

require_cmd gh
LUA_BIN="$(find_lua)"

mkdir -p .ci-debug

if [ -z "$run_id" ]; then
  if [ "${branch:-}" ]; then
    run_id="$(gh run list --branch "$branch" --limit 20 --json databaseId --jq '.[0].databaseId')"
  elif [ "${commit:-}" ]; then
    run_id="$(gh run list --limit 100 --json databaseId,headSha --jq ".[] | select(.headSha == \"$(json_escape "$commit")\") | .databaseId" | head -n 1)"
  else
    run_id="$(gh run list --limit 50 --json databaseId,conclusion --jq '.[] | select(.conclusion == "failure") | .databaseId' | head -n 1)"
  fi
fi

if [ -z "$run_id" ]; then
  echo "No matching GitHub Actions run found." >&2
  exit 1
fi

echo "Using GitHub Actions run: $run_id" >&2

gh run view "$run_id" --json databaseId,url,status,conclusion,workflowName,headSha,headBranch,event,createdAt,updatedAt \
  > .ci-debug/run.json

if ! gh run view "$run_id" --log-failed > .ci-debug/failed.log; then
  echo "gh run view --log-failed failed; trying full log." >&2
  gh run view "$run_id" --log > .ci-debug/failed.log || true
fi

"$LUA_BIN" scripts/ci/analyze-log.lua .ci-debug/run.json .ci-debug/failed.log > ci-debug-report.md

if [ -n "$comment_pr" ]; then
  gh pr comment "$comment_pr" --body-file ci-debug-report.md
fi

echo "Wrote ci-debug-report.md" >&2
