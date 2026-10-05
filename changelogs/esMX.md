# QuestTogether — Registro de cambios

<!-- Generated from canonical release notes; do not edit by hand. -->

## 6.1.1

Menús contextuales más limpios para jugadores y misiones.

### Limpieza del menú contextual

- Los menús de nombres de jugador y nombres de misiones ya no incluyen el acceso directo a la ventana del registro. Mueve los registros de QuestTogether entre la ventana principal de chat y una ventana separada usando el menú del minimapa o la configuración.

## 6.1.0

Encuentra grupos en el mapa, ve quiénes están haciendo misiones juntos y solicita unirte a través de cualquier miembro del grupo. Las descripciones emergentes de jugadores ahora muestran los detalles del grupo al frente y al centro.

### Ve quiénes están haciendo misiones juntos

- Los jugadores agrupados ahora tienen una pequeña insignia de dos personas en sus puntos del mapa y minimapa. Pasa el cursor sobre un miembro del grupo para resaltar a sus compañeros con un contorno blanco, atenuar los puntos no relacionados y mostrar una corona en el líder. Los resplandores dorados de Buscando compañeros para misiones siguen visibles.
- Las descripciones emergentes de jugadores muestran los miembros del grupo con puntos y nombres del color de su clase, con el líder coronado primero. Los grupos de hasta cinco muestran a todos los miembros; los grupos más grandes muestran solo al líder. Estos detalles también aparecen al pasar el cursor sobre nombres de jugadores en el registro de QuestTogether.
- Tu propio grupo usa la lista del juego. Los detalles de grupos remotos se cargan desde pares de QuestTogether actualizados cuando es necesario, con resultados en caché y solicitudes espaciadas para mantener bajo el tráfico del canal. Los clientes antiguos conservan sus puntos normales y la información básica del tamaño del grupo; los detalles completos de grupos remotos requieren un par actualizado.

### Las solicitudes para unirse pueden llegar al líder del grupo

- Puedes solicitar unirte a través de un miembro del grupo que no pueda invitarte. Si su líder está usando QuestTogether y está disponible para invitar, la solicitud se redirige al líder usando la confirmación y la configuración de aprobación automática habituales.
- Si no se sabe si el líder usa QuestTogether, el miembro puede anunciar “[QT] PlayerName solicita unirse al grupo.” en el chat de grupo cuando los anuncios de chat de grupo están activados. Entonces alguien con permiso para invitar deberá invitarte manualmente.
- El solicitante y el miembro que reenvía necesitan esta actualización para las solicitudes redirigidas. Las comprobaciones existentes de grupo lleno, restricciones, ignorados, caducidad y frecuencia de solicitudes siguen aplicándose.

### Descripciones emergentes de jugadores más limpias

- La información de grupo ahora aparece justo debajo de la línea de nivel, raza y clase, con filas compactas de miembros y espacio entre secciones. Las insignias de la Alianza y la Horda son el doble de grandes.
- La versión del addon aparece al final en el formato más corto vX.Y.Z. Cuando se muestra la antigüedad de una ubicación, Última actualización aparece directamente encima de la versión.
- Se eliminaron los recuentos de misiones con seguimiento de las descripciones emergentes de jugadores y del botón del minimapa. Se sigue mostrando el título de la misión activa para los jugadores que buscan compañeros para misiones.

## 6.0.2

Explora las actualizaciones anteriores de QuestTogether en tu idioma, con una mejor recuperación de nombres de misiones para los anuncios de completado.

### Explorar notas de parche anteriores

- La ventana de bienvenida ahora tiene botones de Más antiguas y Más recientes, un acceso directo a La más reciente y un selector de Historial que muestra las versiones y fechas de lanzamiento. Al abrir las notas de parche, se empieza en la versión más reciente.
- El historial incluye todas las versiones publicadas anteriormente, incluidas las primeras betas. Todas las notas históricas están traducidas a todos los idiomas de WoW compatibles e incluidas en los registros de cambios del repositorio correspondiente.
- Los botones de navegación se desactivan cuando no hay a dónde ir. Explorar notas anteriores no cambia qué actualización has confirmado; las ventanas emergentes automáticas siguen apareciendo solo para actualizaciones mayores y menores. Abre la ventana en cualquier momento con /qt notes.

### Títulos de completado de misiones

- Cuando una misión sale de tu registro antes de que QuestTogether tenga un título utilizable, los anuncios de completado ahora intentan usar la búsqueda de títulos de misión disponible del juego antes de recurrir a un ID de misión. Un título recuperado se conserva sin importar el orden de los eventos de entrega y eliminación.
- Los anuncios siguen usando el texto del remitente cuando tu cliente no puede resolver un título local. Si ninguno de los clientes tiene un nombre disponible, el ID de misión sigue siendo la alternativa. La recuperación mejorada del lado del remitente se aplica cuando el remitente se actualiza.

## 6.0.1

Las celebraciones ahora permanecen con los jugadores que realmente puedes ver cerca.

### Correcciones de celebraciones cercanas

- Las reacciones a otro jugador que completa una misión o sube de nivel ahora requieren una unidad de jugador visible que coincida. Las coordenadas del mapa o solo un nombre ya no activan un gesto, incluso cuando devlogall está activado.
- Los gestos entrantes deben coincidir con la lista de celebraciones propia de QuestTogether. Los gestos no incluidos, incluidos mountspecial y los vítores de facción, se ignoran sin elegir un sustituto.
- Tus propias celebraciones por completar misiones y subir de nivel mantienen su comportamiento y configuración existentes.

