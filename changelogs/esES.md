# QuestTogether — Registro de cambios

<!-- Generated from canonical release notes; do not edit by hand. -->

## 8.0.5

Este parche suaviza el movimiento de los puntos del minimapa y facilita la lectura de las descripciones de jugadores.

### Marcadores del mapa y descripciones de jugadores

- Los puntos de jugadores del minimapa se actualizan con cada fotograma al caminar o girar, para reducir las sacudidas de los puntos de quienes están quietos.
- En el mapa del mundo y el minimapa, la descripción permanece en su sitio mientras mantienes el cursor quieto, aunque el marcador se mueva. Los resúmenes de puntos agrupados conservan los jugadores que consultaste. Al apartar el cursor, cerrar o cambiar el mapa, desactivar las ubicaciones o dejar de disponer de datos válidos, la descripción se cierra.
- Las descripciones individuales muestran el mismo contorno blanco, icono de grupo y número total de miembros que las de puntos agrupados. Los jugadores sin grupo ya no muestran un recuadro de grupo ni una etiqueta que lo indique.
- En grupos de más de cinco miembros, la descripción individual muestra primero al líder y después al jugador señalado, sin repetirlo si es el líder. Se mantiene el número total del grupo, incluso cuando solo se conocen algunos de sus miembros.

## 8.0.4

Los marcadores de jugadores y del grupo siguen mejor los movimientos del mapa del mundo.

### Marcadores del mapa del mundo

- Los puntos de jugadores y los puntos de ruta compartidos del grupo se desplazan con fluidez al mover el mapa o usar la rueda del ratón para acercarlo o alejarlo.
- Los marcadores se actualizan de inmediato al cambiar de nivel del mapa, también al volver atrás con un clic derecho. Los puntos de la zona anterior ya no se quedan en pantalla.

## 8.0.3

Hemos revisado las notas de actualización para que sean más claras y naturales, y recuperado una entrada que faltaba en el historial de versiones.

### Notas de actualización e historial de versiones

- Las notas de actualización, tanto actuales como antiguas, se han revisado en los diez idiomas disponibles además del inglés para que resulten más claras y naturales.
- Hemos recuperado la entrada de la versión 7.4.4, que faltaba en el historial de versiones y en los registros de cambios. Ya puedes volver a consultarla.

## 8.0.2

Marcadores y reconocimiento VIP más fiables.

### Correcciones

- Las estrellas VIP siguen visibles al terminar tus pantallas de carga y las actualizaciones VIP simultáneas ya no se bloquean entre sí.
- Una actualización temporalmente sin coordenadas ya no hace desaparecer puntos. También mejora el intercambio de datos cuando el canal limita los envíos.

## 8.0.1

Navega con el teclado sin activar un botón aparte.

### Registro de misiones del grupo

- Abrir el registro o pulsar una misión da el foco a la lista automáticamente. Se retira el botón Teclado; usa flechas para recorrer e Intro para desplegar o contraer.
- Tabulador alterna lista y búsqueda. Escape cierra desde la lista y pulsar fuera libera el teclado. Las actualizaciones de misiones no recuperan el foco por su cuenta.

## 8.0.0

Presentamos QuestTogether VIP.

### Aspecto VIP

- Los VIP tienen una estrella de su color de clase en el mapa, un logo QT con estrella dorada en el chat y el botón del minimapa, y la etiqueta QuestTogether VIP en su tooltip individual. Son adornos visuales, sin acceso de desarrollador.

**Forever**

![Aspecto VIP — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v8.0.0/Media/ReleaseNotes/VIPCosmetics.png)

### Cómo conseguir VIP

- Comparte el enlace de descarga de QT con amigos, tu hermandad, un Discord adecuado o redes sociales. Haz una captura del mensaje enviado o publicación que muestre el enlace y dónde lo compartiste. Envíala por mensaje directo a @chevcast para revisión; antes únete al servidor QT o envíale una solicitud de amistad para que pueda recibirla. La ventana VIP incluye el enlace para copiar y los pasos de activación tras la aprobación.

### Activa tu recompensa

- Abre la ventana desde el minimapa, Ajustes o /qt vip. Espera a que @chevcast confirme la concesión a tu cuenta de Discord: el comando /qt claim de Discord solo funciona después de esa concesión.
- Entonces copia tu código de solicitud con Ctrl+C y envíalo a @chevcast, o usa /qt claim en el servidor QT. Pega el código privado de activación que recibas en la ventana VIP y pulsa Activar VIP. Repite el proceso en Retail o Forever para usar allí la misma recompensa.

### Permanente y opcional

- La recompensa está vinculada a Discord y se comparte entre personajes de cada instalación. Solicítala por separado en Retail y Forever. Puedes desactivar «Mostrar mis cosméticos VIP» sin perder la recompensa. Los botones normales, VIP y de desarrollador tienen un borde dorado adaptado a su forma; el aspecto de desarrollador prevalece sobre VIP.

## 7.4.4

Lee cada actualización de funciones junto con sus correcciones.

### Historial agrupado

- La ventana reúne cada versión menor y sus parches en una página: primero la versión inicial y después las correcciones en orden, bajo encabezados con fecha y versión. El historial navega entre esas páginas.
- Las notas antiguas de parches ya solo cuentan sus propios cambios, sin repetir guías, consejos ni capturas. Los parches solos siguen sin abrir la ventana automáticamente; usa /qt notes cuando quieras.

## 7.4.3

Nombres y controles más claros para las misiones en grupo.

### Herramientas de grupo

- Quest Tracker pasa a llamarse Party Objective Tracker (POT), localizado como Seguimiento de objetivos del grupo. Conserva visualización y posición guardadas.
- /qt pql abre el Registro de misiones del grupo. /qt compare sigue como alias; ayuda y consejos usan /qt pql.
- Ocultar cuando no estés en un grupo está en modo de edición del HUD y Ajustes > Grupos y compartir > Seguimiento de objetivos del grupo. Ambas casillas controlan lo mismo. Viene activado en perfiles nuevos y al restablecer; tus decisiones guardadas se conservan.

## 7.4.2

Corrección del texto de las notas.

### Texto compatible

- Los separadores que no se podían dibujar se sustituyen por texto sencillo para evitar cuadros vacíos.

## 7.4.1

Correcciones y nuevas opciones de distribución para el Seguimiento de objetivos del grupo.

### Contadores correctos

- Los objetivos de un solo paso sin completar ya no aparecen como 1/1 en Forever, incluido Use Walk on Air. Se corrige tanto el panel de objetivos como el registro del grupo.

### Ocúltalo estando solo

- modo de edición del HUD permite Ocultar cuando no estés en un grupo. Viene desactivado; la vista previa para colocar el panel sigue disponible en modo de edición.

### Tamaño y anclaje

- Ajustar al seguimiento de objetivos de Blizzard viene activado y coloca QT junto a su borde exterior, sin separación. Arrastrarlo desactiva el anclaje y permite redimensionar por las esquinas. Reactivarlo restablece la posición. Los controles de ancho y altura máxima funcionan en ambos modos.
- El panel se reduce al contenido hasta la altura máxima y después permite desplazarse. El máximo inicial pasa a 600; se conservan tamaños guardados.
- Los fondos de clase de cada jugador mantienen una opacidad fija del 25%, independiente del fondo de ventana.

## 7.4.0

Mantén a la vista los objetivos de tu grupo con el nuevo Seguimiento de objetivos del grupo.

### Progreso del grupo

- Una ventana compacta con colores de clase muestra cantidades y barras de progreso. Los compañeros necesitan QT para compartir sus datos.
- Se actualiza al recibir anuncios del grupo, independientemente de lo que muestres en chat o burbujas. Las misiones sin contadores indican su estado, por ejemplo listas para entregar.

**Forever**

![Progreso del grupo — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTracker.png)

### Elige qué mostrar

- Puedes elegir Oculto, Misión enfocada, Misión bajo el cursor o Enfoque y cursor. Esta última viene activada: muestra la misión que señalas en el tracker de Blizzard y luego vuelve a tu selección.
- Sin una misión válida, la ventana permanece oculta. Cambia el modo en modo de edición del HUD o Ajustes > Grupos y compartir > Seguimiento de objetivos del grupo.

**Forever**

![Elige qué mostrar — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTrackerDisplay.png)

### Adáptalo a tu interfaz

- Selecciona el panel en modo de edición del HUD para moverlo, redimensionarlo y ajustar opacidad. Guardar, Revertir y Restablecer incluyen modo de visualización y distribución.
- Los apartados de jugador aprovechan el ancho y permiten desplazarse si hace falta. Los temas claro y oscuro conservan texto legible y fondos tenues por jugador incluso a opacidad cero.

**Forever**

![Adáptalo a tu interfaz — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTrackerEditMode.png)

## 7.3.5

Mejor navegación y resaltado de jugadores, con datos de grupo más recientes.

### Mapas y detalles

- El botón QT muestra una leyenda visual al pasar el cursor. Clic izquierdo en un punto mundial lo resalta y abre el mapa más detallado de su ubicación; en el nivel final abre su menú. El derecho siempre abre el menú.
- Buscar en el mapa también va al nivel más detallado. El brillo verde se mantiene al cambiar de mapa y termina al minuto, al cerrarlo o al seleccionar a otra persona.
- Consultar un jugador, conjunto o destino compartido atenúa mapa y marcadores ajenos, conservando brillantes los de interés. El botón QT ya no atenúa el mapa.
- Los brillos usan un efecto uniforme. Tooltips y agrupaciones comparten miembros más recientes y se recuperan mejor de solicitudes tardías. Mejoran los diagnósticos del desarrollador sin cambiar permisos de diagnóstico ni privacidad de ubicación pública.

## 7.3.4

Indicadores QT más coherentes y tooltips más claros.

### Jugadores y chat

- Las listas de grupo muestran logos QT en cuanto hay una ubicación válida, incluso después de recargar.
- Los estados de listas de grupo y agrupaciones permanecen compactos. Las explicaciones de desarrollador y ubicación oculta solo aparecen al consultar directamente a esa persona; los indicadores de ubicación oculta solo los ve el desarrollador.
- Sus anuncios verificados usan un icono de pergamino y engranaje, con brillo dorado mientras busca compañeros.

