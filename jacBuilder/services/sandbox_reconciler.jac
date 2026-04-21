"""Sandbox Reconciler — Background loop that reconciles desired vs actual K8s state.

Runs as a background thread on every jac-builder pod. Every pod runs the
full reconcile cycle independently — safe because all K8s operations are
idempotent and state is read fresh from K8s API each cycle (no in-memory state).

Active reconciliation (K8s-only, no graph access):
  - TTL enforcement: deletes active pods older than configured TTL
  - CrashLoopBackOff detection: deletes pods stuck in crash loops
  - Terminal pod cleanup: deletes Failed/Succeeded pods
  - Duplicate detection: keeps only newest pod per (user, project)
  - Warm pool maintenance: ensures target warm pod count
  - Full resource cleanup: pod + service + configmap + ingress route
"""

import os;
import time;
import logging;
import from typing { Any }
import from threading { Thread, Event }

glob logger: logging.Logger = logging.getLogger("reconciler");

glob _MY_POD: str = os.environ.get("HOSTNAME", os.environ.get("POD_NAME", "local"));
glob _RECONCILE_INTERVAL: int = 120;
glob _stop_event: Event = Event();

# ---------------------------------------------------------------------------
# Leader Election (via ReconcilerLease graph node)
# ---------------------------------------------------------------------------

"""Attempt to acquire or renew the reconciler leader lease.
Returns True if this pod is the leader."""
def try_acquire_lease(here: Any, all_leases: list) -> bool {
    now = time.time();

    lease: Any = None;
    for l in all_leases {
        lease = l;
        break;
    }

    if lease is None {
        # No lease exists — caller walker must create one
        return True;
    }

    if lease.holder == _MY_POD {
        lease.expires_at = now + _LEADER_LEASE_TTL;
        return True;
    }
    if lease.expires_at < now {
        lease.holder = _MY_POD;
        lease.expires_at = now + _LEADER_LEASE_TTL;
        return True;
    }
    return False;
}

# ---------------------------------------------------------------------------
# Reconciliation Phases
# ---------------------------------------------------------------------------

"""Phase 1: Create K8s resources for pending sandboxes owned by this pod."""
def reconcile_pending_creations(instances: list, backend: Any) -> int {
    import from services.ideServer { SandboxInstance }
    cnt: int = 0;
    for raw in instances {
        inst: SandboxInstance = raw;
        if inst.desired_state == "running" and inst.observed_state == "pending" and inst.owner_pod == _MY_POD {
            logger.info(f"Creating K8s resources for sid={inst.sandbox_id}");
            inst.observed_state = "creating";
            try {
                result = backend.create(inst.user_id, inst.project_id, inst.staging_dir);
                if result.is_successful() {
                    inst.observed_state = "starting";
                    inst.pod_name = result.sandbox_id;
                    inst.configmap_name = f"{result.sandbox_id}-code";
                    inst.service_name = f"{result.sandbox_id}-svc";
                    if result.url {
                        inst.url = result.url;
                    }
                    if result.port {
                        inst.port = result.port;
                    }
                    inst.version = int(getattr(inst, "version", 0)) + 1;
                    cnt = int(cnt) + 1;
                    logger.info(f"K8s create succeeded for sid={inst.sandbox_id}");
                } else {
                    inst.observed_state = "error";
                    inst.error_message = result.message or "K8s create failed";
                    logger.error(f"K8s create failed for sid={inst.sandbox_id}: {inst.error_message}");
                }
            } except Exception as e {
                inst.observed_state = "error";
                inst.error_message = str(e);
                logger.error(f"Exception creating sid={inst.sandbox_id}: {e}");
            }
        }
    }
    return cnt;
}

