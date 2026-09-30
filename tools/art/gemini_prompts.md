# Prompts para probar en Gemini (u otro generador)

Cada prompt es autocontenido: incluye el bloque de estilo al principio, así lo
pegás tal cual. Los textos entre [CORCHETES] son decisiones tuyas: reemplazalos
por lo que tenés en la cabeza, o borralos y dejá que el modelo decida.

Cuando un resultado te guste, copiá tu versión final al campo `prompt` del asset
en `tools/art/asset_manifest.json` (o desde el estudio de assets, `python tools/studio/server.py`) y generalo con
GPT Image. El bloque de estilo va una sola vez en el campo `style`.

---

## Bloque de estilo (se repite en todos)

```
2D side-view video game art for a fast action platformer. [ESTILO: por ejemplo pixel art 32-bit, ilustración pintada a mano, anime cel-shading, cartoon]. Consistent art style across all assets. Original designs not based on any existing franchise. No text, no logos, no watermark.
```

---

## 1. Héroe: el joven mago (Nico Ravel)

```
2D side-view video game art for a fast action platformer. [ESTILO]. Original designs not based on any existing franchise. No text, no logos, no watermark.

Full-body young wizard student, [EDAD Y RASGOS], wearing [ROPA Y COLORES], holding a wand, side view facing right, standing idle pose, single character centered, whole body visible. Original costume design: no round glasses, no scar, no school house crest, no striped tie or scarf. Isolated subject on a fully transparent background: no scenery, no ground, no shadow, no glow, no frame.
```

## 2. Araña de sombra (enemiga básica)

```
2D side-view video game art for a fast action platformer. [ESTILO]. Original designs not based on any existing franchise. No text, no logos, no watermark.

Giant shadow forest spider enemy, [TAMAÑO, COLOR, OJOS], side view facing right, whole body visible, single creature centered, menacing but not gory. Isolated subject on a fully transparent background: no scenery, no ground, no shadow, no glow, no frame.
```

## 3. Hombre lobo (enemigo pesado)

```
2D side-view video game art for a fast action platformer. [ESTILO]. Original designs not based on any existing franchise. No text, no logos, no watermark.

Werewolf enemy standing on two legs, [PELAJE, COMPLEXIÓN, ROPA ROTA O NO], side view facing right, aggressive stance, whole body visible, single creature centered, no blood. Isolated subject on a fully transparent background: no scenery, no ground, no shadow, no glow, no frame.
```

## 4. Villano: el señor oscuro (Morvane)

```
2D side-view video game art for a fast action platformer. [ESTILO]. Original designs not based on any existing franchise. No text, no logos, no watermark.

Original dark sorcerer lord, [ROSTRO, VESTIMENTA, COLORES], menacing presence, side view facing left, whole body visible, single character centered. Must not resemble any famous fantasy villain: no snake-like noseless face, no bald pale head. Isolated subject on a fully transparent background: no scenery, no ground, no shadow, no glow, no frame.
```

## 5. Proyectil del hechizo Fulgor

```
2D side-view video game art for a fast action platformer. [ESTILO]. No text, no logos, no watermark.

A single magic spell projectile, [FORMA Y COLOR: orbe, rayo, chispa], centered, nothing else in the image. Isolated subject on a fully transparent background, no frame.
```

## 6. Fondo del nivel: el Bosque Umbrío

```
2D side-view video game art for a fast action platformer. [ESTILO]. Original designs not based on any existing franchise. No text, no logos, no watermark.

Wide background scene of a dark enchanted forest clearing at night, [ELEMENTOS: árboles, niebla, luna, hongos brillantes], no characters, no buildings, low contrast and muted so gameplay stays readable in front of it. 3:2 landscape composition.
```

## 7. Textura del suelo

```
2D side-view video game art for a fast action platformer. [ESTILO]. No text, no logos, no watermark.

Seamless horizontally tileable texture of forest ground seen from the side: [SUPERFICIE: pasto, raíces, piedras] on the top edge, earth below, filling the entire frame edge to edge.
```

## 8. Textura de plataforma

```
2D side-view video game art for a fast action platformer. [ESTILO]. No text, no logos, no watermark.

Seamless horizontally tileable texture of a [MATERIAL: tronco con musgo, piedra, raíces] platform seen from the side, filling the entire frame edge to edge.
```

---

## Qué mirar al revisar cada resultado

- **Legibilidad a tamaño real:** en el juego el héroe mide ~57 px de alto y la araña ~29 px. Achicá la imagen a ese tamaño: si no se entiende qué es, el diseño es demasiado detallado.
- **Silueta:** el jugador tiene que distinguir al héroe de los enemigos en un vistazo, aunque solo vea la sombra.
- **Propiedad intelectual:** si algo te recuerda a una saga conocida, cambialo antes de usarlo en el curso.
- **Gemini vs GPT Image:** el mismo prompt no da la misma imagen en los dos. Gemini sirve para explorar ideas; el arte final se genera con GPT Image para que todos los assets compartan referencia de estilo.
