# QuestTogether — Registro de cambios

<!-- Generated from canonical release notes; do not edit by hand. -->

## 5.17.1

El chat de QT es más fácil de distinguir de los anuncios de misiones.

### Texto blanco en el chat de QT

- Los mensajes de los jugadores en el chat de QT ahora usan texto blanco en el registro de chat y en los bocadillos sobre la cabeza.
- Los nombres de los jugadores conservan los colores de su clase, y los anuncios de misiones conservan su texto amarillo.

## 5.17.0

Saluda en el chat de QT, encuentra compañeros de misiones por tu zona y descubre detalles de jugadores y ajustes más claros.

### Chatea con otros jugadores de QuestTogether

- Escribe /qt <text>, o elige Enviar mensaje de chat de QT en el menú del minimapa. Las conversaciones aparecen en los registros de QT y en bocadillos sobre jugadores cercanos con un icono de bocadillo; los comandos de barra existentes siguen funcionando.
- Elige chat global (el predeterminado), Solo zona u oculta el chat de QT por completo. Solo zona requiere una ubicación compartida reciente del remitente; Global no.
- El nuevo canal de QuestTogether funciona junto a QuestTogetherAnnounce1 durante la transición. QT coloca ambos después de tus otros canales cuando es compatible, con QuestTogether primero; el chat escrito solo usa el canal nuevo.

### Encuentra compañeros de misiones

- Activar Buscando compañeros de misiones anuncia tu búsqueda por toda tu zona con un icono de QT con brillo dorado y una carita sonriente. La entrega a toda la zona requiere compartir ubicación y respeta las preferencias de anuncios; al desactivarla, no se anuncia nada.
- Controla estos mensajes en Qué anunciar. Un tiempo de reutilización de 30 segundos limita los anuncios repetidos mientras tu estado y el brillo se actualizan igualmente al instante. También puedes elegir dejar de buscar automáticamente al unirte a un grupo; esto empieza desactivado.
- Mayús-clic en el botón del minimapa para activar o desactivar tu búsqueda de compañeros. Un anillo dorado más brillante y pulsante resalta tu búsqueda activa sin recortar el logotipo.

### Elige tu alcance y consulta más detalles de jugadores

- Alcance cercano ahora va del 5% a Toda la zona, con un valor predeterminado del 25%. Escala la distancia en tu zona actual; los miembros del grupo y los jugadores visibles directamente conservan su comportamiento actual.
- Pasa el cursor sobre los nombres en los registros de QT para ver la misma descripción mejorada que en los puntos del mapa: nombre con el color de la clase, nivel, raza, clase, emblema de facción, estado de compañero, misión seguida cuando esté disponible y versión de QT. Las descripciones de nombres ahora aparecen junto al cursor.
- La descripción de tu propio nombre ahora muestra tu misión con seguimiento destacado actual mientras buscas compañeros. Los clientes actualizados anuncian versiones aproximadamente cada 40 segundos usando los mensajes de latido existentes; los clientes antiguos mantienen su programación anterior.

### Controles y anuncios más claros

- La descripción del minimapa ahora muestra tu versión de QT, estado de compañero, ámbito del chat, número de misiones vigiladas, alcance cercano y estado de compartir ubicación.
- Los controles de ajustes ahora tienen explicaciones traducidas al pasar el cursor, incluidos menús desplegables, deslizadores, acciones de perfil y controles de color.
- Cuando tu cliente no pueda resolver el título localizado de una misión, los anuncios conservarán el texto original del remitente tanto en los registros como en los bocadillos en lugar de mostrar un número de misión genérico. La visualización localizada se reanudará en anuncios posteriores cuando el título esté disponible.

## 5.16.7

Lee las mismas notas de la versión de QuestTogether en el juego, en Discord y en tu idioma preferido en los archivos de registro de cambios.

### Registros de cambios coherentes y multilingües

- El registro de cambios en inglés ahora comparte los mismos resúmenes de versión y puntos de la lista que la ventana de bienvenida y los anuncios de Discord.
- Los archivos de registro de cambios están disponibles para todos los idiomas compatibles, con el historial de versiones traducido existente y una copia conservada de las antiguas notas en inglés escritas a mano.
- Las comprobaciones de versión mantienen los archivos de registro de cambios sincronizados con las notas canónicas y las traducciones.

## 5.16.6

Consulta de un vistazo cuándo estás buscando compañeros para hacer misiones.

### Un recordatorio luminoso en el minimapa