## 6.0.0

QuestTogether 6.0 se prepara para el lanzamiento de Forever con un sistema de comunicación diseñado para reducir el tráfico en segundo plano a medida que la comunidad crece.

### Actividad local, descubrimiento mundial

- Los anuncios de misiones y las actualizaciones frecuentes de jugadores ahora usan canales de zona. Los anuncios de grupo siguen llegando a tu grupo a través de los límites de zona.
- Los puntos de jugadores siguen disponibles por todo el mundo, con actualizaciones en segundo plano más lentas. Abrir otra zona en el mapa del mundo te suscribe temporalmente a sus actualizaciones.
- El chat de texto de QT permanece en el canal global de QuestTogether. Tu ajuste de chat Global o Solo zona sigue controlando qué mensajes ves.

### Menos tráfico en segundo plano

- La presencia, la versión, los conteos de misiones, el estado de compañero y la ubicación se agrupan en actualizaciones compactas. Las zonas concurridas se actualizan con menos frecuencia para reducir el tráfico.
- Los anuncios se dosifican y tienen prioridad sobre las actualizaciones en segundo plano. Las respuestas de ping se distribuyen para evitar una ráfaga de respuestas. WoW aún puede retrasar la entrega del canal; esta actualización no garantiza mensajes instantáneos.
- Las descripciones emergentes de jugadores muestran la antigüedad de las ubicaciones más antiguas. El diagnóstico ahora informa conteos de mensajes, limitación y retrasos de anuncios reportados por el remitente.

### Una actualización importante durante la beta

- Estamos haciendo este cambio de comunicación más grande ahora en anticipación al lanzamiento de Forever. La beta es el mejor momento para tomar estas decisiones fundamentales, antes de que más jugadores dependan del comportamiento anterior.
- La versión 6.0 abandona QuestTogetherAnnounce1 y ya no envía ni recibe en ese canal heredado. Usa QuestTogether para chat global y descubrimiento, además de canales de zona para la actividad local.
- QuestTogether mantiene sus canales después de tus otros canales de chat, con el canal de chat principal antes de sus canales de zona. Tus preferencias de compartir ubicación, lista de ignorados y anuncios se conservan.

### Compatibilidad con versiones anteriores

- Por favor actualicen juntos. Las versiones anteriores no pueden leer las nuevas actualizaciones de jugadores agrupadas ni escuchar los nuevos canales de zona, así que los jugadores con versiones mezcladas podrían perderse puntos en el mapa, estado de compañero y anuncios de misiones cercanas.
- Los jugadores que usan solo el canal heredado ya no son detectables mediante ese canal en 6.0. Algunos intercambios con versiones 5.x más nuevas aún pueden funcionar mediante el canal global compartido o un grupo, pero esta es una compatibilidad parcial, no la experiencia completa.
- El /qt ping manual todavía usa el canal global. Puede escuchar clientes anteriores compatibles ahí, pero es una herramienta de descubrimiento de mejor esfuerzo, no un conteo completo de todos los que usan QuestTogether.

## 5.17.2

El chat de QT es más fácil de distinguir de los anuncios de misiones.

### Texto blanco del chat de QT

- Los mensajes de los jugadores en el chat de QT ahora usan texto blanco en el registro de chat y en los globos sobre la cabeza.
- Los nombres de los jugadores conservan los colores de su clase, y los anuncios de misiones conservan su texto amarillo.

## 5.17.1

Consulta más información sobre tus compañeros de misión y revisa el estado de la misión directamente desde las descripciones emergentes del chat.

### Descripciones emergentes de jugador más útiles

- Las descripciones emergentes del nombre del jugador y de los puntos del mapa ahora muestran cuántas misiones está monitoreando QuestTogether, además de Solo o Grupo de N. Tu propia descripción emergente usa tu estado local actual.
- La descripción emergente del minimapa ahora cuenta las misiones monitoreadas por QuestTogether, coincidiendo con el anuncio de inicio en lugar de contar solo las misiones vigiladas en el seguimiento de WoW.
- Los conteos de misiones remotas y tamaños de grupo requieren un par actualizado. Se actualizan aproximadamente cada 80 segundos mediante los mensajes de latido existentes, sin mensajes adicionales; los informes faltantes o antiguos se muestran como desconocidos. Las versiones anteriores siguen recibiendo anuncios de versión compatibles.

### Estado de misión al pasar el cursor

- Pasa el cursor sobre el nombre de una misión en los registros de QT para ver el estado de tu misión, si se puede compartir, el ID de misión y el progreso de los objetivos seguidos localmente en una descripción emergente junto al cursor.
- Se eliminó el elemento Estado del menú. Al hacer clic en el nombre de una misión, aún se abren Compartir, Abrir en el Diario de misiones, Comparar misiones del grupo y la acción de destino de la ventana de registro.
- Las nuevas etiquetas de las descripciones emergentes están traducidas a todos los idiomas admitidos. Los detalles de la misión reflejan tu propio progreso, no la etapa de misión del remitente.

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

## 5.15.0

Pide unirte a un grupo de misiones directamente desde el menú de jugador de QuestTogether.

### Unirse a un grupo de misiones

