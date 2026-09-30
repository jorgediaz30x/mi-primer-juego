# Los 8 prompts supremos

Un prompt por clase, en orden, listo para copiar en Claude Code. Usa una sesión nueva de
Claude Code por clase.

---

## 1. Presentación

**Cuándo usarlo:** En la primera clase, en una sesión nueva sobre la rama main, para conocer el juego de referencia y el plan del curso.


```text
Estoy en el repositorio de Claude Code Game Studios y empiezo un curso para crear un
videojuego con Claude Code. El material del curso está en docs/curso/. El juego terminado
que vamos a usar de referencia, Vallebruma: El Bosque Umbrío, está en la rama
juego-referencia, y cómo quedó está explicado en docs/estado/estado-del-juego.md y
docs/estado/pendientes.md.

Antes de construir nada quiero entender a dónde vamos. Lee esos documentos, el README del
curso y el CLAUDE.md del repo, y cuéntame:
- Cómo es Vallebruma: el héroe, el villano, los tres niveles, los controles, los
  hechizos, cómo se hace más fuerte el personaje y qué pasa al morir.
- Qué voy a tener al terminar cada una de las 8 clases, en una línea por clase.
- Cuáles son las reglas de trabajo de este repo, en pocas palabras.
- Qué tengo que preparar para la próxima clase (cuentas, keys, Godot, Python) y cuánto
  cuesta según los documentos. Si un precio no aparece, dime que hay que verificarlo.

También quiero ver el juego terminado sin perder lo que tengo en main. Muéstrame cómo
abrir la rama juego-referencia aparte (por ejemplo, con un worktree), pero no lo ejecutes.

Al final, hazme tres preguntas para empezar a pensar mi propio juego: la temática, el
héroe y el villano, y los tres niveles. Los nombres tienen que ser originales.

Ten en cuenta que no quiero que leas .env.local, que si algo no está en los documentos me
lo digas en vez de suponerlo, y que separes lo que ya está probado de lo que está
pendiente (por ejemplo, la publicación en la web).

Cuando termines, quiero una respuesta que pueda leer en cinco minutos y comparar con
docs/curso/README.md.

Esta clase es solo para leer: no cambies nada.
```

---

## 2. Herramientas

**Cuándo usarlo:** En la clase 2, después de crear las cuentas y el archivo .env.local, para dejar todo instalado y probado sin gastar.


```text
Estoy en el repositorio de Claude Code Game Studios y quiero dejar listas todas las
herramientas del curso antes de empezar a construir el juego. Voy a usar Godot 4.7.2, que
está en <ruta de Godot>; en Windows es una carpeta con dos ejecutables, uno de consola y
uno con ventana. Ya creé el archivo .env.local en la raíz con mi OPENAI_API_KEY y mi
ELEVENLABS_API_KEY.

Quiero comprobar todo sin gastar en imágenes ni audio:
1. Que Godot responde y es la versión 4.7.2. Guarda la ruta en la memoria del proyecto
   para no tener que repetirla. Ojo: la referencia del repo está fijada en 4.6.
2. Que tengo Python 3 y Git Bash.
3. Que .env.local existe, que Git lo ignora y que cada key aparece una sola vez. Nunca me
   muestres los valores.
4. Que mi key de OpenAI ve los modelos de imagen: corre
   python tools/art/generate_art.py --list-models y compara los nombres con la
   documentación oficial.
5. Que mi cuenta de ElevenLabs funciona, con una consulta que no genere audio. Si responde
   401 payment_issue, es una factura pendiente, no el código.
6. Que los dos generadores arman sus prompts: corre los dos con --dry-run.
7. Que el estudio de assets arranca: python tools/studio/server.py, en
   http://localhost:8765, con las pestañas Imágenes y Audio.

Además, proponme una lista de permisos para Claude Code con los comandos que vamos a usar
en el curso, para que no me pidas autorización a cada paso. No la apliques hasta que te
diga.

Si algo falla, dime el error tal cual y qué crees que lo causa antes de reintentar.

Cuando termines, quiero una tabla con cada herramienta, si funciona y qué hago yo si no,
y el estudio abierto en el navegador.

Esta clase es solo para comprobar: no cambies nada del repo sin preguntarme, y antes de
empezar cuéntame qué vas a correr.
```

---

## 3. Cómo está construido un juego

**Cuándo usarlo:** En la clase 3, sobre la rama juego-referencia, para recorrer el juego sistema por sistema.