## 7.3.3

Tooltips de puntos agrupados más limpios.

### Identificación del desarrollador

- En las agrupaciones, el desarrollador se identifica solo por el engranaje de su clase. El texto explicativo permanece en el tooltip individual.

## 7.3.2

Datos de grupo coherentes y navegación por mapas más precisa.

### Grupos y navegación

- Tooltips individuales, agrupaciones y resaltado de compañeros comparten la información conocida, reduciendo cargas repetidas e incoherencias. El icono blanco del tooltip agrupado incluye el tamaño total del grupo.
- Pulsar un conjunto desde el mapa mundial completo abre el mapa más detallado que contiene a todos y lo despliega si aún hace falta.

## 7.3.1

Más claridad en grupos y controles de mapa.

### Jugadores del mapa

- Los tooltips de puntos agrupados reúnen miembros de un grupo conocido dentro de un borde blanco redondeado, con icono de grupo. Si sus compañeros están fuera del conjunto, el jugador mantiene la indicación de grupo.
- Al ocultar marcadores, el botón QT sigue plenamente visible con una X roja. En ese estado, pasar el cursor ya no atenúa el mapa.

## 7.3.0

Encuentra jugadores en mapas concurridos, vuelve a contactar con compañeros recientes y recibe menos avisos repetidos de objetivos.

### Jugadores en el mapa

- Los puntos superpuestos del mapa mundial se agrupan por defecto; puedes desactivarlo en Ubicaciones de jugadores. Al pulsar un grupo se abre el mapa más detallado que contiene a todos. Si siguen juntos, se separan en puntos con tooltips y menús normales; la rueda permite recorrer grupos grandes.
- El botón QT arriba a la derecha alterna puntos y destinos compartidos. Pasar el cursor atenúa el mapa detrás de ellos. No modifica el minimapa ni compartir ubicación. Buscar en el mapa abre la posición reciente compartida de un jugador y resalta su punto.

### Compañeros recientes

- /qt companions o el minimapa abre un historial privado con menús para susurrar, invitar y anotar. Se comparte entre tus personajes del mismo cliente y reino, guarda hasta 100 personas durante 90 días y permite retirar entradas o vaciarlo.

### Progreso y detalles

- Los avances rápidos de un mismo objetivo se reúnen en un anuncio con el último valor; completarlo sigue avisando enseguida.
- Los desarrolladores QT verificados por firma tienen engranajes de clase y una etiqueta en tooltips. Las listas de grupos de puntos muestran colores de clase, logos QT y búsqueda de compañeros, como las listas de grupo.

## 7.2.1

Correcciones de notas privadas y columnas contraídas.

### Lectura y edición

- Vuelve el cursor de texto de las notas y el borde de foco es más discreto. También mejora el desplazamiento al editar notas largas.
- Las columnas contraídas usan iconos fiables para misiones listas y completadas, en vez de caracteres que podían verse como cuadros vacíos.

## 7.2.0

Añade notas privadas sobre jugadores y aprovecha mejor el Registro de misiones del grupo.

### Notas privadas

- El menú de un jugador permite añadir, editar o borrar una nota, que aparece al pasar el cursor por él. Se comparte entre tus personajes y permanece en tu ordenador: nunca se envía a jugadores ni forma parte de diagnósticos.

### Mejoras del registro

- Contrae columnas individuales para ganar espacio y despliega cuando necesites detalles. El botón Teclado permite recorrer misiones con flechas, abrir objetivos con Intro y acciones con Espacio; Escape devuelve los controles normales.
- Las misiones completadas se distinguen de las ausentes si el cliente actualizado del compañero confirma su historial. Si no se conoce, se indica que no está en el diario.
- Las explicaciones al compartir aclaran por qué no pudo realizarse una solicitud. Los tooltips también muestran resultados recientes comunicados por WoW.

### Consejos y tooltips

- Muchos consejos incluyen enlaces a la ventana o ajuste correspondiente. Al mantener el cursor sobre un jugador lejano se piden metadatos nuevos y su lista completa de grupo pequeño, con reintentos durante la consulta.

> <img src="https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.2.0/Media/QuestTogetherTipIcon.png" width="20" height="20" alt=""> Consejo: Escribe /qt tip o /qt hint y utiliza los enlaces del consejo para explorar QuestTogether.

## 7.1.3

Los títulos locales de misiones se recuperan con más fiabilidad.

### Texto de misiones

- Anuncios, registro del grupo y avisos de seguimiento aprovechan mejor los nombres disponibles en tu cliente. Los avances conservan su orden mientras se cargan.
- Detalles de misión se recupera cuando el texto del tooltip llega tarde, y se mejora el tratamiento de títulos recibidos de otros jugadores.

## 7.1.2

Controla los consejos iniciales desde unos ajustes más sencillos.

### Consejos y ajustes

- Puedes desactivar los consejos automáticos en General de la página principal. /qt tip y /qt hint siguen disponibles.
- Se simplifica esa página y el tema claro u oscuro pasa a elegirse en un desplegable.

## 7.1.1

Iconos y colores de consejos más legibles.

### Consejos QT

- El emoji incompatible se sustituye por un icono QT con bombilla. La etiqueta es dorada y el texto, de color crema.

## 7.1.0

Descubre funciones de QuestTogether con consejos útiles.

### Consejos QT

- Al entrar o recargar aparece un consejo de una lista barajada. No se repite ninguno hasta agotar la lista.

> 💡 Consejo: Escribe /qt tip o /qt hint para ver otro consejo de QuestTogether cuando quieras.

## 7.0.2

Mejoras de información de misiones y diagnóstico opcional.

### Novedades

- Una ventana de Detalles de misión permite leer el texto disponible.
- Mejoran la fiabilidad de comunicación y los diagnósticos opcionales del desarrollador, respetando tu ajuste de compartir.

## 7.0.1

Los controles QT se acercan al aspecto actual de Blizzard.

### Controles nativos

- Las barras de ajustes tienen flechas para cambios precisos y un valor al lado. Casillas, colores, barras de desplazamiento y botones adoptan el estilo actual de Blizzard.
- Las búsquedas del registro del grupo y de depuración incluyen lupa y botón de borrar.

### Desplazamiento

- Se mejora el desplazamiento en ajustes, registro, notas y depuración, incluido el cambio de tamaño y la alineación de filas. Flechas y arrastres de barras nativas terminan correctamente al cerrar.

## 7.0.0

Reconstruimos las comunicaciones de QT de cara al lanzamiento de WoW Forever. El nuevo protocolo exige actualizar juntos.

### Importante: las versiones anteriores no se comunican

- QuestTogether 7.x no intercambia ubicaciones, progreso, datos del Registro de misiones del grupo ni otros mensajes con 6.x o anteriores. Pide a tus compañeros que actualicen también.

### Preparándonos para Forever

- Hacemos estos cambios incompatibles antes del lanzamiento para establecer una base más sólida. Después cuidaremos más la compatibilidad entre versiones y evitaremos exigir actualizaciones disruptivas. Si hiciera falta otra ruptura de protocolo, la anunciaremos claramente.

### Información donde estás mirando

- Tienen prioridad tu zona actual y una zona que mantengas abierta en el mapa; los lugares más lejanos se renuevan en segundo plano. El movimiento cercano usa mensajes breves y el descubrimiento se comparte y escalona para limitar tráfico en zonas concurridas.

### Intercambios más fiables

- Misiones, registros del grupo, detalles de jugadores y diagnósticos comparten un envío regulado para que las respuestas grandes dejen espacio a lo demás. Se recuperan fragmentos perdidos sin reiniciar toda la transferencia.
- Las ubicaciones demoradas conservan su edad original y no sustituyen datos nuevos ni retiradas. Dejar de compartir cancela coordenadas públicas en cola. Al cerrar sesión o cargar una zona se intenta enviar una salida final; si falla, queda la caducidad.

## 6.5.11

Nuevas teclas para herramientas QT y búsqueda de compañeros.

### Asignaciones de teclas

- QuestTogether aparece correctamente en Ajustes > Teclas, en lugar de HEADER_QUESTTOGETHER. Puedes asignar abrir el menú, alternar el registro de grupo, buscar compañeros, dejar de seguir, abrir chat QT o ajustes.
- Se conserva tu tecla anterior del registro. Las acciones nuevas no tienen tecla inicial; la del menú funciona aunque ocultes el icono del minimapa.

## 6.5.10

Actualizaciones del registro más fluidas y correcciones de perfiles, solicitudes, mapas y burbujas.

### Registro del grupo

- Con actualización automática, las listas sin cambios generan menos tráfico; Actualizar manualmente sigue pidiendo todos los datos. Las listas se recuperan tras cambios de objetivos o ignorar y dejar de ignorar, sin conservar progreso antiguo ni quedar cargando.

### Perfiles y ventanas

- Cambiar, copiar o restablecer perfil recupera sus posiciones guardadas o las iniciales. Cambiar pantalla mantiene las ventanas visibles sin perder tamaño y posición preferidos.
- Cerrar una confirmación de unión o compartir deja pasar la siguiente solicitud. Abrir ajustes durante modo de edición ya no impide que Revertir restaure la burbuja original. Las ventanas de ayuda abiertas siguen adaptándose al tema y pantalla aunque QT esté desactivado.

### Seguimiento y comunicación

- Las solicitudes caducadas o innecesarias se cancelan antes de enviarse. Los objetivos de bonificación y misiones del mundo conservan su tipo de anuncio aunque desaparezcan antes del evento de finalización.
- Las actualizaciones manuales de ubicación aprovechan respuestas públicas de versiones antiguas para los puntos normales, sin sustituir posiciones más nuevas ni ignorar preferencias de compartir.

## 6.5.9

Mejoran las actualizaciones del grupo, los mapas y la recuperación de interfaz tras Alt+Z.

### Registro y ventanas