- Los jugadores de QT agrupados ahora muestran Solicitar unirse en lugar de Invitar cuando hay información reciente de grupo disponible. Ambos jugadores necesitan esta actualización; quien solicita debe estar sin grupo.
- El destinatario puede enviar una invitación normal de WoW o rechazarla. Debe tener permiso para invitar y espacio en un grupo normal. Aun así debes aceptar la invitación normal para unirte.

### Invitaciones automáticas opcionales

- Dos opciones nuevas aprueban automáticamente las solicitudes de amigos de personaje o de otros jugadores mientras estás Buscando compañeros para misiones. Ambas empiezan desactivadas y aparecen en el aviso y en la configuración de Varios. Los amigos de cuenta de Battle.net no están incluidos.
- Las solicitudes caducan y respetan los ignorados, los cambios de grupo y las restricciones del juego. QT nunca abandona tu grupo actual ni acepta invitaciones por ti.

## 5.14.1

Los anuncios de grupo ahora muestran el nombre completo de QuestTogether.

### Chat de grupo

- Se amplió el prefijo de anuncio en chat de grupo de [QT] a [QuestTogether], para que a otros jugadores les sea más fácil encontrar el addon.

## 5.14.0

QuestTogether ahora habla cinco idiomas más y te ayuda a mantener informados a los miembros del grupo que no tienen QT.

### Juega en tu idioma

- La interfaz ahora está disponible en alemán, francés, español, portugués brasileño y ruso. QuestTogether sigue el idioma de tu juego, con inglés como alternativa.
- La configuración, los menús, las descripciones emergentes, las comparaciones de misiones y las notas del parche están traducidos. Los nombres de misiones y el texto de progreso recibidos de otros jugadores permanecen en su idioma original.
- Encuentra anuncios de lanzamiento traducidos en los cinco canales de registro de cambios específicos por idioma en nuestro Discord.

### Mantén informado a todo tu grupo

- Una nueva opción Dónde anunciar envía tus anuncios de eventos activados al chat de grupo cuando alguien de tu grupo no ha sido reconocido como usuario de QT. Empieza activada y se puede desactivar en la configuración.
- Esto también funciona en grupos de instancia emparejados. Se excluyen el juego en solitario y las bandas, y nunca se retransmiten los anuncios de otros jugadores.

## 5.13.1

Esta actualización de mantenimiento mejora la recuperación de placas de misión, borra globos y logos de jugador obsoletos, y mantiene el comportamiento consistente de la configuración y la ventana de depuración.

### Placas de misión e indicadores de jugador

- Los íconos de misión y los tintes de salud se recuperan correctamente después de que se cierran las vistas restringidas. Los escaneos de misiones retrasados conservan su tiempo de estabilización, y los datos de descripción emergente que faltan temporalmente mantienen su margen de reintentos.
- Los globos de anuncio se limpian cuando una placa de jugador desaparece o se reutiliza durante el combate. Los marcos protegidos o prohibidos esperan a una limpieza segura.
- Las ubicaciones en el mapa y la presencia de jugadores se recuperan después de desactivar QuestTogether, cambiar de zona y volver a activarlo. Los jugadores que se fueron ya no recuperan un logo de QT por retiradas tardías de ubicación o estado de compañero.

### Correcciones de configuración y ventanas

- La casilla Buscando compañeros para misiones se mantiene sincronizada cuando el estado cambia mediante comandos, menús o configuración de perfil.
- La ventana de depuración finaliza de forma segura los gestos de arrastre y cambio de tamaño interrumpidos cuando se levantan las restricciones, incluso después de haber estado oculta.

### Mejoras de fiabilidad

- Las pruebas reforzadas detectan el acceso a marcos prohibidos incluso cuando un error se captura internamente.
- Las comprobaciones de lanzamiento ahora se niegan a publicar mientras queden cambios de implementación sin confirmar, lo que ayuda a asegurar que las correcciones realmente lleguen a la descarga.

## 5.13.0

Encuentra compañeros para misiones de un vistazo con puntos de mapa y logos de jugador resaltados, configuración de ubicación más sencilla y recordatorios cuando otro jugador tiene una versión estable más nueva de QuestTogether.

### Detecta compañeros para misiones

- Los jugadores que buscan compañeros para misiones tienen un suave brillo dorado alrededor de sus puntos del mapa y minimapa con color de clase.
- Su logo de QuestTogether en la placa de nombre obtiene un suave brillo dorado. Los resaltados desaparecen cuando el estado se desactiva o caduca.
- La configuración de Ubicaciones de jugadores incluye Mostrar solo jugadores que buscan compañeros para misiones. Empieza desactivada y filtra ambos mapas al activarse.
- La ventana de Novedades dentro del juego muestra logos y puntos de mapa normales y brillantes lado a lado. El brillo dorado significa que buscan compañeros para misiones.

### Configuración de ubicación más sencilla

- Compartir mi ubicación y Mostrar otros jugadores se aplican al mapa del mundo y al minimapa.
- Ambas opciones empiezan activadas para los perfiles nuevos. Las exclusiones existentes de compartir ubicación se conservan al actualizar.

### Recordatorios de versión nueva

- QuestTogether detecta cuando otro jugador informa una versión estable más nueva del addon e imprime un recordatorio de actualización en la ventana de chat de QuestTogether que elegiste.
- El recordatorio se guarda entre personajes y aparece una vez en cada recarga hasta que instales la versión detectada o una más nueva. Las versiones alfa y beta no activan recordatorios.
- Los anuncios de versión son pequeños y poco frecuentes. QuestTogether también reconoce información de versión en las respuestas de ping existentes.

