"""Game audio generator — ElevenLabs -> assets/audio/*.mp3 -> Godot config.

Reads tools/audio/audio_manifest.json and asks ElevenLabs for each asset:
    kind "music" -> POST /v1/music            (prompt + music_length_ms, instrumental)
    kind "sfx"   -> POST /v1/sound-generation (text + duration_seconds)
saves the MP3 (previous version kept in assets/audio/_history/) and writes its
res:// path into assets/data/game_config.json at the asset's "link".

Standard library only. API key from ELEVENLABS_API_KEY or .env.local (gitignored).

    python tools/audio/generate_audio.py --dry-run          # show prompts, no API calls
    python tools/audio/generate_audio.py                    # generate missing assets
    python tools/audio/generate_audio.py --only sfx_nova music_forest
    python tools/audio/generate_audio.py --force            # regenerate (old file -> _history)
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "tools" / "audio" / "audio_manifest.json"
GAME_CONFIG = ROOT / "assets" / "data" / "game_config.json"
HISTORY_DIR = ROOT / "assets" / "audio" / "_history"
USAGE_LOG = ROOT / "tools" / "audio" / "generation_log.jsonl"
ENV_FILE = ROOT / ".env.local"
API_BASE = "https://api.elevenlabs.io/v1"
TIMEOUT_SECONDS = 600


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def get_api_key() -> str:
    """ELEVENLABS_API_KEY from the environment, else from .env.local."""
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if key or not ENV_FILE.exists():
        return key
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        name, _, value = line.partition("=")
        if name.strip() == "ELEVENLABS_API_KEY":
            return value.strip().strip('"').strip("'")
    return ""


def request_audio(endpoint: str, body: dict, api_key: str, output_format: str) -> bytes:
    request = urllib.request.Request(
        f"{API_BASE}/{endpoint}?output_format={output_format}",
        data=json.dumps(body).encode(),
        headers={"xi-api-key": api_key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:600]
        raise RuntimeError(f"ElevenLabs {error.code}: {detail}") from None


def generate(asset: dict, manifest: dict, api_key: str) -> bytes:
    fmt = manifest.get("output_format", "mp3_44100_128")
    if asset["kind"] == "music":
        body = {
            "prompt": asset["prompt"],
            "music_length_ms": int(float(asset.get("length_s", 120)) * 1000),
            "model_id": asset.get("model") or manifest.get("music_model", "music_v1"),
            "force_instrumental": True,
        }
        return request_audio("music", body, api_key, fmt)
    body = {
        "text": asset["prompt"],
        "duration_seconds": float(asset.get("duration_s", 1.0)),
        "prompt_influence": float(asset.get("prompt_influence", 0.5)),
        "model_id": manifest.get("sfx_model", "eleven_text_to_sound_v2"),
    }
    return request_audio("sound-generation", body, api_key, fmt)


def set_config_path(dotted: str, value: object) -> None:
    """Writes [value] at a dotted path in game_config.json; skipped (with a notice) if the game has none yet."""
    if not dotted:
        print("      aviso: el asset no tiene link; no se enlaza en game_config.json", flush=True)
        return
    if not GAME_CONFIG.exists():
        print(f"      aviso: no existe {GAME_CONFIG.relative_to(ROOT).as_posix()}; no se enlaza {dotted}", flush=True)
        return
    config = load_json(GAME_CONFIG)
    node = config
    keys = dotted.split(".")
    for key in keys[:-1]:
        node = node.setdefault(key, {})
    node[keys[-1]] = value
    save_json(GAME_CONFIG, config)


def archive(path: Path, asset_id: str) -> None:
    if not path.exists():
        return
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(path.stat().st_mtime))
    shutil.move(str(path), HISTORY_DIR / f"{asset_id}-{stamp}{path.suffix}")


def run_asset(asset: dict, manifest: dict, api_key: str, force: bool) -> dict:
    out = ROOT / asset["out"]
    if out.exists() and not force:
        return {"status": "skipped"}
    started = time.monotonic()
    try:
        audio = generate(asset, manifest, api_key)
    except (RuntimeError, urllib.error.URLError, TimeoutError) as error:
        return {"status": "error", "error": str(error)}
    if len(audio) < 1000:
        return {"status": "error", "error": f"respuesta demasiado pequeña ({len(audio)} bytes)"}
    archive(out, asset["id"])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(audio)
    set_config_path(asset.get("link", ""), "res://" + out.relative_to(ROOT).as_posix())
    seconds = round(time.monotonic() - started, 1)
    with USAGE_LOG.open("a", encoding="utf-8") as log:
        log.write(json.dumps({"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "asset": asset["id"],
                              "kind": asset["kind"], "bytes": len(audio), "seconds": seconds}) + "\n")
    return {"status": "ok", "bytes": len(audio), "seconds": seconds}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", nargs="*", help="asset ids to generate")
    parser.add_argument("--force", action="store_true", help="regenerate existing files (old -> _history)")
    parser.add_argument("--dry-run", action="store_true", help="print prompts without calling the API")
    args = parser.parse_args()

    manifest = load_json(MANIFEST)
    selected = [a for a in manifest["assets"] if not args.only or a["id"] in args.only]
    if args.dry_run:
        for asset in selected:
            length = asset.get("length_s") or asset.get("duration_s")
            print(f"[dry] {asset['id']} ({asset['kind']}, {length}s) -> {asset.get('link') or 'sin link'}\n      {asset['prompt']}\n")
        return 0
    api_key = get_api_key()
    if not api_key:
        print("ELEVENLABS_API_KEY is not set (environment or .env.local).", file=sys.stderr)
        return 1
    for asset in selected:
        print(f"[gen] {asset['id']} ...", flush=True)
        result = run_asset(asset, manifest, api_key, args.force)
        print(f"[{result['status']}] {asset['id']} {result.get('error') or result.get('bytes', '')}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