- Ocultar y restaurar con Alt+Z conserva confirmaciones de seguimiento y fondos de clase de los nombres. Las solicitudes del registro se recuperan de recargas, pantallas de carga o páginas perdidas sin quedarse en Cargando.
- Ventanas y burbujas personales caben mejor en pantallas pequeñas. Restablecer su distribución no pierde decisiones pendientes de los diálogos.

### Mapas y grupo

- Ubicación, grupo y misión seleccionada rechazan mensajes antiguos para no resucitar salidas ni sobrescribir datos nuevos. Al salir del mundo, QT intenta avisar para retirar el punto antes; la caducidad cubre los avisos perdidos. La disponibilidad para unirse se recupera tras cargar.
- Tu grupo usa los marcadores de Blizzard sin puntos QT duplicados. Jugadores mostrados ofrece Todos, Buscando compañeros o Ninguno, separado de compartir tu ubicación.

### Seguimiento y comunicación

- El seguimiento se recupera de diarios incompletos al entrar y los eventos frecuentes no aplazan indefinidamente actualizaciones pendientes.
- Los envíos comparten una cola espaciada y verificar al desarrollador se reparte en pasos pequeños. Desactivar diagnósticos cancela el trabajo pendiente.
- Los informes grandes tienen más tiempo; solicitantes antiguos reciben un aviso explícito de límite de tamaño si no caben, en lugar de esperar sin respuesta.

## 6.5.8

Desplegables nativos, controles de mapa más claros y diagnóstico para el desarrollador.

### Ajustes y mapas

- Los nueve desplegables usan controles WoW, texto seleccionado dorado, menús negros y botones anterior/siguiente.
- Jugadores mostrados en mapas sustituye casillas de visibilidad y excepción del grupo. Permite todos los usuarios QT, quienes buscan compañeros con o sin tu grupo, solo grupo o ninguno. Conserva tus preferencias y no modifica compartir ubicación.
- Desarrollador reúne Abrir depuración, Volver a revisar diario y la opción de compartir diagnóstico.

### Respuestas de diagnóstico

- Compartir datos de diagnóstico con el desarrollador viene activado. Permite solicitudes autenticadas de diagnóstico QT, ajustes y datos del personaje, grupo y ubicación dentro del juego, incluso si no compartes ubicación públicamente. Puedes detenerlo desde Desarrollador.
- Las respuestas usan susurros privados de addon y páginas espaciadas, conservando todos los campos de informes grandes. Ambos participantes necesitan 6.5.8 o posterior; los clientes publicados 6.5.7 no pueden responder.

## 6.5.7

Selecciona jugadores desde el minimapa y distingue mejor los iconos del grupo.

### Puntos e iconos

- Fuera de combate, clic izquierdo en un punto selecciona al jugador si WoW puede hacerlo. El derecho abre el menú con Seleccionar primero; los puntos del mapa mundial conservan su comportamiento.
- Los iconos de búsqueda tienen un contorno dorado mucho más marcado, y las listas del grupo muestran el logo brillante de quienes tienen ese estado activo. Los símbolos de misión del registro usan una capa frontal para que el fondo no los tape.

## 6.5.6

Reconoce a quienes buscan compañeros también en el registro.

### Indicadores de búsqueda

- El icono LFQP tiene contorno dorado más brillante y halo más intenso para tamaños pequeños. El prefijo QT de un jugador brilla si busca compañeros; los iconos específicos de misión y de conversación no cambian.

## 6.5.5

Los iconos de misión del registro vuelven a dibujarse correctamente.

### Botones de misión

- Al desplazarte o actualizar, algunos botones quedaban como círculos vacíos. Los botones reutilizados reinician su dibujo y usan un icono alternativo si no se puede aplicar el solicitado.

## 6.5.3

La guía incluye tres capturas del Registro de misiones del grupo con compañeros simulados de Forever. No cambia el funcionamiento.

### Tu grupo de un vistazo

- Se añade una captura general del registro.

**Forever**

![Tu grupo de un vistazo — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestOverviewForever.png)

### Elige o sigue una misión

- Se ilustra cómo utilizar los controles de seguimiento.

**Forever**

![Elige o sigue una misión — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestFollowingForever.png)

### Confirma los cambios

- Se muestra el aviso de confirmación al cambiar de misión.

**Forever**

![Confirma los cambios — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestFocusWarningForever.png)

## 6.5.2

Corrección de la demostración de seguimiento.

### Vuelve a tu grupo

- Cerrar la vista previa del registro reanuda el seguimiento que tenías en tu grupo real.

## 6.5.1

Botones más claros, confirmación al dejar de seguir e iconos acordes con el tracker de Blizzard.

### Colores que indican la selección

- Al seguir, solo el botón activo del compañero seguido conserva color. Sin seguimiento, tus botones y las misiones activas ajenas están coloreados; el resto queda gris, sin desvanecerse. Los activos ajenos siguen siendo pulsables para empezar o cambiar de compañero.

### Confirma el cambio

- Elegir una misión propia o cambiar de compañero pide confirmar el fin del seguimiento actual. También cambiar o quitar la selección desde Blizzard: QT restaura temporalmente la misión seguida mientras decides. Cancelar sigue; Cambiar selección aplica tu elección. /qt preview unfollow muestra el diálogo.

### Iconos de estado correctos

- La consulta de finalización coincide con Blizzard, corrigiendo misiones de entrega que mostraban progreso en vez de interrogación. El estado Listo corregido también se comparte en instantáneas del registro.

### Prueba con tus misiones

- La comparación de demostración usa tu diario real con cuatro compañeros simulados y misiones extra que te faltan. Los botones cambian tu navegación real, pero compartir sigue siendo simulado. El menú de un compañero permite avanzar su misión. Si no se puede compartir, se muestra No compartible o Se desconoce en vez de una columna vacía.

## 6.5.0

Elige o sigue misiones desde el Registro de misiones del grupo, incluso después de recargar.

### Botones de misión

- Botones de estilo Blizzard sustituyen los títulos seleccionados en los encabezados. En tu columna cambian tu misión de navegación; los botones activos de compañeros señalan la suya y permiten seguirlos.

### Seguimiento persistente

- La elección se guarda por personaje al recargar y espera los huecos temporales de datos. La información nueva del grupo mantiene tu misión alineada si la tienes. Elegir navegación propia, la salida del compañero, disolver el grupo o convertirlo en banda termina el seguimiento.

### Si no tienes la misión

- Si el compañero elige una misión que te falta, el seguimiento se detiene sin cambiar tu navegación. Un diálogo explica el motivo y abre el registro para pedirla y volver a seguir. /qt preview focus muestra el aviso; /qt preview compare permite probar botones y cambios simulados.

## 6.4.3

Correcciones de misión seleccionada y grupos, con ajustes de mapa más simples.

### Tu misión seleccionada

- El encabezado lee directamente tu misión, incluso solo o sin compartirla. Cambiar la misión de navegación lo actualiza sin pulsar Actualizar.

### Miembros en el tooltip

- Los grupos pequeños muestran de inmediato al jugador señalado y al líder mientras carga la lista. Solo aparece Cargando si faltan otros miembros; por encima de cinco sigue mostrándose solo el líder.

### Un ajuste para ambos mapas

- Mostrar otros jugadores en mapa y minimapa controla las dos vistas, separado de compartir ubicación. Al actualizar se mantiene visible si cualquiera de las dos estaba activa y oculto si ambas estaban apagadas.

## 6.4.2

Más control sobre los datos de misiones, la ubicación visible y la accesibilidad de las ventanas. Discord sigue siendo el punto de contacto para comentarios y ayuda.

### Datos del registro de grupo

- Los encabezados muestran la antigüedad de cada instantánea y permiten actualizar solo a ese jugador. Filtros añade actualización automática opcional, aproximadamente cada 30 segundos mientras esté abierta la ventana real.
- Actualizar conserva búsqueda, misiones desplegadas, posición horizontal y misión visible cuando es posible. Las etiquetas de misión seleccionada distinguen espera, caducidad y falta de compatibilidad; si no se sabe más, indican «no compartida o no disponible». El menú avisa si seguir crearía un bucle.

### Accesibilidad y distribución

- Accesibilidad ofrece escala del 80% al 150% para texto y controles y movimiento reducido, con desplazamiento y expansión instantáneos. La escala puede limitarse para que la ventana quepa.
- Registro de grupo y bienvenida guardan tamaño y posición relativa a la pantalla por perfil. Las ventanas se reajustan al cambiar pantalla o escala de interfaz. Restablecer distribución o /qt resetlayout borra las posiciones QT guardadas y las centra.

### Visualización de jugadores

- Puedes mostrar u ocultar los puntos del mapa y del minimapa por separado, sin cambiar si compartes tu ubicación. El filtro ofrece todos los usuarios QT, quienes buscan compañeros o solo grupo.
- Mostrar siempre mi grupo viene activado para incluir compañeros incluso con el filtro de búsqueda, si sus permisos de ubicación lo permiten.

### Otros ajustes

- La detección experimental conserva ajustes e interfaz, con solicitudes más fluidas al cambiar los indicios o esperar otros candidatos. Escape usa la acción normal de cierre de los diálogos. Puedes asignar una tecla al registro de grupo en las teclas nativas; no tiene una por defecto.
- El cursor permite leer completos títulos y objetivos largos. Las barras de escala y alcance cercano son más brillantes y tienen contorno oscuro.

## 6.4.1

Detección experimental de capas para usuarios QT cercanos.

### Estimaciones de capa

- Detectar capas diferentes viene activado en Ajustes > QuestTogether > Experimental. Desactivarlo detiene comparaciones y oculta indicadores inferidos.
- En el mundo abierto de Forever, clientes QT compatibles cercanos comparan observaciones de PNJ y jugadores visibles. Un icono de fase indica una capa probablemente distinta; consulta el tooltip. Hace falta compartir ubicación.
- Puede equivocarse: no ver a alguien no demuestra nada por sí solo. Verse entre sí o ver al mismo jugador invalida la estimación de PNJ. Los indicios antiguos caducan; clientes anteriores no participan.

### Imágenes de las notas

- Las capturas se adjuntan directamente a Discord para permanecer visibles en las publicaciones de cambios.

## 6.4.0

Ventanas QT más cuidadas y acceso directo a las misiones del grupo.