## 5.12.0

Encuentra personas con quienes hacer misiones usando el nuevo estado Buscando compañeros para misiones. Esta actualización también mejora la visibilidad de las descripciones emergentes del minimapa y separa el comportamiento del Modo de guerra y los reinos de Retail respecto a Forever.

### Buscando compañeros para misiones

- Haz saber a otros usuarios de QuestTogether que quieres compañía. Tu estado aparece en tu menú de jugador y en las descripciones emergentes de puntos del mapa; no activa compartir ubicación ni envía invitaciones.
- Cambia el estado desde el menú del minimapa, Configuración > Varios o /qt lfg. Usa /qt lfg on, off o status para establecerlo o consultarlo. Empieza desactivado y se guarda por perfil.
- El estado de compañero caduca cuando las actualizaciones se detienen. Los jugadores ignorados se excluyen, y desactivar QuestTogether pausa tu anuncio.

### Retail y Forever

- Forever ya no muestra el Modo de guerra en las descripciones emergentes de puntos de jugador, detalles de ubicación de misión ni salida de ping. Los pings de Forever también omiten las etiquetas de reino mientras conservan los nombres completos de los jugadores.
- Las actualizaciones de misiones cercanas en Forever ya no requieren información del Modo de guerra de Retail. Los puntos del mapa permanecen visibles entre fases para que puedas encontrar personas con quienes formar grupo.
- Retail usa el estado activo del Modo de guerra cuando está disponible. El Modo de guerra desconocido o no compatible ya no se informa como Desactivado.

### Puntos de jugador más estables

- La falta breve de coordenadas ya no elimina tu punto de inmediato. Las últimas posiciones informadas permanecen hasta dos minutos, y los informes más antiguos muestran su antigüedad en la descripción emergente. Las exclusiones de compartir aún se retiran de inmediato cuando la comunicación está disponible.
- Las transmisiones de movimiento están limitadas a una vez cada diez segundos, lo que reduce el tráfico de ubicación. Los latidos estacionarios permanecen cada veinte segundos para que los clientes antiguos sigan siendo compatibles.
- La caché de ubicación ahora conserva hasta 512 jugadores. Cada mapa aún dibuja como máximo 128 puntos visibles, y los jugadores fuera del mapa mostrado ya no consumen ese límite de dibujo.

### Logos de jugador fiables

- Se corrigen los logos que faltaban en las placas de nombre de jugadores amistosos en los clientes actuales de Forever y Retail al leer la configuración actual de visibilidad de jugadores amistosos.
- Los logos ubicados a la izquierda se mueven hacia afuera para dejar espacio a los beneficios visibles, y luego vuelven a su posición habitual cuando los beneficios desaparecen.
- Todos los mensajes compatibles de QuestTogether ahora identifican a su remitente. Una caché limitada recuerda a los jugadores durante la sesión actual de la IU, de modo que los latidos perdidos ya no eliminan sus logos. Las salidas explícitas y los jugadores ignorados aún se borran; no se envían mensajes adicionales.

### Mejoras del minimapa

- La descripción emergente del minimapa de QuestTogether ahora usa una capa de descripción emergente independiente para poder aparecer sobre la IU de la barra de acción. Se oculta cuando el botón deja de estar disponible o comienzan las restricciones.

## 5.11.0

QuestTogether ahora agrega ubicaciones de jugadores, logos en placas de jugador, comparaciones de misiones específicas y comentarios y soporte de Discord más fáciles. La configuración te permite elegir qué compartes y qué ves mientras el progreso de misiones se mantiene coordinado con otros usuarios de QuestTogether.

### Encuentra jugadores de QuestTogether cercanos

- Muestra el logo de pergamino junto a jugadores amistosos de QuestTogether cuando las placas de nombre amistosas de WoW están activadas. Placas de jugador está activado de forma predeterminada, con una posición Izquierda con espacio adicional; elige Izquierda, Derecha, Arriba o Prefijo sin cambiar los colores de la barra de salud.
- Pueden aparecer puntos de jugador con color de clase en el mapa del mundo y el minimapa para los jugadores que comparten su ubicación. Pasa el cursor sobre un punto para ver nombre, facción, raza, clase y nivel; haz clic en él para abrir el menú de jugador de QuestTogether.
- Ubicaciones de jugadores tiene interruptores separados para compartir y ver en el mapa del mundo y el minimapa, y los cuatro empiezan activados. La presencia para los logos en placas de jugador puede continuar incluso cuando ambos interruptores de compartir ubicación están desactivados.
- Las ubicaciones se actualizan periódicamente y desaparecen cuando caducan. Ambos jugadores necesitan el addon actualizado; un punto no garantiza que compartan la misma fase o capa.

### Compara un jugador o todo el grupo

- La acción Comparar misiones del menú de jugador ahora compara solo a ti y al jugador seleccionado, incluidos compañeros de QuestTogether accesibles que no están en tu grupo. La comparación de todo el grupo sigue disponible desde el menú del minimapa, los menús de nombres de misión y /qt compare.
- Compartir misiones y las solicitudes para compartir siguen siendo solo para el grupo. Las comparaciones dirigidas explican cuándo se necesita un grupo para compartir y cuándo el jugador seleccionado necesita QuestTogether para responder.
- Si una solicitud para compartir ya está esperando a otro jugador, la comparación ahora muestra a quién está esperando después de que cambias de objetivo.

### Comentarios y soporte

