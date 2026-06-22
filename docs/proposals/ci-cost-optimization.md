# Proposal: Reduce CI cost on Blacksmith runners

> Status: data-backed draft. Baseline numbers below are pulled from real
> `test-jaseci.yml` runs via the GitHub Actions API (job + step timing), not
> estimates. The optimized-variant numbers are projections until the benchmark
> PR (see "Getting real numbers") is run.

## TL;DR

1. **The repo is PUBLIC** (`jaseci-labs/jaseci`). GitHub-hosted `ubuntu-latest`
   is therefore **free and unlimited**. Blacksmith is a paid third-party service
   bought for *speed*, not necessity. The cheapest design moves work back to free
   runners and keeps Blacksmith only where its speed actually pays for itself.
2. **A full core PR run costs ~76-80 Blacksmith runner-minutes** (measured).
3. **Setup is already cheap; test *execution* is the cost.** Caching is a minor
   lever, not the main one (corrected from an earlier draft).
4. The big levers, in order: (a) move pure-pytest jobs to free `ubuntu-latest`,
   (b) shard the long-pole suites across free runners, (c) fail-fast gate so a
   trivial lint error doesn't pay for the 80-minute fan-out.

---

## Measured baseline (real data)

Per-job wall-clock from run `27950975813` (a full run, nothing skipped). On
Blacksmith, summed job wall-clock ~= billable runner-minutes.

| Job | Wall-clock | of which: test exec | of which: install/setup |
|-----|-----------:|--------------------:|------------------------:|
| test-core-compiler | 11.6 min | 11.3 min (680s) | ~12s |
| test-pypi-build | 10.2 min | (multi-step smoke) | (builds wheels) |
| test-scale (server) | 8.3 min | 7.0 min (422s) | 64s |
| test-scale-k8s (failure-path) | 7.8 min | kind cluster | docker/network |
| test-core-runtime | 7.5 min | ~7 min | ~10s |
| test-scale (data) | 7.3 min | ~6.5 min | ~60s |
| test-scale-k8s (deploy-core) | 5.2 min | kind cluster | docker/network |
| test-client | 4.4 min | 3.8 min (228s) | 8s + 17s playwright |
| test-packages-and-docs | 4.3 min | byllm + docs build | install |
| test-scale (microservices) | 3.3 min | ~2.7 min | ~60s |
| test-scale (misc) | 2.8 min | ~2.2 min | ~60s |
| test-desktop-native | 2.0 min | ~1.5 min | ~10s |
| test-solid-jsdom | 1.9 min | ~1.5 min | ~15s |
| test-scale (deploy) | 1.9 min | ~1.3 min | ~60s |
| test-mcp | 1.4 min | 0.3 min (19s) | 59s |
| changes | 0.1 min | (path filter) | already on free `ubuntu-latest` |
| **TOTAL (Blacksmith)** | **~80 min** | | |

Cross-checked against two other runs: 75.9 min and 75.6 min. So **~76-80
runner-minutes per core PR**, billed at the Blacksmith 4-vcpu rate. Multiply by
your per-minute rate and your monthly PR volume to get the spend.

### Key insight from step-level timing

Install steps are tiny (7-64s) because Blacksmith already has a fast/cached pip
path. **Test execution is 80-95% of each job.** Therefore:

- Dependency caching (the obvious first idea) saves seconds, not minutes. It is a
  nice-to-have, not the lever.
- Cost is driven by *how long tests run* and *where they run*. The two ways down
  are: run them somewhere free, and/or finish them faster by sharding.

---

## Finding 1 (biggest lever): move pure-pytest jobs to free `ubuntu-latest`

Standard GitHub-hosted `ubuntu-latest` for **public** repos is now 4 vCPU / 16 GB
(same core count as `blacksmith-4vcpu`) and **costs nothing**. Blacksmith's
advantage is faster cores + faster disk/network, i.e. lower wall-clock - not a
capability these jobs need.

Candidates to move to free `ubuntu-latest` (no docker/k8s, just pytest):

- `test-mcp`, `test-desktop-native`, `test-solid-jsdom`, `test-packages-and-docs`,
  `test-client` (light; little latency cost)
- `test-core-compiler`, `test-core-runtime` (long poles; move + shard, see
  Finding 2)
- `test-scale` matrix (server/data/microservices/misc/deploy)
- `test-pypi-build`

Keep on Blacksmith only where its fast disk/network genuinely helps:

- `test-scale-k8s` (kind cluster: image pulls + disk-heavy)
- optionally `test-pypi-build` (builds many wheels + admin UI; network-heavy)

If ~66 of the ~80 minutes move to free runners, **Blacksmith spend drops ~80%**
(only the k8s tier remains paid). The tradeoff is wall-clock: GitHub-hosted cores
are ~1.3-1.7x slower per test, so moved jobs run a bit longer - mitigated by
Finding 2 (sharding) since the runners are free and parallel.

Note: public-repo GitHub Actions allows up to 20 concurrent standard jobs. The
current fan-out is ~14-16 jobs; aggressive sharding must stay under that ceiling
or jobs queue (still free, just slower).

---

## Finding 2: shard the long poles across free runners

The cost/latency concentration is `test-core-compiler` (11.3 min of `pytest -n
auto` on 4 cores) and `test-core-runtime` (~7 min). On Blacksmith these are a
single expensive job each. On free runners you can split them:

- Shard `jac/tests/compiler` across 2-3 `ubuntu-latest` jobs (pytest-xdist
  `--splits`/`--group`, or `pytest-split`, or path-based matrix). Wall-clock for
  the long pole drops from ~11-18 min to ~5-7 min, at **$0**.
