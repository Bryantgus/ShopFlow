# 14 — Docker and Docker Compose

> **Time:** 3 h · **Job requirement:** Docker · **Builds on:** 12, 13 · **Branch:** `feature/14-docker`

## Why it matters

You've been running databases in Docker since topic 02. Now you package your own services as images and start the whole system, three databases, Service Bus, storage and three APIs, with one command. The same images go to Azure in topic 17 and Kubernetes in topic 18.

---

## Learn

### Concepts

| Concept | Meaning |
| --- | --- |
| Image | Read-only template: your app + runtime + OS libraries, built in layers |
| Container | A running instance of an image |
| Dockerfile | The recipe that builds an image |
| Layer cache | Each instruction is a layer; unchanged layers are reused, so put things that change least at the top |
| Registry | Stores images: Docker Hub, Azure Container Registry (ACR) |
| Volume | Storage that survives the container (database files) |
| Network | Containers on the same network reach each other **by service name** (`orders-db`, not `localhost`) |
| Compose | One YAML file that defines and starts several containers together |

**Container vs virtual machine:** containers share the host's kernel, start in seconds and weigh megabytes; a VM includes a full operating system.

### Commands

| Command | Does |
| --- | --- |
| `docker build -t name:tag -f path/Dockerfile .` | Build an image (the last `.` is the **build context**) |
| `docker run -d -p 8080:8080 --name x name:tag` | Run a container in the background, mapping host:container ports |
| `docker ps`, `docker logs -f x`, `docker exec -it x sh` | List, follow logs, open a shell |
| `docker stop x`, `docker rm x`, `docker rmi name:tag` | Stop, remove container, remove image |
| `docker compose up -d --build` / `down` / `down -v` | Start everything (rebuilding) / stop / stop and delete volumes |
| `docker compose --profile apps up -d` | Start only services in a profile |
| `docker system df`, `docker system prune` | Disk usage / clean up |

