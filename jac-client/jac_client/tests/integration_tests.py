"""End-to-end tests for `jac serve` HTTP endpoints."""

from __future__ import annotations

import os
import socket
import tempfile
import time
from subprocess import Popen, run
from typing import Optional
from urllib.error import URLError, HTTPError
from urllib.request import urlopen

from unittest import TestCase


def _wait_for_port(
    host: str,
    port: int,
    timeout: float = 60.0,
    poll_interval: float = 0.5,
) -> None:
    """Block until a TCP port is accepting connections or timeout.

    Raises:
        TimeoutError: if the port is not accepting connections within timeout.
    """
    deadline = time.time() + timeout
    last_err: Optional[Exception] = None

    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(poll_interval)
            try:
                sock.connect((host, port))
                return
            except OSError as exc:  # Connection refused / timeout
                last_err = exc
                time.sleep(poll_interval)

    raise TimeoutError(
        f"Timed out waiting for {host}:{port} to become available. Last error: {last_err}"
    )


class ServeIntegrationTests(TestCase):
    """Integration tests that run `jac serve` and hit HTTP endpoints."""

    def test_create_app_and_serve_page_endpoint(self) -> None:
        """Create a Jac app, run `jac serve`, and verify HTTP endpoints."""
        app_name = "test-e2e-app"
        print(f"[DEBUG] Starting test_create_app_and_serve_page_endpoint with app_name={app_name}")

        with tempfile.TemporaryDirectory() as temp_dir:
            print(f"[DEBUG] Created temporary directory at {temp_dir}")
            original_cwd = os.getcwd()
            try:
                os.chdir(temp_dir)
                print(f"[DEBUG] Changed working directory to {temp_dir}")

                # 1. Create a new Jac app via CLI (requires jac + jac-client plugin installed)
                print(f"[DEBUG] Running 'jac create_jac_app {app_name}'")
                create_result = run(
                    ["jac", "create_jac_app", app_name],
                    capture_output=True,
                    text=True,
                )
                print(
                    "[DEBUG] 'jac create_jac_app' completed "
                    f"returncode={create_result.returncode}\n"
                    f"STDOUT:\n{create_result.stdout}\n"
                    f"STDERR:\n{create_result.stderr}\n"
                )
                # If the currently installed `jac` CLI does not support `create_jac_app`,
                # skip this integration test instead of failing the whole suite. This
                # can happen in environments where the jac-client plugin is not installed.
                if (
                    create_result.returncode != 0
                    and "invalid choice: 'create_jac_app'" in create_result.stderr
                ):
                    self.skipTest(
                        "Skipping: installed `jac` CLI does not support `create_jac_app`."
                    )

                self.assertEqual(
                    create_result.returncode,
                    0,
                    msg=(
                        "jac create_jac_app failed\n"
                        f"STDOUT:\n{create_result.stdout}\n"
                        f"STDERR:\n{create_result.stderr}\n"
                    ),
                )

                project_path = os.path.join(temp_dir, app_name)
                print(f"[DEBUG] Created project at {project_path}")
                self.assertTrue(os.path.isdir(project_path))

                # 2. Start the server: `jac serve app.jac`
                server: Optional[Popen[str]] = None
                try:
                    print("[DEBUG] Starting server with 'jac serve app.jac'")
                    server = Popen(
                        ["jac", "serve", "app.jac"],
                        cwd=project_path,
                    )

                    # 3.a Wait for localhost:8000 to become available
                    print("[DEBUG] Waiting for server to be available on 127.0.0.1:8000")
                    _wait_for_port("127.0.0.1", 8000, timeout=90.0)
                    print("[DEBUG] Server is now accepting connections on 127.0.0.1:8000")

                    # 3.b Verify root JSON API responds: "/"
                    try:
                        print("[DEBUG] Sending GET request to root endpoint /")
                        with urlopen(
                            "http://127.0.0.1:8000",
                            timeout=10,
                        ) as resp_root:
                            root_body = resp_root.read().decode(
                                "utf-8", errors="ignore"
                            )
                            print(
                                "[DEBUG] Received response from root endpoint /\n"
                                f"Status: {resp_root.status}\n"
                                f"Body (truncated to 500 chars):\n{root_body[:500]}"
                            )
                            self.assertEqual(resp_root.status, 200)
                            self.assertIn('"Jac API Server"', root_body)
                            self.assertIn('"endpoints"', root_body)
                    except (URLError, HTTPError) as exc:
                        print(f"[DEBUG] Error while requesting root endpoint: {exc}")
                        self.fail(f"Failed to GET root endpoint: {exc}")

                    # 3.c /page/app should respond with HTML (main app page)
                    try:
                        print("[DEBUG] Sending GET request to /page/app endpoint")
                        with urlopen(
                            "http://127.0.0.1:8000/page/app",
                            timeout=200,
                        ) as resp_page:
                            page_body = resp_page.read().decode(
                                "utf-8", errors="ignore"
                            )
                            print(
                                "[DEBUG] Received response from /page/app endpoint\n"
                                f"Status: {resp_page.status}\n"
                                f"Body (truncated to 500 chars):\n{page_body[:500]}"
                            )
                            self.assertEqual(resp_page.status, 200)
                            self.assertIn("<html", page_body.lower())
                    except (URLError, HTTPError) as exc:
                        print(f"[DEBUG] Error while requesting /page/app endpoint: {exc}")
                        self.fail(f"Failed to GET /page/app endpoint: {exc}")

                    # 3.d /page/app#/nested – client-side nested route via hash fragment.
                    # Note: the hash fragment is not sent to the server, but this URL should
                    # still correctly serve the main app shell HTML.
                    try:
                        print("[DEBUG] Sending GET request to /page/app#/nested endpoint")
                        with urlopen(
                            "http://127.0.0.1:8000/page/app#/nested",
                            timeout=200,
                        ) as resp_nested:
                            nested_body = resp_nested.read().decode(
                                "utf-8", errors="ignore"
                            )
                            print(
                                "[DEBUG] Received response from /page/app#/nested endpoint\n"
                                f"Status: {resp_nested.status}\n"
                                f"Body (truncated to 500 chars):\n{nested_body[:500]}"
                            )
                            self.assertEqual(resp_nested.status, 200)
                            self.assertIn("<html", nested_body.lower())
                    except (URLError, HTTPError) as exc:
                        print(f"[DEBUG] Error while requesting /page/app#/nested endpoint: {exc}")
                        self.fail(f"Failed to GET /page/app#/nested endpoint: {exc}")

                    # 3.e /static/main.css – compiled CSS is served
                    try:
                        print("[DEBUG] Sending GET request to /static/main.css")
                        with urlopen(
                            "http://127.0.0.1:8000/static/main.css",
                            timeout=20,
                        ) as resp_css:
                            css_body = resp_css.read().decode(
                                "utf-8", errors="ignore"
                            )
                            print(
                                "[DEBUG] Received response from /static/main.css\n"
                                f"Status: {resp_css.status}\n"
                                f"Body (truncated to 500 chars):\n{css_body[:500]}"
                            )
                            self.assertEqual(resp_css.status, 200)
                            # Basic sanity check: CSS should not be empty.
                            self.assertTrue(len(css_body.strip()) > 0)
                    except (URLError, HTTPError) as exc:
                        print(f"[DEBUG] Error while requesting /static/main.css: {exc}")
                        self.fail(f"Failed to GET /static/main.css: {exc}")

                    # 3.f /static/assets/burger.png – static assets are served
                    try:
                        print("[DEBUG] Sending GET request to /static/assets/burger.png")
                        with urlopen(
                            "http://127.0.0.1:8000/static/assets/burger.png",
                            timeout=20,
                        ) as resp_png:
                            png_bytes = resp_png.read()
                            print(
                                "[DEBUG] Received response from /static/assets/burger.png\n"
                                f"Status: {resp_png.status}\n"
                                f"Content-Length: {len(png_bytes)} bytes"
                            )
                            self.assertEqual(resp_png.status, 200)
                            # Basic sanity check: PNG should be non-empty and start with PNG signature.
                            self.assertGreater(len(png_bytes), 0)
                            self.assertTrue(
                                png_bytes.startswith(b"\x89PNG"),
                                msg="Expected PNG signature at start of burger.png",
                            )
                    except (URLError, HTTPError) as exc:
                        print(f"[DEBUG] Error while requesting /static/assets/burger.png: {exc}")
                        self.fail("Failed to GET /static/assets/burger.png")

                    # 3.g /walker/get_server_message – walker endpoint is up
                    try:
                        print("[DEBUG] Sending GET request to /walker/get_server_message")
                        with urlopen(
                            "http://127.0.0.1:8000/walker/get_server_message",
                            timeout=20,
                        ) as resp_walker:
                            walker_body = resp_walker.read().decode(
                                "utf-8", errors="ignore"
                            )
                            print(
                                "[DEBUG] Received response from /walker/get_server_message\n"
                                f"Status: {resp_walker.status}\n"
                                f"Body (truncated to 500 chars):\n{walker_body[:500]}"
                            )
                            self.assertEqual(resp_walker.status, 200)
                            # The walker is defined in the all-in-one example and should be discoverable here.
                            self.assertIn("get_server_message", walker_body)
                    except (URLError, HTTPError) as exc:
                        print(f"[DEBUG] Error while requesting /walker/get_server_message: {exc}")
                        self.fail("Failed to GET /walker/get_server_message")

                finally:
                    if server is not None:
                        print("[DEBUG] Terminating server process")
                        server.terminate()
                        try:
                            server.wait(timeout=15)
                            print("[DEBUG] Server process terminated cleanly")
                        except Exception:
                            print("[DEBUG] Server did not terminate cleanly, killing process")
                            server.kill()
            finally:
                print(f"[DEBUG] Restoring original working directory to {original_cwd}")
                os.chdir(original_cwd)


