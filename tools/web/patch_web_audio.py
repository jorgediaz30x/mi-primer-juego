"""Parche de audio para la exportación web de Godot 4.x.

El problema: al arrancar, el juego web de Godot carga un procesador de audio
(AudioWorklet) en el AudioContext del navegador. En algunos navegadores esa carga
(audioWorklet.addModule) nunca termina, y mientras está pendiente el navegador no
deja reanudar el audio: el contexto queda en "suspended" aunque hagas clic, y el
juego queda mudo.

El arreglo: hacer que Godot use el camino de audio sin AudioWorklet
(ScriptProcessor, que funciona en todos los navegadores) y que no cargue el
procesador de posición, que solo se usa en el modo de audio "Sample". Por eso el
proyecto tiene que usar el modo "Stream" en la web:

    [audio]
    general/default_playback_type.web=0

Uso, después de cada exportación web:

    python tools/web/patch_web_audio.py build/web

El script no hace nada si el archivo ya estaba parcheado, y falla con un mensaje
claro si la exportación cambió y ya no encuentra lo que tiene que reemplazar.
"""

import sys
from pathlib import Path

# Cada par: (texto original de index.js, reemplazo).
PATCHES = [
    (
        "function _godot_audio_has_worklet(){return GodotAudio.ctx&&GodotAudio.ctx.audioWorklet?1:0}",
        "function _godot_audio_has_worklet(){return 0}",
    ),
    (
        "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path);",
        "GodotAudio.audioPositionWorkletPromise=Promise.resolve();",
    ),
]


def patch(build_dir: Path) -> int:
    js_files = [p for p in build_dir.glob("*.js") if not p.name.endswith(".worklet.js")]
    if not js_files:
        print(f"error: no hay archivos .js del motor en {build_dir}", file=sys.stderr)
        return 1
    engine = max(js_files, key=lambda p: p.stat().st_size)  # el JS del motor es el más grande
    text = engine.read_text(encoding="utf-8")
    changed = 0
    for original, replacement in PATCHES:
        if replacement in text:
            continue
        if original not in text:
            print(f"error: no encontré en {engine.name}:\n  {original}\n"
                  "La versión de Godot cambió; revisa el parche.", file=sys.stderr)
            return 1
        text = text.replace(original, replacement)
        changed += 1
    engine.write_text(text, encoding="utf-8")
    print(f"{engine.name}: {changed} cambio(s) aplicados" if changed else f"{engine.name}: ya estaba parcheado")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("uso: python tools/web/patch_web_audio.py <carpeta de la exportación web>", file=sys.stderr)
        sys.exit(2)
    sys.exit(patch(Path(sys.argv[1])))