- La ventana de bienvenida y la página principal de configuración ahora incluyen Discord — Comentarios y soporte. Abre una invitación copiable cuando está disponible, o imprime la invitación en el chat si la ventana de enlace no puede abrirse.

### Correcciones y mejoras

- Los jugadores ignorados ahora se filtran de forma más completa. Se suprimen nuevos registros, globos, puntos, comparaciones y acciones de compartir, mientras que los globos y ubicaciones existentes se borran cuando cambia la lista de ignorados.
- Se corrigieron placas de misión falsas causadas por límites de descripción emergente no disponibles que coincidían con el texto de objetivo de otra misión.
- Desactivar compartir en el mapa o minimapa ahora reintenta la actualización después de fallas temporales de comunicación. Desactivar ambas opciones de compartir también elimina los detalles de ubicación de otras actualizaciones del addon.
- Los logos de jugador se borran correctamente cuando la presencia de un jugador caduca justo antes de que se vaya. Susurrar desde los puntos del mapa abre tu ventana de chat, y cambiar el destino del registro desde Configuración no está disponible durante restricciones.

## 5.10.0

QuestTogether comparte el progreso de misiones con tu grupo y jugadores cercanos. Usa el botón del minimapa para la configuración, comparaciones de misiones del grupo, tu registro de misiones y estas notas más recientes.

### Comparar y compartir misiones del grupo

- Abre Comparar misiones del grupo desde el minimapa o los menús de misiones y jugadores, o escribe /qt compare. Ve quién tiene cada misión y cuánto ha progresado cada uno.
- Todas las misiones del grupo aparecen de forma predeterminada. Marca Ocultar misiones que no tengo para concentrarte en las misiones de tu propio registro.
- Solicita misiones compartibles a los miembros del grupo que usen el addon actualizado. Las solicitudes piden permiso de forma predeterminada; compartir automáticamente es una configuración opcional.
- Las comparaciones se recuperan después de restricciones de mapa o combate. Las actualizaciones reemplazan las respuestas anteriores, y los tiempos de reutilización y fallos de las solicitudes explican cuándo puedes volver a intentarlo.

### Atajos y menús de misiones

- Arrastra el botón con forma de pergamino del minimapa para reposicionarlo. Su menú abre la configuración, comparaciones, el registro de misiones, notas de parche y el control de destino de la ventana de registro. Ocúltalo desde el menú y restáuralo en la configuración de Miscelánea.
- Los menús de nombre de misión ofrecen Estado, Compartir, Abrir en el registro de misiones y Comparar misiones del grupo. Al hacer clic, las acciones de compartir y del registro vuelven a comprobar la misión actual y las restricciones.
- Los enlaces de estado de misión conservan sus títulos intactos después de que una misión sale de tu registro. La casilla de compartir automáticamente ahora sigue la configuración guardada y los cambios de perfil.

### Ayuda y notas más recientes

- Lee la bienvenida y las notas de parche más recientes en su propia ventana en lugar de mensajes de chat repetidos. Elige Notas de parche en el menú del minimapa o en la página principal de Configuración, o usa /qt notes, /qt changelog o /qt patchnotes.
- La ventana de notas se abre automáticamente para actualizaciones mayores y menores. Las actualizaciones de parche aún incluyen notas nuevas sin abrir la ventana automáticamente.
- Usa /qt help para comandos normales y /qt help debug para vistas previas, diagnósticos y comandos de desarrollador.

## 5.9.2

Haz clic izquierdo o derecho en el nombre de una misión en el registro de QuestTogether para abrir su menú, con Estado primero y Compartir segundo. Compartir usa la entrada actual del registro de misiones sin cambiar la misión seleccionada de Blizzard, y no está disponible cuando estás solo, restringido o la misión no se puede compartir. Después de un separador, la opción final mueve los registros de QuestTogether entre la ventana principal y una separada, coincidiendo con el menú de nombre de jugador de QT.

### Cambios en esta versión

- Hace que los nombres de misiones en los mensajes de estado sean clicables, incluidos títulos alternativos de los registros de otros jugadores. Conserva los enlaces de misión existentes al dar formato a comparaciones de misiones completadas para que los detalles de estado no se conviertan en parte de un segundo enlace roto.
- Validación: 521 pruebas pasan en orden normal e inverso en Lua 5.1 y 5.2. Pasan los seis perfiles de API de cliente, las comprobaciones de sintaxis de Lua y shell, la verificación exacta de libchev y las comprobaciones de diferencias. El comportamiento de menús del cliente en vivo, la entrega de misiones compartidas y la validación de contaminación a nivel de motor permanecen por separado.

## 5.9.1

Corrige el seguimiento de misiones, la visibilidad de placas de misión, los anuncios de áreas de tarea, la fiabilidad de la comunicación y las acciones de usuario identificadas en la auditoría integral.

### Cambios en esta versión

