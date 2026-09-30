# Estudio de assets

Una página web local para **ver, escuchar y regenerar** todos los assets del juego:
las imágenes que pide `tools/art/generate_art.py` a GPT Image y el audio que pide
`tools/audio/generate_audio.py` a ElevenLabs.

El estudio no llama a ninguna API por su cuenta. Cuando regeneras algo, corre el mismo
generador que usarías en la terminal. Así hay una sola fuente de verdad: los manifiestos y
los dos scripts.

## Cómo abrirlo

```bash
python tools/studio/server.py
```

Se abre el navegador en **http://127.0.0.1:8765** (es lo mismo que `localhost:8765`). Para
cerrarlo, pulsa `Ctrl+C` en la terminal.

```bash
python tools/studio/server.py --port 9000       # otro puerto, si el 8765 está ocupado
python tools/studio/server.py --no-browser      # no abrir el navegador
```

Solo necesitas Python 3.10 o más reciente. No hay que instalar nada: todo es biblioteca
estándar, y la página es HTML, CSS y JavaScript sin build ni CDN, así que funciona sin
internet. El servidor escucha solo en `127.0.0.1`, así que nadie más en tu red puede
entrar.

## Pestaña Imágenes

- **Categorías**: Personajes, Animaciones, Fondos y niveles, Efectos, Interfaz e iconos.
  Salen de los campos que ya tiene el manifiesto (`kind`, `role` y el prefijo de `link`),
  así que no hay que agregar nada.
- **Estado**: Generados o Sin generar. Un asset que todavía no existe muestra
  "Sin generar" y un botón **Generar**.
- **Búsqueda** (tecla `/`): busca en el id y en el prompt. No distingue tildes.
- **Fondo**: cuadros (para ver la transparencia), oscuro o claro.
- Las tarjetas muestran el pixel art con **zoom entero** y sin suavizado. Las animaciones se
  mueven solas, a los fps del manifiesto.

Al hacer clic en una tarjeta se abre el **panel de detalle**:

- **En el juego**: los PNG finales, tal como los carga Godot, con zoom de 1x a 8x.
  Si es una animación, se reproduce con play/pausa, fotograma anterior y siguiente, y
  control de fps. También hay una tira con todos los fotogramas. Atajos: `Espacio` y
  las flechas.
- **Original**: la imagen en alta resolución que devolvió GPT Image. En una hoja de
  sprites se dibuja la rejilla (`columns` x `rows`) y se resalta la celda que se está
  reproduciendo. Es el mismo corte que hace `sprite_ops.slice_grid`.
- **Comparar**: la versión actual al lado de una versión anterior de `assets/art/_history/`.
  Si una versión anterior te gusta más, puedes **restaurarla**. Restaurar es gratis:
  la actual pasa al historial y se rehacen los PNG del juego.
- **Datos**: tamaño real en píxeles, archivo de salida, original, modelo, tamaño pedido,
  rejilla, fps y referencias.

## Pestaña Audio

- Se divide en **Música** y **Efectos**. Los efectos se agrupan por el prefijo del id
  (`sfx_boss_*`, `sfx_wolf_*`...); los sueltos van a "Varios". Si quieres otro grupo,
  agrega `"group": "Jefe"` a la entrada del manifiesto.
- Cada fila tiene reproducir y detener, la forma de onda (haz clic en ella para saltar a ese
  punto), la duración, el prompt, el modelo, el archivo y el nivel medido (RMS y pico, en
  dB).
- La música tiene la casilla **Loop**, activada como en el juego.
- **Editar** abre el prompt y las versiones anteriores de `assets/audio/_history/`, que
  también puedes escuchar y restaurar.

## Regenerar (esto gasta créditos)

1. Edita el prompt en el cuadro de texto.
2. **Ver prompt final** (gratis) corre el generador con `--dry-run`. Muestra el texto
   completo que se enviaría: el estilo común, las reglas de la hoja y tu prompt. Muestra la
   versión **guardada**, así que guarda antes si cambiaste algo.
3. **Regenerar** (o **Generar**) pide confirmación, porque llama a la API y **gasta
   créditos**. Al confirmar:
   - se guarda tu prompt en el manifiesto. Solo cambia ese texto: el resto del archivo
     queda igual, con su formato y sus tildes;
   - se corre `python tools/art/generate_art.py --only <id> --force` (o
     `generate_audio.py`);
   - el registro aparece abajo en vivo, y los errores se ven tal cual los imprime el
     generador;
   - la versión anterior pasa a `_history/` (no se pierde nada) y la página muestra la
     nueva.

