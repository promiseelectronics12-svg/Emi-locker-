#!/usr/bin/env python3
"""
Terminal trigger for the Codex supervisor.

Usage:
    python codex_cli.py "Audit the current build"
    Get-Content task.txt | python codex_cli.py --stdin
    python codex_cli.py --prompt-file task.txt --model gpt-5

Required environment:
    OPENAI_API_KEY

Optional environment:
    OPENAI_MODEL, default: gpt-5
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


DEFAULT_SYSTEM = (
    "You are Codex, the supervisor for the EMI Locker autonomous builder. "
    "Be concise, security-focused, and return directly usable guidance."
)


def read_prompt(args: argparse.Namespace) -> str:
    parts = []
    if args.stdin:
        parts.append(sys.stdin.read())
    if args.prompt_file:
        with open(args.prompt_file, "r", encoding="utf-8") as handle:
            parts.append(handle.read())
    if args.prompt:
        parts.append(" ".join(args.prompt))
    prompt = "\n\n".join(part.strip() for part in parts if part and part.strip())
    if not prompt:
        raise SystemExit("No prompt supplied. Use text args, --stdin, or --prompt-file.")
    return prompt


def extract_text(payload: dict) -> str:
    if payload.get("output_text"):
        return payload["output_text"]

    chunks = []
    for item in payload.get("output", []):
        for content in item.get("content", []):
            if content.get("type") in ("output_text", "text"):
                chunks.append(content.get("text", ""))
    return "\n".join(chunk for chunk in chunks if chunk).strip()


def call_openai(prompt: str, model: str, system: str, max_output_tokens: int) -> str:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise SystemExit("OPENAI_API_KEY is not set.")

    body = {
        "model": model,
        "input": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        "max_output_tokens": max_output_tokens,
    }
    request = urllib.request.Request(
        "https://api.openai.com/v1/responses",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"OpenAI API error {exc.code}: {detail}")

    text = extract_text(payload)
    if not text:
        raise SystemExit("OpenAI API returned no text.")
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description="Trigger Codex supervisor from the terminal.")
    parser.add_argument("prompt", nargs="*", help="Prompt text")
    parser.add_argument("--stdin", action="store_true", help="Read prompt from stdin")
    parser.add_argument("--prompt-file", help="Read prompt from a text file")
    parser.add_argument("--model", default=os.environ.get("OPENAI_MODEL", "gpt-5"))
    parser.add_argument("--system", default=DEFAULT_SYSTEM)
    parser.add_argument("--max-output-tokens", type=int, default=2000)
    args = parser.parse_args()

    prompt = read_prompt(args)
    print(call_openai(prompt, args.model, args.system, args.max_output_tokens))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
