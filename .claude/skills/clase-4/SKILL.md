---
name: clase-4
description: "Deja el proyecto como queda al terminar la clase 4 (el arte). Personajes, fondos, efectos e interfaz; el Estudio muestra solo el arte."
user-invocable: true
allowed-tools: Bash(python tools/curso/clase.py *), Bash(curl -s *), Bash(python tools/studio/server.py*), Bash(python -m webbrowser *)
---

# Clase 4: el arte

## 1. Dejar el proyecto en la clase 4

`python tools/curso/clase.py 4`

Personajes, fondos, efectos e interfaz; el Estudio muestra solo el arte. Si falla, muestra el error tal cual.

## 2. Abrir el Estudio

Comprueba si ya está abierto:
`curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8765/api/audio`

- Si responde `200`, recarga la página con `python -m webbrowser -t http://127.0.0.1:8765`.
- Si no, arráncalo en segundo plano (`run_in_background`):
  `python tools/studio/server.py --port 8765`

## 3. Avisar

Responde en una o dos líneas, en español neutro: el proyecto quedó en la clase 4. El Estudio está abierto en http://127.0.0.1:8765 mostrando solo el arte. No agregues nada más.
