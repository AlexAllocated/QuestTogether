# QuestTogether — Registro de cambios

<!-- Generated from canonical release notes; do not edit by hand. -->

## 5.17.0

Saluda en el chat de QT, encuentra compañeros para hacer misiones por tu zona y descubre detalles y ajustes de jugador más claros.

### Chatea con otros jugadores de QuestTogether

- Escribe /qt <text>, o elige Enviar mensaje de chat de QT en el menú del minimapa. Las conversaciones aparecen en los registros de QT y en globos cercanos sobre la cabeza con un ícono de globo de diálogo; los comandos con barra existentes siguen funcionando.
- Elige chat global (el predeterminado), Solo zona, u oculta el chat de QT por completo. Solo zona requiere una ubicación compartida reciente del remitente; Global no.
- El nuevo canal QuestTogether funciona junto con QuestTogetherAnnounce1 durante la transición. QT coloca ambos después de tus otros canales cuando es compatible, con QuestTogether primero; el chat escrito usa solo el canal nuevo.

### Encuentra compañeros para hacer misiones

- Activar Buscando compañeros para hacer misiones anuncia tu búsqueda por toda tu zona con un ícono de QT con brillo dorado y una carita sonriente. La entrega en toda la zona requiere compartir ubicación y respeta las preferencias de anuncios; desactivarlo no envía nada.
- Controla estos mensajes en Qué anunciar. Un tiempo de reutilización de 30 segundos limita los anuncios repetidos mientras tu estado y brillo se actualizan de inmediato. También puedes elegir dejar de buscar automáticamente al unirte a un grupo; esta opción empieza desactivada.
- Mayús-clic en el botón del minimapa para activar o desactivar tu búsqueda de compañeros. Un anillo dorado más brillante y palpitante resalta tu búsqueda activa sin recortar el logo.

### Elige tu alcance y ve más detalles de jugadores

- El alcance cercano ahora va de 5% a Toda la zona, con un valor predeterminado de 25%. Ajusta la distancia en toda tu zona actual; los miembros del grupo y los jugadores directamente visibles conservan su comportamiento existente.
- Pasa el cursor sobre los nombres en los registros de QT para ver la misma descripción emergente mejorada que en los puntos del mapa: nombre con color de clase, nivel, raza, clase, emblema de facción, estado de compañero, misión seguida cuando esté disponible y versión de QT. Las descripciones emergentes de nombres ahora aparecen junto al cursor.
- La descripción emergente de tu propio nombre ahora muestra tu misión actual con seguimiento destacado mientras buscas compañeros. Los clientes actualizados anuncian versiones aproximadamente cada 40 segundos usando los mensajes de latido existentes; los clientes antiguos mantienen su intervalo anterior.

### Controles y anuncios más claros

- La descripción emergente del minimapa ahora muestra tu versión de QT, estado de compañero, alcance del chat, cantidad de misiones vigiladas, alcance cercano y estado de compartir ubicación.
- Los controles de ajustes ahora tienen explicaciones traducidas al pasar el cursor, incluidos menús desplegables, controles deslizantes, acciones de perfil y controles de color.
- Cuando tu cliente no puede resolver el título localizado de una misión, los anuncios conservan el texto original del remitente tanto en los registros como en los globos, en lugar de mostrar un número de misión genérico. La visualización localizada se reanuda para anuncios posteriores cuando el título esté disponible.

## 5.16.7

Lee las mismas notas de lanzamiento de QuestTogether dentro del juego, en Discord y en tu idioma preferido en los archivos de registro de cambios.

### Registros de cambios multilingües y coherentes

- El registro de cambios en inglés ahora comparte los mismos resúmenes de lanzamiento y puntos clave que la ventana de bienvenida y los anuncios de Discord.
- Los archivos de registro de cambios están disponibles para todos los idiomas compatibles, con el historial de lanzamientos traducido existente y una copia preservada de las notas antiguas en inglés escritas manualmente.
- Las comprobaciones de lanzamiento mantienen los archivos de registro de cambios sincronizados con las notas canónicas y las traducciones.

## 5.16.6

Ve de un vistazo cuando estés buscando compañeros para misiones.

### Un recordatorio brillante en el minimapa

- Tu botón de QuestTogether en el minimapa ahora pulsa con el mismo brillo dorado del logo que las placas de nombre de los jugadores mientras Buscar compañeros para misiones está activado.
- El brillo sigue tu estado de compañero y se detiene cuando QT está desactivado o el botón del minimapa está oculto. Tu botón y el logo mantienen su tamaño actual.

## 5.16.5

Un prefijo más corto mantiene compactos los anuncios del grupo.

### Anuncios de grupo compactos

- El progreso de misión publicado para miembros del grupo sin QuestTogether ahora empieza con [QT] en lugar de [QuestTogether].
- Los anuncios siguen respetando el límite de mensajes del chat y conservan caracteres completos en todos los idiomas.

## 5.16.4

Conserva la configuración de tus burbujas al salir del modo Edición y encuentra compañeros cercanos para hacer misiones en mapas concurridos.

### La configuración de las burbujas permanece guardada

- Al cerrar el modo Edición del HUD, ahora se conservan el tamaño de fuente, la duración de visualización y la posición de tus burbujas de QT en lugar de revertirlos.
- El panel de burbujas de QT ahora tiene su propio botón Guardar cambios y un mensaje de estado guardado. La configuración se aplica automáticamente; Guardar cambios establece el punto al que vuelve Revertir cambios.
- Después de guardar y hacer más ajustes, Revertir cambios restaura la última configuración guardada de QT.

