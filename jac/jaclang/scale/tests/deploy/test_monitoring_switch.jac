"""`[scale.monitoring].enabled` must decide whether the metrics stack deploys,
and the collectors it decides about must be cluster singletons rather than one
copy per app.
The observability path force-set `monitoring_enabled = True` on the config it
handed the deployer, so a configured `false` was overridden and a configured
`true` alone never reached the deployer at all. Real config objects, no mocks:
`gateway_config` is injected as a plain dict, which is the same seam
`_gateway_cfg` reads in production."""

import from jaclang.scale.deploy.target.kubernetes.kubernetes_config {
    KubernetesConfig
}
import from jaclang.scale.deploy.target.kubernetes.target { KubernetesTarget }
import from jaclang.scale.deploy.target.kubernetes.shared_observability {
    SharedObservability,
    lane_key,
    NODE_EXPORTER_NAME,
    KSM_NAME,
    PROMETHEUS_NAME,
    ALLOY_NAME
}


def _shared(app: str, ns: str, logs: bool = False) -> SharedObservability {
    return SharedObservability(
        k8s_config=KubernetesConfig(
            app_name=app,
            namespace=ns,
            monitoring_enabled=True,
            loki_enabled=logs,
            admin_username="scraper"
        )
    );
}


def _target(
    monitoring: bool, logs: bool = False, tracing: bool = False
) -> KubernetesTarget {
    return KubernetesTarget(
        config=KubernetesConfig(
            app_name="t", namespace="t-ns", monitoring_enabled=monitoring
        ),
        gateway_config={"logs": {"enabled": logs}, "tracing": {"enabled": tracing}}
    );
}


test "a disabled monitoring switch is not overridden on the way to the deployer" {
    target = _target(monitoring=False, logs=True);
    obs = target._build_observability_config();
    assert obs.monitoring_enabled == False;
    assert obs.loki_enabled == True;
}


test "an enabled monitoring switch reaches the deployer" {
    target = _target(monitoring=True);
    obs = target._build_observability_config();
    assert obs.monitoring_enabled == True;
}


test "the monitoring switch alone requests the observability stack" {
    assert _target(monitoring=True)._observability_requested() == True;
}


test "logs or tracing still request the stack without the monitoring switch" {
    assert _target(monitoring=False, logs=True)._observability_requested() == True;
    assert _target(monitoring=False, tracing=True)._observability_requested() == True;
}


test "nothing enabled requests nothing" {
    assert _target(monitoring=False)._observability_requested() == False;
}


test "the shared collector names carry no app or namespace prefix" {
    # A name that varies per app is what makes N objects instead of one.
    # jacBuilder#1711: every deployed app stamped out its own
    # `{app}-node-exporter` DaemonSet on every node of the cluster.
    for name in [NODE_EXPORTER_NAME, KSM_NAME, PROMETHEUS_NAME, ALLOY_NAME] {
        assert name.startswith("jac-");
        for app_or_ns in ["alpha", "beta", "jb-299afd1f-dev-flowline"] {
            assert app_or_ns not in name;
        }
    }
}


test "two apps get two scrape lanes, each labelled with its own namespace" {
    alpha = _shared("alpha", "ns-alpha");
    beta = _shared("beta", "ns-beta");
    lane_a = alpha.prometheus_lane("alpha", "ns-alpha", "alpha-service", 8000);
    lane_b = beta.prometheus_lane("beta", "ns-beta", "beta-service", 8000);

    assert "alpha-service.ns-alpha.svc.cluster.local:8000" in lane_a;
    assert "beta-service.ns-beta.svc.cluster.local:8000" in lane_b;
    # Attribution is the bar that matters most once the collector is shared.
    assert "namespace: 'ns-alpha'" in lane_a;
    assert "jac_app: 'alpha'" in lane_a;
    assert "ns-beta" not in lane_a;
    assert "ns-alpha" not in lane_b;
    # Each app keeps its own scrape credential rather than sharing one.
    assert lane_key("alpha", "ns-alpha") in lane_a;
    assert lane_key("beta", "ns-beta") in lane_b;
    assert "username: 'scraper'" in lane_a;
}


test "one rendered config holds every app's lane over a single base" {
    shared = _shared("alpha", "ns-alpha");
    lanes = {
        lane_key("alpha", "ns-alpha"): shared.prometheus_lane(
            "alpha", "ns-alpha", "alpha-service", 8000
        ),
        lane_key("beta", "ns-beta"): shared.prometheus_lane(
            "beta", "ns-beta", "beta-service", 8000
        )
    };
    rendered = shared._render_prometheus_config(lanes);

    assert rendered.count("global:") == 1;
    assert rendered.count("job_name: 'node-exporter'") == 1;
    assert rendered.count("job_name: 'kube-state-metrics'") == 1;
    assert rendered.count("job_name: 'kubernetes-cadvisor'") == 1;
    assert "ns-alpha" in rendered;
    assert "ns-beta" in rendered;

    # Removing one app leaves the other app's lane and the shared base intact.
    lanes.pop(lane_key("beta", "ns-beta"));
    after = shared._render_prometheus_config(lanes);
    assert "ns-alpha" in after;
    assert "ns-beta" not in after;
    assert after.count("job_name: 'node-exporter'") == 1;
}


test "a shared log agent keeps only its own app's pods and ships them home" {
    shared = _shared("alpha", "ns-alpha", logs=True);
    lane = shared.alloy_lane("alpha", "ns-alpha");

    # Without this keep rule a shared agent reads every pod on the node.
    assert 'action        = "keep"' in lane;
    assert 'regex         = "ns-alpha"' in lane;
    assert "alpha-loki-service.ns-alpha.svc.cluster.local:3100" in lane;

    other = shared.alloy_lane("beta", "ns-beta");
    assert "beta-loki-service.ns-beta" in other;
    assert "ns-alpha" not in other;
}


test "grafana is pointed at the shared prometheus, not a per-app one" {
    shared = _shared("alpha", "ns-alpha");
    url = shared.prometheus_url();
    assert PROMETHEUS_NAME in url;
    assert "jac-observability" in url;
    assert "alpha" not in url;
}


test "the observability namespace is configurable but defaults to one place" {
    assert _shared("alpha", "ns-alpha").namespace() == "jac-observability";
    pinned = SharedObservability(
        k8s_config=KubernetesConfig(
            app_name="alpha", namespace="ns-alpha", observability_namespace="obs"
        )
    );
    assert pinned.namespace() == "obs";
}
