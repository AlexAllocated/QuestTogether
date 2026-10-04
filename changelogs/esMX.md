# QuestTogether — Registro de cambios

<!-- Generated from canonical release notes; do not edit by hand. -->

## 5.16.6

Lee las mismas notas de lanzamiento de QuestTogether dentro del juego, en Discord y en tu idioma preferido en los archivos de registro de cambios.

### Registros de cambios multilingües y coherentes

- El registro de cambios en inglés ahora comparte los mismos resúmenes de lanzamiento y puntos clave que la ventana de bienvenida y los anuncios de Discord.
- Los archivos de registro de cambios están disponibles para todos los idiomas compatibles, con el historial de lanzamientos traducido existente y una copia preservada de las notas antiguas en inglés escritas manualmente.
- Las comprobaciones de lanzamiento mantienen los archivos de registro de cambios sincronizados con las notas canónicas y las traducciones.

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