- Evita que bloques de misiones de descripciones emergentes no relacionadas tomen prestado texto de objetivos compartidos. Conserva el progreso válido del grupo y recupera las placas después de cambios de mapa, instancia, lista de miembros y misiones.
- Mantiene las misiones recién aceptadas y los escaneos iniciales pendientes hasta que lleguen datos legibles. Conserva hitos de objetivos, clasificación de tareas y estado de ubicación desconocida sin salidas falsas ni entradas duplicadas.
- Mejora los anuncios localizados y las comparaciones de misiones, incluidos límites de carga útil, ritmo, reintentos, cancelación e informes de posibilidad de compartir.
- Respeta los fallos nativos de puntos de ruta sin rastrear un marcador antiguo. Rechaza clics restringidos mientras está desactivado en lugar de perder trabajo en cola.
- Convierte las pruebas de burbujas en vistas previas locales y acepta nombres Forever completos o nombres entre comillas, mientras conserva la identidad exacta del jugador.
- Corrige el manejo de activar/desactivar y perfiles, la apertura del Modo de edición del HUD, emotes de celebración aprobados y diagnósticos.
- Refuerza el aislamiento de pruebas seguras en vivo y la cobertura de regresiones, corrige suposiciones de prueba defectuosas y hace que CI propague fallos de sintaxis de Lua.
- Validación: 516 pruebas pasan en orden normal e inverso en Lua 5.1 y 5.2. Pasan los seis perfiles de API de cliente, comprobaciones de sintaxis, verificación exacta de libchev y comprobaciones de diferencias. El renderizado del cliente en vivo, la entrega entre dos clientes y la validación de contaminación a nivel de motor permanecen por separado.

## 5.9.0

Celebra las subidas de nivel tuyas y de jugadores cercanos de QuestTogether con emotes sincronizados. Agrega interruptores separados para emotes de subida de nivel, activados de forma predeterminada, junto a la configuración de emotes de completar misión en Miscelánea. Las reacciones cercanas respetan las reglas existentes de alcance de jugador y proximidad.

### Cambios en esta versión

- Recuerda la confirmación de completar objetivos de misión por tipo de criatura además de apariciones individuales. Los enemigos que aparecen durante el combate permanecen sin marcar cuando no hay datos de descripción emergente disponibles, incluso si una aparición anterior estaba en caché como necesaria. Los objetivos nuevos sin terminar pueden restaurar el resaltado; los cambios de estado de misión borran la memoria de completado. Los datos parciales o inaccesibles de descripción emergente nunca se tratan como prueba de que todos terminaron.
- Borra los íconos de placas de misión y el tinte de salud inmediatamente cuando se deniega el etiquetado de un enemigo, incluso durante el combate. Escucha cambios de propiedad y vuelve a comprobar el etiquetado en actualizaciones de salud y amenaza.
- Detecta enemigos de misión recién encontrados durante combates normales en el mundo abierto usando datos legibles de descripción emergente de unidad. Actualiza las placas cuando vuelven de detrás de la cámara, se convierten en tu objetivo o pasas el mouse por encima. Reintenta fotogramas retrasados, GUID y líneas de misión de descripción emergente con un presupuesto acotado por unidad, cancela trabajo obsoleto cuando se eliminan unidades y restaura el tinte y el ícono juntos. Conserva las protecciones de mapa, instancia, datos inaccesibles y fotogramas protegidos; el descubrimiento en combate no invoca Questie ni IU oculta de descripciones emergentes.
- Validación: 374 pruebas sin conexión pasan en orden normal e inverso en Lua 5.1 y 5.2. Pasan seis perfiles de API de cliente, comprobaciones de sintaxis de Lua, verificación exacta de bibliotecas y comprobaciones de diferencias. Las regresiones de caché de completado reprodujeron el error antes de la corrección. La jugabilidad en vivo y la validación de contaminación a nivel de motor permanecen por separado.

## 5.8.6

Refuerza nombres de personajes, nombres de clases, títulos de misiones y colores de clase personalizados contra valores de API inaccesibles o mal formados. Valida los datos opcionales de integración con TomTom y Questie antes de usarlos, y deja de leer líneas de descripciones emergentes de Questie al encontrar datos inaccesibles. Normaliza la visibilidad de burbujas y el estado del modo de edición a valores booleanos antes de pasarlos a controles de IU.

### Cambios en esta versión

- Consolida el manejador de eventos de la pantalla de carga, elimina argumentos privados sin usar y una rama de enumeración de restricciones sin usar, y aclara el manejo de callbacks y valores de retorno. Mantiene intactas las alternativas para clientes modernos/antiguos y la revisión exacta de la biblioteca privada.
- Validación: 336 pruebas pasan en orden normal e inverso en Lua 5.1 y 5.2, con comprobaciones ampliadas de adaptadores en seis perfiles de cliente. Las nuevas regresiones fallan contra la implementación anterior. Pasan el análisis de Lua, la verificación exacta de bibliotecas y las comprobaciones de diferencias. Se revisaron los diagnósticos restantes de Ketho WoW API/LuaLS, incluida una pasada separada sin mocks de cliente sin conexión; los hallazgos conservados tienen motivos específicos de compatibilidad, protección, callback, biblioteca o fixture. La validación de jugabilidad en vivo de Retail y Forever permanece por separado.

## 5.8.5

Corrige el descubrimiento de misiones de tarea/mundo en el mapa en clientes modernos leyendo questID desde C_TaskQuest.GetQuestsOnMap, mientras conserva la API antigua y el campo questId para clientes anteriores. Prefiere C_ChatInfo.PerformEmote para que los emotes de completado funcionen cuando los globales obsoletos están desactivados; maneja de forma segura APIs de emotes faltantes o con fallos.

### Cambios en esta versión