- El botón de QuestTogether del minimapa ahora palpita con el mismo brillo dorado del logotipo que las placas de nombre de los jugadores mientras Buscar compañeros para hacer misiones está activado.
- El brillo sigue tu estado de compañero y se detiene cuando QT está desactivado o el botón del minimapa está oculto. Tu botón y el logotipo mantienen su tamaño actual.

## 5.16.5

Un prefijo más corto mantiene compactos los anuncios de grupo.

### Anuncios de grupo compactos

- El progreso de las misiones publicado a los miembros del grupo sin QuestTogether ahora empieza con [QT] en lugar de [QuestTogether].
- Los anuncios siguen respetando el límite de mensajes del chat y conservan caracteres completos en todos los idiomas.

## 5.16.4

Conserva tus ajustes de bocadillos al salir del modo de edición y encuentra compañeros de misión cercanos en mapas concurridos.

### Los ajustes de bocadillos permanecen guardados

- Al cerrar el modo de edición del HUD, ahora se conserva el tamaño de fuente, la duración de visualización y la posición de tus bocadillos de QT en lugar de revertirlos.
- El panel de bocadillos de QT ahora tiene su propio botón Guardar cambios y un mensaje de estado guardado. Los ajustes se aplican automáticamente; Guardar cambios establece el punto al que vuelve Revertir cambios.
- Tras guardar y realizar más ajustes, Revertir cambios restaura tus últimos ajustes de QT guardados.

### Los jugadores cercanos tienen prioridad

- Cuando más de 128 puntos válidos compiten por espacio en el mapa o minimapa, los jugadores más cercanos tienen prioridad según la distancia a tu personaje.
- Cuando la caché de 512 ubicaciones se llena, se conservan los jugadores más cercanos antes que los que llegan desde más lejos. Desplazar y ampliar el mapa no cambia la prioridad por proximidad.
- Estos cambios mantienen los límites existentes de puntos y caché sin enviar mensajes de comunicación adicionales.

## 5.16.3

Encuentra los ajustes que necesitas más fácilmente y consulta de un vistazo tus preferencias de QuestTogether.

### Ajustes organizados en torno a tu forma de jugar

- Grupos y compartir reemplaza a Varios, reuniendo la disponibilidad de compañeros, las solicitudes para unirse y las aprobaciones para compartir misiones.
- Los gestos de celebración ahora están en Dónde anunciar. La visibilidad del minimapa está en General, en la página principal, con las herramientas de depuración y el reescaneo del registro de misiones juntos en Solución de problemas.
- Comparar misiones de grupo y Buscar compañeros de misión ahora son las primeras acciones rápidas. Tus preferencias existentes se conservan.

### Un estado rápido más útil

- Consulta en secciones enlazadas tu estado de compañero, tus preferencias de compartir ubicación y visualización, las aprobaciones de solicitudes, la salida de anuncios y los ajustes de misiones y nombres de jugadores.
- Comprueba tu perfil activo, la versión instalada y cualquier versión más reciente detectada. Cuando QT está desactivado, el resumen identifica claramente los ajustes como preferencias guardadas.
- Haz clic en el encabezado de una sección para abrir sus ajustes. El resumen crece para ajustarse a su texto y se mantiene actualizado mientras la página está abierta.

## 5.16.2

Reconoce a los jugadores de QuestTogether por sus descripciones emergentes y encuentra compañeros de misiones más fácilmente.

### Descripciones emergentes de jugadores de QuestTogether

- Pasa el cursor sobre el personaje, la placa de nombre o el marco de unidad de un jugador de QT para ver «Este jugador usa QuestTogether». Los jugadores que buscan compañeros para hacer misiones también muestran ese estado y un logotipo de QT brillante.
- La sección de QT se ajusta al ancho y la escala de la descripción emergente, se mantiene separada de su barra de salud y se desplaza encima de la descripción emergente cuando el espacio inferior es limitado.

### Un brillo de compañero más visible

- El brillo dorado de la placa de nombre ahora llega el doble de lejos alrededor del logotipo, manteniendo el logotipo del mismo tamaño.
- Los iconos y brillos reflejan usuarios reales de QT y su estado actual de búsqueda de compañeros.

## 5.16.1

Encuentra compañeros de misiones más fácilmente y consulta en qué misión se están centrando.

### Un brillo de compañero más intenso

- Los jugadores que buscan compañeros de misiones ahora tienen un brillo dorado más intenso alrededor del logotipo de QT en su placa de nombre, con una suave pulsación. El logotipo permanece fijo.

### Consulta su misión actual

