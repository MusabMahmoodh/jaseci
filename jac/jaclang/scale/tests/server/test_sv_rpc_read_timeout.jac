"""sv-to-sv RPC idempotency: a walker spawn whose response read times out
must not be silently re-executed by the transport retry loop.

The service is a real `jac start` subprocess and the call travels the real
HTTP client path; the only injected condition is a per-service rpc_timeout
shorter than the walker's handler.
"""

import shutil;
import tempfile;
import time;
import from pathlib { Path }
import from jaclang.runtimelib { sv_client }
import from jaclang.scale.config.config_loader { get_scale_config, reset_scale_config }
import from jaclang.scale.plugin { JacScalePlugin }
import from jaclang.scale.tests.server_support { get_free_port, start_server }

glob INVOICE_SRC: str = """import time;

walker:pub ChargeCard {
    has invoice_id: str = "",
        amount: int = 0;

    can charge with Root entry {
        with open("ledger.txt", "a") as f {
            f.write("CHARGE " + self.invoice_id + " " + str(self.amount) + "\\n");
        }
        time.sleep(3);
        report {"charged": self.invoice_id, "amount": self.amount};
    }
}
""",
     RPC_TOML: str = """[scale.microservices.services.invoice_sv]
rpc_timeout = 1.5
""";


test "a walker spawn that read-times-out executes at most once" {
    tmp = Path(tempfile.mkdtemp());
    (tmp / "invoice_sv.jac").write_text(INVOICE_SRC);
    (tmp / "jac.toml").write_text(RPC_TOML);

    port = get_free_port();
    server = start_server(tmp, tmp / "invoice_sv.jac", port);
    caller_error = "";
    try {
        reset_scale_config();
        get_scale_config(project_dir=tmp);
        sv_client.register("invoice_sv", "http://localhost:" + str(port));

        try {
            JacScalePlugin.sv_walker_call(
                "invoice_sv",
                "ChargeCard",
                {"invoice_id": "INV-1001", "amount": 4999},
                None
            );
        } except RuntimeError as e {
            caller_error = str(e);
        }

        # the injected timeout must have fired, or nothing is being tested
        assert caller_error != "" , "expected the caller to see a timeout";

        # let any retried requests still in flight reach the service
        time.sleep(4);

        ledger = tmp / "ledger.txt";
        charges = ledger.read_text().splitlines() if ledger.exists() else [];
        msg = "invoice INV-1001 charged " + str(len(charges)) + " times";
        assert len(charges) == 1 , msg;
    } finally {
        sv_client.unregister("invoice_sv");
        reset_scale_config();
        server.terminate();
        server.wait(timeout=10);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}