"""Phase 2: Check if starting sandboxes have become ready.
Queries K8s directly via pod labels — does NOT use backend._registry."""
def reconcile_readiness(instances: list, backend: Any) -> int {
    import from services.ideServer { SandboxInstance }
    cnt: int = 0;

    # Build sandbox_id → pod status map from K8s directly
    pod_phases: dict = {};
    try {
        backend._init_k8s();
        import from kubernetes { client }
        core_v1 = client.CoreV1Api();
        namespace = os.environ.get("SANDBOX_NAMESPACE", "jac-sandboxes");
        all_pods = core_v1.list_namespaced_pod(namespace, label_selector="jac-sandbox=true");
        for pod in all_pods.items {
            labels = pod.metadata.labels or {};
            pod_sid = labels.get("jac-sandbox-id", "");
            phase = str(pod.status.phase) if pod.status else "Unknown";
            ready = True;
            if phase == "Running" and pod.status.container_statuses {
                for cs in pod.status.container_statuses {
                    if not cs.ready {
                        ready = False;
                        break;
                    }
                }
            }
            if pod_sid {
                pod_phases[pod_sid] = {"phase": phase, "ready": ready, "pod_name": pod.metadata.name};
            }
        }
    } except Exception as e {
        logger.error(f"K8s pod list failed in readiness check: {e}");
        return 0;
    }

    for raw in instances {
        inst: SandboxInstance = raw;
        if inst.observed_state in ("starting", "creating") and inst.desired_state == "running" {
            sid = str(inst.sandbox_id);
            pod_info = pod_phases.get(sid);
            if pod_info is None {
                # Pod not found — don't immediately error, it may still be scheduling
                x = 0;
            } elif pod_info["phase"] == "Running" and pod_info["ready"] {
                inst.observed_state = "running";
                if not inst.pod_name {
                    inst.pod_name = str(pod_info["pod_name"]);
                }
                inst.version = int(getattr(inst, "version", 0)) + 1;
                cnt = int(cnt) + 1;
                logger.info(f"Sandbox ready: sid={sid} pod={pod_info['pod_name']}");
            } elif pod_info["phase"] in ("Failed", "Succeeded") {
                inst.observed_state = "error";
                inst.error_message = f"Pod phase: {pod_info['phase']}";
                logger.warning(f"Sandbox failed: sid={sid} phase={pod_info['phase']}");
            }
        }
    }
    return cnt;
}

"""Phase 3: Clean up K8s resources for sandboxes that should be stopped/destroyed."""
def reconcile_stops_and_destroys(instances: list, backend: Any) -> int {
    import from services.ideServer { SandboxInstance }
    cnt: int = 0;
    for raw in instances {
        inst: SandboxInstance = raw;
        should_cleanup = False;
        if inst.desired_state == "stopped" and inst.observed_state in ("running", "starting", "creating", "error") {
            should_cleanup = True;
        }
        if inst.desired_state == "destroyed" and inst.observed_state != "stopped" and inst.observed_state != "destroyed" {
            should_cleanup = True;
        }
        if should_cleanup {
            logger.info(f"Cleaning up K8s resources for sid={inst.sandbox_id} desired={inst.desired_state}");
            try {
                namespace = inst.namespace or os.environ.get("SANDBOX_NAMESPACE", "jac-sandboxes");
                backend._init_k8s();
                cleanup_sandbox_resources(backend, inst.sandbox_id, inst.pod_name, namespace, inst.warm_start);
                inst.observed_state = "stopped";
                inst.version = int(inst.version) + 1;
                cnt = int(cnt) + 1;
                logger.info(f"Cleanup done for sid={inst.sandbox_id}");
            } except Exception as e {
                logger.error(f"Cleanup error for sid={inst.sandbox_id}: {e}");
                inst.observed_state = "stopped";
            }

            if inst.purpose == "deploy" and inst.staging_dir {
                if inst.staging_dir.startswith("/tmp/") and os.path.exists(inst.staging_dir) {
                    import shutil;
                    shutil.rmtree(inst.staging_dir, ignore_errors=True);
                }
            }
        }
    }
    return cnt;
}