### Registro de misiones del grupo

- El registro presentado en 6.3 compara hasta cinco jugadores por columnas de clase: quién tiene cada misión, a quién le falta y cuándo todos están listos para entregar. Combina búsqueda con filtros de posesión, progreso y acciones; Compartir y Solicitar compartir aparecen cuando es posible.
- Cada encabezado muestra la misión seleccionada. Pulsa el nombre de un compañero para seguirla voluntariamente; si no la tienes, no cambia tu navegación. Actualizar pide una instantánea nueva. Las capturas usan datos ficticios de demostración.
- Tus misiones tienen un botón de libro para abrir detalles en el Registro de misiones de Blizzard; pulsar la fila sigue desplegando objetivos. La corona del líder se actualiza con los cambios y tu columna permanece primera.

**Retail**

![Registro de misiones del grupo — Retail](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogRetail.png)

**Forever**

![Registro de misiones del grupo — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogForever.png)

### Objetivos de todos

- Despliega una o varias misiones para consultar cantidades, barras y pasos terminados por jugador. Los paneles son más compactos y sus encabezados y fondos coinciden en color de clase. Una misión típica de cinco jugadores con dos objetivos cada uno cabe al tamaño inicial; otras más largas pueden necesitar desplazamiento.

**Forever**

![Objetivos de todos — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestObjectivesForever.png)

### Ventanas y minimapa

- Clic izquierdo en el minimapa abre o cierra el registro; derecho abre el menú. Ajustes vuelve al menú y el tooltip explica los accesos.
- Recordatorios de chat de grupo, solicitudes de compartir o unirse, ajustes de burbujas e invitación a Discord usan el marco QT y sus temas claro y oscuro, con más espacio para márgenes y valores.
- Arrastrar conserva la distancia del cursor al borde, también en la vista previa. Los textos llaman de forma coherente Registro de misiones a la ventana de Blizzard.

### Vistas previas

- /qt preview enumera vistas previas de ventanas y anuncios; los comandos antiguos siguen funcionando. Las acciones simuladas no invitan, comparten ni envían mensajes.
- La comparación de demostración incluye cinco jugadores, Cazador y Pícaro entre ellos, con objetivos variados, misiones seleccionadas y corona de líder.

## 6.3.1

Más espacio para leer objetivos en el Registro de misiones del grupo.

### Espaciado de objetivos

- Los paneles desplegados tienen margen inferior para separar las barras del borde. El desplazamiento y la animación incluyen ese espacio.
- Mensajes como «No hay detalles de objetivos» quedan centrados verticalmente junto al nombre, sin amontonarse arriba.

## 6.3.0

El nuevo Registro de misiones del grupo reúne objetivos, destinos compartidos y seguimiento opcional de la misión de un compañero.

### Registro de misiones del grupo

- Comparar misiones del grupo pasa a llamarse Registro de misiones del grupo. Puedes desplegar varias misiones a la vez para consultar objetivos, progreso y un resumen de si el grupo está listo.
- Busca misiones y combina filtros de posesión, progreso y acciones de compartir. Actualizar renueva las instantáneas remotas; clientes antiguos aún comparan listas, pero no aportan detalles de objetivos.
- La ventana de pergamino admite cambios de tamaño y desplazamiento suave, con columnas de clase, encabezados de jugador amplios y paneles de objetivos redondeados.

### Misión seguida y destinos del grupo

- Bajo cada nombre aparece su misión activa. Seguir misión desde el encabezado o menú QT sigue las que tú también tienes. Si falta o se borra una, tu navegación no cambia. Navegar manualmente, salir del grupo o recargar termina el seguimiento.
- Los puntos de Blizzard de otros miembros aparecen con su color de clase en el mapa y, si están cerca, en el minimapa. Los superpuestos enumeran propietarios; Navegar aquí usa TomTom o navegación nativa. Recibir un punto no te redirige ni garantiza compartir fase.
- Compartir mi misión seleccionada, Compartir mi punto y Mostrar puntos del grupo vienen activados en Grupos y compartir, independientes de ubicación pública y búsqueda de compañeros. Seguir es voluntario. Requieren usuarios actualizados en grupos de hasta cinco, también mazmorras; no bandas.

### Ventanas y menús

- Las notas usan pergamino oscuro con modo Claro opcional. Puedes mover y redimensionar, consultar filas de historial más limpias y usar flechas entre versiones o hasta los extremos. Discord y Ajustes están en el pie.
- Los tooltips se ajustan mejor a su contenido. El minimapa separa herramientas de misiones de notas, destino del registro y visibilidad del icono. Ajustes y Enviar mensaje QT salen de ese menú; /qt options sigue abriendo ajustes.

## 6.2.3

Menos anuncios repetidos de misiones listas para entregar.

### Avisos de finalización

- Las misiones ya listas o completadas al empezar el seguimiento se registran en silencio. Datos ausentes o actualizaciones posteriores no repiten una disponibilidad ya observada.
- Las nuevas finalizaciones sí se anuncian y volver a aceptar una misión reinicia su historial. El emisor debe actualizar; las versiones anteriores aún pueden mandar ráfagas.

## 6.2.2

El progreso conserva sus detalles en cualquier idioma.

### Mantén el texto del objetivo

- Misiones normales, del mundo y objetivos de bonificación mantienen la redacción y cifras del remitente en chat y burbujas, en lugar de fórmulas genéricas como «Objetivo 1: 5/5».
- Los anuncios de aceptación y finalización siguen usando etiquetas traducidas y títulos locales disponibles.

## 6.2.1

Queda más claro cuándo QT habla por el chat del grupo.

### Controla los anuncios al grupo

- Dónde anunciar explica que QT también publica si un miembro no está reconocido como usuario QT. La opción sigue activada por defecto.
- Tras una breve espera de descubrimiento aparece un diálogo con logo QT. Elige Mantener activado o Desactivar anuncios antes de comenzar los envíos; No volver a recordarlo guarda la confirmación en el perfil.
- El recordatorio localizado identifica a los afectados y puede volver con nuevos miembros no reconocidos. Desaparece si se confirma que usan QT. Los eventos retenidos durante la espera no se repiten después.

## 6.2.0

El movimiento del minimapa es más fluido, los detalles llegan antes y las comunicaciones ganan fiabilidad.

### Movimiento cercano

- Hasta cuatro usuarios cercanos elegibles tienen prioridad para intercambiar posiciones por susurros de addon espaciados. Se respetan ubicación compartida, filtros, ignorados y límites de tráfico.
- Ambos necesitan esta versión para el movimiento continuo y las respuestas directas al cursor. Versiones anteriores conservan envíos normales; retrasos del servidor y restricciones siguen afectando la entrega.

### Descubrimiento y grupos

- Pasar el cursor por nombres o puntos puede pedir datos nuevos directamente, con límites de frecuencia. Las listas de grupo que no cambian dejan de caducar a los dos minutos.
- Ubicaciones recientes, búsqueda y grupos conocidos sobreviven a /reload hasta tres minutos desde la toma original. Entrar en una zona solicita descubrimiento espaciado.
- Mientras falta el tamaño exacto se muestra el estado conocido de solo o agrupado. Un logo pequeño identifica usuarios QT en las filas del grupo sin desalinear nombres.

### Textos e indicadores

- Razas, detalles de ping, datos de misiones y más interfaz usan textos locales disponibles. Sin traducción de misión queda el texto legible recibido; los objetivos no toman descripciones locales ajenas.
- Los avisos genéricos llevan el logo QT y Buscar compañeros encabeza el menú del minimapa.

### Fiabilidad

- Comparaciones, listas de grupo, solicitudes de unión y misiones y respuestas a ping prefieren susurros con clientes compatibles. Avisos agrupados y menos posiciones idénticas reducen tráfico público.
- Se corrigen exploraciones repetidas, demasiados reintentos de placas, diálogos que no cerraban bajo restricciones y /qt set aceptando opciones que no son interruptores. Desactivar ubicación ya no elimina solicitudes pendientes de otro tipo.

## 6.1.2

Los puntos cercanos reaccionan antes y los anuncios localizados son más claros.

### Puntos del minimapa

- Si el minimapa no ofrece un ID de mapa, QT usa tu mapa actual para evitar puntos ausentes.

### Posiciones más frecuentes

- Con menos de 10 usuarios QT conocidos en la zona se intenta actualizar cada segundo; con 10–19, cada 5–10 segundos; con 100, cada 15–20. Los intervalos crecen gradualmente entre esos niveles y no cambian desde 500 usuarios.
- Solo se envían posiciones compactas recién tomadas a ese ritmo; los demás datos siguen más despacio. Los límites de tráfico pueden retrasar la entrega, y el emisor debe actualizar para enviar más deprisa.

### Anuncios localizados

- Etiquetas como Misión aceptada usan tu idioma aunque falte título local o metadatos opcionales. Si WoW no ofrece un título, se mantiene el legible del remitente. El progreso conserva su texto original si no puede reconstruirse con seguridad.

## 6.1.1

Menús de jugadores y misiones más sencillos.

### Limpieza de menús

- Los menús de nombres ya no incluyen el acceso para mover registros. Usa el minimapa o los ajustes para alternar entre el chat principal y una ventana independiente.

## 6.1.0

Los mapas muestran quién va en grupo y permiten solicitar unirse a través de cualquiera de sus miembros.

### Reconoce los grupos

- Una insignia de dos personas marca a los jugadores agrupados en ambos mapas. Al pasar el cursor, sus compañeros reciben contorno blanco, los demás puntos se atenúan y el líder lleva corona. Los brillos dorados de búsqueda siguen visibles.
- Los tooltips de puntos y nombres del registro enumeran miembros con puntos y nombres en el color de la clase de cada jugador, primero el líder coronado. Se muestran todos hasta cinco; en grupos mayores, solo el líder.
- Tu grupo utiliza la lista nativa. Los detalles remotos se solicitan cuando hacen falta a clientes actualizados, con caché y ritmo limitado. Clientes antiguos conservan puntos y tamaño básico; la lista completa requiere actualización.

### Solicitudes dirigidas al líder

