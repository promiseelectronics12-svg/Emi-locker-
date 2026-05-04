#!/usr/bin/env python3
"""
Live Codex supervisor watcher for the EMI autonomous builder.

It tails build_log.md and triggers Codex when risky events appear:
- ERROR
- Timeout
- NEEDS WORK
- low review scores
- BUILD COMPLETE

Reports are written to supervisor_reports/ and a short AUDIT line is appended
to build_log.md so the browser monitor can show the supervisor intervention.
"""

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


SUPERVISOR_MODEL = "gpt-5.4"
RISK_PATTERNS = [
    ("error", re.compile(r"\bERROR\b|Exception running|OpenCode stderr", re.I)),
    ("timeout", re.compile(r"\bTimeout after\b|timed out", re.I)),
    ("needs-work", re.compile(r"\bNEEDS WORK\b|status=needs_changes", re.I)),
    ("low-score", re.compile(r"score[=:]\s*([0-5]?\d)\b", re.I)),
    ("complete", re.compile(r"\bBUILD COMPLETE\b|Trigger flag written", re.I)),
]


def utf8_stdio() -> None:
    if sys.stdout.encoding != "utf-8":
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if sys.stderr.encoding != "utf-8":
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def log_line(project_dir: Path, message: str, level: str = "INFO") -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    entry = f"[{ts}] [{level}] {message}"
    print(entry)
    with (project_dir / "build_log.md").open("a", encoding="utf-8") as handle:
        handle.write(entry + "\n")


def is_pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def acquire_lock(project_dir: Path) -> bool:
    lock_file = project_dir / ".supervisor_watcher.pid"
    if lock_file.exists():
        try:
            existing_pid = int(lock_file.read_text(encoding="utf-8").strip())
            if is_pid_alive(existing_pid):
                return False
        except Exception:
            pass
    lock_file.write_text(str(os.getpid()), encoding="utf-8")
    return True


def release_lock(project_dir: Path) -> None:
    lock_file = project_dir / ".supervisor_watcher.pid"
    try:
        if lock_file.exists() and lock_file.read_text(encoding="utf-8").strip() == str(os.getpid()):
            lock_file.unlink()
    except Exception:
        pass


def load_state(project_dir: Path) -> dict:
    path = project_dir / "supervisor_watch_state.json"
    if not path.exists():
        return {"position": 0, "seen": [], "last_trigger_at": 0}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"position": 0, "seen": [], "last_trigger_at": 0}


def save_state(project_dir: Path, state: dict) -> None:
    (project_dir / "supervisor_watch_state.json").write_text(
        json.dumps(state, indent=2),
        encoding="utf-8",
    )


def classify_event(line: str) -> str | None:
    if "AUDIT (Codex)" in line or "SUPERVISOR_WATCH" in line:
        return None
    for name, pattern in RISK_PATTERNS:
        match = pattern.search(line)
        if not match:
            continue
        if name == "low-score":
            try:
                score = int(match.group(1))
            except Exception:
                return None
            return name if score < 60 else None
        return name
    return None


def read_tail(path: Path, limit: int = 120) -> str:
    if not path.exists():
        return ""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(lines[-limit:])


def read_optional(path: Path, limit_chars: int = 5000) -> str:
    if not path.exists():
        return "[missing]"
    text = path.read_text(encoding="utf-8", errors="replace")
    return text[-limit_chars:]


def build_prompt(project_dir: Path, event_type: str, event_line: str) -> str:
    state = read_optional(project_dir / "build_state.json", 4000)
    tail = read_tail(project_dir / "build_log.md", 120)
    lock_delivery = read_optional(
        project_dir / "backend" / "src" / "modules" / "lock" / "lockDeliveryService.js",
        7000,
    )
    return (
        "You are Antigravity, the live FIRST FRONTIER SUPERVISOR for the EMI Locker autonomous builder.\n"
        "A risky build event just occurred. Audit it and return a concise report.\n\n"
        "Required output:\n"
        "1. Verdict: BLOCKING, WATCH, or OK\n"
        "2. Why this event matters\n"
        "3. Exact next action for Worker/Executor/User\n"
        "4. Any file/module that should be inspected next\n\n"
        f"EVENT TYPE: {event_type}\n"
        f"EVENT LINE: {event_line}\n\n"
        f"BUILD STATE:\n{state}\n\n"
        f"RECENT BUILD LOG:\n{tail}\n\n"
        f"LOCK DELIVERY SERVICE CONTEXT:\n{lock_delivery}\n"
    )