```text
Estoy en el repositorio de Claude Code Game Studios, en la rama juego-referencia, donde
está Vallebruma terminado. Antes de construir mi propio juego quiero entender cómo está
hecho este, sistema por sistema, con el código real.

Explícame, en este orden:
1. El bucle del juego y la física.
2. Las escenas y los nodos.
3. Los sprites, las hojas de sprites y la escala del pixel art.
4. La animación, y por qué se ancla en los pies.
5. El movimiento y el feel: coyote time, jump buffer, salto variable, dash y la
   micropausa al impactar.
6. Cómo se apunta, y por qué el disparo sale de un solo punto (cast_origin).
7. Los enemigos y el jefe: los estados del lobo y las fases de Morvane.
8. La configuración en game_config.json y cómo se lee.
9. main.gd: quién crea cada pieza y cómo se la pasa a las demás.
10. Las señales.
11. La lógica de src/core/ y sus tests.
12. La música que cambia con el peligro.
13. El guardado y los puntos de control.
14. La interfaz: título, pausa, opciones, cartas y HUD.

De cada uno quiero saber qué problema resuelve, en qué archivo está, un pedacito de código
real (no más de diez líneas), qué valores de la configuración usa y qué test lo cubre, si
tiene. Explícame primero la idea y después el código, sin palabras técnicas que no me
hayas explicado antes.

Al final, dibújame en texto cómo main.gd crea y conecta todas las piezas, y hazme cinco
preguntas para ver si entendí, sin darme las respuestas.

Ten en cuenta que quiero rutas y líneas reales y los fragmentos copiados tal cual. Si algo
no está en el repo, dímelo.

Cuando termines, voy a correr los tests y abrir dos de los archivos que citaste para
comparar. Después voy a poner player.coyote_time en 0, jugar un minuto y volverlo a 0.1
para sentir la diferencia.

Esta clase es solo para leer: no cambies nada.
```

---

## 4. El prompt inicial

**Cuándo usarlo:** En la clase 4, para pasar de la idea a un boceto jugable en cajas grises. Los alumnos cambian el nombre, los personajes, los niveles y las referencias por los de su juego.


```text
Estoy en el repositorio de Claude Code Game Studios y quiero crear mi propio videojuego
en Godot 4.7.2 con GDScript. Godot está en <ruta de Godot>.

El juego se va a llamar Vallebruma: El Bosque Umbrío. Es un juego de acción 2D de magia,
inspirado en el mundo de Harry Potter pero con nombres propios: el héroe es Nico Ravel,
un joven estudiante de magia, y el villano es Morvane. Nico está perdido en un bosque
prohibido y tiene que abrirse paso a punta de hechizos hasta enfrentarse a Morvane.

Quiero que se juegue así:
- Que avance como en Cuphead: vista lateral, voy hacia la derecha y el último nivel
  termina contra un jefe.
- Que sea rápido y difícil como Hotline Miami: si me tocan, muero. Pero sin gore.
- Que al morir sea como Bloodborne: conservo lo que gané y vuelvo al último punto de
  control para intentarlo de nuevo.
- Nada de plataformas flotantes: el mundo está al nivel del suelo y los enemigos caen
  del techo, salen de los costados y de la tierra.

Va a tener tres niveles:
1. El Bosque Umbrío, con arañas que mueren de un disparo.
2. La Cueva de los Aullidos, oscura, con arañas y hombres lobo. El lobo tiene barra de
   vida, es más lento y aguanta varios disparos.
3. El Cementerio de la Tormenta, que termina contra Morvane. Tiene tres fases, avisa
   cada ataque antes de lanzarlo y en la última se transforma.

Me muevo con A/D, salto con W o Espacio y hago dash con Shift. Apunto con el mouse y el
personaje mira hacia donde apunto. Los hechizos son Fulgor, un rayo (clic izquierdo);
Aerum, para levantar y lanzar enemigos (clic derecho); Nova, de área (E); y Lumos, una
luz que solo sirve en la oscuridad (F).

Para hacerme más fuerte: al subir de nivel el juego se pausa y elijo 1 de 3 cartas de
mejora, con 10 segundos para decidir. Puedo tener como máximo 4; si ya tengo 4, la nueva
reemplaza la más vieja. Solo me ofrece cartas que sirvan donde estoy.

Por ahora quiero solo el boceto jugable, con cajas grises. El arte lo hacemos después
con GPT Image. Reglas que no quiero que rompas:
- Todos los números y textos del juego van en un archivo de configuración, nada escrito
  directo en el código.
- La lógica importante lleva tests.
- Los textos del juego en español neutro.
- Nada de emojis ni dibujos hechos por ti.
- No hagas commits.

Cuando termines, quiero poder jugar desde el nivel 1 hasta ganarle a Morvane. Corre los
tests, abre el juego y muéstrame capturas del nivel 1, de la pantalla de cartas y del jefe.

Antes de escribir código, cuéntame tu plan y hazme las preguntas que tengas.
```

