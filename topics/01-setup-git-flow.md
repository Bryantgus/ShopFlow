# 01 — Setup, Git and Git Flow

> **Time:** 2 h · **Job requirement:** Git Flow · **Builds on:** nothing · **Branch:** `feature/01-solution-skeleton`

## Why it matters

Every team uses Git, and this job asks for Git Flow by name. From this topic on, every piece of ShopFlow goes through a feature branch and a pull request. By topic 18 you'll have done Git Flow 18 times.

---

## Learn

### Git commands you must know without thinking

| Command | What it does |
| --- | --- |
| `git init` / `git clone <url>` | Start a repository / copy an existing one |
| `git status` | What changed and what is staged |
| `git add <file>` / `git add .` | Stage changes for the next commit |
| `git commit -m "feat: add orders schema"` | Save a snapshot with a message |
| `git switch -c feature/x` | Create a branch and move to it (`git checkout -b` is the older form) |
| `git switch develop` | Move to an existing branch |
| `git pull` / `git push` | Get / send commits from / to the remote (GitHub) |
| `git merge feature/x` | Bring another branch's commits into the current branch |
| `git rebase develop` | Replay your commits on top of `develop` (linear history) |
| `git log --oneline --graph --all` | See the branch history as a graph |
| `git stash` / `git stash pop` | Put unfinished work aside / bring it back |
| `git revert <commit>` | Undo a commit with a new commit (safe on shared branches) |
| `git reset --soft HEAD~1` | Undo the last commit but keep its changes (only on your own branch) |
| `git cherry-pick <commit>` | Copy one commit to the current branch |

### Git Flow

| Branch | Purpose | Created from | Merged into |
| --- | --- | --- | --- |
| `main` | Production; every merge is a tagged release | — | — |
| `develop` | Finished work waiting for the next release | `main` | `release/*` |
| `feature/*` | One feature or task | `develop` | `develop` (pull request) |
| `release/*` | Prepare a version: final fixes, version number | `develop` | `main` and `develop` |
| `hotfix/*` | Urgent production fix | `main` | `main` and `develop` |

```text
main      ●────────────────────────●───────────●        v1.0 … v1.1 … v1.1.1
           \                      /│\         /│
hotfix/*    \                    / │ ●───────● │
release/*    \            ●─────●  │           │
              \          /       \ │           │
develop        ●───●────●─────────●───────────●──────
                    \  /
feature/*            ●●
```

- **Release and hotfix merge twice**: into `main` to ship, into `develop` so the fix isn't lost in the next version.
- **Trunk-based development** is the alternative: everyone merges small changes into `main` daily, behind feature flags. Many CI/CD teams prefer it. Know both and say why.
- **Merge vs rebase:** merge keeps history as it happened (with a merge commit); rebase rewrites your commits on top of the target for a straight line. Never rebase a branch other people already pulled.

### Conventional Commits

`type: short description` — `feat:` new feature · `fix:` bug fix · `test:` tests · `docs:` documentation · `refactor:` same behavior, better code · `chore:` tooling and config.

### .NET solution structure

- A **solution** (`.sln` or the newer `.slnx`) groups projects. A **project** (`.csproj`) builds one assembly (`.dll`).
- **Project references** set the direction of dependencies: `dotnet add A reference B` means A can use B, and B knows nothing about A.
- Templates you'll use: `classlib` (library), `webapi` (ASP.NET Core API), `xunit` (tests), `worker` (background service), `func` (Azure Functions, through Core Tools).

---

## Build: the ShopFlow repository and solution skeleton

### Tasks

- [ ] ⭐ Install: .NET 10 SDK, Git, VS Code + extensions (C# Dev Kit, SQL Server (mssql), Oracle SQL Developer, MongoDB for VS Code, Docker, REST Client), Docker Desktop. Check with `dotnet --version` (10.x) and `docker version`.
- [ ] ⭐ Create an empty GitHub repository `ShopFlow`, clone it, and add `.gitignore` (`dotnet new gitignore`) and `.editorconfig` (`dotnet new editorconfig`).
- [ ] ⭐ Write a first `README.md` for your project: one paragraph about ShopFlow, plus the architecture diagram from this guide. Commit it on `main`: `docs: add project readme`.
- [ ] ⭐ Create `develop` from `main` and push it. On GitHub, protect `develop` and `main` (Settings → Branches): changes only through pull requests.
- [ ] ⭐ Create `feature/01-solution-skeleton` from `develop`.
- [ ] ⭐ Create the solution and the empty projects below. Use the right template for each, put them in the folders from the repository skeleton in the main README, and add each one to the solution.

| Project | Template | References |
| --- | --- | --- |
| `src/Orders/ShopFlow.Orders.Domain` | `classlib` | — |
| `src/Orders/ShopFlow.Orders.Application` | `classlib` | Domain |
| `src/Orders/ShopFlow.Orders.Infrastructure` | `classlib` | Application |
| `src/Orders/ShopFlow.Orders.Api` | `webapi` (with controllers) | Application, Infrastructure |
| `src/Catalog/ShopFlow.Catalog.Api` | `webapi` (minimal APIs) | — |
| `src/Inventory/ShopFlow.Inventory.Api` | `webapi` (with controllers) | — |
| `src/BuildingBlocks/ShopFlow.Contracts` | `classlib` | — |

Hints:
- One example to start: `dotnet new classlib -n ShopFlow.Orders.Domain -o src/Orders/ShopFlow.Orders.Domain`, then `dotnet sln add src/Orders/ShopFlow.Orders.Domain`.
- `dotnet new webapi --help` shows the option for controllers.
- Delete the sample `Class1.cs` and the `WeatherForecast` files.
- Notice that Domain references nothing. That's the dependency rule of Clean Architecture (topic 07).

- [ ] ⭐ Set the API ports from the main README (5101, 5102, 5103) in each `Properties/launchSettings.json`.
- [ ] Add a `Directory.Build.props` at the root that turns on `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>` and `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` for every project.
- [ ] ⭐ Commit (`chore: create solution skeleton`), push, open a pull request into `develop`, describe it in 3 lines of English, and merge it.

---

## Check yourself

- `dotnet build` at the root builds all 7 projects with 0 warnings.
- `git log --oneline --graph --all` shows `main`, `develop` and your merged feature branch.
- Trying to push straight to `develop` on GitHub is rejected.

---

## Interview questions

1. **Explain Git Flow.** Name the five branch types, where each one starts and where it merges.
2. **Git Flow vs trunk-based development?** Long-lived branches and planned releases vs small daily merges to main with feature flags; trunk-based fits continuous deployment.
3. **Merge vs rebase?** History as it happened vs a rewritten linear history; never rebase shared branches.
4. **`git revert` vs `git reset`?** Revert adds a new commit that undoes one (safe on shared branches); reset moves the branch pointer back (only on your own branch).
5. **How do you resolve a merge conflict?** Open the file, choose or combine the changes between the markers, build and test, `git add`, then commit.
6. **What makes a good pull request?** Small, one purpose, a clear description, passing pipeline, tests included.

---

## Done when

- [ ] The solution builds with 0 warnings.
- [ ] `develop` exists and is protected.
- [ ] Your first pull request is merged into `develop`.
