---
description: Fetch GitHub Actions logs and generate a CI debug report.
agent: build
---

Run the repository CI debug helper with these arguments:

```text
$ARGUMENTS
```

Use:

```bash
scripts/ci/debug-ci.sh $ARGUMENTS
```

After the script finishes, read `ci-debug-report.md`, summarize the likely root
cause, and propose the smallest next fix. Do not edit code unless the user asks
for a fix.