- Elimina un cálculo de huella digital de la lista de miembros del grupo sin usar y variables locales sin usar. Extiende las comprobaciones de cliente sin conexión para cubrir APIs modernas y antiguas de tareas/emotes, precedencia de API, datos de misión inaccesibles y APIs faltantes/con fallos. Validación: 334 pruebas pasan en orden normal e inverso en Lua 5.1 y 5.2, además de las comprobaciones de API ampliadas en seis perfiles de cliente, análisis de Lua y verificación exacta de bibliotecas. La validación de jugabilidad en Retail y Forever permanece separada de las comprobaciones sin conexión.

## 5.8.4

Mantenimiento del repositorio: mantiene las notas de desarrollo locales fuera del código fuente rastreado y de los paquetes de lanzamiento. El comportamiento de jugabilidad no cambia.

### Cambios en esta versión

- Mantenimiento del repositorio: mantiene las notas de desarrollo locales fuera del código fuente rastreado y de los paquetes de lanzamiento. El comportamiento de jugabilidad no cambia.

## 5.8.3

Anuncia la versión instalada, los clientes compatibles y el comando de configuración una vez por inicio de sesión o recarga de IU. Incluye enlaces de comentarios específicos del addon en CurseForge y GitHub; al hacer clic en un enlace se abre una ventana de copia de estilo nativo. Comparte el comportamiento de mensajes y la IU de copia segura mediante libchev privada 1.2.0. Si el registro de enlaces o la ventana de copia no están disponibles, muestra la URL completa en el chat. Un asistente de bienvenida no disponible no puede interrumpir el inicio normal del addon.

### Cambios en esta versión

- Validación: 334 pruebas pasan en ambos órdenes en Lua 5.1 y 5.2, con comprobaciones de API de cliente, análisis de Lua y verificación exacta del proveedor de bibliotecas. Las simulaciones rápidas de NoPoizen ejercitan ambos enlaces de comentarios en los siete perfiles de cliente/conjunto de reglas. El renderizado en vivo permanece como una comprobación separada.

## 5.8.2

Aísla las búsquedas de GUID de fixtures de prueba de los jugadores cercanos. Corrige dos fallos falsos en /qt test cuando una unidad real ocupa el token de placa usado por las comprobaciones de descripción emergente e ícono en caché. El comportamiento de placas en el juego no cambia.

### Cambios en esta versión

- El entorno sin conexión ahora incluye esa colisión de tokens y reproduce ambos fallos sin la corrección del fixture. Las 333 pruebas pasan en ambos órdenes en Lua 5.1 y 5.2 después de la corrección; también pasan seis perfiles de API de cliente. La confirmación en el juego permanece por separado.

## 5.8.1

Muestra el marcador de misión de Blizzard junto a QuestTogether en la lista de AddOns en lugar del signo de interrogación predeterminado.

### Cambios en esta versión

- Muestra el marcador de misión de Blizzard junto a QuestTogether en la lista de AddOns en lugar del signo de interrogación predeterminado.

## 5.8.0

Compatibilidad con los clientes Classic actuales mediante cargas correctas de aceptación de misiones, resguardos para API de objetivos, capacidad de compartir desconocida mostrada de forma honesta, metadatos de variante y comprobaciones de regresión de API para seis clientes. Se conserva el comportamiento de Retail/Forever y las utilidades de depuración compartidas.

### Cambios en esta versión

- Validación: 333 pruebas pasan en ambos órdenes en Lua 5.1 y 5.2, con seis perfiles de cliente, análisis de Lua y comprobaciones exactas de proveedor de biblioteca privada. También pasan las pruebas rápidas del cliente NoPoizen y la verificación de paquetes. La validación en vivo de los nuevos adaptadores sigue pendiente.
- Consulta CLIENT_COMPATIBILITY.md para ver la evidencia de origen, el alcance y los límites de validación.

## 5.7.7

Mantiene las consolas de depuración superpuestas y sus controles en un solo grupo de apilamiento nativo mediante la biblioteca privada libchev 1.1.3. Los menús de categorías permanecen con su consola propietaria.

### Cambios en esta versión

- Los íconos de objetivos de misión predeterminados se colocan a la izquierda de la placa de nombre. Las posiciones de íconos guardadas existentes no cambian.
- Respeta la configuración “Mi apellido” de Forever al mostrar el nombre de tu personaje. Mantiene visibles los apellidos de otros jugadores, coincidiendo con el alcance de la configuración nativa. Usa nombres completos de forma coherente para comunicaciones, pertenencia al grupo, coincidencia de placas de nombre y acciones sociales, conservando las claves existentes de perfil y de posición de burbuja personal.
- Corrige los anuncios locales de misión duplicados causados por recibir tu propio mensaje de canal con un formato de nombre completo distinto. La cobertura de regresión prueba el anuncio local seguido de sus ecos de canal y grupo, incluido otro personaje con el mismo nombre.
- Validación: 331 pruebas pasan en ambos órdenes con Lua 5.1/5.2. La confirmación en vivo del nuevo valor predeterminado de ícono y la interacción entre varias ventanas se mantiene aparte.

## 5.7.6

Usa la misma consola de depuración privada libchev 1.1.2 en los tres addons, incluidos filtros de categoría/búsqueda, controles de copia, resultados de pruebas, informes de diagnóstico, marcas de tiempo cuando estén disponibles y un único resumen final de pruebas. Corrige el arte estirado del marco nativo con límites de textura explícitos.

### Cambios en esta versión

- QuestTogether proporciona sus propios diagnósticos de misiones y pruebas aisladas, mientras que la biblioteca compartida se encarga de la consola y del comportamiento genérico de depuración. Ejecuta /qt test, /qt debug o /qt diagnostics.
- Validación: 324 pruebas pasan en ambos órdenes en Lua 5.1/5.2. El usuario confirmó en el juego la apariencia corregida del marco. La validación en vivo de otras restricciones y del gameplay se mantiene aparte.