---

## 5. El arte

**Cuándo usarlo:** En la clase 5, cuando el boceto gris ya se juega bien, para generar e integrar todo el arte.


```text
Sigo con mi juego Vallebruma. El boceto en cajas grises ya se juega bien y ahora quiero
ponerle todo el arte con GPT Image, en pixel art. En el repo ya están el pipeline de arte
en tools/art/ (generate_art.py y asset_manifest.json) y el estudio de assets
(python tools/studio/server.py). Mi key de OpenAI está en .env.local.

Quiero que todo se vea del mismo juego: pixel art 2D nítido, con píxeles cuadrados, sin
suavizado ni degradados, contorno oscuro en los personajes, una paleta limitada y diseños
originales, sin texto ni logos. Ese estilo va en el campo style del manifiesto, así se
aplica a todo.

Empieza solo por Nico: de cuerpo entero, de perfil mirando a la derecha, con túnica con
capucha y varita, y fondo transparente. Que no tenga nada de Harry Potter: ni anteojos
redondos, ni cicatriz, ni escudo de casa, ni corbata a rayas. Muéstramelo y espera a que te
diga que sí antes de gastar en lo demás. Después usa a Nico como referencia de estilo para
el resto.

Lo que necesita el juego:
- Los personajes, todos de perfil mirando a la derecha, con fondo transparente y sin
  sombra ni brillo alrededor: Nico; la araña y el hombre lobo, que se distingan bien
  sobre un fondo oscuro; Morvane, un hechicero alto con capa rasgada y un bastón con un
  cristal que brilla, sin parecerse a ningún villano famoso; y su forma final, un espectro
  gigante de humo violeta, con garras, ojos brillantes y sin piernas.
- El Bosque Umbrío de noche: un fondo lejano con luna y árboles a lo lejos, y tramos de
  nivel con piso de pasto, raíces y piedras.
- La Cueva de los Aullidos, que tiene que ser una cueva de verdad y no el bosque
  oscurecido: cerrada, con estalactitas en todo el techo, piedra fría gris violeta y piso
  de piedra y grava con charcos, sin pasto, sin cielo y sin luna. La única luz sale de
  cristales y hongos que brillan, y esos cristales tienen que dar luz de verdad en el
  juego. Solo el primer tramo muestra la entrada y solo el último la salida.
- El Cementerio de la Tormenta: lápidas torcidas, rejas, árboles secos y niebla, con un
  último tramo que es la arena de Morvane.
- Los efectos: el rayo de Fulgor, el destello de la varita, la chispa del impacto, el
  humo al morir, la explosión, el aviso antes de que aparezca un enemigo, el
  teletransporte, la luz de Lumos, la subida de nivel, y los orbes, el rayo y la onda de
  choque de Morvane. Solo el efecto, sin ningún personaje, y lo que hace daño en colores
  que se vean.
- La interfaz: la mira para apuntar, un panel, el marco de las barras y los íconos de los
  hechizos y las cartas, que se entiendan a 32 píxeles y sin letras. La fuente es
  Pixelify Sans, esa no se genera.
- La pantalla de título: Nico pequeño, de espaldas, con la varita en alto, frente a
  Morvane enorme, en un paisaje en ruinas con tormenta.

En todos los tramos de nivel el piso tiene que ser plano, continuo y estar pintado dentro
del escenario, a la misma altura de punta a punta, y los bordes tienen que empalmar con
el tramo siguiente. Nada de plataformas sueltas que parezcan un PNG pegado.

Ten en cuenta que la API no acepta cualquier tamaño: 1024x512 falla. Usa 1024x1024 para
personajes, íconos y efectos cuadrados, 1536x1024 para hojas de animación y fondos,
1536x512 para los tramos de nivel, 1536x768 para imágenes anchas como el título y
1024x1536 para algo alto. Cada asset tiene su alto real en píxeles (Nico 48, la araña 24,
el lobo 56, Morvane 64, el espectro 72, los tramos 240) y Godot lo agranda por 3 sin
suavizado, así todo comparte la misma densidad de píxeles. La referencia de la cueva no
puede ser un tramo del bosque, y las referencias de escenarios y efectos no pueden traer
personajes. Los números nuevos van en game_config.json. Todo el arte sale de GPT Image:
nada dibujado por ti y nada de emojis. No hagas commits, y avísame cuánto va costando cada
tanda.

Registra cada asset en el manifiesto para que yo pueda revisarlo y regenerarlo desde el
estudio, también los que agregue con el botón Crear nuevo.

Cuando termines, quiero ver capturas de los tres niveles, del jefe, de las cartas y del
título, y que me digas qué ves mal antes de que te lo diga yo. Mide que los personajes y
los efectos sean transparentes de verdad, no lo supongas a ojo. Después lo reviso todo en
el estudio.

Antes de empezar, cuéntame tu plan y hazme las preguntas que tengas.
```

