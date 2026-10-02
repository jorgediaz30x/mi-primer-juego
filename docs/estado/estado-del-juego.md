# Estado del juego: documento de traspaso

**Para qué sirve:** si abres una sesión nueva (con Claude Code u otro modelo), pásale este
archivo primero. Resume qué se pidió, qué se decidió y cómo está construido el juego, para no
tener que explicarlo de nuevo. Fecha: 30 de septiembre de 2026.

Prompt sugerido para empezar una sesión nueva:

> Lee `docs/estado/estado-del-juego.md` y, si lo necesitas, `docs/notas/conversacion-completa.md`.
> Ese es el estado del juego y lo que ya decidí. No cambies esas decisiones sin preguntarme.
> Lo siguiente que quiero hacer es: ...

---

## 1. Qué es el juego

**Vallebruma: El Bosque Umbrío.** Es un juego de acción 2D en pixel art, hecho en Godot 4.7.2
con GDScript. Está inspirado en una escuela de magia, pero todos los nombres son originales:
nada de propiedad intelectual de Harry Potter.

- **Héroe:** Nico Ravel. **Villano y jefe final:** Morvane.
- **Estructura:** la de Cuphead. Se avanza con scroll lateral por tres niveles y el último
  termina contra el jefe.
- **Ritmo:** rápido y castigador como Hotline Miami, pero en vista lateral y sin gore.
- **Niveles:**
  1. **El Bosque Umbrío:** solo arañas.
  2. **La Cueva de los Aullidos:** oscura, con lobos y arañas. Aquí sirve Lumos.
  3. **El Cementerio de la Tormenta:** con relámpagos. Termina contra Morvane.

## 2. Decisiones del usuario (no cambiarlas sin preguntar)

**Arte y tono**
- **Todo el arte sale de GPT Image.** Nada de dibujos del modelo, nada de emojis, nada de
  "diseño propio". Solo se permiten cajas grises como marcador mientras falta un asset.
- **Pixel art** para todo: personajes, animaciones, efectos, fondos e interfaz.
- **Nada de plataformas flotantes.** El mundo está al nivel del suelo, y los enemigos llegan
  desde el techo y los costados. Los pisos tienen que verse parte del fondo, no PNG pegados.
- **La cueva tiene que ser una cueva de verdad:** arte propio (piso de piedra, cristales que
  brillan), no el bosque oscurecido.
- **El jefe tiene que sentirse como uno de Cuphead:** entrada con cartel de título, ataques
  anunciados antes de que lleguen y cambio de forma entre fases.
- **Textos del juego y del chat en español neutro (tú).** Nada de voseo ni modismos regionales.
- **Fuente:** Pixelify Sans.

**Control**
- El personaje mira hacia donde apunta el mouse, y se dispara con un puntero.

**Progresión**
- **No hay árbol de habilidades:** el usuario no lo entendía. Se usan **cartas**: al subir
  de nivel se elige 1 de 3.
- **10 segundos para elegir.** Si se acaba el tiempo, se pierde la mejora.
- **Máximo 4 mejoras.** Con el mazo lleno, la carta nueva **reemplaza la más vieja**, y el
  jugador **no** elige cuál sale: es un castigo deliberado. También se puede rechazar la
  carta y conservar las actuales.
- **Muerte al estilo Bloodborne:** se conservan el nivel, la XP y las cartas, y se reaparece
  en el último punto de control (tecla R). La tecla N empieza una partida de cero.
- **Solo se ofrecen mejoras útiles donde estás.** Nada de más daño en el bosque, donde las
  arañas mueren de un tiro. Las cartas de Lumos aparecen al entrar en la oscuridad.

**Balance**
- El abanico de Fulgor da como máximo **2 rayos**.
- El lobo aguanta varios disparos: 4 le bajan más o menos media barra. Tiene barra de vida
  y es más lento que las arañas.

**Audio**
- Música suave y cálida, estilo Minecraft, que sube de intensidad cuando se acercan enemigos.
- Efectos para todo: arañas, lobos, jefe, hechizos y eventos.

## 3. Controles

| Acción | Tecla |
|---|---|
| Moverse | A / D o flechas |
| Saltar | W, Espacio o flecha arriba |
| Dash | Shift |
| Fulgor (rayo) | Clic izquierdo o J |
| Aerum (levantar y lanzar enemigos) | Clic derecho o K |
| Nova (hechizo de área) | E |
| Lumos (luz; solo funciona en la oscuridad) | F |
| Elegir carta | 1 a 4, o clic |
| Pausa | Esc |
| Reaparecer en el punto de control | R |
| Partida nueva | N |

El juego arranca en una **pantalla de título** (arte a pantalla completa, música y menú:
Continuar / Partida nueva / Opciones / Controles / Salir), no directo en el nivel. Esc
durante una partida abre la pausa (Seguir / Opciones / Controles / Volver al inicio).
Opciones y Controles son pantallas compartidas, alcanzables desde el título y desde la
pausa. Los menús son navegables con teclado (flechas o WASD + Enter/Espacio), mouse y
mando (el foco de teclado/mando usa las acciones `ui_*` propias de Godot, con WASD
agregado encima de las flechas y el D-pad sin tocar sus eventos por defecto).

## 4. Cómo está construido

**Principios del código:**
- **Todos los valores del juego viven en `assets/data/game_config.json`.** Nada se escribe
  directo en el código. Balancear es cambiar números en ese archivo.
- **Inyección de dependencias.** `src/main.gd` es la raíz de composición: crea y conecta todo.
- **La lógica pura va en `src/core/` y tiene tests.** Lo que dibuja o suena va en
  `src/gameplay/`, `src/ui/` y `src/audio/`.
- **Los sistemas se comunican con señales**, nunca llamándose directamente.

