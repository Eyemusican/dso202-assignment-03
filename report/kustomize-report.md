# DSO202 Assignment 3 Report: Kustomize

This report covers Part A of Assignment 3, where I deployed my Assignment 1 Task Tracker app with Kustomize, following the Unit 4 Kustomize notes (concepts, and patches and generators). I kept the Assignment 1 manifests in one base and wrote two thin overlays, dev and prod, that only describe what is different. For every overlay I followed the same order from the notes: render first, diff, apply, verify, and delete when done. The environment check and the images check are in the README.

## The base

I copied every Assignment 1 manifest into `kustomize/base` and removed the hardcoded namespace lines, so the base works for any environment. Instead of copying `configmap.yaml` and `secret.yaml`, I used `configMapGenerator` and `secretGenerator` with two env files. Kustomize adds a hash of the content to each generated name and rewrites every `configMapKeyRef` and `secretKeyRef` in the Deployments to match, which shows in the render below. I also gave the database Deployment `strategy: Recreate`, because a normal rolling update would start a second PostgreSQL Pod on the same data folder before the old one stops.

![Base render with hashed names and rewritten references](../evidence/assignment3-02-base-render-hash-references.png)

## Dev overlay

The dev overlay pulls in the base with `resources: ../../base` and only adds what is different for dev: its own namespace, environment labels and replica counts. I added the labels with `includeSelectors: false`, so the selectors stay exactly as they were in Assignment 1.

![Dev overlay render, every object in the dev namespace](../evidence/assignment3-03-dev-overlay-render.png)
![Selectors unchanged](../evidence/assignment3-04-dev-selectors-unchanged.png)

I did not use `namePrefix`. It would rename `db-svc` to `dev-db-svc`, while the ConfigMap still says `DB_HOST=db-svc`. Kustomize rewrites name references in fields like `configMapKeyRef`, but not plain text inside ConfigMap data, so the backend would lose its database. Separate namespaces give the isolation instead.

Before applying I rendered and diffed. The first diff failed because the dev namespace did not exist yet, so I created it from the overlay's own `namespace.yaml` and ran the diff again.

![Diff failed, namespace not found](../evidence/assignment3-06-diff-namespace-not-found.png)
![Diff preview of all 12 objects](../evidence/assignment3-07-dev-diff-preview.png)

Then I applied the whole overlay with one command and checked everything it created.

![Apply](../evidence/assignment3-08-dev-apply.png)
![Pods running](../evidence/assignment3-09-dev-pods-running.png)
![All resources, PVC bound, quota counting](../evidence/assignment3-10-dev-all-resources.png)
![Backend connected to the database](../evidence/assignment3-11-dev-backend-connected.png)

The backend retried a few times while PostgreSQL was still starting, then connected. I tested the API with `curl` through a port forward, then the real page in the browser on NodePort 30080, and added a task from the page.

![API create and list working](../evidence/assignment3-12-dev-api-crud-working.png)
![Frontend loaded](../evidence/assignment3-13-dev-frontend-loaded.png)
![Task added from the browser](../evidence/assignment3-14-dev-frontend-task-added.png)

## Generated name hash and rollout

To see the hash in action, I changed one setting only in dev: `CORS_ORIGIN` from `*` to `http://localhost:30080`, using `behavior: merge` in the dev overlay. The ConfigMap got a new hash, all 7 references in the three Deployments changed with it, and because their Pod templates changed, all three Deployments replaced their Pods on their own.

![Before](../evidence/assignment3-15-hash-before.png)
![New hash in the render](../evidence/assignment3-16-hash-changed-render.png)
![Diff shows the 7 references changing](../evidence/assignment3-17-hash-diff.png)
![Rollout](../evidence/assignment3-18-hash-rollout.png)
![After: new Pods with the new value](../evidence/assignment3-19-hash-after.png)

After the rollout the page showed backend unreachable. The backend itself was running, but my port forward had stopped, because it was attached to the old backend Pod that the rollout deleted. Restarting the port forward fixed it, and all 5 tasks were still there because the data lives on the PVC, not in the Pod.

![Port forward lost after the rollout](../evidence/assignment3-20-port-forward-lost-after-rollout.png)
![Working again with the data kept](../evidence/assignment3-21-dev-app-after-rollout.png)

## Prod overlay

Prod uses the same base, with these differences:

| Change | Kustomize feature |
| --- | --- |
| 2 backend and 2 frontend replicas | `replicas` transformer |
| Bigger backend CPU and memory | strategic merge patch |
| Bigger ResourceQuota | strategic merge patch |
| Frontend Service becomes ClusterIP, `nodePort` removed | JSON 6902 patch from a file |
| Owner annotation on every Deployment | inline JSON 6902 patch, with `~1` for the `/` in the key |

The quota patch was needed: prod needs 1700m of CPU limits, over the Assignment 1 ceiling of 1500m, and its memory is exactly at the ceiling with no room for rollouts. NodePort 30080 is already used by dev, so prod's frontend stays internal.

![Prod render](../evidence/assignment3-22-prod-overlay-render.png)
![Prod diff](../evidence/assignment3-23-prod-diff-preview.png)
![Prod applied, 5 Pods](../evidence/assignment3-24-prod-apply-pods.png)
![Replicas, strategic merge patches](../evidence/assignment3-25-prod-patches-replicas-resources-quota.png)
![JSON 6902 patches](../evidence/assignment3-26-prod-patches-json6902.png)

I opened prod through two port forwards. It only had the 3 seed tasks, which shows it has its own database, separate from dev.

![Prod frontend](../evidence/assignment3-27-prod-frontend-loaded.png)
![Task added in prod](../evidence/assignment3-28-prod-frontend-task-added.png)

## Both environments and cleanup

![Dev and prod running together from one base](../evidence/assignment3-29-dev-and-prod-side-by-side.png)

`kubectl delete -k` removed everything each overlay builds, including its namespace. The old dev ConfigMap left over from the hash change was not in the current build, so `delete -k` did not list it, but it was still removed together with the namespace.

![Dev deleted](../evidence/assignment3-30-dev-delete.png)
![Prod deleted, nothing left](../evidence/assignment3-31-prod-delete-and-cleanup-confirmed.png)


## Problems I ran into and how I solved them

**`kubectl diff -k` failed with namespace not found.** The diff is a dry run, so the dev namespace in my overlay was never actually created, and every other object pointed at a namespace that did not exist yet. I created only the namespace first, from the overlay's own `namespace.yaml`, and then the diff worked. A real `apply -k` does not have this problem, because it creates the namespace first.

**`namePrefix` would have broken the database connection.** The notes show `namePrefix: dev-`, but that would rename `db-svc` to `dev-db-svc` while `DB_HOST` in the ConfigMap stays `db-svc`. Kustomize does not change text inside ConfigMap data, so I left `namePrefix` out and used a separate namespace for each environment instead.

**Only one Service can use NodePort 30080.** My kind cluster only maps port 30080 to my laptop, and dev already uses it. I used a JSON 6902 patch in prod to change the frontend Service to ClusterIP and remove the `nodePort` field.

**A rolling update would start two PostgreSQL servers on one volume.** When the ConfigMap hash changes, the database Deployment rolls out too, and by default the new Pod starts before the old one stops. I set `strategy: Recreate` on the database in the base, so the old Pod stops first.

**Prod did not fit in the Assignment 1 quota.** With 2 backend and 2 frontend replicas and bigger backend resources, prod needs 1700m of CPU limits against a ceiling of 1500m, and its memory sits exactly at the ceiling. I added a strategic merge patch that raises the quota for prod only, and the live quota showed exactly the usage I had calculated.

**The page showed backend unreachable after the hash rollout.** The backend was running, but my port forward had stopped, because a port forward attaches to one Pod and the rollout deleted that Pod. I restarted it and the page came back with all the data.

**The old ConfigMap was left behind after the hash change.** `kubectl apply` does not delete objects that are no longer in the build, so the old `task-tracker-config-5hbggdmfm7` stayed in dev, unused. `kubectl delete -k` did not list it either, because it only deletes what the overlay builds now. It was still removed, because deleting the namespace removes everything inside it, which is one reason I kept the Namespace inside each overlay.

## What I learned

The base stores what is shared and the overlays store what is different, so a change like the database strategy was made once and reached both environments. Rendering before applying showed me exactly what would reach the cluster, and the generated name hash meant a config change rolled out new Pods without me restarting anything. Strategic merge patches were easier to read for Kubernetes shaped changes like resources and quota, while JSON 6902 was the right tool for removing one exact field.