- Puedes pedir unirte a través de alguien sin permiso para invitar. Si su líder tiene QT y puede invitar, recibe la solicitud con las confirmaciones y aprobaciones automáticas habituales.
- Si no consta que el líder use QT y están permitidos los anuncios al grupo, el miembro puede avisar por ese chat de que pides unirte. Entonces debe invitarte manualmente alguien con permiso.
- Tú y quien reenvía necesitáis esta versión. Se mantienen límites de grupo lleno, restricciones, ignorados, caducidad y frecuencia de solicitudes.

### Tooltips más claros

- La información del grupo va justo debajo de nivel, raza y clase, con filas compactas y separación entre apartados. Los emblemas de facción duplican su tamaño.
- La versión cierra el tooltip como vX.Y.Z; Última actualización aparece encima cuando se muestra la edad de la posición. Se retira el número de misiones de tooltips de jugadores y minimapa, pero se conserva la misión activa de quienes buscan compañeros.

## 6.0.2

Consulta actualizaciones anteriores en tu idioma y recupera mejor los títulos de misiones completadas.

### Historial de novedades

- La ventana incluye Anteriores, Siguientes, Última e Historial con versiones y fechas. Siempre abre la más reciente e incluye todas las publicaciones anteriores, también betas, en todos los idiomas de WoW y sus archivos de cambios.
- La navegación se desactiva cuando no hay destino. Consultar notas antiguas no cambia la actualización que has reconocido; solo las versiones mayores o menores abren la ventana automáticamente. Puedes abrirla con /qt notes.

### Títulos al completar misiones

- Si una misión sale del diario antes de tener un título válido, QT intenta consultarlo en el juego antes de usar su ID. El título recuperado se conserva independientemente del orden de entrega y retirada.
- Si tu cliente no resuelve el título local, se usa el texto del remitente; si ninguno tiene nombre, queda el ID. La mejora de recuperación requiere que actualice quien envía el anuncio.

## 6.0.1

Las celebraciones ajenas quedan limitadas a jugadores que realmente puedes ver cerca.

### Reacciones cercanas

- Reaccionar a una misión completada o subida de nivel requiere una unidad visible que coincida con el jugador. Ni coordenadas ni nombre bastan, incluso con devlogall activo.
- Solo se aceptan gestos de la lista de celebraciones QT. mountspecial, vítores de facción y otros no incluidos se ignoran sin sustituirlos. Tus celebraciones propias conservan comportamiento y ajustes.

## 6.0.0

QuestTogether 6.0 prepara el lanzamiento de Forever con comunicaciones que reducen el tráfico de fondo conforme crece la comunidad.

### Actividad local y descubrimiento global

- Los anuncios de misiones y actualizaciones frecuentes pasan a canales de zona. Los del grupo siguen llegando entre zonas. Los puntos mundiales permanecen disponibles con actualizaciones de fondo más lentas; mirar otra zona en el mapa te suscribe temporalmente a ella.
- El chat escrito sigue en el canal global QuestTogether. Global o Solo zona continúa determinando lo que ves.

### Menos tráfico

- Presencia, versión, número de misiones, búsqueda y ubicación se reúnen en mensajes compactos. Las zonas concurridas actualizan con menor frecuencia.
- Los anuncios se espacian y tienen prioridad sobre el fondo; las respuestas a ping se reparten para evitar ráfagas. WoW todavía puede retrasar entregas: no se prometen mensajes instantáneos.
- Los tooltips muestran la edad de posiciones antiguas. Los diagnósticos incluyen número de mensajes, limitaciones de envío y retrasos de anuncios informados por el remitente.

### Un cambio importante durante la beta

- Aprovechamos la beta, antes de que más jugadores dependan del funcionamiento antiguo, para preparar la base de comunicaciones del lanzamiento.
- 6.0 abandona QuestTogetherAnnounce1 y no envía ni recibe en él. QuestTogether sirve para chat y descubrimiento global; los canales regionales, para actividad local.
- QT coloca sus canales después de los demás, con el principal antes de los regionales. Se conservan preferencias de ubicación, ignorados y anuncios.

### Actualizad juntos

- Las versiones antiguas no leen los nuevos mensajes agrupados ni escuchan los canales de zona. Mezclarlas puede ocultar puntos, búsqueda de compañeros y anuncios cercanos.
- Quien solo usa el canal anterior deja de ser descubrible por él. Algunas comunicaciones con versiones 5.x recientes pueden funcionar mediante el canal global común o el grupo, pero la compatibilidad es parcial.
- /qt ping sigue usando el canal global y puede detectar clientes antiguos compatibles ahí. Es una ayuda de descubrimiento, no un censo completo de usuarios QT.

## 5.17.2

El chat QT se distingue mejor de los anuncios de misión.

### Texto blanco para conversaciones

- Los mensajes de jugadores se muestran en blanco en el registro y las burbujas. Los nombres conservan su color de clase y los anuncios de misión siguen amarillos.

## 5.17.1

Los tooltips muestran más sobre tus compañeros y permiten consultar el estado de una misión directamente desde el chat.

### Datos de jugadores

- Los nombres y puntos indican cuántas misiones controla QT y si el jugador está solo o en un grupo de N. Tu tooltip utiliza el estado local actual. El minimapa cuenta las misiones controladas por QT, igual que el anuncio inicial, no solo las seguidas en el tracker de WoW.
- Los datos ajenos de misiones y tamaño de grupo requieren un cliente actualizado y se renuevan cada 80 segundos aproximadamente en avisos existentes, sin tráfico extra. Si faltan o caducan, aparecen como desconocidos. Los clientes anteriores siguen recibiendo versiones compatibles.

### Consulta una misión al pasar el cursor

- En el registro QT, el nombre de misión muestra junto al cursor tu estado, si puedes compartirla, su ID y el progreso de objetivos local. Las etiquetas están en todos los idiomas y los datos reflejan tu etapa, no la del remitente.
- Estado desaparece del menú. Al pulsar siguen disponibles Compartir, Abrir en el diario, Comparar misiones del grupo y el destino de la ventana de registro.

## 5.17.0

Habla por el chat QT, anuncia que buscas compañeros en tu zona y consulta más información de jugadores y ajustes.

### Conversa por QT

- Escribe /qt <text> o elige Enviar mensaje de chat QT en el minimapa. Se muestra en registros y burbujas cercanas con un icono de conversación; los comandos habituales siguen funcionando.
- Puedes ver chat Global, activado por defecto, Solo zona o ninguno. Solo zona exige una ubicación compartida reciente del remitente; Global no.
- Durante la transición conviven QuestTogether y QuestTogetherAnnounce1. QT intenta situarlos después de tus otros canales, con QuestTogether primero. El chat escrito solo usa el canal nuevo.

### Anuncia tu búsqueda

- Activar la búsqueda envía un aviso a toda la zona con un icono QT dorado y una sonrisa. Necesita compartir ubicación y respeta tus preferencias de anuncios; desactivarla no envía aviso.
- Configura estos mensajes en Qué anunciar. Hay 30 segundos de espera entre anuncios repetidos, aunque estado y brillo cambian al instante. Puedes dejar de buscar al entrar en grupo automáticamente; esta opción viene apagada.
- Mayús-clic en el botón del minimapa alterna la búsqueda. Un anillo dorado más brillante pulsa mientras está activa sin recortar el logo.

### Alcance y detalles

- Alcance cercano va del 5% a Toda la zona y empieza en 25%. Ajusta la distancia según tu zona; los miembros del grupo y jugadores visibles mantienen su comportamiento.
- Los nombres del registro tienen el mismo tooltip que los puntos: nombre en el color de su clase, nivel, raza, clase, emblema de facción, búsqueda, misión seguida disponible y versión QT. Aparece junto al cursor.
- Tu propio tooltip muestra tu misión seleccionada para navegación mientras buscas compañeros. Los clientes actualizados incluyen la versión aproximadamente cada 40 segundos en avisos periódicos existentes; los anteriores conservan su frecuencia.

### Controles más claros

- El tooltip del minimapa muestra versión, búsqueda, alcance del chat, misiones seguidas, alcance cercano y ubicación compartida. Los controles de ajustes, incluidos desplegables, barras, perfiles y colores, tienen explicaciones localizadas al pasar el cursor.
- Si no se puede resolver un título local, registros y burbujas conservan el texto original del remitente en lugar de un número genérico. Los anuncios posteriores vuelven al idioma local cuando el título está disponible.

## 5.16.7

Las notas del juego, Discord y los archivos de cambios cuentan las mismas novedades.

### Historial coherente en todos los idiomas

- El registro inglés comparte resúmenes y puntos con la bienvenida y Discord. Hay archivos para todos los idiomas compatibles, con el historial traducido existente y una copia conservada de las antiguas notas inglesas escritas a mano.
- Las comprobaciones de publicación mantienen esos archivos sincronizados con las notas canónicas y sus versiones localizadas.

## 5.16.6

El minimapa te recuerda que estás buscando compañeros.

### Recordatorio dorado

- El botón QT pulsa con el mismo brillo dorado de los logos de placas mientras buscas compañeros. Sigue tu estado y se apaga al desactivar QT u ocultar el botón. Ni el botón ni su logo cambian de tamaño.

## 5.16.5

Los avisos de grupo ocupan menos espacio.

### Anuncios compactos

- El progreso enviado a compañeros sin QT usa [QT] en lugar de [QuestTogether]. Se respeta el límite del chat sin cortar caracteres de ningún idioma.

## 5.16.4

Se conservan los ajustes de burbuja al salir de modo de edición y se da prioridad a jugadores próximos en mapas llenos.

### Guarda los ajustes de burbuja

- Cerrar modo de edición del HUD ya no revierte tamaño de letra, duración ni posición. El panel QT tiene su propio botón Guardar cambios e indicación de guardado. Los ajustes se aplican al momento; Guardar fija el punto al que vuelve Revertir cambios, incluso después de hacer más ajustes.

### Los más cercanos primero