---

## 6. La animación

**Cuándo usarlo:** En la clase 6, con todo el arte fijo ya integrado, para animar personajes, efectos y el jefe.


```text
Sigo con mi juego Vallebruma. Ya tiene todo el arte, pero los personajes son imágenes
quietas que se deslizan por la pantalla. Ahora quiero que se muevan de verdad y que
Morvane se sienta como un jefe de Cuphead. El pipeline de tools/art/ ya sabe generar
hojas de animación.

Las animaciones que necesito, cada una con el personaje fijo como referencia para que no
cambie entre cuadros:
- Nico: quieto, correr, saltar (un cuadro subiendo y otro cayendo) y lanzar un hechizo.
- La araña: caminar. El lobo: caminar, rugir y embestir.
- Morvane: flotar, lanzar y transformarse. Su forma de espectro: flotar y lanzar.

La carrera de Nico es la que más cuesta. Descríbela cuadro por cuadro, como se lo
pedirías a un animador: contacto, bajada, paso y subida, y después lo mismo con la otra
pierna, ocho cuadros en total. Las piernas tienen que estar claramente en otra posición en
cada cuadro, los brazos van al revés que las piernas y la cabeza sube y baja. Usa el
modelo más preciso para esa hoja.

Todas las animaciones se anclan en los pies, para que el personaje no flote ni se hunda
al cambiar de pose. Nico mira siempre hacia donde apunto con el mouse; si camino hacia un
lado y apunto al otro, retrocede y la carrera se reproduce al revés para que no parezca
que patina. Déjalo configurable, por si prefiero que mire hacia donde camina.

Los efectos también van animados (el rayo con estela, el impacto, el humo, la explosión,
los avisos, el teletransporte y los ataques de Morvane), sin ningún personaje adentro.
Antes de embestir, el lobo se pone rojo para avisar.

Y Morvane, como un jefe de Cuphead:
1. Aparece saliendo de la tierra con un cartel grande con su nombre y su título, y es
   cerca del doble de alto que Nico.
2. En la primera fase lanza ráfagas de orbes y se teletransporta.
3. En la segunda manda ondas de choque por el suelo que hay que saltar, invoca arañas y
   hace llover orbes.
4. En la tercera se transforma en el espectro y barre la pantalla con un rayo: si va bajo
   lo salto, si va alto me quedo en el piso.
Cada ataque se anuncia antes de llegar. Quiero relámpagos en el escenario y un cartel
grande cuando le gano.

Ten en cuenta que los tiempos, las velocidades y las fases de Morvane van en
game_config.json, que la lógica de sus fases lleva tests, que todo el arte sale de GPT
Image y que no quiero commits.

Cuando termines, quiero correr los tests y ver capturas de la entrada de Morvane, de su
segunda fase y de su forma de espectro. Como una captura no muestra el movimiento, dime
qué tengo que mirar yo cuando juegue.

Antes de empezar, cuéntame tu plan y hazme las preguntas que tengas.
```

---

## 7. La música y el sonido

**Cuándo usarlo:** En la clase 7, con la suscripción de ElevenLabs activa, para la música adaptativa y los efectos nivelados.