"""Phase 4 (leader-only): Detect and fix drift between graph state and K8s."""
def reconcile_drift(instances: list, backend: Any) -> int {
    import from services.ideServer { SandboxInstance }
    cnt: int = 0;
    try {
        backend._init_k8s();
        import from kubernetes { client }
        core_v1 = client.CoreV1Api();
        namespace = os.environ.get("SANDBOX_NAMESPACE", "jac-sandboxes");

        pods = core_v1.list_namespaced_pod(namespace, label_selector="jac-sandbox=true");

        known_sids: set = set();
        sid_to_inst: dict = {};
        for raw in instances {
            inst: SandboxInstance = raw;
            if inst.desired_state != "destroyed" {
                known_sids.add(inst.sandbox_id);
                known_sids.add(inst.pod_name or inst.sandbox_id);
                sid_to_inst[inst.sandbox_id] = inst;
            }
        }

        for pod in pods.items {
            pod_name = pod.metadata.name;
            pod_labels = pod.metadata.labels or {};
            pod_sid = pod_labels.get("jac-sandbox-id", pod_name);

            if pod_labels.get("jac-sandbox-pool") == "warm" {
                continue;
            }

            if pod_sid not in known_sids and pod_name not in known_sids {
                logger.info(f"Deleting orphan pod: {pod_name} (no graph node)");
                try {
                    core_v1.delete_namespaced_pod(pod_name, namespace);
                    cnt = int(cnt) + 1;
                } except Exception as e {
                    logger.error(f"Failed to delete orphan pod {pod_name}: {e}");
                }
            } elif pod_sid in sid_to_inst {
                drift_inst: SandboxInstance = sid_to_inst[pod_sid];
                phase = str(pod.status.phase) if pod.status else "Unknown";
                if phase in ("Failed", "Succeeded") and drift_inst.observed_state in ("running", "starting") {
                    logger.warning(f"Pod {pod_name} is {phase} but graph says {drift_inst.observed_state}, updating");
                    drift_inst.observed_state = "error";
                    drift_inst.error_message = f"Pod entered {phase} state";
                    drift_inst.version = int(drift_inst.version) + 1;
                    cnt = int(cnt) + 1;
                }
            }
        }
    } except Exception as e {
        logger.error(f"Drift detection error: {e}");
    }
    return cnt;
}

"""Phase 5 (leader-only): Enforce TTL on expired sandboxes."""
def reconcile_ttl(instances: list) -> int {
    import from services.ideServer { SandboxInstance }
    cnt: int = 0;
    now = time.time();
    for raw in instances {
        inst: SandboxInstance = raw;
        if inst.desired_state != "destroyed" and inst.ttl_seconds > 0 {
            age = now - inst.created_at;
            if age > inst.ttl_seconds {
                logger.info(f"TTL expired for sid={inst.sandbox_id} age={int(age)}s ttl={inst.ttl_seconds}s");
                inst.desired_state = "destroyed";
                inst.version = int(inst.version) + 1;
                cnt = int(cnt) + 1;
            }
        }
    }
    return cnt;
}

"""Phase 6 (leader-only): Ensure warm pool is at target size."""
def reconcile_warm_pool(backend: Any) -> int {
    cnt: int = 0;
    try {
        if not hasattr(backend, "config") or backend.config.warm_pool_size <= 0 {
            return 0;
        }
        target = backend.config.warm_pool_size;
        backend._init_k8s();
        import from kubernetes { client }
        core_v1 = client.CoreV1Api();
        namespace = backend.config.namespace;
        warm_pods = core_v1.list_namespaced_pod(
            namespace,
            label_selector="jac-sandbox-pool=warm"
        );
        current = len(warm_pods.items);

        deficit = target - current;
        if deficit > 0 {
            logger.info(f"Warm pool: {current}/{target}, creating {deficit} pods");
            for _ in range(deficit) {
                try {
                    if hasattr(backend, "_create_warm_pod") {
                        backend._create_warm_pod();
                        cnt = int(cnt) + 1;
                    }
                } except Exception as e {
                    logger.error(f"Warm pod creation failed: {e}");
                    break;
                }
            }
        }
    } except Exception as e {
        logger.error(f"Warm pool reconciliation error: {e}");
    }
    return cnt;
}

# ---------------------------------------------------------------------------
# K8s-only drift detection (no graph nodes needed)
# ---------------------------------------------------------------------------