### Los jugadores cercanos tienen prioridad

- Cuando más de 128 puntos elegibles compiten por espacio en el mapa o minimapa, los jugadores más cercanos tienen prioridad según la distancia desde tu personaje.
- Cuando se llena la caché de 512 ubicaciones, se conservan los jugadores más cercanos antes que las llegadas más lejanas. Desplazar y hacer zoom en el mapa no cambia la prioridad por cercanía.
- Estos cambios mantienen los límites existentes de puntos y caché sin enviar mensajes de comunicación adicionales.

## 5.16.3

Encuentra más fácilmente la configuración que necesitas y ve tus preferencias de QuestTogether de un vistazo.

### Configuración organizada según cómo juegas

- Grupos y uso compartido reemplaza a Misceláneo, reuniendo la disponibilidad de compañeros, las solicitudes para unirse y las aprobaciones para compartir misiones.
- Los gestos de celebración ahora están en Dónde anunciar. La visibilidad del minimapa está en General, en la página principal, con las herramientas de depuración y el nuevo escaneo del registro de misiones juntos en Solución de problemas.
- Comparar misiones del grupo y Buscar compañeros de misiones ahora son las primeras Acciones rápidas. Tus preferencias existentes se conservan.

### Un Estado rápido más útil

- Ve el estado de tus compañeros, las preferencias de compartir ubicación y visualización, las aprobaciones de solicitudes, la salida de anuncios y la configuración de placas de nombre de misiones y jugadores en secciones vinculadas.
- Consulta tu perfil activo, la versión instalada y cualquier versión más reciente detectada. Cuando QT está desactivado, el resumen identifica claramente la configuración como preferencias guardadas.
- Haz clic en el encabezado de una sección para abrir su configuración. El resumen crece para ajustarse a su texto y se mantiene actualizado mientras la página está abierta.

## 5.16.2

Reconoce a los jugadores de QuestTogether por sus tooltips y encuentra compañeros de misiones más fácilmente.

### Tooltips de jugadores de QuestTogether

- Pasa el cursor sobre el personaje, la barra de nombre o el marco de unidad de un jugador de QT para ver “Este jugador está usando QuestTogether.” Los jugadores que buscan compañeros de misiones también muestran ese estado y un logo de QT brillante.
- La sección de QT coincide con el ancho y la escala del tooltip, queda separada de su barra de salud y se mueve encima del tooltip cuando el espacio debajo es limitado.

### Un brillo de compañero más visible

- El brillo dorado de la barra de nombre ahora se extiende el doble alrededor del logo, manteniendo el logo del mismo tamaño.
- Los íconos y brillos reflejan a usuarios reales de QT y su estado actual de búsqueda de compañeros.

## 5.16.1

Encuentra compañeros de misiones más fácilmente y ve en qué misión se están enfocando.

### Un brillo de compañero más intenso

- Los jugadores que buscan compañeros de misiones ahora tienen un brillo dorado más intenso alrededor del logo de QT en su placa de nombre, con un suave pulso de respiración. El logo permanece estable.

### Ve su misión actual

- Pasa el cursor sobre el punto del mapa o minimapa de un jugador que busca compañeros de misiones para ver su misión superrastreada: la única misión seleccionada para la navegación. Ambos jugadores necesitan esta actualización.
- La información de la misión se actualiza aproximadamente cada 20 segundos. Solo se comparte mientras Buscar compañeros de misiones y compartir ubicación están activados.
- Los nombres de las misiones usan el idioma de tu cliente cuando está disponible, con el título o ID de misión del remitente como alternativa. Las versiones anteriores de QT conservan sus puntos e indicadores de compañero existentes.

## 5.16.0

QuestTogether ahora es compatible con todos los idiomas de WoW y puede mostrar las actualizaciones de misiones de otros jugadores en el idioma de tu cliente.

### Juega en más idiomas

- Los menús, ajustes y notas del parche ahora son compatibles con todas las configuraciones regionales de idioma de WoW: inglés, alemán, francés, español europeo, español latinoamericano, portugués brasileño, ruso, italiano, coreano, chino simplificado y chino tradicional.
- El español latinoamericano ahora tiene su propio texto en lugar de compartir el español europeo.

### Progreso de misión localizado

- Los eventos de misión compatibles de jugadores de QT actualizados pueden aparecer en el idioma de tu cliente en los registros de chat y burbujas de QT, usando títulos de misión locales cuando estén disponibles y los números de progreso reales del remitente.
- Cuando no se puede elegir de forma segura una descripción traducida de un objetivo, QT usa un número de objetivo localizado con conteos, porcentajes, finalización o estado de progreso en su lugar.
- Las versiones anteriores de QT y el chat público de grupo conservan la redacción del remitente. Cuando WoW no puede proporcionar un título de misión local, QT conserva el título de origen o muestra el ID de la misión. Los eventos en el mismo idioma conservan su redacción nativa detallada.

### Mejoras en títulos de misión

- La comparación de misiones ahora prefiere tu título de misión local cuando esté disponible.
- Los títulos de misión localizados con puntuación no ASCII se mantienen clicables con mayor fiabilidad.
