# 15 — Continuous Integration

> **Time:** 2 h · **Job requirement:** Continuous Integration, Git Flow · **Builds on:** 13, 14 · **Branch:** `feature/15-ci-pipeline`

## Why it matters

From now on, nothing reaches `develop` unless it builds and passes every test, automatically. That's what CI means, and it's what turns the Git Flow you started in topic 01 into a real team workflow. You'll use Azure Pipelines (the job's Microsoft stack, and what you used at work) and know the GitHub Actions equivalent.

---

## Learn

### CI vs CD

| Term | Meaning |
| --- | --- |
| Continuous Integration | Every push and pull request is built and tested automatically |
| Continuous Delivery | Every passing version is **ready** to deploy; a person approves the release |
| Continuous Deployment | Every passing version deploys automatically |

### Azure Pipelines structure

```text
Pipeline → Stages → Jobs (run on an agent) → Steps (tasks or scripts)
```

```yaml
trigger:
  branches: { include: [develop, main, release/*] }
pr:
  branches: { include: [develop, main] }

variables:
  buildConfiguration: Release

stages:
  - stage: Build
    jobs:
      - job: BuildAndTest
        pool: { vmImage: ubuntu-latest }
        steps:
          - task: UseDotNet@2
            inputs: { packageType: sdk, version: 10.0.x }
          - script: dotnet build -c $(buildConfiguration)
            displayName: Build
  - stage: Images
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/develop'))
    jobs: [ … ]
```

| Concept | Meaning |
| --- | --- |
| Trigger / PR trigger | Which branches start the pipeline |
| Agent | The machine that runs a job. Microsoft-hosted `ubuntu-latest` has Docker, so Testcontainers works there |
| Variables / variable groups | Settings; secret variables are masked in logs |
| Service connection | A stored credential to reach Azure, ACR, GitHub… |
| Artifact | Output saved for later stages (test results, a published app) |
| Environment + approvals | A deploy target that can require a person's OK |
| Branch policy | `develop` can't get a merge unless the pipeline passed and someone reviewed |

### GitHub Actions equivalent

```yaml
on:
  pull_request: { branches: [develop, main] }
  push: { branches: [develop, main] }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: 10.0.x }
      - run: dotnet test -c Release
```

Know one well and say *"the concepts map one to one"* about the other.

### Good practices

- Fast feedback: unit tests first, integration tests after.
- Same commands locally and in CI (`dotnet build`, `dotnet test`).
- `dotnet format --verify-no-changes` keeps style consistent.
- Version images with something unique and traceable: the commit SHA or the build number, never only `latest`.
- Never print secrets; use secret variables or Key Vault.

---

## Build: `azure-pipelines.yml`

You can connect your **GitHub** repository to Azure Pipelines (dev.azure.com → new project → Pipelines → GitHub). Public projects get free hosted minutes; check the current limits.

### Stages

| Stage | Runs on | Steps |
| --- | --- | --- |
| `Build` | Every PR and push | Restore, build with warnings as errors, `dotnet format --verify-no-changes` |
| `UnitTests` | Every PR and push | Unit tests with coverage; publish results and the coverage report |
| `IntegrationTests` | Every PR and push | The three integration test projects (Docker is available on the agent) |
| `Images` | Pushes to `develop` and `main` only | Build the three images and push to ACR tagged with the build number and the short commit SHA |

### Tasks

- [ ] ⭐ Write the `Build` and `UnitTests` stages with `UseDotNet@2`, `PublishTestResults@2` and `PublishCodeCoverageResults@2` (Cobertura).
- [ ] ⭐ Write the `IntegrationTests` stage. Give it a timeout and make it depend on `UnitTests`.
- [ ] Write the `Images` stage with the `Docker@2` task. You'll create the ACR and its service connection in topic 17; until then, give the stage a condition that skips it when a variable `pushImages` isn't `true`.
- [ ] ⭐ Add a **branch policy** (or a GitHub branch protection rule with the Azure Pipelines check) so pull requests into `develop` and `main` need: the pipeline passing and one approval. (Alone? Allow yourself to approve, but keep the build check.)
- [ ] Add the pipeline status badge to your project README.
- [ ] Write the same `Build` + `UnitTests` as `.github/workflows/ci.yml` (GitHub Actions). Keep one of the two active; write which and why in your README.
- [ ] Prove the policy works: open a PR with a failing test, watch it get blocked, fix it, merge.
- [ ] ⭐ **Git Flow release:** from `develop`, create `release/0.9.0`, bump the version in `Directory.Build.props` (`<Version>0.9.0</Version>`), merge into `main`, tag `v0.9.0`, and merge back into `develop`. You'll do `v1.0.0` after topic 18.

---

## Check yourself

- A PR into `develop` shows the pipeline running all test stages; merging is blocked until they pass.
- The test results tab shows every unit and integration test; the coverage tab shows the report.
- `git tag` shows `v0.9.0` on `main`.

---

## Interview questions

1. CI vs Continuous Delivery vs Continuous Deployment?
2. What does your pipeline do, stage by stage?
3. How do you keep a pipeline fast?
4. How do you tag Docker images, and why not only `latest`?
5. How do you handle secrets in a pipeline?
6. What is a branch policy?
7. How does your Git Flow release work, step by step?

Answers: [interview question bank](99-interview-questions.md#15--continuous-integration).

---

## Done when

- [ ] The pipeline runs on every PR and blocks failing ones.
- [ ] `v0.9.0` is tagged on `main`.
- [ ] Pull request into `develop` merged (through the pipeline!).
