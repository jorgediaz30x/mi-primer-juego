# Saltar a una clase

El juego terminado está guardado en `tools/curso/juego-completo/`. Un comando deja
el proyecto como queda al terminar cada clase, sin esperar a que GPT Image o
ElevenLabs generen todo en vivo:

```bash
python tools/curso/clase.py 4
```

En Claude Code también están los comandos `/clase-1` a `/clase-8`, que hacen lo mismo
(y en las clases 4, 6 y 7 abren el Estudio).

| Comando | Qué queda en el proyecto | Qué muestra el Estudio |
|---|---|---|
| `inicio` | La plantilla sin juego (clases 1 a 3) | Nada |
| `4` | Personajes, fondos, efectos e interfaz | Solo el arte |
| `5` | + el juego en Godot con el arte fijo, sin animación ni sonido | Solo el arte |
| `6` | + los personajes y el jefe animados | Solo las animaciones |
| `7` | + la música y los efectos de sonido | Solo el audio |
| `8` o `final` | El juego terminado, con el preset de exportación web | Todo |

Se puede ir hacia adelante o hacia atrás en cualquier orden. Después de cambiar de
clase, abre Godot una vez para que importe los assets nuevos.

El comando solo toca los archivos que están en `juego-completo/`. Los cambios que
deja no se guardan en git: para volver a la plantilla limpia, usa
`python tools/curso/clase.py inicio`.

## En una PC nueva

```bash
git clone -b main-profesor https://github.com/jorgediaz30x/mi-primer-juego.git
cd mi-primer-juego
python tools/curso/clase.py final
```