- Si compiten más de 128 puntos válidos en cualquiera de los mapas, se prioriza la distancia a tu personaje. Al llenarse la memoria de 512 ubicaciones, se conservan los cercanos antes que nuevas llegadas lejanas. Desplazar o ampliar el mapa no cambia esa prioridad.
- Se mantienen los límites de puntos y memoria sin enviar mensajes adicionales.

## 5.16.3

Los ajustes se reorganizan para encontrar antes lo que necesitas y consultar tus preferencias de un vistazo.

### Ajustes por actividad

- Grupos y compartir sustituye a Miscelánea y reúne búsqueda de compañeros, solicitudes de unión y permisos para compartir misiones. Los gestos de celebración pasan a Dónde anunciar.
- La visibilidad del minimapa está en General de la página principal. Herramientas de depuración y revisión del diario se agrupan en Solución de problemas. Comparar misiones del grupo y Buscar compañeros encabezan las acciones rápidas. Tus preferencias se conservan.

### Estado rápido más útil

- Los apartados enlazados muestran búsqueda de compañeros, ubicación compartida y visible, permisos, destinos de anuncios y ajustes de placas de misiones y jugadores. También puedes consultar perfil activo, versión instalada y otra más reciente detectada. Con QT desactivado, se aclara que son preferencias guardadas.
- Pulsa un encabezado para abrir sus ajustes. El resumen crece con el texto y se actualiza mientras la página está abierta.

## 5.16.2

Los tooltips identifican a los usuarios QT y el brillo ayuda a encontrar compañeros.

### Identificación en el tooltip

- Pasa el cursor por un personaje QT, su placa o su marco de unidad para ver que usa QuestTogether. Si busca compañeros, también aparece ese estado con un logo brillante.
- El apartado QT se adapta al ancho y escala del tooltip, evita su barra de salud y pasa arriba si no hay sitio debajo.

### Brillo más amplio

- El halo dorado de las placas llega al doble de distancia alrededor del logo, sin agrandarlo. Tanto el icono como el brillo representan usuarios QT reales y su estado actual de búsqueda.

## 5.16.1

Los compañeros que buscan grupo se distinguen mejor y pueden mostrar qué misión están siguiendo.

### Un brillo más visible

- El logo QT de su placa tiene un brillo dorado más intenso, con una pulsación suave. El propio logo permanece estable.

### Su misión actual

- Pasa el cursor por el punto de mapa o minimapa de alguien que busca compañeros para ver su misión seleccionada para navegación. Ambos necesitan esta actualización.
- Se renueva aproximadamente cada 20 segundos y solo se comparte mientras estén activados la búsqueda de compañeros y el envío de ubicación.
- Se usa el título de tu idioma cuando existe, o el del remitente o ID como alternativa. Las versiones anteriores conservan sus puntos e indicadores de búsqueda.

## 5.16.0

QuestTogether admite todos los idiomas de WoW y puede mostrar las actualizaciones de misiones de otros jugadores en el tuyo.

### Todos los idiomas de WoW

- Menús, ajustes y notas están disponibles en inglés, alemán, francés, español europeo y latinoamericano, portugués brasileño, ruso, italiano, coreano, chino simplificado y tradicional. El español latinoamericano tiene textos propios.

### Progreso localizado

- Los eventos compatibles de usuarios QT actualizados pueden aparecer en tu idioma en el chat y las burbujas, con el título local disponible y las cifras reales del remitente.
- Si no se puede elegir con seguridad la descripción traducida de un objetivo, se muestra su número localizado junto a cantidades, porcentaje, estado de finalización o progreso.
- Las versiones antiguas y el chat público de grupo conservan el texto del remitente. Si WoW no ofrece título local, se usa el original o el ID de misión. Los eventos del mismo idioma mantienen su redacción detallada.

### Títulos de misiones

- Las comparaciones prefieren el título local disponible y los nombres con puntuación no ASCII mantienen sus enlaces de forma más fiable.

## 5.15.0

Solicita unirte al grupo de otro jugador desde su menú QT.

### Pide unirte

- Si hay datos recientes que confirman que el jugador tiene grupo, Solicitar unirse sustituye a Invitar. Ambos necesitan esta actualización y tú debes estar sin grupo.
- Quien recibe la solicitud puede rechazarte o enviar una invitación normal de WoW si tiene permiso y espacio en un grupo ordinario. Sigues teniendo que aceptar esa invitación.

### Invitaciones automáticas opcionales

- Dos ajustes permiten aceptar automáticamente solicitudes de amigos de personaje o de otros jugadores mientras buscas compañeros. Ambos vienen apagados, aparecen en la solicitud y en Miscelánea y no incluyen amigos de cuenta Battle.net.
- Las solicitudes caducan y respetan ignorados, cambios de grupo y restricciones. QT no abandona tu grupo ni acepta invitaciones por ti.

## 5.14.1

El chat de grupo identifica el addon por su nombre completo.

### Chat de grupo

- El prefijo [QT] pasa a ser [QuestTogether], para que otros jugadores puedan encontrarlo con más facilidad.

## 5.14.0

QT incorpora cinco idiomas y permite informar a compañeros que no usan el addon.

### Interfaz en tu idioma

- Alemán, francés, español, portugués brasileño y ruso se suman a la interfaz. QT sigue el idioma del juego y usa inglés como alternativa.
- Se localizan ajustes, menús, tooltips, comparaciones y notas. Los títulos y avances recibidos de otros jugadores conservan su idioma original.
- Discord cuenta con cinco canales de cambios específicos para estos idiomas.

### Avisos para todo el grupo

- Una opción nueva en Dónde anunciar envía tus eventos activados al chat de grupo si hay alguien que aún no se ha reconocido como usuario QT. Viene activada y puedes desactivarla en ajustes.
- Funciona también en grupos de instancia emparejados. No se aplica estando solo ni en bandas y nunca reenvía anuncios de otros jugadores.

## 5.13.1

Mejoran la recuperación de placas y la limpieza de burbujas y logos antiguos. Los ajustes y la ventana de depuración también se mantienen sincronizados.

### Placas e indicadores

- Los iconos de misión y colores de salud se recuperan al cerrar vistas restringidas. Las exploraciones aplazadas conservan su tiempo de estabilización y los tooltips temporalmente ausentes mantienen sus reintentos.
- Las burbujas se limpian si una placa desaparece o se reutiliza en combate; los marcos protegidos o prohibidos esperan a poder limpiarse con seguridad.
- Ubicaciones y presencia se recuperan al desactivar QT, cambiar de zona y reactivarlo. Los avisos tardíos de retirada de ubicación o búsqueda de compañeros no devuelven el logo a quienes ya se fueron.

### Ajustes y ventanas

- La casilla de búsqueda de compañeros refleja cambios hechos mediante comandos, menús o perfiles.
- Al terminar las restricciones, la ventana de depuración finaliza correctamente movimientos y cambios de tamaño interrumpidos, aunque se haya ocultado.

### Comprobaciones de fiabilidad

- Las pruebas detectan accesos a marcos prohibidos aunque el código capture el error.
- La publicación se bloquea si quedan cambios de implementación sin confirmar en Git, para que los arreglos lleguen al paquete descargable.

## 5.13.0

Los puntos y logos resaltados facilitan encontrar compañeros. Se simplifican los ajustes de ubicación y llegan recordatorios cuando otro usuario tiene una versión estable más reciente.

### Reconoce a quienes buscan grupo

- Un brillo dorado suave rodea sus puntos de clase en ambos mapas y el logo QT de su placa. Desaparece al desactivar o caducar el estado.
- Ubicaciones de jugadores incluye «Mostrar solo jugadores que buscan compañeros»: viene apagado y filtra ambos mapas.
- La ventana de novedades compara logos y puntos normales con sus variantes brillantes. El dorado significa que el jugador busca compañeros.

### Ubicación más sencilla

- Compartir mi ubicación y Mostrar otros jugadores se aplican cada uno a ambos mapas. En perfiles nuevos empiezan activados; actualizar conserva las decisiones previas de no compartir.

### Avisos de actualización

- Si otro usuario comunica una versión estable más reciente, QT muestra un recordatorio en la ventana de chat que elegiste. Se guarda entre personajes y aparece una vez por recarga hasta instalar esa versión o una superior. Las versiones alfa y beta no lo activan.
- Los mensajes de versión son pequeños y poco frecuentes; QT también aprovecha la versión que ya incluyen las respuestas a ping.

## 5.12.0

El estado Buscando compañeros para misiones te ayuda a encontrar compañía. También mejoran los puntos y el tooltip del minimapa, con un tratamiento distinto de reinos y modo guerra en Retail y Forever.

### Busca compañeros

- El estado aparece en tu menú y en los tooltips de puntos; no activa la ubicación ni envía invitaciones. Cámbialo desde el minimapa, Ajustes > Miscelánea o /qt lfg. /qt lfg on, off o status permite activarlo, desactivarlo o consultarlo. Empieza apagado y se guarda por perfil.
- El estado caduca si deja de actualizarse, excluye a ignorados y deja de anunciarse al desactivar QT.

### Retail y Forever

- Forever deja de mostrar modo guerra en puntos, detalles de ubicaciones de misiones y respuestas a ping. Los pings tampoco muestran reinos, pero conservan nombres completos. Sus avisos cercanos ya no necesitan datos de modo guerra de Retail y los puntos siguen visibles entre fases para encontrar grupo.
- Retail utiliza el estado activo del modo guerra cuando puede consultarlo. Si es desconocido o no es compatible, ya no lo presenta como desactivado.

### Puntos más estables

- Una pérdida breve de coordenadas conserva la última posición hasta dos minutos; el tooltip indica la antigüedad de los datos. Dejar de compartir sigue retirando el punto inmediatamente cuando la comunicación lo permite.
- El movimiento se envía como máximo cada diez segundos. Parado se mantiene el aviso cada veinte segundos, compatible con clientes anteriores.
- Se guardan hasta 512 jugadores y se dibujan hasta 128 puntos por mapa. Los jugadores fuera del mapa visible no consumen ese límite de dibujo.

### Logos de jugadores