## 5.7.6-beta.3

QuestTogether 5.7.6-beta.3 actualiza la consola de depuración compartida integrada a libchev 1.1.1.

### Cambios en esta versión

- Restaura la apariencia de ventana nativa estilo WoW en la consola compartida de los addons.
- Elimina la línea duplicada de resumen de pruebas mientras conserva el resumen final en el historial limitado.
- Mantiene el comportamiento común de búsqueda, categoría, copia, desplazamiento, pruebas y diagnósticos, así como los resguardos de restricción existentes.
- El usuario informó que las 324 pruebas de QT pasaron en Forever 1.60.1 build 70009 en beta.2. También se auditaron los siete archivos de prueba cargados en vivo de QT en busca de aritmética inválida; no se encontraron fixtures que generen NaN ni divisiones entre cero. Ese resultado anterior de prueba en vivo no valida este nuevo cambio de apariencia.
- Después de /reload, abre /qtd, ejecuta /qt test y revisa la apariencia de la ventana y el resumen único. El renderizado en vivo y el comportamiento de restricción/taint de esta revisión aún necesitan verificación en el cliente.
- Validación: los 324 casos pasan hacia adelante y en reversa en Lua 5.1.5 y 5.2.4 reales; cada ejecución de CLI emite un resumen, y el ZIP instalable extraído de 26 archivos pasa en ambas versiones. Los 23 archivos Lua se analizan correctamente; las 22 entradas TOC y el manifiesto del proveedor se verifican. Pasan las comprobaciones de formato y diferencias. Biblioteca fijada: 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. No hay CI de GitHub configurado para QT; la CI de la biblioteca upstream pasó.

## 5.7.6-beta.2

QuestTogether 5.7.6-beta.2 reemplaza su ventana de depuración separada por la consola compartida libchev v1.1 usada en todos los addons. La biblioteca integrada está incluida; no se requiere instalación por separado.

### Cambios en esta versión

- Filtrado de categorías compartido, búsqueda difusa/entre comillas, copiar/seleccionar, borrar, recargar, pruebas, diagnósticos y comportamiento de seguimiento del desplazamiento.
- /qt test abre los resultados actuales; las ejecuciones repetidas reemplazan el historial TEST anterior y borran filtros de búsqueda obsoletos.
- /qt diagnostics [questID] y /qt diag [questID] reconstruyen el informe actual en caché en la misma consola, conservando los eventos recientes dentro del presupuesto de exportación compartido.
- Los resguardos compartidos de restricción y de marcos propios reemplazan las antiguas callbacks de consola y la implementación de menú desplegable de QT.
- El estado de misiones, los anuncios, las placas de nombre, las comunicaciones y el aislamiento de pruebas específico de QT siguen siendo propiedad de QuestTogether.
- Esta es una versión beta. El renderizado en vivo en Retail/Forever y el comportamiento de taint aún necesitan verificación. Después de /reload, ejecuta /qt test y /qt diagnostics; luego prueba categoría/búsqueda, copiar, borrar, redimensionar, desplazamiento, ejecuciones repetidas de pruebas y el cambio entre informes y registros. Incluye transiciones de combate/restricción y tu conjunto habitual de addons.
- Validación: 324/324 pruebas pasan en ambos órdenes con Lua 5.1.5 y 5.2.4. Los 23 archivos Lua se analizan correctamente, las 22 entradas TOC se validan y el manifiesto de la biblioteca fijada se verifica. El ZIP instalable se extrajo y pasó los 324 casos usando el arnés sin conexión separado. Biblioteca fijada: 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

QuestTogether 5.7.6-beta.1 integra libchev v1.0.0 para compartir registro, diagnósticos, resguardos de callbacks, mecánicas de trabajo diferido y ejecución de pruebas con los otros addons Together. La biblioteca está incluida; no se necesita instalar un addon por separado.

### Cambios en esta versión

- Los informes de diagnóstico incluyen información común de cliente/addon/biblioteca y conservan los eventos más recientes cuando la ventana de copia se llena.
- El comportamiento de misiones, grupo, placas de nombre y restricciones sigue siendo propiedad de QuestTogether, con almacenes de ejecución aislados por addon.
- Los enlaces de coordenadas siguen siendo utilizables mientras QT está desactivado cuando las restricciones lo permiten; el trabajo en segundo plano en cola permanece pausado y los temporizadores obsoletos se descartan.
- /qt test ahora incluye 315 casos: los 300 existentes, diez comprobaciones de biblioteca compartida y cinco regresiones de integración.
- Validación: las 315 pruebas pasan en ambos órdenes con Lua 5.1.5 y 5.2.4; pasan la sintaxis de Lua, el orden de carga TOC y el manifiesto de revisión/hash integrado. Fuente de libchev integrada: 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- Esta es una versión beta. El renderizado de IU en vivo en Retail/Forever y el comportamiento de taint después de esta extracción aún necesitan verificación. Después de recargar, ejecuta /qt test y /qt diagnostics; luego prueba misiones, burbujas de progreso, placas de nombre y enlaces de coordenadas durante combate, cambio de zona, desactivar/reactivar y recargar con tus addons habituales. La confirmación anterior de 300 pruebas en Retail se aplicaba a v5.7.5.