```
assets/data/game_config.json   configuración central: textos, jugador, hechizos, enemigos,
                               cartas, niveles, arte, animaciones y audio
src/main.gd                    raíz de composición: partida, guardado, cartas, niveles, audio
src/core/                      lógica pura y testeable
  game_config.gd               lee la config con rutas con puntos ("player.max_hearts")
  upgrade_deck.gd              el mazo de mejoras: tope, reemplazo de la más vieja, flags
  experience.gd                XP y niveles
  encounter_director.gd        oleadas de enemigos por nivel
  boss_brain.gd                fases y patrones de ataque del jefe
  music_mixer.gd               la mezcla de la música adaptativa
  save_store.gd                guardado (versión 3), reutilizado también para settings.json
  settings.gd                  volumen (master/música/sfx, lineal 0..1) y pantalla completa;
                               convierte a dB, aclara y serializa — puro, sin AudioServer
  input_setup.gd               los controles; agrega WASD sobre ui_up/down/left/right
                               (built-in de Godot) sin borrar flechas ni mando
  capture_tool.gd              capturas automáticas para QA (--capture=..., --capture-title,
                               --capture-options, --capture-controls, --capture-pause)
src/gameplay/
  level.gd                     nivel con scroll: encuentros, puntos de control, oscuridad,
                               arena del jefe; emite señales de sonido y de música
  player.gd                    movimiento, corazones y los 4 hechizos más el dash
  enemy.gd, spider.gd, werewolf.gd, boss.gd (Morvane), bolt.gd, boss_*.gd, fx.gd
  sprite_hook.gd               arma las animaciones desde el bloque "animations" de la config
src/ui/                        HUD, pantalla de cartas, estilo y puntero
  title_screen.gd               pantalla de título: arte, menú, relámpago, música
  pause_menu.gd                 menú de pausa (Esc)
  options_screen.gd             volumen y pantalla completa (compartida título/pausa)
  controls_screen.gd            lista de controles (compartida título/pausa)
src/audio/audio_director.gd    reproduce la música y los efectos; crea los buses Music/SFX
                               y aplica Settings encima de la mezcla base de la config
tests/unit/                    89 tests (progression, combat, level, core, audio)
tools/art/                     pipeline de GPT Image: manifiesto y generador
tools/audio/                   pipeline de ElevenLabs: manifiesto y generador
tools/studio/                  estudio de assets: web local para ver, escuchar y regenerar
production/qa/evidence/        capturas de evidencia
```

**Arte (`tools/art/`):**
- `asset_manifest.json` lista cada asset con su prompt.
- `generate_art.py` llama a GPT Image. Después limpia el ruido del canal alfa, corta las
  hojas de sprites, reduce a pixel real y ancla los personajes en los pies.
- El **estudio de assets** (`python tools/studio/server.py`, http://127.0.0.1:8765) reemplaza
  al previsualizador viejo (`preview_server.py`, retirado). Tiene una pestaña de imágenes y
  otra de audio, anima las hojas de sprites, muestra el historial y regenera un asset desde
  el navegador. Para eso corre el generador con `--only <id> --force`, gasta créditos y pide
  confirmación. Detalles en `tools/studio/README.md`.
- Si no existe `assets/data/game_config.json` (repo sin el juego), los generadores igual
  crean el asset y solo avisan que no lo pudieron enlazar.
- En Godot, todo se escala por 3 (`render.pixel_scale`) con filtro nearest.

**Música adaptativa:**
- Cada nivel tiene dos pistas en loop: una tranquila y una de tensión. El juego las mezcla
  según la distancia al enemigo más cercano.
- Durante una pelea, la tensión nunca baja del 55 %.
- La tensión sube rápido y baja despacio.
- El jefe tiene una pista propia.

## 5. Cómo se corre

Godot está en
`C:\Users\PC\Downloads\Godot_v4.7.2-stable_win64.exe\`. Esa ruta es una **carpeta**, con dos
ejecutables: uno de consola y uno con ventana. Los comandos se corren con Bash.

```bash
G="/c/Users/PC/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path . --import                              # 1. importar (siempre primero)
"$G" --headless --path . -s res://tests/run_unit_tests.gd      # 2. tests
"$G" --headless --path . --quit-after 900                      # 3. correr sin ventana y ver errores
"/c/Users/PC/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --path .   # jugar
```

**Ojo:**
- Los tests no cargan `main.gd`, así que después de los tests hay que correr también el
  paso 3.
- Las capturas de QA usan `user://qa_save.json`, para no tocar la partida real
  (`user://save.json`).

**Keys:** van en `.env.local` (ignorado por Git), con `OPENAI_API_KEY` y `ELEVENLABS_API_KEY`.
Nunca se escriben en el código ni se commitean.

## 6. Lecciones de la sesión (para no repetir errores)

- **Verificar lo que dice otra IA:** el código de Gemini usaba un modelo y parámetros de
  OpenAI que no existían.
- **Algunos tamaños fallan:** GPT Image rechaza 1024x512; para imágenes anchas se usa 1536x768.
- **La referencia de estilo contamina:** se copió el piso del bosque en la cueva y el
  personaje en los efectos. Usar referencias sin personajes y prompts por escenario.
- **Calcular cada dato en un solo lugar:** la mira y el disparo calculaban el origen por
  separado, y el tiro salía más arriba del puntero. Ahora comparten `cast_origin()`.
- **Conexiones de señales al reaparecer:** se duplicaban y daban "Signal already connected".
  Se protegen con `is_connected`.
- **Compilar no es verificar:** cada cambio visible se prueba abriendo el juego y se guarda
  una captura.

## 7. Qué falta

Todo lo pendiente está en [pendientes.md](pendientes.md).
