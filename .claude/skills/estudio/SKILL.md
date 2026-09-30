---
name: estudio
description: "Abre el Estudio de assets (visor y editor de imágenes y audio) en el navegador. Úsalo cuando el usuario quiera ver, escuchar, crear o regenerar assets."
argument-hint: "[opcional: puerto, por defecto 8765]"
user-invocable: true
allowed-tools: Bash(curl -s *), Bash(python tools/studio/server.py*), Bash(python -m webbrowser *)
---

# Abrir el Estudio de assets

Abre `tools/studio/server.py` en el navegador. No cambia ningún archivo.

El puerto es el argumento, si lo hay (`$ARGUMENTS`), o `8765` si no.

## 1. Comprobar si ya está abierto

`curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:<puerto>/api/audio`

Si responde `200`, ya está corriendo. Ábrelo en el navegador con
`python -m webbrowser -t http://127.0.0.1:<puerto>` y pasa al paso 3.

## 2. Arrancarlo si no está corriendo

Arráncalo en segundo plano (`run_in_background`), porque el servidor queda escuchando y no
termina solo:

`python tools/studio/server.py --port <puerto>`

El servidor abre el navegador por su cuenta. Si falla, muestra el error tal cual. Lo más
común es que Python no esté instalado o que el puerto esté ocupado; en ese caso, sugiere
otro puerto, por ejemplo `/estudio 8766`.

## 3. Avisar al usuario

Responde en una o dos líneas, en español neutro: que el estudio está abierto en
`http://127.0.0.1:<puerto>` y que tiene las pestañas Imágenes y Audio, más el botón Crear
nuevo. No agregues nada más.

## Después

Para generar arte o audio nuevo, el usuario usa Crear nuevo en el estudio. Para cerrarlo,
basta con cerrar la terminal o detener la tarea en segundo plano.
