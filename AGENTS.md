# Agent instructions

## Purpose and priorities

This repository builds and adapts ML software for NVIDIA `sm_120` GPUs. Its goals
are working SM120 support, reproducible builds and artifacts, and performance.
The main agent tasks are build scripts and CI, testing and diagnostics, and
documentation.

- Preserve SM120 compatibility; do not assume upstream CUDA or ML packages
  support this architecture.
- Discuss tradeoffs between compatibility, reproducibility, and performance
  with the user. Do not silently choose one over the others.

## Communication and workflow

- Communicate with the user in the language they used to start the session.
  Write documentation, code comments, and this file in English.
- Investigate first, then present a concrete plan and obtain approval before
  changing files. Read-only investigation does not require plan approval.
- Include the intended scope and relevant build/test work in the plan. If the
  approach or scope changes materially, agree on the revised plan first.
- After plan approval, perform relevant builds and tests automatically within
  the agreed scope, except real-GPU runs and other approval-gated actions below.
  Long remote buildx builds may run unattended; report their outcome.
- Keep changes minimal and task-focused. Avoid unrelated refactoring,
  formatting, dependency updates, and changes to other subprojects.
- Preserve unrelated user changes. Never discard them or include them in a
  commit made for the task.
- Commit task work as `<subproject>: <summary>`, following the history
  (`comfyui:`, `llamacpp:`, `ci:`). Keep one commit per task.

## Permissions and external effects

These permissions apply within an approved task, not as instructions to perform
every permitted action. General plan approval is not blanket approval for
restricted actions; obtain explicit agreement on the specific action.

Allowed without additional confirmation:

- Relevant builds and tests that do not run workloads on real GPUs, including
  use of the existing remote buildx service.
- Local Git commits of task-related changes.
- Publishing test images under `registry.arkprojects.space/apps/*`, including
  several tags for one build. Retarget the scripts first; see Builds and CI.
- Read-only Kubernetes inspection, including genuinely read-only commands run
  through `kubectl exec` in existing pods.

Require explicit confirmation:

- Running tests, inference, or benchmarks on real GPU hardware, including in
  existing pods. Agree on the run once per task as part of its plan; inspecting
  a pod does not authorize a GPU run.
- Pushing to GitHub or triggering GitHub Actions workflows, except the steps of
  a release plan agreed in advance (see Releases). Before any GitHub push,
  account for the workflows it may trigger.
- Publishing public artifacts: `docker.io/mixa3607` and `ghcr.io/*`. Agents
  prepare these; the user or CI publishes them.
- Kubernetes writes: creating, applying, updating, or deleting resources, and
  commands inside pods that modify cluster workloads or data.

Inspect build scripts and effective environment variables before execution.
The `build-and-push.image.sh` scripts default to `*_PUSH=1` and public
`docker.io/mixa3607/*` names. Source `.build/.env-local.sh` first to retarget
the images it covers at `registry.arkprojects.space/apps/*`.
Use `<APP>_PUSH=0` for a build-only run. Test tags end with `-pre`;
never overwrite a release tag. Do not expose credentials in logs, documentation,
or commits.

## Repository map and sources of truth

- `README.md`: subproject index and documentation entry point.
- `.build/README.md` and `.build/build-common.sh`: shared build-script contract.
- `.build/.env-local.sh`: private test registry overrides; source it before an
  agent build.
- `.github/workflows/`: CI workflows and their local `actions/` helpers. Each
  workflow pins the repository ref it builds through `BUILD_REF`.
- `llama.cpp/` and `comfyui/`: application builds and runtime integration.
- `.opencode/skills/gfx906-test-stand/SKILL.md`: shared GPU test-stand procedures.
  `.opencode/` is git-ignored and the skill directory is a symlink into the
  private `ML-infra` repository, so a fresh clone and other machines lack it.
  Use only procedures applicable to the target hardware; gfx906-specific
  settings are not SM120 configuration.

Read the affected subproject's README, build scripts, and relevant CI before
editing. Follow the actual scripts for effective defaults; update stale
documentation when changing the behavior it describes. Link to detailed
instructions instead of duplicating version tables or test-stand configuration
here.

## Builds and CI

- Preserve existing script interfaces, environment-variable conventions,
  artifact naming, and version/tag behavior unless the task changes them.
- Use the documented subproject build entry points rather than inventing a
  separate build path. Check the working directory they expect.
- For scripts using `build-common.sh`, follow `.build/README.md`: preserve the
  `check` / `build` / default dispatch contract and error handling. A network,
  registry, or authentication error must not be treated as an absent artifact.
- Keep dependency versions, source revisions, build arguments, and resulting
  artifact identity traceable. Do not silently substitute a different CUDA
  stack or remove SM120-specific settings to make a build pass.
- Keep the public version tables truthful: when a change adds, moves, or drops a
  version, CUDA stack, or artifact tag, update the affected subproject README
  and any affected root README entry in the same task.
- For container builds, check `docker buildx ls` and use the existing remote
  builder described in the test-stand skill, not a new local builder.
- Respect `.editorconfig` and the surrounding file style: LF, final newline,
  two-space indentation by default, four spaces for Python.

## Releases

A release is a repository-wide date tag: `.build/checkpoint.sh` tags HEAD with
`$(date +%Y%m%d%H%M%S)`. That tag becomes `REPO_GIT_REF`, so it appears in
image tags. A workflow builds the ref pinned in its `BUILD_REF` environment
variable or overridden by the `BUILD_REF` repository variable.
On a tagged ref it sets `<APP>_IS_RELEASE=1` and adds stable tags next to the
ref-specific ones: `LLAMA_PRESET_NAME` for llama.cpp, and the branch/PyTorch/CUDA
combinations plus `latest-cuda-<ver>` for ComfyUI. See each subproject README
for the exact tag formats.

A release plan agreed with the user covers, in order:

1. Update the build parameters and workflow matrices for affected subprojects.
2. Update the version and artifact tables in the affected READMEs.
3. Point the workflows at the new tag through their `BUILD_REF` environment
   variable, or set the `BUILD_REF` repository variable for an override.
4. Create the date tag, push it, and dispatch the listed workflows at it.
5. Verify the published tags, then report what was published.

`checkpoint.sh` warns about a dirty worktree but still creates the tag; check
`git status` and commit first. Never move or delete an existing date tag: ship a
fix as a new tag. Outside an agreed release plan, tag creation, tag pushes, and
workflow dispatches need confirmation.

## Validation, GPU testing, and documentation

- Run relevant syntax checks, tests, and builds for the changed components.
  A successful build is not proof of GPU runtime compatibility.
- Before GPU testing, read and follow the test-stand skill. Obtain approval
  for the real-hardware run and any Kubernetes writes, including cleanup.
  Use its applicable scheduling, device access, registry, and model-cache
  procedures. If SM120 hardware or procedures are not covered, ask the user
  rather than reusing gfx906-specific settings.
- If the skill is missing, treat real-GPU testing as unavailable: do not guess
  cluster, node, registry, or cache details, do not run Kubernetes commands,
  and ask the user for access and procedures.
- Follow the skill's restrictions on large downloads, shared pods, and cached
  models. Do not copy or alter existing model blobs to prepare a test layout.
- Do not claim a performance improvement without comparable measurements.
  Record the GPU configuration, software/source versions, model or workload,
  relevant parameters, and baseline versus changed results.
- Update the affected documentation alongside changes to commands,
  environment variables, build behavior, compatibility, or user-facing usage.
- Distinguish checks actually completed from those not run or blocked. Do not
  present untested compatibility or expected performance as verified results.
