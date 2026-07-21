#!/usr/bin/env python3
"""Fetch quota data from the `agy` CLI's embedded local HTTPS server.

`agy` (the Antigravity CLI) only exposes its quota endpoint while an
interactive session is alive, so this script:
  1. Looks for an already-running `agy` process for the current user and
     reuses its port if the quota endpoint answers (no extra process spawned).
  2. Otherwise launches a short-lived `agy` session in a pty (the CLI needs a
     real terminal to start), waits for its local server to come up, queries
     it once, and tears the process back down immediately.

Privacy: this never touches Google/Antigravity account credentials — it only
talks to 127.0.0.1 over the loopback HTTPS port `agy` itself opens. The local
cert is self-signed, so TLS verification is skipped (loopback only, matching
Antigravity's own local-only design). On any problem this always prints valid
JSON (usage data or an error object) and always exits 0, so the widget never
hangs waiting for input.
"""
import json
import os
import pty
import re
import shutil
import signal
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

QUOTA_PATH = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
STARTUP_TIMEOUT = 8.0
POLL_INTERVAL = 0.3


def emit_error(message):
    print(json.dumps({"error": {"message": message}}))


def find_binary():
    override = os.environ.get("ANTIGRAVITY_CLI_PATH")
    if override and os.path.isfile(override) and os.access(override, os.X_OK):
        return override
    found = shutil.which("agy")
    if found:
        return found
    for candidate in (
        os.path.expanduser("~/.local/bin/agy"),
        "/opt/homebrew/bin/agy",
        "/usr/local/bin/agy",
    ):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def listening_ports(pid):
    try:
        out = subprocess.run(
            ["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", str(pid)],
            capture_output=True, text=True, timeout=3,
        ).stdout
    except Exception:
        return []
    ports = []
    for line in out.splitlines()[1:]:
        m = re.search(r"127\.0\.0\.1:(\d+)\s*\(LISTEN\)", line)
        if m:
            ports.append(int(m.group(1)))
    return ports


def query_quota(port):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(
        f"https://127.0.0.1:{port}{QUOTA_PATH}",
        data=b"{}",
        headers={
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=2, context=ctx) as resp:
            body = resp.read()
    except (urllib.error.URLError, TimeoutError, ConnectionError, OSError):
        return None
    try:
        data = json.loads(body)
    except ValueError:
        return None
    if isinstance(data, dict) and isinstance(data.get("response"), dict):
        return data["response"]
    return None


def existing_pids():
    try:
        out = subprocess.run(
            ["pgrep", "-u", str(os.getuid()), "-x", "agy"],
            capture_output=True, text=True, timeout=3,
        ).stdout
    except Exception:
        return []
    return [int(p) for p in out.split() if p.isdigit()]


def try_existing():
    for pid in existing_pids():
        for port in listening_ports(pid):
            quota = query_quota(port)
            if quota is not None:
                return quota
    return None


def launch_and_query(binary):
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp(binary, [binary])
        except Exception:
            os._exit(1)

    quota = None
    deadline = time.time() + STARTUP_TIMEOUT
    try:
        while time.time() < deadline:
            for port in listening_ports(pid):
                quota = query_quota(port)
                if quota is not None:
                    break
            if quota is not None:
                break
            time.sleep(POLL_INTERVAL)
    finally:
        try:
            os.kill(pid, signal.SIGTERM)
            time.sleep(0.2)
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass

    return quota


def main():
    binary = find_binary()
    if not binary:
        emit_error("agy CLI not found. Install Antigravity's agy or set ANTIGRAVITY_CLI_PATH.")
        return

    quota = try_existing()
    if quota is None:
        quota = launch_and_query(binary)

    if quota is None:
        emit_error("Could not reach the agy local quota server.")
        return

    print(json.dumps(quota))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        emit_error(f"agy fetch failed: {e}")
