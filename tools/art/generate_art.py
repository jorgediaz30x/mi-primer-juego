"""Game art generator — GPT Image -> real pixel art -> Godot config.

Reads tools/art/asset_manifest.json. For each asset it asks the OpenAI Images
API for a high-resolution image (kept in assets/art/_raw/, older versions in
assets/art/_history/), then post-processes it into real pixel art:

    static   -> clean alpha -> trim -> downscale to pixel_height        -> one PNG
    sheet    -> clean alpha -> slice grid -> align frames -> downscale   -> frame PNGs
    backdrop -> cover-crop to the screen aspect -> downscale             -> one PNG
    panorama -> downscale only (level segments: the ground is painted in) -> one PNG

and writes the result into assets/data/game_config.json at the asset's "link"
path ("sprites.hero", "animations.hero.run", "level_art.segments.0", ...), so
Godot picks it up on next launch. Godot scales everything by one integer factor
(render.pixel_scale) with nearest filtering: one shared pixel density.

Standard library only. API key from OPENAI_API_KEY or .env.local (gitignored).

    python tools/art/generate_art.py --list-models      # verify key + image models
    python tools/art/generate_art.py --dry-run          # show prompts, no API calls
    python tools/art/generate_art.py                    # generate missing assets
    python tools/art/generate_art.py --only hero hero_run
    python tools/art/generate_art.py --force            # regenerate (old raw -> _history)
    python tools/art/generate_art.py --reprocess        # re-run post-processing, no API

The asset studio (tools/studio/server.py) runs this script to regenerate one asset.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import png_alpha  # noqa: E402
import sprite_ops  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "tools" / "art" / "asset_manifest.json"
GAME_CONFIG = ROOT / "assets" / "data" / "game_config.json"
RAW_DIR = ROOT / "assets" / "art" / "_raw"
HISTORY_DIR = ROOT / "assets" / "art" / "_history"
USAGE_LOG = ROOT / "tools" / "art" / "generation_log.jsonl"
ENV_FILE = ROOT / ".env.local"
API_BASE = "https://api.openai.com/v1"
TIMEOUT_SECONDS = 300
SCREEN_ASPECT = 1280 / 720


# --- Config ---------------------------------------------------------------

def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_manifest() -> dict:
    return load_json(MANIFEST)


def find_asset(manifest: dict, asset_id: str) -> dict | None:
    return next((a for a in manifest["assets"] if a["id"] == asset_id), None)


def raw_path(asset_id: str) -> Path:
    return RAW_DIR / f"{asset_id}.png"


def get_api_key() -> str:
    """OPENAI_API_KEY from the environment, else from .env.local (KEY=value lines)."""
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if key or not ENV_FILE.exists():
        return key
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        name, _, value = line.partition("=")
        if name.strip() == "OPENAI_API_KEY":
            return value.strip().strip('"').strip("'")
    return ""


def model_for(asset: dict, manifest: dict) -> str:
    return asset.get("model") or os.environ.get("OPENAI_IMAGE_MODEL") or manifest.get("model", "gpt-image-2.5-flare")


def build_prompt(manifest: dict, asset: dict) -> str:
    parts = [manifest.get("style", "")]
    if asset.get("kind") == "sheet":
        rules_key = {"effect": "effect_rules", "icons": "icon_rules"}.get(asset.get("role", ""), "sheet_rules")
        parts.append(manifest.get(rules_key, "").format(
            frames=int(asset["columns"]) * int(asset["rows"]), columns=asset["columns"], rows=asset["rows"]))
    parts.append(asset["prompt"])
    return "\n\n".join(p for p in parts if p).strip()


# --- HTTP -----------------------------------------------------------------

def encode_multipart(fields: dict[str, str], files: list[tuple[str, Path]]) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts: list[bytes] = []
    for name, value in fields.items():
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
        )
    for name, path in files:
        parts.append(
            (
                f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; '
                f'filename="{path.name}"\r\nContent-Type: image/png\r\n\r\n'
            ).encode()
            + path.read_bytes()
            + b"\r\n"
        )
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def request_json(method: str, endpoint: str, api_key: str, body: bytes | None = None,
                 content_type: str = "application/json") -> dict:
    request = urllib.request.Request(
        f"{API_BASE}/{endpoint}",
        data=body,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": content_type},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(f"OpenAI API {error.code}: {detail}") from None


# --- Generation -----------------------------------------------------------

def generate(asset: dict, manifest: dict, api_key: str) -> tuple[bytes, dict]:
    """Calls the Images API. References are the RAW (full-res) versions. Returns (png, usage)."""
    fields = {
        "model": model_for(asset, manifest),
        "prompt": build_prompt(manifest, asset),
        "size": asset.get("size", "1024x1024"),
        "quality": asset.get("quality") or manifest.get("quality", "high"),
        "background": asset.get("background", "transparent"),
        "output_format": "png",
    }
    references = [raw_path(ref) for ref in asset.get("reference", []) if raw_path(ref).exists()]
    if references:
        body, content_type = encode_multipart(fields, [("image[]", path) for path in references])
        payload = request_json("POST", "images/edits", api_key, body, content_type)
    else:
        payload = request_json("POST", "images/generations", api_key, json.dumps({**fields, "n": 1}).encode())
    return base64.b64decode(payload["data"][0]["b64_json"]), payload.get("usage", {})


def archive_raw(asset_id: str) -> None:
    """Moves the current raw PNG into _history/ so a regeneration is never destructive."""
    current = raw_path(asset_id)
    if not current.exists():
        return
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(current.stat().st_mtime))
    shutil.move(str(current), HISTORY_DIR / f"{asset_id}-{stamp}.png")


# --- Post-processing ------------------------------------------------------

def res_path(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def process(asset: dict) -> dict:
    """Turns the raw PNG into game-ready pixel art and links it in game_config.json."""
    img = sprite_ops.Image.load(raw_path(asset["id"]))
    kind = asset.get("kind", "static")
    pixel_height = int(asset["pixel_height"])
    info: dict = {"warnings": []}

    if kind in ("backdrop", "panorama"):
        if kind == "backdrop":
            img = sprite_ops.cover_crop(img, float(asset.get("aspect", SCREEN_ASPECT)))
        out = ROOT / asset["out"]
        transparent = asset.get("background") == "transparent"
        if transparent:
            sprite_ops.clean_alpha(img)
        small = sprite_ops.to_pixel_height(img, pixel_height, hard_alpha=transparent)
        small.save(out)
        if asset.get("glow_link"):
            points = sprite_ops.glow_points(small)
            info["glow_points"] = len(points)
            set_config_path(asset["glow_link"], points)
        if asset.get("floor_link"):
            row = sprite_ops.floor_row(small)
            info["floor_row"] = row
            if row is None:
                info["warnings"].append("no se detectó el suelo pintado")
            else:
                set_config_path(asset["floor_link"], row)
        value: object = res_path(out)
        info["frame_size"] = [small.width, small.height]
    elif kind == "sheet":
        sprite_ops.clean_alpha(img)
        frames, warnings = sprite_ops.slice_grid(img, int(asset["columns"]), int(asset["rows"]))
        info["warnings"] += warnings
        small = _trim_union([sprite_ops.to_pixel_height(f, pixel_height) for f in frames])
        out_dir = ROOT / asset["out_dir"]
        for old in out_dir.glob(f"{asset['id']}_*.png"):
            old.unlink()
        paths = []
        for i, frame in enumerate(small):
            path = out_dir / f"{asset['id']}_{i:02d}.png"
            frame.save(path)
            paths.append(res_path(path))
        value = {"frames": paths, "fps": asset.get("fps", 10), "loop": bool(asset.get("loop", True)),
                 "anchor": list(sprite_ops.feet_anchor(small)) if asset.get("anchor", "feet") == "feet" else None}
        info["frame_size"] = [small[0].width, small[0].height] if small else None
    else:
        sprite_ops.clean_alpha(img)
        box = sprite_ops.bbox(img)
        if box is None:
            raise ValueError("image is fully transparent")
        out = ROOT / asset["out"]
        small = sprite_ops.to_pixel_height(sprite_ops.crop(img, *box), pixel_height)
        small.save(out)
        value = res_path(out)
        info["frame_size"] = [small.width, small.height]

    set_config_path(asset.get("link", ""), value)
    if asset.get("background") == "transparent":
        info["alpha"] = png_alpha.alpha_stats(raw_path(asset["id"]))
    return info


def _trim_union(frames: list[sprite_ops.Image]) -> list[sprite_ops.Image]:
    """Crops every frame with the union of their boxes (keeps alignment, drops empty margins)."""
    boxes = [sprite_ops.bbox(f) for f in frames]
    valid = [b for b in boxes if b]
    if not valid:
        return frames
    x0, y0 = min(b[0] for b in valid), min(b[1] for b in valid)
    x1, y1 = max(b[2] for b in valid), max(b[3] for b in valid)
    return [sprite_ops.crop(f, x0, y0, x1, y1) for f in frames]


def set_config_path(dotted: str, value: object) -> None:
    """Writes [value] at a dotted path in game_config.json. Numeric keys index lists.

    A repo without the game yet has no game_config.json: then the asset is still
    generated, only the link is skipped (you connect it when the game exists).
    """
    if not dotted:
        print("      aviso: el asset no tiene link; no se enlaza en game_config.json", flush=True)
        return
    if not GAME_CONFIG.exists():
        print(f"      aviso: no existe {GAME_CONFIG.relative_to(ROOT).as_posix()}; no se enlaza {dotted}", flush=True)
        return
    config = load_json(GAME_CONFIG)
    node: object = config
    keys = dotted.split(".")
    for i, key in enumerate(keys[:-1]):
        node = _child(node, key, keys[i + 1].isdigit())
    last = keys[-1]
    if last.isdigit() and isinstance(node, list):
        index = int(last)
        while len(node) <= index:
            node.append(None)
        node[index] = value
    else:
        node[last] = value
    save_json(GAME_CONFIG, config)


def _child(node, key: str, next_is_index: bool):
    empty = [] if next_is_index else {}
    if key.isdigit() and isinstance(node, list):
        index = int(key)
        while len(node) <= index:
            node.append(None)
        if node[index] is None:
            node[index] = empty
        return node[index]
    return node.setdefault(key, empty)


# --- Orchestration --------------------------------------------------------

def log_usage(asset_id: str, model: str, usage: dict, seconds: float) -> None:
    entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "asset": asset_id, "model": model,
             "seconds": round(seconds, 1), "usage": usage}
    with USAGE_LOG.open("a", encoding="utf-8") as log:
        log.write(json.dumps(entry) + "\n")


def run_asset(asset_id: str, force: bool = False, api_key: str | None = None) -> dict:
    """Generates + processes one asset. Returns a status dict (used by CLI and previewer)."""
    manifest = load_manifest()
    asset = find_asset(manifest, asset_id)
    if asset is None:
        return {"id": asset_id, "status": "error", "error": "unknown asset id"}
    if raw_path(asset_id).exists() and not force:
        return {"id": asset_id, "status": "skipped"}
    missing = [r for r in asset.get("reference", []) if not raw_path(r).exists()]
    if missing:
        return {"id": asset_id, "status": "error", "error": f"genera primero la referencia: {', '.join(missing)}"}
    key = api_key if api_key is not None else get_api_key()
    if not key:
        return {"id": asset_id, "status": "error", "error": "OPENAI_API_KEY not set (env or .env.local)"}
    started = time.monotonic()
    try:
        png, usage = generate(asset, manifest, key)
    except (RuntimeError, urllib.error.URLError, KeyError, TimeoutError) as error:
        return {"id": asset_id, "status": "error", "error": str(error)}
    archive_raw(asset_id)
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    raw_path(asset_id).write_bytes(png)
    log_usage(asset_id, model_for(asset, manifest), usage, time.monotonic() - started)
    return {"id": asset_id, "status": "ok", "usage": usage, **reprocess_asset(asset)}


def reprocess_asset(asset: dict) -> dict:
    try:
        return process(asset)
    except (ValueError, OSError) as error:
        return {"warnings": [f"post-proceso falló: {error}"]}


def list_image_models(api_key: str) -> list[str]:
    payload = request_json("GET", "models", api_key)
    return sorted(m["id"] for m in payload.get("data", []) if "image" in m["id"])


def reimport_godot() -> None:
    godot = os.environ.get("GODOT_BIN")
    if not godot:
        print("Tip: set GODOT_BIN to re-import automatically, or open the project in Godot.")
        return
    subprocess.run([godot, "--headless", "--path", str(ROOT), "--import"], check=False)


# --- CLI ------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", nargs="*", help="asset ids to generate")
    parser.add_argument("--force", action="store_true", help="regenerate existing assets (old raw -> _history)")
    parser.add_argument("--dry-run", action="store_true", help="print prompts without calling the API")
    parser.add_argument("--reprocess", action="store_true", help="re-run pixel post-processing from raw, no API")
    parser.add_argument("--list-models", action="store_true", help="list image models your key can use")
    args = parser.parse_args()

    manifest = load_manifest()
    selected = [a for a in manifest["assets"] if not args.only or a["id"] in args.only]

    if args.dry_run:
        for asset in selected:
            refs = ", ".join(asset.get("reference", [])) or "none"
            print(f"[dry] {asset['id']} ({asset.get('kind', 'static')}, {asset.get('size')}, refs: {refs}) -> {asset.get('link') or 'sin link'}")
            print(f"      {build_prompt(manifest, asset)}\n")
        return 0

    if args.reprocess:
        for asset in selected:
            if raw_path(asset["id"]).exists():
                info = reprocess_asset(asset)
                print(f"[reprocess] {asset['id']} {info.get('frame_size') or ''} {'; '.join(info['warnings'])}")
        return 0

    api_key = get_api_key()
    if not api_key:
        print("OPENAI_API_KEY is not set (environment or .env.local).", file=sys.stderr)
        return 1
    if args.list_models:
        for model in list_image_models(api_key):
            print(model)
        return 0

    generated = 0
    for asset in selected:
        print(f"[gen] {asset['id']} ...", flush=True)
        result = run_asset(asset["id"], args.force, api_key)
        detail = result.get("error") or result.get("frame_size") or ""
        print(f"[{result['status']}] {asset['id']} {detail}")
        for warning in result.get("warnings", []):
            print(f"      aviso: {warning}")
        generated += result["status"] == "ok"
    if generated:
        reimport_godot()
    return 0


if __name__ == "__main__":
    sys.exit(main())
