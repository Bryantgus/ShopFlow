# 18 — Kubernetes

> **Time:** 3 h · **Job requirement:** Kubernetes · **Builds on:** 12, 14 · **Branch:** `feature/18-kubernetes`

## Why it matters

Kubernetes is desirable in the post, so the goal is to explain the core objects and show that you've run your own services on a cluster: probes, scaling, rolling updates and rollback. You'll run the three ShopFlow APIs on a **local** cluster and keep the databases in Docker Compose, which is also how many teams work in development.

---

## Learn

### Why Kubernetes

Docker runs containers on one machine. Kubernetes runs them on a **cluster** of machines and keeps them in the state you declare: it restarts crashed containers, spreads them across nodes, scales them, balances traffic and replaces them gradually during updates. You describe the desired state in YAML; Kubernetes makes reality match it.

### Core objects

| Object | What it does |
| --- | --- |
| Pod | Smallest unit: one or more containers sharing network and storage |
| Deployment | Keeps N replicas of a pod running; rolling updates and rollback |
| ReplicaSet | Created by a Deployment; ensures the replica count |
| Service | Stable name and IP for a group of pods (`ClusterIP` internal, `NodePort`, `LoadBalancer`) |
| Ingress | HTTP routing from outside to Services by host or path (needs an ingress controller) |
| ConfigMap / Secret | Configuration / sensitive values given to pods as env vars or files |
| Namespace | Logical separation inside a cluster |
| StatefulSet | Like a Deployment, but with stable identities and storage per pod (databases) |
| PersistentVolumeClaim | A request for storage |
| HorizontalPodAutoscaler | Changes the replica count based on CPU, memory or custom metrics |
| Job / CronJob | Run-to-completion work / on a schedule |

### Probes

| Probe | Question | If it fails |
| --- | --- | --- |
| Liveness | Is the process stuck? | Restart the container |
| Readiness | Can it take traffic right now? | Remove it from the Service until it's ready |
| Startup | Has it finished starting? | Hold the other probes until it passes |

In ASP.NET Core, split health checks with tags: a **live** endpoint that checks only the process, and a **ready** endpoint that also checks the database and Service Bus. A database outage shouldn't make Kubernetes restart every pod in a loop.

### Resources

`requests` = what the scheduler reserves for the pod; `limits` = the maximum it may use. A container over its memory limit is killed (`OOMKilled`).

### kubectl

| Command | Does |
| --- | --- |
| `kubectl apply -f deploy/k8s/` | Create or update everything in the folder |
| `kubectl get pods,svc,deploy -n shopflow` | List objects |
| `kubectl describe pod <name> -n shopflow` | Details and **events**: start here when something fails |
| `kubectl logs -f <pod> -n shopflow` | Container logs |
| `kubectl port-forward svc/orders-api 5102:80 -n shopflow` | Reach a service from your machine |
| `kubectl scale deploy/orders-api --replicas=3 -n shopflow` | Scale by hand |
| `kubectl set image deploy/orders-api orders-api=<image>:<tag>` | Trigger a rolling update |
| `kubectl rollout status` / `rollout history` / `rollout undo deploy/orders-api` | Follow / list / roll back an update |

### In Azure

**AKS** is managed Kubernetes. **Azure Container Apps** runs containers on Kubernetes without you managing the cluster (scale to zero, KEDA autoscaling on Service Bus messages, Dapr), a common middle ground between App Service and AKS.

---

## Build: `deploy/k8s/`

Use the Kubernetes in **Docker Desktop**, **kind** or **minikube**. The databases, Service Bus emulator and Azurite keep running in Compose (`--profile infra`); pods reach them through `host.docker.internal` (Docker Desktop) or your machine's IP.

### Files

