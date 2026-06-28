---
id: workflow-ci-dependency-audit-gates
created: 2026-06-28
updated: 2026-06-28
tags: [workflow, security]
---

# Add routine CI and dependency-audit gates

Repo-eval and security review both found release workflows but no routine PR/push test matrix or dependency audit automation. Consider adding CI for documented subproject checks plus Dependabot/Renovate/cargo-audit/cargo-deny or equivalent.