"""Detect and clean up orphaned/expired sandbox pods using K8s labels only.
No graph node access needed — uses pod creation timestamp and TTL config.

Handles: TTL expiry, CrashLoopBackOff, terminal pods, and per-user duplicates."""
def reconcile_drift_k8s_only(backend: Any) -> int {
    cnt: int = 0;
    try {
        backend._init_k8s();
        import from kubernetes { client }
        import from kubernetes.client.exceptions { ApiException }
        core_v1 = client.CoreV1Api();
        namespace = os.environ.get("SANDBOX_NAMESPACE", "jac-sandboxes");

        # List ALL sandbox pods (warm + active) so we can handle each case
        all_pods = core_v1.list_namespaced_pod(namespace, label_selector="jac-sandbox=true");
        now = time.time();

        # Read TTL from jac.toml [plugins.scale.sandbox] config
        import from services.sandbox_store { _get_sandbox_config }
        sandbox_cfg = _get_sandbox_config();
        ttl = int(sandbox_cfg.get("ttl_seconds", 0));
        if ttl <= 0 and hasattr(backend, "config") and backend.config.ttl_seconds > 0 {
            ttl = backend.config.ttl_seconds;
        }
        if ttl <= 0 {
            logger.warning("No TTL configured in jac.toml [plugins.scale.sandbox].ttl_seconds, skipping TTL enforcement");
            return 0;
        }

        # Track active pods per (user, project) for duplicate detection
        user_project_pods: dict = {};
        pods_to_delete: list = [];

        for pod in all_pods.items {
            pod_name = pod.metadata.name;
            labels = pod.metadata.labels or {};
            pool = str(labels.get("jac-sandbox-pool", ""));
            pod_sid = str(labels.get("jac-sandbox-id", ""));
            phase = str(pod.status.phase) if pod.status else "Unknown";

            # Calculate pod age from creation timestamp
            pod_age: float = 0.0;
            if pod.metadata.creation_timestamp {
                import from datetime { timezone }
                created_ts = pod.metadata.creation_timestamp.timestamp();
                pod_age = now - created_ts;
            }

            # --- Check 1: Terminal pods (any pool) ---
            if phase in ("Failed", "Succeeded") {
                logger.info(f"Deleting terminal pod: {pod_name} phase={phase} age={int(pod_age)}s");
                pods_to_delete.append({"pod_name": pod_name, "sandbox_id": pod_sid, "warm_start": pool == "warm"});
                continue;
            }

            # --- Check 2: CrashLoopBackOff detection (any pool) ---
            is_crash_loop = False;
            if pod.status and pod.status.container_statuses {
                for cs in pod.status.container_statuses {
                    waiting = cs.state.waiting if cs.state else None;
                    if waiting and str(waiting.reason) == "CrashLoopBackOff" and cs.restart_count > 5 {
                        is_crash_loop = True;
                        logger.warning(f"Deleting CrashLoopBackOff pod: {pod_name} restarts={cs.restart_count} age={int(pod_age)}s");
                        break;
                    }
                }
            }
            if is_crash_loop {
                pods_to_delete.append({"pod_name": pod_name, "sandbox_id": pod_sid, "warm_start": pool == "warm"});
                continue;
            }

            # --- Check 3: TTL enforcement for active pods only ---
            if pool == "active" and pod_age > ttl {
                logger.info(f"TTL expired for pod: {pod_name} sid={pod_sid} age={int(pod_age)}s ttl={ttl}s");
                pods_to_delete.append({"pod_name": pod_name, "sandbox_id": pod_sid, "warm_start": False});
                continue;
            }

            # --- Track active pods for duplicate detection ---
            if pool == "active" {
                user_id = str(labels.get("jac-sandbox-user", ""));
                project_id = str(labels.get("jac-sandbox-project", ""));
                if user_id and project_id {
                    key = f"{user_id}:{project_id}";
                    if key not in user_project_pods {
                        user_project_pods[key] = [];
                    }
                    user_project_pods[key].append({
                        "pod_name": pod_name,
                        "sandbox_id": pod_sid,
                        "created_ts": pod.metadata.creation_timestamp.timestamp() if pod.metadata.creation_timestamp else 0.0
                    });
                }
            }
        }

        # --- Check 4: Per-user/project duplicate detection ---
        # Keep only the newest pod for each (user, project) pair
        for key in user_project_pods {
            pods_list: list = user_project_pods[key];
            if len(pods_list) > 1 {
                # Sort by created_ts descending (newest first)
                sorted_pods = sorted(pods_list, key=lambda p: p["created_ts"], reverse=True);
                # Delete all except the newest
                for i in range(1, len(sorted_pods)) {
                    dup = sorted_pods[i];
                    logger.info(f"Deleting duplicate pod: {dup['pod_name']} sid={dup['sandbox_id']} (newer exists for same user/project)");
                    pods_to_delete.append({"pod_name": dup["pod_name"], "sandbox_id": dup["sandbox_id"], "warm_start": False});
                }
            }
        }

        # --- Execute deletions with full resource cleanup ---
        for entry in pods_to_delete {
            try {
                cleanup_sandbox_resources(backend, str(entry["sandbox_id"]), str(entry["pod_name"]), namespace, bool(entry["warm_start"]));
                cnt = int(cnt) + 1;
            } except Exception as e {
                logger.error(f"Failed to cleanup {entry['pod_name']}: {e}");
                # Fallback: try to at least delete the pod directly
                try {
                    core_v1.delete_namespaced_pod(str(entry["pod_name"]), namespace);
                    cnt = int(cnt) + 1;
                } except Exception {
                    x = 0;
                }
            }
        }

        if cnt > 0 {
            logger.info(f"K8s cleanup cycle: deleted {cnt} pods");
        }
    } except Exception as e {
        logger.error(f"K8s drift detection error: {e}");
    }
    return cnt;
}