- Se consulta el ajuste actual de placas amistosas para recuperar logos ausentes en Retail y Forever. Los logos a la izquierda dejan espacio a beneficios visibles y vuelven a su lugar al desaparecer estos.
- Todos los mensajes QT compatibles identifican al remitente. Una memoria limitada por sesión de interfaz conserva esa identidad aunque se pierda un aviso periódico, sin enviar mensajes extra. Las salidas explícitas y los ignorados sí se limpian.

### Tooltip del minimapa

- El tooltip del botón QT usa una capa independiente para mostrarse por encima de las barras de acción. Se oculta si el botón deja de estar disponible o empiezan restricciones.

## 5.11.0

Llegan las ubicaciones de jugadores, los logos en placas, las comparaciones individuales y el acceso a ayuda por Discord. Puedes elegir qué compartes y qué ves mientras coordinas el progreso con otros usuarios de QT.

### Reconoce jugadores QT

- Con las placas amistosas de WoW activadas, los jugadores QT muestran el logo de pergamino. Placas de jugadores viene activado y lo coloca a la izquierda con margen; también puedes elegir derecha, arriba o prefijo, sin cambiar el color de las barras.
- Quienes comparten ubicación pueden aparecer como puntos del color de su clase en el mapa y minimapa. Al pasar el cursor verás nombre, facción, raza, clase y nivel; al pulsar se abre su menú.
- Ubicaciones de jugadores separa compartir y visualizar en cada mapa: las cuatro opciones empiezan activadas. La presencia para los logos puede seguir disponible aunque desactives ambas formas de compartir ubicación.
- Las ubicaciones se renuevan periódicamente y caducan. Ambos usuarios necesitan esta actualización; ver un punto no garantiza estar en la misma fase o capa.

### Compara con una persona o con el grupo

- Comparar misiones en el menú de un jugador muestra solo tus misiones y las suyas, incluso fuera de tu grupo si se puede contactar con su QT. La comparación de todo el grupo sigue en el minimapa, los menús de misión y /qt compare.
- Compartir y pedir misiones siguen limitados al grupo. La comparación individual explica cuándo hace falta grupo para compartir y cuándo el otro jugador necesita QT para responder.
- Si hay una solicitud de compartir pendiente, al cambiar de jugador se indica de quién se espera respuesta.

### Ayuda por Discord

- La bienvenida y la página principal de ajustes incluyen Discord: comentarios y ayuda. Abre una invitación para copiar; si no se puede abrir esa ventana, la muestra en el chat.

### Correcciones

- Ignorar a un jugador bloquea nuevos registros, burbujas, puntos, comparaciones y solicitudes de compartir; al cambiar la lista también se retiran sus burbujas y ubicaciones existentes.
- Se corrigen placas falsas causadas por límites de tooltip ilegibles que confundían texto de otra misión.
- Desactivar una forma de compartir ubicación reintenta el aviso si falla temporalmente la comunicación. Desactivar ambas también retira la ubicación de los demás mensajes del addon.
- Los logos se limpian si la presencia caduca justo antes de la salida. Susurrar desde un punto abre el chat; cambiar el destino del registro desde Ajustes queda bloqueado durante restricciones.

## 5.10.0

QuestTogether comparte el progreso con tu grupo y con jugadores cercanos. El botón del minimapa reúne ajustes, comparación de misiones, diario y novedades.

### Misiones del grupo

- Usa /qt compare o abre Comparar misiones del grupo desde el minimapa o los menús de misiones y jugadores. Verás quién tiene cada misión y su progreso. Se muestran todas por defecto; «Ocultar misiones que no tengo» limita la vista a tu diario.
- Puedes pedir misiones compartibles a compañeros con el addon actualizado. Por defecto deben dar permiso; compartir automáticamente es opcional.
- Las comparaciones se recuperan tras restricciones de mapa o combate. Una actualización sustituye respuestas anteriores, y los tiempos de espera y errores indican cuándo puedes volver a intentarlo.

### Accesos y menús

- Arrastra el botón de pergamino para moverlo por el minimapa. Su menú abre ajustes, comparaciones, diario, notas y destino del registro. Puedes ocultarlo ahí y recuperarlo en Miscelánea.
- El menú de una misión ofrece Estado, Compartir, Abrir en el diario y Comparar misiones del grupo. Al compartir o abrir el diario se vuelven a comprobar la misión actual y las restricciones.
- Los enlaces de estado conservan el título aunque abandones la misión. La casilla de compartir automáticamente sigue los ajustes guardados y los cambios de perfil.

### Ayuda y notas

- La bienvenida y las novedades tienen su propia ventana para no repetir mensajes en el chat. Ábrela desde el minimapa, la página principal de ajustes o con /qt notes, /qt changelog o /qt patchnotes.
- Se abre sola al cambiar de versión mayor o menor. Las revisiones de mantenimiento también incluyen notas, pero no abren la ventana automáticamente.
- /qt help muestra los comandos habituales; /qt help debug reúne vistas previas, diagnósticos y herramientas de desarrollo.

## 5.9.2

El nombre de una misión en el registro QT abre su menú con cualquiera de los dos botones del ratón. Estado aparece primero y Compartir después. La última opción, tras un separador, mueve el registro entre la ventana principal y una independiente, igual que el menú de jugadores.

### Cambios de esta versión

- Compartir utiliza la entrada actual del registro sin cambiar la misión seleccionada por Blizzard. No está disponible si estás solo, hay restricciones o la misión no es compartible.
- Los nombres de misión en mensajes de estado también se pueden pulsar, incluidos los títulos alternativos recibidos de otros jugadores. Al dar formato a comparaciones completadas se conservan los enlaces existentes para no crear un segundo enlace roto con el texto de estado.
- Pasaron 521 pruebas en ambos órdenes con Lua 5.1 y 5.2, seis perfiles de API, sintaxis Lua y shell, revisión exacta de libchev y diferencias. El menú en el cliente, la entrega de misiones compartidas y el taint del motor se comprueban aparte.

## 5.9.1

Una revisión general corrige problemas en el seguimiento de misiones, las placas, los avisos de zonas de tareas, las comunicaciones y las acciones del usuario.

### Cambios de esta versión

- Los bloques de misiones ajenas en un tooltip ya no toman prestado texto de objetivos compartidos. Se conserva el progreso válido del grupo y se recuperan placas tras cambios de mapa, instancia, miembros o misiones.
- Las misiones recién aceptadas y los análisis iniciales esperan datos legibles. Se preservan hitos de progreso, tipos de tarea y ubicaciones desconocidas, sin inventar salidas ni duplicar entradas.
- Mejoran los anuncios localizados y las comparaciones: límites de mensajes, ritmo de envío, reintentos, cancelación e información sobre si una misión puede compartirse.
- Si falla un marcador nativo, QT no sigue uno anterior. Los clics restringidos mientras está desactivado se rechazan sin perder trabajo pendiente. Las pruebas de burbuja son vistas previas locales y aceptan nombres completos de Forever o entre comillas, conservando la identidad exacta.
- Se corrigen activación, desactivación, perfiles, apertura de modo de edición del HUD, gestos de celebración permitidos y diagnósticos. Las pruebas se aíslan mejor para ejecutarlas en el juego, se corrigen supuestos erróneos y CI comunica los fallos de sintaxis Lua.
- Pasaron 516 casos en ambos órdenes con Lua 5.1 y 5.2, los seis perfiles de API, sintaxis, revisión exacta de libchev y diferencias. La presentación en el cliente, la entrega entre dos clientes y el taint del motor se validan aparte.

## 5.9.0

Celebra las subidas de nivel propias y de otros jugadores QT cercanos con gestos sincronizados. En Miscelánea hay controles independientes junto a los de finalización de misiones, activados por defecto. Las reacciones respetan el alcance de jugadores y las reglas de proximidad existentes.

### Cambios de esta versión

- QT recuerda los objetivos completados tanto por aparición como por tipo de criatura. Si aparece otra durante el combate y no se puede leer su tooltip, no la marca por un dato antiguo que indicaba que aún hacía falta. Un objetivo pendiente confirmado puede recuperar el resaltado; los cambios en el estado de misiones borran esa memoria. Un tooltip parcial o inaccesible nunca demuestra que todos hayan terminado.
- Si ya no puedes obtener crédito de una criatura, se retiran inmediatamente el icono de misión y el color de su barra, también en combate. QT observa cambios de propiedad y vuelve a comprobarlos al cambiar salud o amenaza.
- En combate normal al aire libre se detectan criaturas de misión nuevas a partir de tooltips legibles. Las placas se actualizan al volver a la cámara, seleccionarlas o pasar el cursor. Los reintentos por marcos, GUID o líneas tardías son limitados por unidad; al desaparecer se cancela el trabajo pendiente. Icono y color se restauran juntos. Se mantienen las protecciones de mapa, instancia, datos inaccesibles y marcos protegidos, sin invocar Questie ni tooltips ocultos durante esta detección.
- Pasaron 374 pruebas en ambos órdenes con Lua 5.1 y 5.2, seis perfiles de API, sintaxis, biblioteca exacta y diferencias. Las regresiones de la memoria de completados reprodujeron el fallo antes del arreglo. La comprobación de partida y taint del motor sigue siendo independiente.

## 5.8.6

QT maneja mejor los valores inaccesibles o incorrectos de nombres, clases, títulos de misiones y colores de clase personalizados. Comprueba los datos de TomTom y Questie antes de usarlos y deja de leer un tooltip de Questie al encontrar información inaccesible.

### Cambios de esta versión

- La visibilidad de las burbujas y el estado de modo de edición se convierten en valores booleanos antes de enviarlos a los controles. Se unifica el manejador de pantallas de carga, se retiran argumentos privados y una rama de restricciones sin uso, y se aclara el tratamiento de callbacks y valores devueltos. Se conservan las alternativas para clientes actuales y antiguos y la revisión exacta de la biblioteca privada.
- Pasaron 336 casos en ambos órdenes con Lua 5.1 y 5.2 y las pruebas ampliadas de adaptadores en seis clientes. Las regresiones nuevas fallan con la versión anterior, como corresponde; sintaxis, revisión de biblioteca y diferencias también pasan. Se revisaron los avisos restantes de Ketho WoW API/LuaLS, incluso sin simulaciones de cliente. Cada aviso conservado tiene un motivo concreto de compatibilidad, protección, callbacks, biblioteca o datos de prueba. La validación de partida en Retail y Forever sigue siendo independiente.

