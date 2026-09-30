# Pendientes

Lo que falta del juego, en orden de prioridad. El estado actual está en
[estado-del-juego.md](estado-del-juego.md).

| # | Pendiente | Bloqueado por |
|---|---|---|
| 1 | [Escuchar el audio en el juego y ajustarlo](#1-generar-el-audio-con-elevenlabs) | Tu prueba jugando |
| 2 | [Publicar el juego en la web para que los alumnos lo prueben](#2-publicar-el-juego-en-la-web) | Hay que investigarlo |
| 3 | [Confirmar dos dudas de balance](#3-dudas-de-balance) | Tu respuesta |
| 4 | [Rotar las keys](#4-rotar-las-keys) | Nada |
| 5 | [Hacer el commit](#5-commit) | Tu indicación |

---

## 1. Generar el audio con ElevenLabs

**Estado al 30 de septiembre de 2026: generado.** Se pagó la suscripción y se generaron los
33 archivos sin errores: 4 pistas de música en `assets/audio/music/` y 29 efectos en
`assets/audio/sfx/`. Ninguno está repetido (se comparó el contenido de cada uno).
`game_config.json` ya tiene las 33 rutas.

Verificado:
- Godot importó los 33 archivos.
- El juego corre sin ventana (`--quit-after 900`) sin errores de carga, y la música del
  nivel se carga y suena.

Falta:
- **Escucharlo jugando** y ajustar volúmenes o regenerar los sonidos que no convenzan
  (pasos 5 en adelante).
- Al cerrar el juego, Godot avisa `4 ObjectDB instances were leaked` y `2 resources still
  in use` (`cave.mp3` y `tension.mp3`). Pasa solo al salir, porque las dos pistas siguen
  sonando cuando se cierra el motor. No afecta al juego, pero se puede limpiar deteniendo la
  música en `AudioDirector` al salir del árbol.

Si ElevenLabs vuelve a responder `401 payment_issue`, es la facturación de la cuenta y no
el código: queda bloqueada hasta pagar la factura pendiente, aunque se use una key nueva.
El script toma la **primera** línea `ELEVENLABS_API_KEY=` de `.env.local`, así que tiene que
haber una sola.

---

### Pasos para generar o regenerar

**1. Revisa la key.** Tiene que estar en `.env.local`, en la raíz del proyecto:

```
ELEVENLABS_API_KEY=tu-key
```

Si la rotaste (te lo recomiendo, porque se pegó en el chat), actualízala ahí.

**2. Prueba con un solo efecto** para confirmar que la cuenta ya funciona:

```bash
python tools/audio/generate_audio.py --only sfx_spider_death
```

Tiene que crear `assets/audio/sfx/spider_death.mp3`.

**3. Genera todo lo demás.** Los archivos que ya existen no se vuelven a generar:

```bash
python tools/audio/generate_audio.py
```

El script escribe solo las rutas de cada archivo en `assets/data/game_config.json`, dentro
de `audio.music` y `audio.sfx`.

**4. Importa en Godot y juega:**

```bash
G="/c/Users/PC/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path . --import
"/c/Users/PC/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --path .
```

**5. Escucha y ajusta.**

Para regenerar un sonido que no te guste, cambia su prompt en `tools/audio/audio_manifest.json`
y corre:

```bash
python tools/audio/generate_audio.py --only sfx_wolf_roar --force
```

La versión anterior se guarda en `assets/audio/_history/`. Para ver los prompts sin gastar
créditos, usa `--dry-run`.

Los ajustes de volumen y ritmo están en el bloque `audio` de `game_config.json` y no
requieren tocar código:

| Valor | Qué hace | Actual |
|---|---|---|
| `volumes.music_db` | Volumen de la música | -8 |
| `volumes.sfx_db` | Volumen de los efectos | -4 |
| `sfx_gain_db.<id>` | Ajuste de un efecto puntual, sumado a `sfx_db`. Nivela todos los efectos a -18 LUFS, bajando solo los que salieron más fuertes | Por ejemplo, `wolf_roar` -15, `boss_transform` -15,5, `spider_death` -6,5 |
| `intensity.danger_range` | A qué distancia (px) un enemigo empieza a subir la tensión | 650 |
| `intensity.fight_floor` | Tensión mínima durante una pelea (0 a 1) | 0.55 |
| `intensity.rise` | Qué tan rápido entra la tensión | 2.0 |
| `intensity.fall` | Qué tan rápido vuelve la calma | 0.35 |
| `pitch_jitter` | Variación de tono entre repeticiones | 0.06 |

---

### Qué se va a generar (33 archivos)

**Música** (modelo `music_v2_5`, instrumental):

| Id | Duración | Dónde suena |
|---|---|---|
| `music_forest` | 3:00 | Bosque, pista tranquila |
| `music_cave` | 3:00 | Cueva y cementerio, pista tranquila |
| `music_tension` | 2:00 | Todos los niveles: se mezcla cuando se acercan enemigos |
| `music_boss` | 2:30 | Pelea contra Morvane |

Si quieres una pista tranquila propia para el cementerio: agrega una entrada `music_graveyard`
al manifiesto y cambia `levels[2].music.calm` a `"graveyard"` en `game_config.json`.

**Efectos** (modelo `eleven_text_to_sound_v2`):

| Grupo | Efectos |
|---|---|
| Hechizos | `bolt_cast`, `bolt_hit`, `nova`, `lumos`, `dash`, `levitate`, `throw`, `explosion` |
| Arañas | `spider_spawn`, `spider_death` |
| Lobos | `wolf_roar` (al aparecer y al preparar la embestida), `wolf_hurt`, `wolf_death` |
| Morvane | `boss_intro`, `boss_cast`, `boss_orb`, `boss_teleport`, `boss_beam`, `boss_shockwave`, `boss_transform`, `boss_hurt`, `boss_death` |
| Jugador | `player_hurt`, `player_death` |
| Eventos | `level_up`, `card_pick`, `warning`, `checkpoint`, `level_complete` |

Los prompts de cada uno están en `tools/audio/audio_manifest.json`. Describen el estilo sin
nombrar artistas ni juegos, porque ElevenLabs rechaza los prompts con nombres propios.

---

### Cómo está conectado (por si hay que tocarlo)

- `src/audio/audio_director.gd` reproduce la música y los efectos:
  - Usa un grupo de 12 reproductores para los efectos.
  - Si el mismo sonido se pide muchas veces seguidas (10 arañas muriendo a la vez), suena
    una sola vez.
  - Si falta un archivo, no suena, pero no da error.
- `src/core/music_mixer.gd` hace la mezcla de la música adaptativa. Es lógica pura y tiene
  tests en `tests/unit/audio/`.
- `src/gameplay/level.gd` emite las señales:
  - `sfx(id)` para cada efecto.
  - `music(tranquila, tensión)` para cambiar la música.
  - `combat_target()` indica cuánta tensión debería sonar en cada momento.
- `src/main.gd` crea el `AudioDirector` y conecta esas señales. También reproduce
  `level_up`, `card_pick` y `level_complete`.

---

## 2. Publicar el juego en la web

**Objetivo:** que los alumnos jueguen desde el navegador, con audio, sin instalar nada.

**Estado al 30 de septiembre de 2026: exporta y corre en el navegador.** Falta publicarlo
en Vercel y escucharlo.

Verificado:
- **Plantillas de exportación de 4.7.2:** instaladas en
  `%APPDATA%/Godot/export_templates/4.7.2.stable/`.
- **Preset "Web"** en `export_presets.cfg`: sin hilos (`variant/thread_support=false`), con
  compresión de texturas solo para escritorio. Incluye `assets/data/*.json`, que Godot no
  exporta solo porque no es un recurso, y excluye `_raw`, `_history`, `tests`, `tools`,
  `docs` y `production`. Ojo: el `.gitignore` del framework ignora este archivo, así que
  se agregó a la fuerza.
- **Sin hilos, a propósito:** así no hacen falta las cabeceras COOP/COEP en el servidor. Es
  lo más simple para un alumno.
- **Exportación sin ventana:**
  `godot --headless --path . --export-release "Web" build/web/index.html`. Terminó sin
  errores ni avisos, y Godot no pidió habilitar nada.
- **Peso:** unos 53 MB en total. `index.wasm` pesa 39,5 MB y `index.pck` 13,5 MB, con todo
  el arte y la música.
- **Prueba local en Edge sin ventana:** la pantalla de inicio se ve bien (Continuar y Salir
  no aparecen: no hay partida guardada y en web no se puede salir). Partida nueva arranca
  el nivel 1 con el arte y la interfaz correctos. La consola no muestra errores. Capturas:
  `production/qa/evidence/web_title.png` y `web_gameplay.png`.

Falta:
- **Escucharlo.** Una prueba automática no oye el audio; se prueba abriendo la página.
- **Publicado en Vercel** el 30 de septiembre de 2026: https://vallebruma.vercel.app
  (cuenta personal `jorgediaz-1021`, proyecto `vallebruma`). Se publicó con
  `cd build/web && vercel deploy --prod --yes --name vallebruma --scope jorgediaz-1021`.
  Carga y arranca el nivel 1 sin errores en la consola. Hay que pasar `--scope` porque la
  cuenta también tiene un equipo, y la CLI no deja elegir sin preguntar. Las URLs con el
  hash del deploy piden iniciar sesión en Vercel; la pública es la de arriba.
  `build/web/vercel.json` solo agrega caché para `index.wasm` y `index.pck`. Ojo: Vercel
  rechaza un `\.` dentro de `source`, porque no es JSON válido.
- Confirmar que el guardado sobrevive al recargar la página, y que las luces de la cueva se
  ven igual.

---

## 3. Dudas de balance

- Si "máximo a dos" era solo para los rayos del abanico (así se implementó) o para el total
  de mejoras.
- Si Nova (el hechizo de área) también te hace sentir invencible.

---

## 4. Rotar las keys

Las keys de ElevenLabs y OpenAI se pegaron en el chat. Hay que generar keys nuevas en cada
panel y reemplazarlas en `.env.local`. La key de ElevenLabs que se usó el 30 de septiembre
para generar el audio también se pegó en el chat, así que también hay que rotarla.

---

## 5. Commit

Nada del juego ni de estos documentos está commiteado todavía. Se hace cuando lo indiques.