# ---------------------------------------------------------------------------
# Cleanup destroyed nodes from graph
# ---------------------------------------------------------------------------

"""Mark destroyed+stopped SandboxInstance nodes for cleanup.
Returns list of sandbox_ids that the caller (walker) should disconnect from graph."""
def find_destroyed_nodes(instances: list) -> list {
    import from services.ideServer { SandboxInstance }
    to_remove: list = [];
    for raw in instances {
        inst: SandboxInstance = raw;
        if inst.desired_state == "destroyed" and inst.observed_state in ("stopped", "destroyed") {
            to_remove.append(inst);
        }
    }
    return to_remove;
}

# ---------------------------------------------------------------------------
# K8s Resource Cleanup (stateless, doesn't depend on backend registry)
# ---------------------------------------------------------------------------

"""Delete K8s resources for a sandbox without depending on backend registry."""
def cleanup_sandbox_resources(backend: Any, sandbox_id: str, pod_name: str, namespace: str, warm_start: bool) -> None {
    import from kubernetes { client }
    import from kubernetes.client.exceptions { ApiException }
    core_v1 = client.CoreV1Api();
    actual_pod = pod_name or sandbox_id;

    try {
        core_v1.delete_namespaced_pod(actual_pod, namespace);
    } except ApiException {
        x = 0;
    }

    if hasattr(backend, "config") and not backend.config.proxy_mode {
        try {
            core_v1.delete_namespaced_service(f"{sandbox_id}-svc", namespace);
        } except ApiException {
            x = 0;
        }
    }

    if not warm_start {
        try {
            core_v1.delete_namespaced_config_map(f"{sandbox_id}-code", namespace);
        } except ApiException {
            x = 0;
        }
    }

    try {
        ingress = backend._get_ingress_provider();
        ingress.delete_route(sandbox_id, namespace);
    } except Exception {
        x = 0;
    }
}

# ---------------------------------------------------------------------------
# Background Loop
# ---------------------------------------------------------------------------

def _reconcile_loop() -> None {
    time.sleep(10);
    logger.info(f"Starting on pod={_MY_POD} interval={_RECONCILE_INTERVAL}s");

    while not _stop_event.is_set() {
        try {
            _run_reconcile_cycle();
        } except Exception as e {
            logger.error(f"Cycle error: {e}");
        }
        _stop_event.wait(_RECONCILE_INTERVAL);
    }
    logger.info("Stopped");
}

def _run_reconcile_cycle() -> None {
    # All reconciliation uses K8s API directly — no walker/graph context needed.
    # Every pod runs the full cycle independently. This is safe because:
    #   - All K8s delete operations are idempotent (404 on already-deleted is caught)
    #   - State comes from K8s API each cycle (no in-memory drift)
    #   - Timestamps are K8s server-side (consistent across pods)
    # Tradeoff: redundant K8s list calls (one per pod per 15s) — negligible overhead.
    try {
        import from services.sandbox_store { get_backend }
        backend = get_backend();
        if backend is not None {
            reconcile_drift_k8s_only(backend);
            reconcile_warm_pool(backend);
        }
    } except Exception as e {
        logger.error(f"Cycle error: {e}");
    }
}

# ---------------------------------------------------------------------------
# Start / Stop
# ---------------------------------------------------------------------------

"""Start the background reconciliation thread."""
def start_reconciler() -> None {
    t = Thread(target=_reconcile_loop, daemon=True);
    t.start();
    logger.info(f"Background thread started on pod={_MY_POD}");
}

"""Signal the reconciler to stop."""
def stop_reconciler() -> None {
    _stop_event.set();
    logger.info("Stop signal sent");
}