# Lines prefixed by these strings are MCP noise and must never reach the audit log
_GEMINI_NOISE_PREFIXES = (
    "MCP issues detected",
    "Ripgrep is not available",
    "Warning: Windows",
    "Warning: 256-color",
    "warning:",
)

def _clean_gemini_output(raw: str) -> str:
    """Strip MCP/UI noise lines emitted by Gemini CLI in headless mode."""
    cleaned = []
    for line in raw.splitlines():
        stripped = line.strip()
        if any(stripped.lower().startswith(p.lower()) for p in _GEMINI_NOISE_PREFIXES):
            continue
        cleaned.append(line)
    return "\n".join(cleaned).strip()


def run_gemini(project_dir: Path, prompt: str, timeout: int) -> str | None:
    # Changed to use Mimo 2.5 Pro as the frontier supervisor via opencode
    model = "xiaomi-token-plan-singapore/mimo-v2.5-pro"
    cmd = f'opencode run -m "{model}"'
    try:
        result = subprocess.run(
            cmd,
            input=prompt,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(project_dir),
            timeout=timeout,
            shell=True,
        )
        raw_out = result.stdout.strip()
        cleaned = _clean_gemini_output(raw_out)
        if result.returncode == 0 and cleaned:
            return cleaned
        raw_err = result.stderr.strip()
        cleaned_err = _clean_gemini_output(raw_err)
        if cleaned_err:
            log_line(project_dir, f"AUDIT (Mimo): CLI warning: {cleaned_err[:240]}", "WARN")
    except subprocess.TimeoutExpired:
        log_line(project_dir, f"AUDIT (Mimo): trigger timed out after {timeout}s", "ERROR")
    except Exception as exc:
        log_line(project_dir, f"AUDIT (Mimo): trigger failed: {exc}", "ERROR")
    return None