```text
deploy/k8s/
├── 00-namespace.yaml
├── 01-configmap.yaml          non-secret settings shared by the APIs
├── 02-secrets.example.yaml    template only; create the real Secret with kubectl, never commit it
├── catalog-api.yaml           Deployment + Service
├── orders-api.yaml            Deployment + Service
├── inventory-api.yaml         Deployment + Service
├── ingress.yaml
└── hpa-orders.yaml
```

### Tasks

- [ ] ⭐ In `ShopFlow.ServiceDefaults`, split health checks: `/health/live` (no dependencies) and `/health/ready` (databases + Service Bus). Keep `/health` working for App Service.
- [ ] ⭐ Namespace `shopflow`; a ConfigMap with the non-secret settings (base URLs between services use Kubernetes service names: `http://catalog-api`); a Secret with connection strings and the JWT key, created with `kubectl create secret generic shopflow-secrets --from-env-file=…`.
- [ ] ⭐ One Deployment + `ClusterIP` Service per API:
  - 2 replicas; image from your local build (with kind: `kind load docker-image …`) or from ACR.
  - `envFrom` the ConfigMap and the Secret.
  - Startup, readiness and liveness probes on the right endpoints.
  - `requests` and `limits` for CPU and memory.
  - Labels `app` and `version`.
- [ ] ⭐ Install an ingress controller (ingress-nginx) and write `ingress.yaml` routing `/catalog`, `/orders`, `/inventory` to the three Services (with path rewriting, or by setting a path base in the APIs; pick one and explain it).
- [ ] Install `metrics-server` and add an HPA for Orders: 2–5 replicas at 70 % CPU. Generate load (a loop of requests, or a tool like `hey`/`k6`) and watch it scale with `kubectl get hpa -w`.
- [ ] ⭐ Rolling update: change something visible (e.g. a version field in `/health`), build a new tag, `kubectl set image`, watch `rollout status`, then `rollout undo` and confirm the old version is back.
- [ ] Kill a pod with `kubectl delete pod …` while sending requests: the Deployment replaces it and requests keep working.
- [ ] Think about the outbox publisher: with 2+ Orders replicas, every replica runs it. Write what that means (duplicates? locks?) and how your consumers already handle it (topic 12).
- [ ] Bonus: run MongoDB inside the cluster as a **StatefulSet** with a PersistentVolumeClaim, and explain why databases use StatefulSets and not Deployments.

### Finish the project: release 1.0.0

- [ ] ⭐ Git Flow: create `release/1.0.0` from `develop`, set `<Version>1.0.0</Version>`, update the project README (architecture, how to run locally, Compose, Kubernetes, Azure, tests, CI badge, what you'd do next), merge into `main`, tag `v1.0.0`, merge back into `develop`.
- [ ] Pin the repository on your GitHub profile and add it to your CV and LinkedIn as a project, with one sentence listing the stack.

---

## Check yourself

- `kubectl get pods -n shopflow` shows 6 pods `Running` and `READY 1/1`.
- Through the ingress, the full saga works (place → confirmed → availability updated).
- Stopping SQL Server makes Orders pods **not ready** (out of the Service) but **not restarted**; starting it again brings them back.
- `rollout undo` restores the previous version without downtime.

---

## Interview questions

1. Why Kubernetes, if you already have Docker?
2. Pod vs Deployment vs Service vs Ingress?
3. Liveness vs readiness vs startup probes? What goes wrong if a liveness probe checks the database?
4. ConfigMap vs Secret? Are Secrets encrypted?
5. How does a rolling update work? How do you roll back?
6. Requests vs limits? What is `OOMKilled`?
7. Deployment vs StatefulSet?
8. AKS vs Azure Container Apps vs App Service?

Answers: [interview question bank](99-interview-questions.md#18--kubernetes).

---

## Done when

- [ ] The three APIs run on a local cluster behind an ingress.
- [ ] `v1.0.0` is tagged on `main`.
- [ ] You can explain the whole ShopFlow architecture, from the client to the three databases, in 2 minutes in English.