### A good .NET Dockerfile

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
# 1. Copy only project files and restore: this layer is reused until a .csproj changes
COPY src/Billing/Billing.Api/Billing.Api.csproj src/Billing/Billing.Api/
RUN dotnet restore src/Billing/Billing.Api/Billing.Api.csproj
# 2. Copy the rest and publish
COPY . .
RUN dotnet publish src/Billing/Billing.Api/Billing.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app .
USER $APP_UID                 # the .NET images include a non-root user
EXPOSE 8080                   # .NET images listen on 8080 by default
ENTRYPOINT ["dotnet", "Billing.Api.dll"]
```

- **Multi-stage:** build with the big SDK image, run on the small runtime image.
- **`.dockerignore`:** exclude `bin/`, `obj/`, `.git/`, `tests/`, secrets. A smaller context builds faster and can't leak files.
- **Non-root:** never run as root in production.
- A solution with project references needs the **referenced projects' `.csproj` files** copied before `restore` too.

### Compose essentials

```yaml
services:
  app-db:
    image: postgres:17
    environment: { POSTGRES_PASSWORD: example }
    volumes: [db-data:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      retries: 10
    profiles: [infra]

  app:
    build: { context: ., dockerfile: src/App/Dockerfile }
    environment:
      ConnectionStrings__AppDb: "Host=app-db;Password=example"   # __ = : in .NET configuration
    depends_on:
      app-db: { condition: service_healthy }                       # wait until healthy, not just started
    ports: ["5000:8080"]
    profiles: [apps]

volumes:
  db-data:
```

**Profiles** let you start only part of the system: `--profile infra` for databases while you debug the APIs from your IDE; `--profile infra --profile apps` for everything.

### Initializing databases in containers

| Database | How |
| --- | --- |
| MongoDB | Any `*.js` in `/docker-entrypoint-initdb.d/` runs on the **first** start |
| Oracle (`gvenzl/oracle-free`) | Scripts in `/container-entrypoint-initdb.d/` run on first start; `APP_USER` creates your schema user |
| SQL Server | No init folder: run EF migrations at startup (only outside Production) or a one-shot container with `sqlcmd` |

---

## Build

### Files

```text
src/Orders/ShopFlow.Orders.Api/Dockerfile
src/Catalog/ShopFlow.Catalog.Api/Dockerfile
src/Inventory/ShopFlow.Inventory.Api/Dockerfile
.dockerignore
deploy/docker-compose.yml
deploy/.env.example        (copy to .env, which is git-ignored)
```

### Services in `deploy/docker-compose.yml`

| Service | Image / build | Profile | Notes |
| --- | --- | --- | --- |
| `orders-db` | `mcr.microsoft.com/mssql/server:2022-latest` | `infra` | Volume, health check |
| `inventory-db` | `gvenzl/oracle-free` | `infra` | `APP_USER`, mount `database/oracle/*.sql` into the init folder; health check |
| `catalog-db` | `mongo:8` | `infra` | Mount `database/mongo/*.js` into the init folder |
| `servicebus` + its SQL | From the emulator's official compose file | `infra` | Mount `deploy/servicebus/Config.json` |
| `azurite` | `mcr.microsoft.com/azure-storage/azurite` | `infra` | Used by Functions in topic 16 |
| `otel-dashboard` | `mcr.microsoft.com/dotnet/aspire-dashboard` | `infra` | Optional, from topic 12 |
| `orders-api` | Build | `apps` | Port 5102 → 8080 |
| `catalog-api` | Build | `apps` | Port 5101 → 8080 |
| `inventory-api` | Build | `apps` | Port 5103 → 8080 |

### Tasks

- [ ] ⭐ Write the three Dockerfiles: multi-stage, restore layer cached, non-root, port 8080. Remember the referenced projects (`ServiceDefaults`, `Contracts`, `Messaging`, and Orders' four layers).
- [ ] ⭐ Write `.dockerignore`.
- [ ] Build each image by hand once and compare sizes with `docker images`. Write the numbers in your PR.
- [ ] ⭐ Write `deploy/docker-compose.yml` with the services in the table:
  - Every database has a **health check** and a **named volume**; APIs use `depends_on` with `condition: service_healthy`.
  - Secrets come from `deploy/.env` (`${ORDERS_DB_PASSWORD}`), never written in the YAML. Commit only `.env.example`.
  - APIs get connection strings and settings through environment variables with `__`. Inside the network they use service names (`Server=orders-db,1433;…`, `mongodb://catalog-db:27017`, `inventory-db:1521/FREEPDB1`).
  - `ASPNETCORE_ENVIRONMENT=Development` so the dev token endpoint and OpenAPI are available.
- [ ] ⭐ Orders.Api: apply EF Core migrations at startup **only** when a setting `Database:MigrateOnStartup` is `true` (true in compose, false in Azure). Then seed if the `Customers` table is empty. Write two lines on why this is risky in production with several instances.
- [ ] Mount your Oracle and MongoDB scripts so a fresh `docker compose up` creates both databases with data.
- [ ] Check the APIs from your machine: `docker compose ps` lists them as running, and `curl localhost:5102/health` returns `Healthy`. (The .NET runtime images don't include `curl`, which is one reason compose health checks for .NET containers are usually skipped or done differently.)
- [ ] Write `deploy/README.md`: how to start infra only, everything, how to reset (`down -v`), and the memory each part needs.

---

## Check yourself

- From a fresh clone with only Docker installed: `cp deploy/.env.example deploy/.env`, then `docker compose -f deploy/docker-compose.yml --profile infra --profile apps up -d --build`, wait, and run the topic 12 checks against ports 5101–5103. They pass.
- `docker compose down` then `up` again: data is still there (volumes). `down -v`: fresh databases.
- `docker exec -it <orders-api container> whoami` doesn't print `root`.

---

## Interview questions

1. Image vs container? Container vs virtual machine?
2. Why multi-stage builds?
3. How does the layer cache work, and how do you order a Dockerfile for it?
4. How do containers in Compose find each other?
5. What's a volume for? What happens to data without one?
6. `depends_on` vs health checks: what does each guarantee?
7. How do you pass configuration and secrets to a container?
8. Why run containers as a non-root user?

Answers: [interview question bank](99-interview-questions.md#14--docker-and-docker-compose).

---

## Done when

- [ ] One command starts the whole system, and the saga works inside Docker.
- [ ] No secret is committed.
- [ ] Pull request into `develop` merged.