def run_codex(project_dir: Path, prompt: str, timeout: int) -> str | None:
    model = os.environ.get("CODEX_SUPERVISOR_MODEL", SUPERVISOR_MODEL)
    output_file = project_dir / ".codex_watch_last.txt"
    if output_file.exists():
        output_file.unlink()

    if shutil.which("codex"):
        cmd = (
            f'codex exec -m "{model}" --skip-git-repo-check '
            f'--sandbox danger-full-access -o ".codex_watch_last.txt" -C . -'
        )
        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                cwd=str(project_dir),
                timeout=timeout,
                shell=True,
            )
            if output_file.exists():
                text = output_file.read_text(encoding="utf-8", errors="replace").strip()
                if text:
                    return text
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
            if result.stderr.strip():
                log_line(project_dir, f"AUDIT (Codex): CLI warning: {result.stderr.strip()[:240]}", "WARN")
        except subprocess.TimeoutExpired:
            log_line(project_dir, f"AUDIT (Codex): supervisor trigger timed out after {timeout}s", "ERROR")
        except Exception as exc:
            log_line(project_dir, f"AUDIT (Codex): supervisor trigger failed: {exc}", "ERROR")

    fallback = project_dir / "codex_cli.py"
    if fallback.exists():
        try:
            result = subprocess.run(
                [sys.executable, str(fallback), "--stdin"],
                input=prompt,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                cwd=str(project_dir),
                timeout=timeout,
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except Exception as exc:
            log_line(project_dir, f"AUDIT (Codex): API fallback failed: {exc}", "ERROR")

    return None


def summarize_report(report: str) -> str:
    for line in report.splitlines():
        clean = line.strip().strip("#").strip()
        if clean:
            return clean[:220]
    return "Supervisor report generated."


def trigger(project_dir: Path, event_type: str, event_line: str, timeout: int) -> None:
    reports_dir = project_dir / "supervisor_reports"
    reports_dir.mkdir(exist_ok=True)
    log_line(project_dir, f"AUDIT (Antigravity): Live supervisor triggered by {event_type}.")
    
    prompt = build_prompt(project_dir, event_type, event_line)
    
    # Tier 1: Gemini
    report = run_gemini(project_dir, prompt, timeout)
    if not report:
        log_line(project_dir, f"AUDIT (Gemini): Failed/Unavailable. Falling back to Codex...", "WARN")
        # Tier 3 (Tier 2 is Claude in main script): Codex
        report = run_codex(project_dir, prompt, timeout)
        
    if not report:
        log_line(project_dir, f"AUDIT (System): No supervisor response for {event_type}.", "WARN")
        return

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_event = re.sub(r"[^a-z0-9_-]+", "-", event_type.lower()).strip("-")
    report_path = reports_dir / f"{stamp}_{safe_event}.md"
    report_path.write_text(report + "\n", encoding="utf-8")
    log_line(project_dir, f"AUDIT (Supervisor): {summarize_report(report)} Report: {report_path}")


def watch(args: argparse.Namespace) -> int:
    project_dir = Path(args.project_dir).resolve()
    log_path = project_dir / "build_log.md"
    state = load_state(project_dir)

    if args.from_end and log_path.exists():
        state["position"] = log_path.stat().st_size
        save_state(project_dir, state)

    log_line(project_dir, "SUPERVISOR_WATCH: Codex live watcher started.")

    try:
        while True:
            if not log_path.exists():
                time.sleep(args.interval)
                continue

            size = log_path.stat().st_size
            position = int(state.get("position", 0))
            if position > size:
                position = 0

            if size > position:
                with log_path.open("r", encoding="utf-8", errors="replace") as handle:
                    handle.seek(position)
                    chunk = handle.read()
                    position = handle.tell()
                state["position"] = position

                for line in [item for item in chunk.splitlines() if item.strip()]:
                    event_type = classify_event(line)
                    if not event_type:
                        continue

                    signature = f"{event_type}:{line[-220:]}"
                    seen = state.setdefault("seen", [])
                    if signature in seen:
                        continue

                    now = time.time()
                    if now - float(state.get("last_trigger_at", 0)) < args.cooldown:
                        seen.append(signature)
                        state["seen"] = seen[-100:]
                        continue

                    seen.append(signature)
                    state["seen"] = seen[-100:]
                    state["last_trigger_at"] = now
                    save_state(project_dir, state)
                    trigger(project_dir, event_type, line, args.timeout)

                    if args.once:
                        return 0
                    if args.stop_after_complete and event_type == "complete":
                        return 0

                save_state(project_dir, state)

            time.sleep(args.interval)
    finally:
        release_lock(project_dir)


def main() -> int:
    utf8_stdio()
    parser = argparse.ArgumentParser(description="Live Codex supervisor watcher.")
    parser.add_argument("--project-dir", default=".")
    parser.add_argument("--interval", type=float, default=2.0)
    parser.add_argument("--cooldown", type=float, default=90.0)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--from-end", action="store_true", help="Start watching new log lines only.")
    parser.add_argument("--once", action="store_true", help="Exit after the first trigger.")
    parser.add_argument("--stop-after-complete", action="store_true")
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    if not acquire_lock(project_dir):
        print("Supervisor watcher already running.")
        return 0

    def handle_stop(signum, frame):
        release_lock(project_dir)
        raise SystemExit(0)

    signal.signal(signal.SIGINT, handle_stop)
    signal.signal(signal.SIGTERM, handle_stop)
    return watch(args)


if __name__ == "__main__":
    raise SystemExit(main())
