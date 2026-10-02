"""Deja el proyecto como queda al terminar una clase del curso.

Uso:
    python tools/curso/clase.py 4        (inicio, 4, 5, 6, 7, 8 o final)

El juego terminado vive en tools/curso/juego-completo/ (Godot lo ignora por el
.gdignore). Este comando copia a la raíz solo lo que se generó hasta esa clase,
y deja en los manifiestos solo lo de esa clase, así el Estudio muestra solo eso:

    inicio  la plantilla sin juego (lo que hay en git)
    4       el arte: personajes, fondos, efectos e interfaz  -> Estudio: solo el arte
    5       + el juego en Godot, sin animación ni sonido       -> Estudio: solo el arte
    6       + las animaciones                                  -> Estudio: solo las animaciones
    7       + la música y los efectos de sonido                -> Estudio: solo el audio
    8       el juego terminado, con el preset de exportación   -> Estudio: todo

Solo toca los archivos que están en juego-completo/. Para volver al principio:
python tools/curso/clase.py inicio
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT = ROOT / "tools" / "curso" / "juego-completo"
ART_MANIFEST = "tools/art/asset_manifest.json"
AUDIO_MANIFEST = "tools/audio/audio_manifest.json"
CONFIG = "assets/data/game_config.json"
CLASSES = {"inicio": 0, "1": 0, "2": 0, "3": 0, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "final": 8}


def is_animation(asset: dict) -> bool:
    """Same rule as tools/studio/server.py image_category(): a sheet with no role is a character animation."""
    return asset.get("kind") == "sheet" and not asset.get("role") \
        and not asset.get("link", "").startswith(("ui.", "vfx."))


def animation_ids() -> set[str]:
    assets = json.loads((SNAPSHOT / ART_MANIFEST).read_text(encoding="utf-8"))["assets"]
    return {a["id"] for a in assets if is_animation(a)}


def kind_of(path: str, anim: set[str]) -> str:
    """Which class adds this file: art, animation, game, audio or export."""
    name = path.rsplit("/", 1)[-1]
    if path.startswith("assets/audio/"):
        return "audio"
    if path == "export_presets.cfg":
        return "export"
    if path.startswith("assets/art/"):
        for asset_id in anim:
            if re.fullmatch(re.escape(asset_id) + r"(_\d{2})?\.png(\.import)?", name):
                return "animation"
        return "art"
    if path.startswith("tools/"):
        return "art"
    return "game"


def included(kind: str, level: int) -> bool:
    first = {"art": 4, "game": 5, "animation": 6, "audio": 7, "export": 8}[kind]
    return level >= first


def asset_spans(text: str) -> tuple[int, int, list[tuple[int, int]]]:
    """Start/end of the assets array body and the span of every object inside it."""
    start = text.index("[", text.index('"assets"')) + 1
    spans, depth, in_str, esc, obj_start, i = [], 0, False, False, 0, start
    while True:
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "{":
            if depth == 0:
                obj_start = i
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                spans.append((obj_start, i + 1))
        elif c == "]" and depth == 0:
            return start, i, spans
        i += 1


def filter_manifest(rel: str, keep) -> None:
    """Keeps only the assets where keep(asset) is true, without touching the hand formatting."""
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    assets = json.loads(text)["assets"]
    start, end, spans = asset_spans(text)
    kept = [text[a:b] for (a, b), asset in zip(spans, assets) if keep(asset)]
    body = ""
    if kept:
        indent = text[text.rfind("\n", 0, spans[0][0]) + 1:spans[0][0]]
        tail_indent = text[text.rfind("\n", 0, end) + 1:end]
        body = "\n" + ",\n".join(indent + k for k in kept) + "\n" + tail_indent
    new_text = text[:start] + body + text[end:]
    json.loads(new_text)
    path.write_text(new_text, encoding="utf-8")


def clear_config(keys: list[str]) -> None:
    """Empties config sections whose files are not there yet: the game falls back to fixed sprites and silence."""
    path = ROOT / CONFIG
    config = json.loads(path.read_text(encoding="utf-8"))
    for dotted in keys:
        *parents, last = dotted.split(".")
        node = config
        for key in parents:
            node = node[key]
        node[last] = {}
    path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def reset(files: list[str]) -> None:
    """Puts every managed file back to what git has (or removes it when git does not have it)."""
    tracked = set(subprocess.run(["git", "-C", str(ROOT), "ls-files", "--", *sorted({f.split("/")[0] for f in files})],
                                 capture_output=True, text=True, check=True).stdout.splitlines())
    restore = [f for f in files if f in tracked]
    for f in files:
        if f not in tracked:
            (ROOT / f).unlink(missing_ok=True)
    if restore:
        subprocess.run(["git", "-C", str(ROOT), "checkout", "HEAD", "--", *restore], check=True)
    for folder in sorted({(ROOT / f).parent for f in files}, key=lambda p: len(p.parts), reverse=True):
        while folder != ROOT and folder.is_dir() and not any(folder.iterdir()):
            folder.rmdir()
            folder = folder.parent


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in CLASSES:
        print("Uso: python tools/curso/clase.py <clase>   (inicio, 4, 5, 6, 7, 8 o final)")
        return 1
    level = CLASSES[sys.argv[1]]
    files = sorted(p.relative_to(SNAPSHOT).as_posix() for p in SNAPSHOT.rglob("*")
                   if p.is_file() and p.name != ".gdignore")
    anim = animation_ids()

    reset(files)
    if level:
        for f in files:
            if included(kind_of(f, anim), level):
                target = ROOT / f
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(SNAPSHOT / f, target)

    # The Studio lists what the manifests list: leave only what this class generates.
    if level in (4, 5):
        filter_manifest(ART_MANIFEST, lambda a: not is_animation(a))
        filter_manifest(AUDIO_MANIFEST, lambda a: False)
    elif level == 6:
        filter_manifest(ART_MANIFEST, is_animation)
        filter_manifest(AUDIO_MANIFEST, lambda a: False)
    elif level == 7:
        filter_manifest(ART_MANIFEST, lambda a: False)
    if level == 5:
        clear_config(["animations", "audio.music", "audio.sfx"])
    elif level == 6:
        clear_config(["audio.music", "audio.sfx"])

    print(f"Listo: el proyecto quedó como al terminar la clase {sys.argv[1]}.")
    if level >= 5:
        print("Abre Godot una vez para que importe los assets nuevos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