```text
Sigo con mi juego Vallebruma. Ya se ve y se mueve bien, y ahora quiero ponerle música y
sonido con ElevenLabs. En el repo está el pipeline de audio en tools/audio/
(generate_audio.py y audio_manifest.json). Mi key está en .env.local, en una sola línea,
y la suscripción está activa.

Quiero una música de fondo suave y cálida, como la de Minecraft, que suba de intensidad
cuando se acerca un enemigo. Mi idea es tener dos pistas que suenan juntas, una tranquila
y una de tensión, y que el juego las mezcle según qué tan cerca esté el enemigo más
próximo: la tensión entra rápido, vuelve despacio a la calma y durante una pelea nunca
baja del todo.

Las pistas:
- El bosque, tranquila, de 3 minutos: piano suave, tempo lento, sin batería ni voces.
- La cueva, tranquila, de 3 minutos y más fría. También sirve para el cementerio.
- La tensión, de 2 minutos, para todos los niveles.
- Morvane, de 2 minutos y medio, épica y oscura.
Que todas empiecen y terminen suave, para que no se note cuando vuelven a empezar.

Y efectos para todo: cada hechizo, el dash, levantar y lanzar; las arañas cuando aparecen
y cuando mueren; el lobo cuando ruge, cuando recibe daño y cuando muere; la entrada de
Morvane, cada uno de sus ataques, su transformación y su muerte; cuando me golpean y
cuando muero; y los eventos, como subir de nivel, elegir carta, el aviso de un enemigo, el
punto de control y terminar un nivel.

Ten en cuenta que ElevenLabs rechaza prompts con nombres de juegos o artistas, así que
"como Minecraft" tiene que convertirse en una descripción del estilo. Los efectos salen
con volúmenes muy distintos: mide la sonoridad de cada uno en LUFS y baja los más fuertes
con un ajuste por efecto en audio.sfx_gain_db, sin subir nunca ninguno. Genera primero un
solo efecto para confirmar que la cuenta funciona. Si falta un archivo, el juego tiene que
seguir sin ese sonido y sin error. Los volúmenes y la velocidad de la tensión van en el
bloque audio de game_config.json, la lógica de la mezcla lleva tests y no quiero commits.

Cuando termines, quiero una tabla con la sonoridad medida de cada efecto y el ajuste que
le pusiste. Corre los tests y abre el juego; después lo escucho yo jugando y en la pestaña
Audio del estudio.

Antes de empezar, cuéntame tu plan y hazme las preguntas que tengas.
```

---

## 8. Mejoras y publicación en la web

**Cuándo usarlo:** En la clase 8, con el juego completo, para cerrar el balance, los menús y preparar la exportación web.


```text
Sigo con mi juego Vallebruma. Ya está completo: tres niveles, Morvane, cartas, arte,
animación y audio. Ahora quiero cerrarlo y dejarlo listo para que otra persona lo juegue
desde el navegador.

Primero, el balance, cambiando solo valores de la configuración. Con el abanico de Fulgor
me vuelvo invencible: que dé como máximo 2 rayos y que la forma de hacerse más fuerte sea
el daño. Quiero máximo 4 mejoras; con el mazo lleno, la nueva reemplaza la más vieja y la
carta me avisa antes a cuál va a reemplazar, aunque también puedo rechazarla. Tengo 10
segundos para elegir, con la cuenta en pantalla; si se acaba, pierdo la mejora. El lobo
tiene que aguantar bastante más (en Vallebruma quedó en 14 de vida). Y la primera vez que
entro a la cueva quiero que aparezcan las cartas de Lumos, sin esperar a subir de nivel.

Después, los menús:
- Una pantalla de título con el arte que generamos, música y las opciones Continuar (solo
  si hay partida), Partida nueva (que pregunte si ya hay una), Opciones, Controles y Salir
  (sin Salir en la web).
- Una pausa con Esc: Seguir, Opciones, Controles y Volver al inicio.
- Opciones con el volumen general, el de la música y el de los efectos, y pantalla
  completa, guardadas aparte de la partida.
- Todo navegable con teclado, mouse y mando.

Y por último, la web. Antes de exportar, investiga y dime qué hace falta en Godot 4.7.2:
las plantillas de exportación y el preset Web, si necesita cabeceras especiales para los
hilos y si itch.io o GitHub Pages las permiten. Espera a que yo elija dónde publicarlo.

Ten en cuenta que la web solo funciona con el renderer Compatibility (el juego ya lo usa),
que el navegador no deja sonar nada hasta el primer clic (la pantalla de título tiene que
esperar esa interacción), que quiero saber cuánto pesa el juego y cuánto tarda en cargar,
y que el progreso tiene que sobrevivir a recargar la página. Los menús solo muestran y
avisan con señales; qué hace cada botón lo decide main.gd. La lógica de las opciones lleva
tests, las capturas de prueba nunca tocan mi partida real y no quiero commits.

Cuando termines, quiero correr los tests y ver capturas del título, la pausa y las
opciones. Para la web, dame el peso, el tiempo de carga y una captura del juego en el
navegador. Lo que no hayas podido probar, dímelo como pendiente, no como hecho.

Antes de empezar, cuéntame tu plan y hazme las preguntas que tengas.
```