- Pasa el cursor sobre el punto del mapa o minimapa de un jugador que busca compañeros de misiones para ver su misión con seguimiento destacado: la única misión seleccionada para la navegación. Ambos jugadores necesitan esta actualización.
- La información de la misión se actualiza aproximadamente cada 20 segundos. Solo se comparte mientras Buscar compañeros de misiones y compartir ubicación están activados.
- Los nombres de las misiones usan el idioma de tu cliente cuando está disponible, con el título del remitente o el ID de misión como alternativa. Las versiones anteriores de QT mantienen sus puntos e indicadores de compañeros existentes.

## 5.16.0

QuestTogether ahora es compatible con todos los idiomas de WoW y puede mostrar las actualizaciones de misiones de otros jugadores en el idioma de tu cliente.

### Jugar en más idiomas

- Los menús, ajustes y notas de parche ahora son compatibles con todos los idiomas locales de WoW: inglés, alemán, francés, español europeo, español latinoamericano, portugués de Brasil, ruso, italiano, coreano, chino simplificado y chino tradicional.
- El español latinoamericano ahora tiene su propio texto en lugar de compartir el español europeo.

### Progreso de misión localizado

- Los eventos de misión compatibles de jugadores con QT actualizado pueden aparecer en el idioma de tu cliente en los registros de chat y bocadillos de QT, usando títulos de misión locales cuando estén disponibles y las cifras de progreso reales del remitente.
- Cuando no se pueda elegir con seguridad una descripción de objetivo traducida, QT usará un número de objetivo localizado con contadores, porcentajes, estado de completado o estado de progreso en su lugar.
- Las versiones antiguas de QT y el chat de grupo público conservan la redacción del remitente. Cuando WoW no pueda proporcionar un título de misión local, QT mantendrá el título de origen o mostrará el ID de misión. Los eventos en el mismo idioma conservan su redacción nativa detallada.

### Pulido de títulos de misión

- La comparación de misiones ahora prefiere el título de misión local cuando esté disponible.
- Los títulos de misión localizados con puntuación no ASCII siguen siendo clicables de forma más fiable.

## 5.15.0

Solicita unirte a un grupo de misiones directamente desde el menú de un jugador de QuestTogether.

### Únete a un grupo de misiones

- Los jugadores de QT que están en grupo ahora muestran Solicitar unirse en lugar de Invitar cuando hay información reciente del grupo. Ambos jugadores necesitan esta actualización; quien envía la solicitud debe estar solo.
- El destinatario puede enviar una invitación normal de WoW o rechazar la solicitud. Debe tener permiso para invitar y espacio en un grupo normal. Para unirte, sigues aceptando la invitación habitual.

### Invitaciones automáticas opcionales

- Dos nuevas opciones aprueban automáticamente las solicitudes de amigos de tu personaje, o de otros jugadores mientras buscas compañeros de misiones. Ambas están desactivadas por defecto y aparecen en la solicitud y en los ajustes Varios. No incluyen a los amigos de cuenta de Battle.net.
- Las solicitudes caducan y respetan la lista de ignorados, los cambios de grupo y las restricciones del juego. QT nunca abandona tu grupo actual ni acepta invitaciones por ti.

## 5.14.1

Los anuncios de grupo ahora muestran el nombre completo de QuestTogether.

### Chat de grupo

- El prefijo de los anuncios en el chat de grupo cambia de [QT] a [QuestTogether] para que otros jugadores puedan encontrar el addon más fácilmente.

## 5.14.0

QuestTogether ahora habla cinco idiomas más y te ayuda a mantener informados a los miembros del grupo que no usan QT.

### Juega en tu idioma

- La interfaz ya está disponible en alemán, francés, español, portugués de Brasil y ruso. QuestTogether usa el idioma del juego y recurre al inglés cuando es necesario.
- Los ajustes, menús, descripciones emergentes, comparaciones de misiones y notas de actualización están traducidos. Los nombres de misiones y los textos de progreso recibidos de otros jugadores conservan su idioma original.
- Encontrarás los anuncios de actualización traducidos en los cinco canales de registro de cambios por idioma de nuestro Discord.

### Mantén informado a todo tu grupo

- Una nueva opción de canales de anuncios envía tus anuncios de eventos habilitados al chat de grupo cuando algún miembro no ha sido reconocido como usuario de QT. Está activada por defecto y se puede desactivar en los ajustes.
- También funciona en grupos de estancia formados automáticamente. No se aplica al juego en solitario ni a las bandas, y nunca reenvía anuncios de otros jugadores.