## 5.8.5

Se corrige la detección en el mapa de tareas y misiones del mundo. Los clientes actuales leen questID de C_TaskQuest.GetQuestsOnMap; los antiguos conservan su API y el campo questId. Para los gestos de celebración se da prioridad a C_ChatInfo.PerformEmote, que funciona sin las funciones globales obsoletas.

### Cambios de esta versión

- La ausencia o el fallo de la API de gestos se controla de forma segura. También se eliminan un cálculo sin uso de la huella del grupo y variables locales innecesarias.
- Las pruebas cubren las API modernas y antiguas de tareas y gestos, su prioridad, datos de misiones inaccesibles y API ausentes o fallidas. Pasaron 334 casos en ambos órdenes con Lua 5.1 y 5.2, las pruebas ampliadas de seis perfiles de cliente, la sintaxis y la revisión exacta de la biblioteca. El funcionamiento dentro de Retail y Forever se valida por separado.

## 5.8.4

Mantenimiento del repositorio, sin cambios durante la partida.

### Cambios de esta versión

- Las notas locales de desarrollo quedan fuera del código versionado y de los paquetes de distribución.

## 5.8.3

Al iniciar sesión o recargar la interfaz, QT anuncia una vez la versión instalada, los clientes compatibles y el comando de ajustes. Los enlaces propios de CurseForge y GitHub abren una ventana de copia con aspecto nativo.

### Cambios de esta versión

- La bienvenida y su ventana de copia segura usan libchev 1.2.0. Si no se pueden registrar enlaces o abrir la ventana, se imprime la URL completa en el chat. Un fallo de la bienvenida no impide el arranque normal del addon.
- Pasaron 334 pruebas en ambos órdenes con Lua 5.1 y 5.2, las comprobaciones de API, sintaxis y revisión exacta de la biblioteca. Las simulaciones de NoPoizen prueban ambos enlaces de comentarios en siete perfiles de cliente o reglas. La presentación en el juego se verifica por separado.

## 5.8.2

Se corrigen dos fallos falsos de /qt test: un jugador cercano podía ocupar el identificador de placa utilizado por las pruebas del tooltip y del icono en caché. Las consultas de GUID de las pruebas quedan aisladas; las placas durante la partida no cambian.

### Cambios de esta versión

- El entorno de pruebas reproduce esa coincidencia y ambos errores sin la corrección. Con ella pasan los 333 casos en ambos órdenes con Lua 5.1 y 5.2 y los seis perfiles de API. La confirmación dentro del juego sigue siendo una comprobación aparte.

## 5.8.1

QuestTogether tiene un icono reconocible en la lista de addons.

### Cambios de esta versión

- La lista de addons muestra el marcador de misión de Blizzard junto a QuestTogether en lugar de la interrogación genérica.

## 5.8.0

Se amplía la compatibilidad con los clientes Classic actuales: recepción correcta de misiones, alternativas protegidas para consultar objetivos, estado desconocido cuando no se puede determinar si una misión es compartible y metadatos por variante. Retail, Forever y las herramientas de depuración conservan su comportamiento.

### Cambios de esta versión

- Las pruebas de API cubren seis clientes. Pasaron 333 casos en ambos órdenes con Lua 5.1 y 5.2, la sintaxis y la comprobación exacta de la biblioteca privada; también las pruebas básicas de cliente de NoPoizen y la verificación del paquete. Los nuevos adaptadores aún necesitan validación dentro del juego.
- CLIENT_COMPATIBILITY.md recoge las fuentes, el alcance y los límites de estas comprobaciones.

## 5.7.7

Con libchev 1.1.3, las consolas de depuración superpuestas y sus controles mantienen el orden nativo de las ventanas. Los menús de categoría permanecen unidos a su consola.

### Cambios de esta versión

- Los iconos de objetivos se sitúan a la izquierda de la placa de nombre de forma predeterminada. Tus posiciones guardadas no cambian.
- En Forever, tu nombre respeta «My Last Name»; los apellidos de los demás siguen visibles, tal como establece ese ajuste. Las comunicaciones, el grupo, las coincidencias de placas y las acciones sociales usan nombres completos de forma coherente, sin cambiar las claves guardadas de perfiles ni de posición de la burbuja personal.
- Se evitan anuncios propios duplicados al recibir desde el canal otra forma del mismo nombre completo. Las pruebas cubren el anuncio local y sus ecos de canal y grupo, incluido otro personaje con el mismo nombre de pila.
- Pasaron 331 pruebas en ambos órdenes con Lua 5.1/5.2. La nueva posición predeterminada de los iconos y la interacción entre varias ventanas aún requieren confirmación en el juego.

## 5.7.6

Los tres addons usan la misma consola privada de libchev 1.1.2, con filtros de categoría y búsqueda, copia, resultados de pruebas, diagnósticos, marcas de tiempo cuando están disponibles y un único resumen final. También se corrigen las texturas estiradas del marco nativo al delimitar su área.

### Cambios de esta versión

- Abre las herramientas con /qt test, /qt debug o /qt diagnostics. QuestTogether aporta sus diagnósticos de misiones y pruebas aisladas; la biblioteca se encarga de la consola y las funciones comunes de depuración.
- Pasaron 324 pruebas en ambos órdenes con Lua 5.1/5.2. El aspecto corregido se confirmó dentro del juego; las demás comprobaciones de restricciones y funcionamiento durante la partida siguen siendo independientes.

## 5.7.6-beta.3

La consola de depuración incluida se actualiza a libchev 1.1.1 y recupera el aspecto de las ventanas de WoW.

### Cambios de esta versión

- El resumen de las pruebas ya no sale duplicado; el resultado final se conserva en el historial limitado. No cambian la búsqueda, las categorías, la copia, el desplazamiento, las pruebas, los diagnósticos ni las protecciones existentes.
- Un jugador confirmó las 324 pruebas en Forever 1.60.1, compilación 70009, con beta.2. Además, se revisaron los siete archivos de pruebas cargados en el juego: no contienen casos que generen NaN ni divisiones por cero. Ese resultado anterior no verifica el nuevo aspecto de esta versión.
- Tras /reload, abre /qtd, ejecuta /qt test y comprueba el aspecto de la ventana y que solo aparezca un resumen. Sigue pendiente validar en el cliente la presentación y las restricciones o el taint de esta revisión.
- Los 324 casos pasan en orden normal e inverso con los intérpretes Lua 5.1.5 y 5.2.4. Cada ejecución por consola produce un resumen y el ZIP extraído, de 26 archivos, supera las pruebas en ambas versiones. Se verificaron los 23 archivos Lua, las 22 entradas del TOC, el manifiesto de dependencias, el formato y las diferencias. Revisión de biblioteca: 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. QT aún no tiene CI en GitHub; el de la biblioteca original sí pasó.

## 5.7.6-beta.2

La depuración pasa a la consola común de libchev v1.1. Sustituye a la ventana independiente de QT y viene incluida, sin instalaciones adicionales.

### Cambios de esta versión

- La consola reúne filtros por categoría, búsqueda aproximada y de frases entre comillas, selección y copia, borrado, recarga, pruebas y diagnósticos. También mantiene el seguimiento de las nuevas líneas al desplazarte por el registro.
- /qt test muestra los resultados actuales; repetirlo sustituye el historial TEST anterior y elimina filtros de búsqueda que podrían ocultarlos. /qt diagnostics [questID] y /qt diag [questID] reconstruyen el informe con los datos en caché en la misma consola y conservan eventos recientes dentro del límite de exportación.
- Las protecciones compartidas para restricciones y marcos del addon sustituyen a los antiguos manejadores de la consola y su desplegable. El estado de las misiones, los anuncios, las placas, las comunicaciones y el aislamiento de las pruebas propias siguen en QuestTogether.
- En esta beta aún falta verificar la presentación y el taint en Retail y Forever. Tras /reload, ejecuta /qt test y /qt diagnostics y comprueba categorías, búsqueda, copia, borrado, tamaño, desplazamiento, pruebas repetidas y cambios entre informes y registro. Incluye entradas y salidas de combate y otras restricciones con tus addons habituales.
- Pasaron 324/324 pruebas en ambos órdenes con Lua 5.1.5 y 5.2.4, la sintaxis de los 23 archivos Lua, las 22 entradas del TOC y el manifiesto de la biblioteca. El ZIP instalable extraído superó también los 324 casos en el entorno de pruebas independiente, fuera del juego. Revisión fijada: 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

Esta beta incorpora libchev v1.0.0, incluida en QuestTogether. Los addons Together comparten así las herramientas de registro, diagnóstico, protección de llamadas, tareas aplazadas y pruebas; no hace falta instalar otra biblioteca.

### Cambios de esta versión

- Los informes reúnen información del cliente, el addon y la biblioteca. Si se llena la ventana de copia, conservan los eventos más recientes.
- QuestTogether sigue gestionando las misiones, el grupo, las placas de nombre y las restricciones. Cada addon mantiene separados sus datos de ejecución.
- Con QT desactivado, los enlaces de coordenadas siguen funcionando cuando el juego lo permite. Las tareas pendientes permanecen en pausa y se descartan los temporizadores caducados.
- /qt test reúne 315 casos: los 300 anteriores, diez pruebas comunes de la biblioteca y cinco de integración. Todos pasan en ambos órdenes con Lua 5.1.5 y 5.2.4; también se verificaron la sintaxis, el orden de carga del TOC y el manifiesto de revisión y hashes. Revisión de libchev: 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- Queda pendiente comprobar en los clientes de Retail y Forever el aspecto de la interfaz y los posibles bloqueos por taint tras este cambio. Después de recargar, ejecuta /qt test y /qt diagnostics; prueba misiones, burbujas de progreso, placas y enlaces de coordenadas en combate, al cambiar de zona, al desactivar y reactivar QT y tras recargar con tus addons habituales. La confirmación anterior de 300 pruebas en Retail correspondía a v5.7.5.