Solo corre **una generación a la vez**. Si una imagen usa otra como referencia (`reference`),
primero genera la referencia: el generador te lo avisa.

Si el repo todavía no tiene el juego (no existe `assets/data/game_config.json`), los
generadores igual crean el asset. Solo avisan que no lo pudieron enlazar en la
configuración.

## Crear un asset nuevo

El botón **Crear nuevo** (arriba a la derecha, en las dos pestañas) abre un formulario.

1. **Tipo**: Personaje, Animación, Fondo / nivel, Efecto, Interfaz / icono, Música o
   Efecto de sonido. Los campos cambian según el tipo.
2. **Valores por defecto**: salen de las entradas que ya tienes en el manifiesto. Para cada
   campo se toma el valor más común entre los assets de ese tipo: tamaño, fondo
   transparente u opaco, alto en pixel art, rejilla, fps, duración y referencia de estilo.
   Así lo nuevo sale igual que lo que ya existe.
   - Una **animación** pide el personaje (se manda como referencia y hereda su alto) y la
     acción. El id se arma solo: `werewolf_attack`.
   - El **tamaño** solo ofrece los que ya funcionan. `1024x512` no aparece, porque GPT
     Image lo rechaza.
   - Solo se sugiere como referencia una imagen que **ya esté generada**. Si eliges una
     sin generar, el formulario te avisa, porque el generador se detendría.
3. **id**: en snake_case y único; el formulario te avisa mientras escribes. La **salida**
   se sugiere según tus carpetas (`assets/art/<id>/`, `assets/art/vfx/`,
   `assets/audio/sfx/<nombre>.mp3`...), y puedes cambiarla.
4. **Enlace en game_config.json**: es opcional. Si lo dejas vacío, o si el juego todavía no
   tiene `assets/data/game_config.json`, el generador crea el asset y solo avisa.
5. **Descripción**: el prompt. Abajo ves el estilo común que se antepone (el mismo que
   agrega `generate_art.py`) y las reglas del proyecto:
   - en las imágenes, sin texto y con diseños originales;
   - en el audio, sin nombres de artistas ni de juegos, porque ElevenLabs los rechaza.

Botones:

- **Ver prompt final** (gratis): muestra el texto completo que se enviaría y la entrada que
  se agregaría. No escribe nada. Usa la misma función que `--dry-run`.
- **Guardar en el manifiesto**: agrega la entrada como "Sin generar". Es gratis.
- **Guardar y generar**: agrega la entrada y la genera. Pide confirmación porque **gasta
  créditos**.

El servidor valida todo otra vez: rechaza un id repetido, un enlace que ya usa otro asset,
una ruta fuera de `assets/` o un archivo que ya existe. La entrada nueva se escribe al
final de la lista con el mismo formato que las demás (sangría, una línea por asset en el
audio, saltos de línea y tildes).

**Eliminar**: una entrada que sigue "Sin generar" tiene el botón **Eliminar entrada** (en su
panel o en su editor). Pide confirmación y solo quita la entrada del manifiesto. Si el asset
ya tiene archivos generados, o si otro asset lo usa como referencia, el servidor se niega.
Nunca se borran archivos.

## Dónde van las claves

En el archivo `.env.local`, en la raíz del repo (Git lo ignora):

```
OPENAI_API_KEY=sk-...
ELEVENLABS_API_KEY=...
```

El servidor nunca manda las claves al navegador. Además, las borra del registro por si
algún mensaje de error las incluyera. Si falta una, la pestaña lo avisa y puedes mirar
todo igual; solo no puedes generar.

## Archivos

| Archivo | Qué hace |
|---|---|
| `server.py` | Servidor local: lista los assets, sirve los archivos de `assets/`, guarda prompts y corre los generadores |
| `index.html` | La página |
| `studio.css` | El estilo (tema oscuro) |
| `app.js` | Pestañas, búsqueda, rutas (`#imagenes/hero_run` abre ese asset) y atajos |
| `shared.js` | Llamadas al servidor, avisos, confirmación y registro de la generación |
| `images.js` | Pestaña Imágenes y panel de detalle con el reproductor de animaciones |
| `audio.js` | Pestaña Audio: reproducción, forma de onda y nivel |
| `create.js` | Formulario "Crear nuevo" |