- Same pattern for runtime.

Net effect: equal-or-better wall-clock than today, on free infrastructure.

---

## Finding 3: `test-pypi-build` is a serial wall-clock furnace on PRs

[test-pypi-build](../../.github/workflows/test-jaseci.yml#L412-L726) builds all
wheels + admin UI, then `jac create`s **three jacpacks over the network** and
polls three servers with `sleep 15` loops (up to 6 min of pure sleeping per
server). It is a release-gate smoke, already non-required.

- Move it to `push` (main) + nightly `schedule`, off the PR path. Removes ~10
  min/PR directly, plus its Blacksmith cost.
- Tighten readiness polls to 5s.

---

## Finding 4: stage the pipeline so cheap checks gate the heavy suite

Today `contribution-checks`, `jac-check`, and the ~14 jobs of `test-jaseci` fire
**in parallel**. A PR that fails a trivial check (formatting, blocked `.py`,
AI co-author trailer, type error) still pays for the entire fan-out before the
cheap failure shows. On a team where the first push often has a lint slip, that
is ~80 minutes wasted on the most common failure mode.

Fix: a lightweight `preflight` job (on free `ubuntu-latest`) that every heavy job
`needs:`. The cheapest signals need near-zero setup - the git-only checks (AI
co-author, block-`.py`, release-notes) need no install; `jac format --check` and
`jac check` need only `pip install -e jac`.

```yaml
jobs:
  changes:        # existing path filter, free runner
    ...
  preflight:      # NEW - cheap gate on FREE ubuntu-latest
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      # git-only: block AI co-author / block new .py / release-notes
      - uses: actions/setup-python@v5
        with: { python-version: '3.12', cache: pip }
      - run: pip install -e jac
      - run: jac format --check ...           # from jac-check
      - run: jac check . --nowarn ...         # from jac-check

  test-core-compiler:
    needs: [preflight]
    ...
  # ...every heavy job adds `preflight` to its `needs:`
```

This also folds most of `contribution-checks` + `jac-check` into one free gate,
removing two paid full-install 4-vcpu jobs.

Tradeoff: gating serializes wall-clock on *passing* PRs (`preflight + heavy`).
Acceptable because preflight is ~1-2 min and the savings on failing PRs are
large. If green-PR latency matters, gate only the expensive tier behind
preflight and let the required core jobs run alongside it.

Related knob: `test-scale`/`test-scale-k8s` use `fail-fast: false`, so all matrix
shards run after one fails - good for debugging, extra cost on red PRs.

---

## Recommended hybrid architecture

| Tier | Runs on | Jobs |
|------|---------|------|
| Gate | free `ubuntu-latest` | `changes`, `preflight` (lint + format + type + git checks) |
| Unit/integration (pytest) | free `ubuntu-latest`, sharded | compiler, runtime, client, mcp, desktop, solid, packages-docs, scale matrix |
| Heavy infra | Blacksmith (paid, fast) | `test-scale-k8s` (kind), optionally `test-pypi-build` |
| Release/nightly | Blacksmith or free | `test-pypi-build` + jacpack smokes (off PR path) |

Expected: Blacksmith spend down ~80% (only the k8s tier stays paid), wall-clock
roughly flat or better (free sharding offsets slower cores), and the common
lint-failure PR costs ~2 min instead of ~80.

---

## Getting real numbers (the benchmark PR)

We can produce a true before/after, not projections:

1. **Baseline (already measured, above):** historical `test-jaseci` runs pulled
   via `gh api repos/jaseci-labs/jaseci/actions/runs/<id>/jobs` -> per-job and
   per-step durations. ~76-80 Blacksmith min/run.
2. **Experiment:** open a PR with the hybrid workflow (free `ubuntu-latest` +
   sharding + preflight gate). Let CI run, then pull the same per-job timing and
   diff against the baseline. The report writes itself from `gh api`.

The report would show, per job: runner type, wall-clock, billable-vs-free
minutes, and total $ delta.

### Caveat to resolve before running

The local remote is a fork (`ahzan-dev/jaseci`). Blacksmith runners are
org-scoped, so `runs-on: blacksmith-...` jobs will not find a runner on the fork
and will hang. The benchmark must run either against upstream `jaseci-labs/jaseci`
(consumes the org's Blacksmith budget, needs maintainer CI approval) or with the
Blacksmith jobs swapped to `ubuntu-latest` on the fork (measures the free-runner
side only - which is still the main thing we want to prove).

---

## Rollout plan (highest ROI first)

| Step | Effort | Risk | Est. savings |
|------|--------|------|--------------|
| 1. Move pure-pytest jobs to free `ubuntu-latest` | Low-Med | Low | ~80% of Blacksmith spend |
| 2. Shard compiler + runtime across free runners | Med | Low | keeps wall-clock flat post-move |
| 3. Move `test-pypi-build` smokes to push/nightly | Low | Low | ~10 min/PR |
| 4. `preflight` gate on free runner | Med | Low-Med | ~80 min saved on lint-fail PRs |

Steps 1 and 3 are independently shippable and do not touch the required merge
gate (`test-core-compiler`, `test-core-runtime`, `test-client`) - though moving
those three to `ubuntu-latest` keeps the *names* identical, so branch protection
is unaffected. Step 4 changes job topology / check names if checks are folded in,
so it needs a branch-protection update and should land last.

Recommended: land **1 + 3** first, run the benchmark PR to confirm the ~80%
figure on real runs, then do **2 + 4**.
