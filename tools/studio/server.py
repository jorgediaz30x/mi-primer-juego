"""Estudio de assets: one local web page to browse, play and regenerate the game's art and audio.

    python tools/studio/server.py                     # opens http://127.0.0.1:8765
    python tools/studio/server.py --port 9000 --no-browser

Images come from tools/art/asset_manifest.json (GPT Image), audio from
tools/audio/audio_manifest.json (ElevenLabs). The page asks this server for both
lists, shows the files under assets/, and regenerates ONE asset at a time by
running the existing generator as a subprocess, exactly as you would by hand:

    python tools/art/generate_art.py     --only <id> --force      (or --dry-run)
    python tools/audio/generate_audio.py --only <id> --force      (or --dry-run)

So the generators stay the single source of truth: the studio never calls an API
itself. Standard library only. Binds to 127.0.0.1, so nobody else on your network
can reach it. The API keys stay in .env.local: this server never sends them to
the browser, and scrubs them from the generator log just in case.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import threading
import time
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse

STUDIO_DIR = Path(__file__).resolve().parent
TOOLS_DIR = STUDIO_DIR.parent
sys.path.insert(0, str(TOOLS_DIR / "art"))
sys.path.insert(0, str(TOOLS_DIR / "audio"))
import generate_art as art  # noqa: E402  (paths, manifest helpers, model_for)
import generate_audio as audio  # noqa: E402

ROOT = art.ROOT
ASSETS_DIR = (ROOT / "assets").resolve()
GENERATORS = {"image": TOOLS_DIR / "art" / "generate_art.py", "audio": TOOLS_DIR / "audio" / "generate_audio.py"}
MANIFESTS = {"image": art.MANIFEST, "audio": audio.MANIFEST}

# Explicit types: on Windows the registry can map .js to text/plain, and the
# browser then refuses to run the page's modules.
CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8", ".woff2": "font/woff2", ".svg": "image/svg+xml",
    ".png": "image/png", ".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".wav": "audio/wav",
}

# The five groups of the Images tab, in display order.
CATEGORIES = [
    ("personajes", "Personajes"),
    ("animaciones", "Animaciones"),
    ("fondos", "Fondos y niveles"),
    ("efectos", "Efectos"),
    ("interfaz", "Interfaz e iconos"),
]
KIND_LABELS = {"static": "Sprite", "sheet": "Animación", "backdrop": "Fondo", "panorama": "Tramo de nivel"}


# --- Files ------------------------------------------------------------------

def png_size(path: Path) -> tuple[int, int] | None:
    """Width/height from the PNG header, without an image library."""
    with path.open("rb") as file:
        header = file.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", header[16:24])


def file_url(path: Path) -> str | None:
    """assets/art/hero/hero.png -> /files/art/hero/hero.png?v=<mtime>.

    The ?v= changes when the file changes, so the browser shows the new version
    right after a regeneration instead of a cached one (cache-busting).
    """
    try:
        relative = path.resolve().relative_to(ASSETS_DIR).as_posix()
    except ValueError:
        return None  # outside assets/: never served
    return f"/files/{quote(relative)}?v={path.stat().st_mtime_ns // 1_000_000}"


def history(folder: Path, asset_id: str, suffix: str) -> list[dict]:
    """Older versions the generators moved aside, named <id>-YYYYmmdd-HHMMSS<suffix>. Newest first."""
    if not folder.is_dir():
        return []
    pattern = re.compile(re.escape(asset_id) + r"-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})\d{2}" + re.escape(suffix) + "$")
    versions = []
    for path in folder.iterdir():
        match = pattern.match(path.name)
        if match:
            y, mo, d, h, mi = match.groups()
            version = {"name": path.name, "url": file_url(path), "date": f"{y}-{mo}-{d} {h}:{mi}"}
            if suffix == ".png":
                version["size"] = list(png_size(path) or ())
            versions.append(version)
    return sorted(versions, key=lambda v: v["name"], reverse=True)


# --- Images -----------------------------------------------------------------

def image_category(asset: dict) -> str:
    """Derives the group from fields the manifest already has (no extra field needed)."""
    link, kind, role = asset.get("link", ""), asset.get("kind", "static"), asset.get("role", "")
    if link.startswith("ui.") or role in ("icons", "ui"):
        return "interfaz"
    if link.startswith("vfx.") or role == "effect":
        return "efectos"
    if kind in ("backdrop", "panorama") or link.startswith("level_art."):
        return "fondos"
    if kind == "sheet":
        return "animaciones"
    return "personajes"


def image_frames(asset: dict) -> list[Path]:
    """The game-ready PNGs generate_art.process() wrote: one file, or <id>_00.png, <id>_01.png... for a sheet."""
    if asset.get("kind") == "sheet":
        folder = ROOT / asset.get("out_dir", "-")
        if not folder.is_dir():
            return []
        pattern = re.compile(re.escape(asset["id"]) + r"_\d{2}\.png$")
        return sorted(p for p in folder.iterdir() if pattern.match(p.name))
    out = ROOT / asset.get("out", "-")
    return [out] if out.is_file() else []


def image_entry(asset: dict, manifest: dict) -> dict:
    frames = [p for p in image_frames(asset) if file_url(p)]
    raw = art.raw_path(asset["id"])
    kind = asset.get("kind", "static")
    entry = {
        "id": asset["id"],
        "kind": kind,
        "kind_label": {"effect": "Efecto", "icons": "Iconos"}.get(asset.get("role", ""), KIND_LABELS.get(kind, kind)),
        "category": image_category(asset),
        "prompt": asset.get("prompt", ""),
        "model": art.model_for(asset, manifest),
        "size": asset.get("size", "1024x1024"),
        "quality": asset.get("quality") or manifest.get("quality", "high"),
        "background": asset.get("background", "transparent"),
        "pixel_height": asset.get("pixel_height"),
        "reference": asset.get("reference", []),
        "columns": int(asset.get("columns", 1)),
        "rows": int(asset.get("rows", 1)),
        "fps": asset.get("fps", 10),
        "loop": bool(asset.get("loop", True)),
        "out_path": asset.get("out") or f"{asset.get('out_dir', '')}/{asset['id']}_NN.png",
        "frames": [file_url(p) for p in frames],
        "frame_size": list(png_size(frames[0]) or ()) if frames else None,
        "raw": {"url": file_url(raw), "size": list(png_size(raw) or ()),
                "path": raw.relative_to(ROOT).as_posix()} if raw.is_file() else None,
        "history": history(art.HISTORY_DIR, asset["id"], ".png"),
    }
    entry["status"] = "ok" if frames or entry["raw"] else "missing"
    return entry


def list_images() -> dict:
    result = {"categories": [{"id": c, "label": label} for c, label in CATEGORIES], "items": [],
              "key_configured": bool(art.get_api_key()), "manifest": art.MANIFEST.relative_to(ROOT).as_posix()}
    try:
        manifest = art.load_manifest()
        result["items"] = [image_entry(a, manifest) for a in manifest.get("assets", [])]
    except (OSError, ValueError, KeyError) as error:
        result["error"] = f"No pude leer el manifiesto de arte: {error}"
    return result


# --- Audio ------------------------------------------------------------------

def audio_group(asset: dict, shared_prefixes: set[str]) -> str:
    """Sound effects are grouped by id prefix (sfx_boss_*), unless the entry sets "group" itself."""
    if asset.get("group"):
        return str(asset["group"])
    if asset.get("kind") == "music":
        return "Música"
    prefix = _prefix(asset["id"])
    return f"{prefix}_*" if prefix in shared_prefixes else "Varios"


def _prefix(asset_id: str) -> str | None:
    parts = asset_id.split("_")
    return "_".join(parts[:2]) if len(parts) > 2 else None


def audio_entry(asset: dict, manifest: dict, shared: set[str]) -> dict:
    out = ROOT / asset.get("out", "-")
    music = asset.get("kind") == "music"
    # The same model choice generate_audio.generate() makes.
    model = (asset.get("model") or manifest.get("music_model", "music_v1")) if music \
        else manifest.get("sfx_model", "eleven_text_to_sound_v2")
    exists = out.is_file() and file_url(out) is not None
    return {
        "id": asset["id"],
        "kind": asset.get("kind", "sfx"),
        "section": "musica" if music else "efectos",
        "group": audio_group(asset, shared),
        "prompt": asset.get("prompt", ""),
        "model": model,
        "target_s": asset.get("length_s") if music else asset.get("duration_s"),
        "out_path": asset.get("out", ""),
        "status": "ok" if exists else "missing",
        "url": file_url(out) if exists else None,
        "bytes": out.stat().st_size if exists else None,
        "history": history(audio.HISTORY_DIR, asset["id"], out.suffix or ".mp3"),
    }


def list_audio() -> dict:
    result = {"items": [], "key_configured": bool(audio.get_api_key()),
              "manifest": audio.MANIFEST.relative_to(ROOT).as_posix()}
    try:
        manifest = audio.load_json(audio.MANIFEST)
        assets = manifest.get("assets", [])
        prefixes = [_prefix(a["id"]) for a in assets if a.get("kind") != "music"]
        shared = {p for p in prefixes if p and prefixes.count(p) > 1}
        result["items"] = [audio_entry(a, manifest, shared) for a in assets]
    except (OSError, ValueError, KeyError) as error:
        result["error"] = f"No pude leer el manifiesto de audio: {error}"
    return result


# --- Manifest edits ---------------------------------------------------------

def save_prompt(kind: str, asset_id: str, prompt: str) -> None:
    """Replaces ONE asset's prompt in its manifest, touching nothing else.

    The manifests are hand-formatted (the audio one keeps each asset on one line),
    so re-dumping the whole JSON would reformat them. Instead we find the exact
    characters of the old "prompt" string and splice in the new one. Then we
    re-parse and check that ONLY that prompt changed before writing, and write
    through a temporary file so a crash can never leave half a manifest.
    """
    path = MANIFESTS[kind]
    raw = path.read_bytes()                      # bytes: keeps the line endings exactly as they are
    text = raw.decode("utf-8")
    data = json.loads(text)
    asset = next((a for a in data.get("assets", []) if a.get("id") == asset_id), None)
    if asset is None:
        raise ValueError(f"no existe el id {asset_id}")

    id_key = re.compile(r'"id"\s*:\s*' + re.escape(json.dumps(asset_id)) + r"\s*[,}]")
    matches = list(id_key.finditer(text))
    if len(matches) != 1:
        raise ValueError(f"el id {asset_id} aparece {len(matches)} veces en el manifiesto")
    prompt_key = re.compile(r'"prompt"\s*:\s*').search(text, matches[0].end())
    next_id = re.compile(r'"id"\s*:').search(text, matches[0].end())
    if prompt_key is None or (next_id and prompt_key.start() > next_id.start()):
        raise ValueError(f"no encontré el prompt de {asset_id} después de su id")
    _, end = json.JSONDecoder().raw_decode(text, prompt_key.end())
    new_text = text[:prompt_key.end()] + json.dumps(prompt, ensure_ascii=False) + text[end:]

    expected = json.loads(text)
    next(a for a in expected["assets"] if a.get("id") == asset_id)["prompt"] = prompt
    if json.loads(new_text) != expected:
        raise ValueError("la edición cambiaría algo más que el prompt; no se guardó")
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(new_text.encode("utf-8"))
    os.replace(temporary, path)


def manifest_ids(kind: str) -> set[str]:
    data = json.loads(MANIFESTS[kind].read_text(encoding="utf-8"))
    return {a["id"] for a in data.get("assets", [])}


def restore_version(kind: str, asset_id: str, name: str) -> list[str]:
    """Puts an older version back (free, no API): the current file goes to history first."""
    if kind == "image":
        source = art.HISTORY_DIR / Path(name).name
        if not history_name_ok(name, asset_id, ".png") or not source.is_file():
            raise ValueError("no encontré esa versión")
        asset = art.find_asset(art.load_manifest(), asset_id)
        art.archive_raw(asset_id)
        art.RAW_DIR.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), art.raw_path(asset_id))
        return art.reprocess_asset(asset).get("warnings", [])   # rebuilds the pixel frames from the raw
    manifest = audio.load_json(audio.MANIFEST)
    asset = next(a for a in manifest["assets"] if a["id"] == asset_id)
    out = ROOT / asset["out"]
    source = audio.HISTORY_DIR / Path(name).name
    if not history_name_ok(name, asset_id, out.suffix) or not source.is_file():
        raise ValueError("no encontré esa versión")
    audio.archive(out, asset_id)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), out)
    return []


def history_name_ok(name: str, asset_id: str, suffix: str) -> bool:
    return re.fullmatch(re.escape(asset_id) + r"-\d{8}-\d{6}" + re.escape(suffix), name) is not None


# --- Creating and deleting entries ------------------------------------------
# The "Crear nuevo" form. Each type has fallback defaults (for an empty
# manifest); derive_templates() replaces them with the most common value among
# the entries you already have, so a new asset matches the existing ones.

ID_PATTERN = re.compile(r"[a-z][a-z0-9_]{1,47}")
LINK_PATTERN = re.compile(r"[a-z0-9_]+(\.[a-z0-9_]+)*")
BASE_SIZES = ["1024x1024", "1536x1024", "1536x768"]
REJECTED_SIZES = {"1024x512"}          # GPT Image rejects it (docs/estado, lessons)

TYPES = {
    "personaje": {"manifest": "image", "label": "Personaje", "kind": "static", "prefix": "",
                  "out": "assets/art/{id}/{id}.png", "link": "sprites.{id}",
                  "size": "1024x1024", "background": "transparent", "pixel_height": 48},
    "animacion": {"manifest": "image", "label": "Animación", "kind": "sheet", "prefix": "",
                  "out_dir": "{character_dir}", "link": "animations.{character}.{action}",
                  "columns": 4, "rows": 1, "fps": 10, "loop": True, "background": "transparent"},
    "fondo": {"manifest": "image", "label": "Fondo / nivel", "kind": "panorama", "prefix": "",
              "out": "{folder}/{id}.png", "folder": "assets/art/level", "link": "",
              "size": "1536x512", "background": "opaque", "pixel_height": 240},
    "efecto": {"manifest": "image", "label": "Efecto", "kind": "sheet", "role": "effect", "prefix": "vfx_",
               "out_dir": "{folder}", "folder": "assets/art/vfx", "link": "vfx.{name}",
               "columns": 3, "rows": 2, "fps": 16, "loop": False, "size": "1536x1024",
               "background": "transparent", "pixel_height": 16},
    "interfaz": {"manifest": "image", "label": "Interfaz / icono", "kind": "static", "role": "ui", "prefix": "ui_",
                 "out": "{folder}/{name}.png", "folder": "assets/art/ui", "link": "ui.{name}",
                 "size": "1024x1024", "background": "transparent", "pixel_height": 16},
    "musica": {"manifest": "audio", "label": "Música", "kind": "music", "prefix": "music_",
               "out": "{folder}/{name}.mp3", "folder": "assets/audio/music", "link": "audio.music.{name}",
               "length_s": 120},
    "sfx": {"manifest": "audio", "label": "Efecto de sonido", "kind": "sfx", "prefix": "sfx_",
            "out": "{folder}/{name}.mp3", "folder": "assets/audio/sfx", "link": "audio.sfx.{name}",
            "duration_s": 1.0},
}


def _mode(values: list, fallback):
    """Most common value (the first one seen wins a tie), or [fallback] if there are none."""
    values = [v for v in values if v not in (None, "")]
    return max(values, key=values.count) if values else fallback


def _entries_of(type_id: str, art_assets: list, audio_assets: list) -> list[dict]:
    if type_id in ("musica", "sfx"):
        return [a for a in audio_assets if a.get("kind") == TYPES[type_id]["kind"]]
    wanted = {"personaje": "personajes", "animacion": "animaciones", "fondo": "fondos",
              "efecto": "efectos", "interfaz": "interfaz"}[type_id]
    found = [a for a in art_assets if image_category(a) == wanted]
    if type_id == "interfaz":
        found = [a for a in found if a.get("kind") == "static"]
    if type_id == "fondo":
        found = [a for a in found if a.get("kind") in ("backdrop", "panorama")]
    return found


def _folder(entry: dict) -> str:
    return (entry.get("out_dir") or Path(entry.get("out", "")).parent.as_posix()).rstrip("/")


def load_manifests() -> tuple[dict, dict]:
    return art.load_manifest(), audio.load_json(audio.MANIFEST)


def derive_templates(art_m: dict, audio_m: dict) -> dict:
    """Defaults per type, taken from the existing entries (fallbacks from TYPES)."""
    art_assets, audio_assets = art_m.get("assets", []), audio_m.get("assets", [])
    ratios = [round(a["game_height"] / a["pixel_height"]) for a in art_assets
              if a.get("game_height") and a.get("pixel_height")]
    templates = {}
    for type_id, base in TYPES.items():
        t = dict(base)
        entries = _entries_of(type_id, art_assets, audio_assets)
        for key in ("size", "background", "pixel_height", "fps", "columns", "rows", "loop", "length_s", "duration_s", "anchor"):
            if key in base or any(key in e for e in entries):
                t[key] = _mode([e.get(key) for e in entries], base.get(key))
        if "folder" in base:
            t["folder"] = _mode([_folder(e) for e in entries], base["folder"])
        # The style reference most entries of this type use (animations use their character).
        t["reference"] = [] if type_id in ("animacion", "musica", "sfx") else \
            [r for r in [_mode([(e.get("reference") or [None])[0] for e in entries], None)] if r]
        if type_id == "fondo":        # backdrop and panorama differ in size and background
            t["by_kind"] = {k: {"size": _mode([e.get("size") for e in entries if e.get("kind") == k], d_size),
                                "background": _mode([e.get("background") for e in entries if e.get("kind") == k], d_bg)}
                            for k, d_size, d_bg in (("backdrop", "1536x1024", "opaque"), ("panorama", "1536x512", "opaque"))}
        templates[type_id] = t
    sheets = [a for a in art_assets if a.get("kind") == "sheet"]
    return {
        "types": templates,
        "game_scale": _mode(ratios, 3),
        "sizes": allowed_sizes(art_m),
        # Which size the existing sheets use for each grid, and for each number of rows.
        "sheet_sizes": {f"{c}x{r}": _mode([s.get("size") for s in sheets if (s.get("columns"), s.get("rows")) == (c, r)], None)
                        for c, r in {(s.get("columns"), s.get("rows")) for s in sheets}},
        "rows_sizes": {str(r): _mode([s.get("size") for s in sheets if s.get("rows") == r], None)
                       for r in {s.get("rows") for s in sheets}},
        "characters": [{"id": a["id"], "pixel_height": a.get("pixel_height"), "folder": _folder(a)}
                       for a in _entries_of("personaje", art_assets, [])],
        "image_ids": [a["id"] for a in art_assets],
        # Only these can be sent as a reference: generate_art.py stops if a reference has no raw PNG yet.
        "generated_images": [a["id"] for a in art_assets if art.raw_path(a["id"]).exists()],
        "audio_ids": [a["id"] for a in audio_assets],
        "image_model": art_m.get("model", "gpt-image-2.5-flare"),
        "quality": art_m.get("quality", "high"),
        "music_model": audio_m.get("music_model", "music_v1"),
        "sfx_model": audio_m.get("sfx_model", "eleven_text_to_sound_v2"),
        "style": art_m.get("style", ""),
        "rules": {k: art_m.get(k, "") for k in ("sheet_rules", "effect_rules", "icon_rules")},
    }


def allowed_sizes(art_m: dict) -> list[str]:
    """The sizes known to work: the base three plus every size an existing entry already uses."""
    used = [a.get("size") for a in art_m.get("assets", []) if re.fullmatch(r"\d+x\d+", str(a.get("size", "")))]
    return [s for s in dict.fromkeys(BASE_SIZES + used) if s not in REJECTED_SIZES]


def _number(fields: dict, key: str, low: float, high: float, errors: list, label: str, cast=int):
    try:
        value = cast(fields.get(key))
    except (TypeError, ValueError):
        errors.append(f"{label}: tiene que ser un número")
        return None
    if not low <= value <= high:
        errors.append(f"{label}: tiene que estar entre {low} y {high}")
    return value


def _safe_path(value: str, suffix: str | None, errors: list, label: str) -> str:
    """A relative path inside assets/, with forward slashes and the right extension."""
    path = str(value or "").strip().replace("\\", "/").strip("/")
    parts = path.split("/")
    if not path.startswith("assets/") or ".." in parts or any(not p for p in parts):
        errors.append(f"{label}: tiene que ser una ruta dentro de assets/ (sin ..)")
    elif suffix and not path.endswith(suffix):
        errors.append(f"{label}: tiene que terminar en {suffix}")
    elif not suffix and Path(path).suffix:
        errors.append(f"{label}: es una carpeta, sin extensión")
    return path


def build_entry(type_id: str, fields: dict, art_m: dict, audio_m: dict) -> tuple[dict, list[str]]:
    """Turns the form into a manifest entry, validating every field. Returns (entry, errors)."""
    if type_id not in TYPES:
        return {}, ["tipo desconocido"]
    t, errors = TYPES[type_id], []
    target = audio_m if t["manifest"] == "audio" else art_m
    assets = target.get("assets", [])
    asset_id = str(fields.get("id", "")).strip()
    if not ID_PATTERN.fullmatch(asset_id):
        errors.append("id: usa snake_case (minúsculas, números y _, empezando por letra, de 2 a 48 caracteres)")
    elif any(a.get("id") == asset_id for a in assets):
        errors.append(f"id: ya existe un asset llamado {asset_id}")
    prompt = str(fields.get("prompt", "")).replace("\r\n", "\n").strip()
    if not prompt:
        errors.append("Descripción: escribe qué quieres que se genere")
    elif len(prompt) > 4000:
        errors.append("Descripción: es demasiado larga (máximo 4000 caracteres)")

    entry: dict = {"id": asset_id, "kind": t["kind"]}
    if type_id == "fondo":
        entry["kind"] = str(fields.get("kind", "panorama"))
        if entry["kind"] not in ("backdrop", "panorama"):
            errors.append("Tipo de fondo: elige fondo lejano o tramo de nivel")
    if t.get("role"):
        entry["role"] = t["role"]

    link = str(fields.get("link", "")).strip()
    if link:
        used = {a.get(k) for a in assets for k in ("link", "floor_link", "glow_link")}
        if not LINK_PATTERN.fullmatch(link):
            errors.append("Enlace: usa claves con puntos, por ejemplo sprites.goblin")
        elif link in used:
            errors.append(f"Enlace: {link} ya lo usa otro asset")
        entry["link"] = link

    if t["manifest"] == "audio":
        out = _safe_path(fields.get("out"), ".mp3", errors, "Archivo")
        entry["out"] = out
        if t["kind"] == "music":
            entry["length_s"] = _number(fields, "length_s", 10, 600, errors, "Duración (s)")
        else:
            entry["duration_s"] = _number(fields, "duration_s", 0.5, 30, errors, "Duración (s)", float)
    else:
        derived = derive_templates(art_m, audio_m)
        sheet = t["kind"] == "sheet"
        key = "out_dir" if sheet else "out"
        entry[key] = _safe_path(fields.get(key), None if sheet else ".png", errors, "Salida")
        size = str(fields.get("size", ""))
        if size not in allowed_sizes(art_m):
            errors.append(f"Tamaño: usa uno de {', '.join(allowed_sizes(art_m))} (1024x512 falla)")
        entry["size"] = size
        if sheet:
            entry["columns"] = _number(fields, "columns", 1, 8, errors, "Columnas")
            entry["rows"] = _number(fields, "rows", 1, 8, errors, "Filas")
            if entry["columns"] and entry["rows"] and entry["columns"] * entry["rows"] > 16:
                errors.append("Rejilla: como máximo 16 fotogramas por hoja")
        background = str(fields.get("background", "transparent"))
        if background not in ("transparent", "opaque"):
            errors.append("Fondo: transparente u opaco")
        entry["background"] = background
        refs = fields.get("reference") or []
        refs = [str(r) for r in (refs if isinstance(refs, list) else [refs]) if str(r).strip()]
        unknown = [r for r in refs if r not in {a["id"] for a in art_m.get("assets", [])}]
        if unknown:
            errors.append(f"Referencias: no existen {', '.join(unknown)}")
        if type_id == "animacion" and not refs:
            errors.append("Personaje: elige a qué personaje anima (se manda como referencia)")
        if refs:
            entry["reference"] = refs
        entry["pixel_height"] = _number(fields, "pixel_height", 8, 480, errors, "Alto en pixel art")
        if sheet:
            entry["fps"] = _number(fields, "fps", 1, 60, errors, "Fotogramas por segundo")
            entry["loop"] = bool(fields.get("loop"))
        if isinstance(entry["pixel_height"], int):
            entry["game_height"] = entry["pixel_height"] * derived["game_scale"]
        anchor = derived["types"][type_id].get("anchor")
        if sheet and anchor:
            entry["anchor"] = anchor
    entry["prompt"] = prompt

    # Never point a new entry at a file that already exists: it would look generated
    # and a regeneration would move someone else's file to the history.
    out_key = "out" if "out" in entry else "out_dir"
    if not errors:
        others = {_folder(a) + "/" + a["id"] if a.get("out_dir") else a.get("out") for a in assets}
        mine = entry["out"] if out_key == "out" else entry["out_dir"] + "/" + asset_id
        if mine in others:
            errors.append("Salida: otro asset ya usa ese archivo")
        elif out_key == "out" and (ROOT / entry["out"]).exists():
            errors.append(f"Salida: ya existe {entry['out']}; elige otro nombre")
    return entry, errors


def _asset_spans(text: str) -> tuple[int, int, list[tuple[int, int]]]:
    """Where the "assets" array and each of its entries sit in the raw text: (open, close, spans)."""
    key = re.search(r'"assets"\s*:\s*\[', text)
    if key is None:
        raise ValueError('el manifiesto no tiene la lista "assets"')
    decoder, spans, i = json.JSONDecoder(), [], key.end()
    while True:
        while text[i] in " \t\r\n,":
            i += 1
        if text[i] == "]":
            return key.end() - 1, i, spans
        _, end = decoder.raw_decode(text, i)
        spans.append((i, end))
        i = end


def _write_checked(path: Path, new_text: str, expected: dict) -> None:
    """Writes only if the new text parses to exactly [expected]; atomic through a .tmp file."""
    if json.loads(new_text) != expected:
        raise ValueError("la edición cambiaría otra parte del manifiesto; no se guardó")
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(new_text.encode("utf-8"))
    os.replace(temporary, path)


def append_entry(kind: str, entry: dict) -> None:
    """Adds [entry] at the end of "assets", in the same style as the last entry.

    One-line entries (the audio manifest) get one line; indented entries (the art
    manifest) get the same indentation. Line endings (CRLF or LF) are kept.
    """
    path = MANIFESTS[kind]
    text = path.read_bytes().decode("utf-8")
    newline = "\r\n" if "\r\n" in text else "\n"
    opening, closing, spans = _asset_spans(text)
    if spans:
        start, end = spans[-1]
        line_start = text.rfind("\n", 0, start) + 1
        indent = text[line_start:start] if not text[line_start:start].strip() else "    "
        compact = "\n" not in text[start:end]
    else:
        start = end = opening + 1
        indent, compact = "    ", False
    body = json.dumps(entry, ensure_ascii=False) if compact else \
        json.dumps(entry, ensure_ascii=False, indent=2).replace("\n", newline + indent)
    if spans:
        new_text = text[:end] + "," + newline + indent + body + text[end:]
    else:
        new_text = text[:opening + 1] + newline + indent + body + newline + "  " + text[closing:]
    expected = json.loads(text)
    expected["assets"].append(entry)
    _write_checked(path, new_text, expected)


def is_generated(kind: str, asset_id: str) -> bool:
    manifest = art.load_manifest() if kind == "image" else audio.load_json(audio.MANIFEST)
    asset = next(a for a in manifest["assets"] if a["id"] == asset_id)
    if kind == "image":
        return art.raw_path(asset_id).exists() or bool(image_frames(asset))
    return (ROOT / asset.get("out", "-")).exists()


def delete_entry(kind: str, asset_id: str) -> None:
    """Removes an entry that was never generated. Files are never touched."""
    if is_generated(kind, asset_id):
        raise ValueError("ya tiene archivos generados; no se borra desde aquí")
    manifest = art.load_manifest() if kind == "image" else audio.load_json(audio.MANIFEST)
    users = [a["id"] for a in manifest["assets"] if asset_id in (a.get("reference") or [])]
    if users:
        raise ValueError(f"lo usan como referencia: {', '.join(users)}")
    path = MANIFESTS[kind]
    text = path.read_bytes().decode("utf-8")
    opening, closing, spans = _asset_spans(text)
    ids = [json.loads(text[s:e]).get("id") for s, e in spans]
    index = ids.index(asset_id)
    start, end = spans[index]
    if len(spans) == 1:
        new_text = text[:opening + 1] + text[closing:]
    elif index > 0:
        new_text = text[:spans[index - 1][1]] + text[end:]           # drops ", <entry>"
    else:
        new_text = text[:start] + text[spans[1][0]:]                   # drops "<entry>, "
    expected = json.loads(text)
    expected["assets"] = [a for a in expected["assets"] if a.get("id") != asset_id]
    _write_checked(path, new_text, expected)


# --- Generation jobs --------------------------------------------------------

class Job:
    """One run of a generator. The page polls /api/job and receives the new log lines."""

    def __init__(self, kind: str, asset_id: str, dry_run: bool) -> None:
        self.id = str(int(time.time() * 1000))
        self.kind, self.asset_id, self.dry_run = kind, asset_id, dry_run
        self.lines: list[str] = []
        self.status = "running"          # running -> ok | error
        self.started = time.time()
        self.finished: float | None = None

    def start(self) -> None:
        script = GENERATORS[self.kind]
        flags = ["--only", self.asset_id, "--dry-run" if self.dry_run else "--force"]
        self.lines.append("$ python " + " ".join([script.relative_to(ROOT).as_posix(), *flags]))
        # -u and PYTHONIOENCODING: unbuffered UTF-8 output, so lines arrive live and
        # accents do not break on a Windows console code page.
        env = {**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONUNBUFFERED": "1"}
        try:
            self.process = subprocess.Popen(
                [sys.executable, "-u", str(script), *flags], cwd=ROOT, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        except OSError as error:
            self._finish(f"No pude iniciar el generador: {error}", failed=True)
            return
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self) -> None:
        secrets = [k for k in (art.get_api_key(), audio.get_api_key()) if k]
        for line in self.process.stdout:
            for secret in secrets:
                line = line.replace(secret, "[clave oculta]")
            self.lines.append(line.rstrip("\n"))
        code = self.process.wait()
        # The generators print "[error] <id> ..." and still exit 0, so check both.
        failed = code != 0 or any(line.startswith("[error]") for line in self.lines)
        self._finish(f"(terminó con código {code})", failed)

    def _finish(self, message: str, failed: bool) -> None:
        self.lines.append(message)
        self.status = "error" if failed else "ok"
        self.finished = time.time()

    def as_dict(self, since: int = 0) -> dict:
        return {"id": self.id, "kind": self.kind, "asset_id": self.asset_id, "dry_run": self.dry_run,
                "status": self.status, "since": since, "lines": self.lines[since:], "total": len(self.lines),
                "seconds": round((self.finished or time.time()) - self.started, 1)}


_job: Job | None = None
_job_lock = threading.Lock()


def job_running() -> bool:
    return _job is not None and _job.status == "running"


def start_job(kind: str, asset_id: str, dry_run: bool) -> Job | None:
    """Starts a job, or returns None when one is already running (one at a time)."""
    global _job
    with _job_lock:
        if job_running():
            return None
        _job = Job(kind, asset_id, dry_run)
        _job.start()
        return _job


# --- HTTP -------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        if self.command == "POST":           # only log actions, not every file the page loads
            super().log_message(fmt, *args)

    def _send(self, status: int, body: bytes, content_type: str, headers: dict | None = None) -> None:
        try:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-cache")
            for name, value in (headers or {}).items():
                self.send_header(name, value)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass                             # the browser cancelled (normal when you skip through audio)

    def _json(self, data: dict, status: int = HTTPStatus.OK) -> None:
        self._send(status, json.dumps(data, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def _error(self, message: str, status: int = HTTPStatus.BAD_REQUEST) -> None:
        self._json({"error": message}, status)

    def do_HEAD(self) -> None:
        self.do_GET()

    def do_GET(self) -> None:
        url = urlparse(self.path)
        path = url.path
        if path in ("/", "/index.html"):
            self._serve(STUDIO_DIR / "index.html", STUDIO_DIR)
        elif path.startswith("/static/"):
            self._serve(STUDIO_DIR / unquote(path[len("/static/"):]), STUDIO_DIR)
        elif path.startswith("/files/"):
            self._serve(ASSETS_DIR / unquote(path[len("/files/"):]), ASSETS_DIR)
        elif path == "/api/images":
            self._json(list_images())
        elif path == "/api/audio":
            self._json(list_audio())
        elif path == "/api/templates":
            try:
                self._json(derive_templates(*load_manifests()))
            except (OSError, ValueError, KeyError) as error:
                self._error(f"No pude leer los manifiestos: {error}", HTTPStatus.INTERNAL_SERVER_ERROR)
        elif path == "/api/job":
            since = int(parse_qs(url.query).get("since", ["0"])[0] or 0)
            self._json({"job": _job.as_dict(since) if _job else None})
        else:
            self._error("no encontrado", HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        except ValueError:
            return self._error("el cuerpo no es JSON válido")
        path = urlparse(self.path).path
        if path in ("/api/preview", "/api/create"):
            return self._create(body, preview=path == "/api/preview")
        kind, asset_id = str(body.get("kind", "")), str(body.get("id", ""))
        if kind not in MANIFESTS:
            return self._error("kind debe ser image o audio")
        try:
            if asset_id not in manifest_ids(kind):
                return self._error(f"no existe el id {asset_id}", HTTPStatus.NOT_FOUND)
        except (OSError, ValueError) as error:
            return self._error(f"No pude leer el manifiesto: {error}", HTTPStatus.INTERNAL_SERVER_ERROR)

        if path in ("/api/prompt", "/api/job") and "prompt" in body:
            prompt = str(body["prompt"]).replace("\r\n", "\n").strip()
            if not prompt:
                return self._error("el prompt está vacío")
            if job_running():
                return self._error("Hay una generación en curso: espera a que termine.", HTTPStatus.CONFLICT)
            try:
                save_prompt(kind, asset_id, prompt)
            except (OSError, ValueError) as error:
                return self._error(f"No se guardó el prompt: {error}", HTTPStatus.INTERNAL_SERVER_ERROR)

        if path == "/api/prompt":
            self._json({"ok": True})
        elif path == "/api/job":
            job = start_job(kind, asset_id, bool(body.get("dry_run")))
            if job is None:
                return self._error("Ya hay una generación en curso: espera a que termine.", HTTPStatus.CONFLICT)
            self._json({"job": job.as_dict()})
        elif path == "/api/delete":
            if job_running():
                return self._error("Hay una generación en curso: espera a que termine.", HTTPStatus.CONFLICT)
            try:
                delete_entry(kind, asset_id)
            except (OSError, ValueError) as error:
                return self._error(f"No se eliminó: {error}", HTTPStatus.CONFLICT)
            self._json({"ok": True})
        elif path == "/api/restore":
            if job_running():
                return self._error("Hay una generación en curso: espera a que termine.", HTTPStatus.CONFLICT)
            try:
                self._json({"ok": True, "warnings": restore_version(kind, asset_id, str(body.get("name", "")))})
            except (OSError, ValueError, KeyError, StopIteration) as error:
                self._error(f"No se pudo restaurar: {error}")
        else:
            self._error("no encontrado", HTTPStatus.NOT_FOUND)

    def _create(self, body: dict, preview: bool) -> None:
        """Validates the "Crear nuevo" form; previews the final prompt, or appends (and maybe generates)."""
        type_id, fields = str(body.get("type", "")), body.get("fields") or {}
        try:
            art_m, audio_m = load_manifests()
        except (OSError, ValueError) as error:
            return self._error(f"No pude leer los manifiestos: {error}", HTTPStatus.INTERNAL_SERVER_ERROR)
        entry, errors = build_entry(type_id, fields, art_m, audio_m)
        if errors:
            return self._json({"error": "Revisa el formulario.", "errors": errors, "entry": entry}, HTTPStatus.BAD_REQUEST)
        kind = TYPES[type_id]["manifest"]
        # The same function generate_art.py uses, so this IS the text a --dry-run prints.
        final = art.build_prompt(art_m, entry) if kind == "image" else entry["prompt"]
        manifest = MANIFESTS[kind].relative_to(ROOT).as_posix()
        if preview:
            return self._json({"entry": entry, "final_prompt": final, "manifest": manifest})
        if job_running():
            return self._error("Hay una generación en curso: espera a que termine.", HTTPStatus.CONFLICT)
        try:
            append_entry(kind, entry)
        except (OSError, ValueError) as error:
            return self._error(f"No se guardó: {error}", HTTPStatus.INTERNAL_SERVER_ERROR)
        result = {"entry": entry, "kind": kind, "manifest": manifest}
        if body.get("generate"):
            job = start_job(kind, entry["id"], False)
            result["job"] = job.as_dict() if job else None
        self._json(result)

    def _serve(self, target: Path, base: Path) -> None:
        """Serves one file that lives inside [base]. Supports Range, which the audio player uses to seek."""
        target = target.resolve()
        if base not in target.parents or not target.is_file():
            return self._error("no encontrado", HTTPStatus.NOT_FOUND)
        data = target.read_bytes()
        content_type = CONTENT_TYPES.get(target.suffix.lower(), "application/octet-stream")
        match = re.fullmatch(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        if not match or not any(match.groups()):
            return self._send(HTTPStatus.OK, data, content_type, {"Accept-Ranges": "bytes"})
        first, last = match.groups()
        start = int(first) if first else max(0, len(data) - int(last))
        end = min(int(last), len(data) - 1) if first and last else len(data) - 1
        if start > end:
            return self._send(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE, b"", content_type,
                              {"Content-Range": f"bytes */{len(data)}"})
        self._send(HTTPStatus.PARTIAL_CONTENT, data[start:end + 1], content_type,
                   {"Accept-Ranges": "bytes", "Content-Range": f"bytes {start}-{end}/{len(data)}"})


class StudioServer(ThreadingHTTPServer):
    # On Windows SO_REUSEADDR lets a SECOND server grab a busy port silently; we want a clear error instead.
    allow_reuse_address = sys.platform != "win32"
    daemon_threads = True


def main() -> int:
    parser = argparse.ArgumentParser(description="Estudio de assets (imágenes y audio)")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-browser", action="store_true", help="no abrir el navegador")
    args = parser.parse_args()
    try:
        server = StudioServer(("127.0.0.1", args.port), Handler)
    except OSError as error:
        print(f"No pude abrir el puerto {args.port} ({error}).\n"
              f"¿Ya tienes el estudio abierto? Prueba con: python tools/studio/server.py --port {args.port + 1}")
        return 1
    url = f"http://127.0.0.1:{args.port}"
    print(f"Estudio de assets en {url}  (Ctrl+C para cerrar)", flush=True)
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
