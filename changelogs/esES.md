# QuestTogether — Registro de cambios

<!-- Generated from canonical release notes; do not edit by hand. -->

## 6.1.2

Puntos de jugadores cercanos con mejor respuesta y anuncios traducidos más claros.

### Puntos de jugadores en el minimapa

- Se han corregido los puntos de jugadores de QT que faltaban cuando el minimapa no proporciona un ID de mapa. QT ahora usa tu mapa actual cuando sea necesario.

### Actualizaciones de ubicación local más rápidas

- Las actualizaciones de ubicación ahora se realizan una vez por segundo con menos de 10 usuarios de QT conocidos en tu zona, cada 5–10 segundos con 10–19, y cada 15–20 segundos con 100. Los intervalos aumentan gradualmente entre estos niveles; los tiempos con 500 o más no cambian.
- Las actualizaciones rápidas envían ubicaciones compactas y recién muestreadas, mientras que el resto de detalles de los jugadores mantienen su latido más lento. Los límites de tráfico existentes siguen aplicándose, así que la congestión puede retrasar la entrega. Los demás jugadores necesitan esta actualización para enviar posiciones más rápidas.

### Anuncios traducidos más claros

- Las etiquetas de eventos de misión, como Misión aceptada, ahora usan tu idioma incluso cuando no haya disponible un título de misión local o metadatos de traducción opcionales.
- Cuando WoW no puede proporcionar un título de misión local, QT conserva el título legible del remitente. Los mensajes de progreso siguen conservando su texto original cuando no se pueden reconstruir de forma segura.

## 6.1.1

Menús contextuales más claros para jugadores y misiones.

### Limpieza de menús contextuales

- Los menús de nombre de jugador y nombre de misión ya no incluyen el atajo de la ventana de registro. Mueve los registros de QuestTogether entre la ventana principal del chat y una ventana independiente usando el menú del minimapa o los ajustes.

## 6.1.0

Encuentra grupos en el mapa, consulta quién está haciendo misiones en grupo y solicita unirte a través de cualquier miembro del grupo. Las descripciones emergentes de los jugadores ahora muestran los detalles del grupo en primer plano.

### Consulta quién está haciendo misiones en grupo

- Los jugadores agrupados ahora tienen una pequeña insignia de dos personas en sus puntos del mapa y el minimapa. Pasa el cursor sobre un miembro del grupo para resaltar a sus compañeros con un contorno blanco, atenuar los puntos no relacionados y mostrar una corona sobre el líder. Los resplandores dorados de «Buscando compañeros para misiones» siguen siendo visibles.
- Las descripciones emergentes de los jugadores muestran los miembros del grupo con puntos y nombres del color de su clase, con el líder coronado en primer lugar. Los grupos de hasta cinco muestran todos sus miembros; los grupos más grandes solo muestran al líder. Estos detalles también aparecen al pasar el cursor sobre nombres de jugadores en el registro de QuestTogether.
- Tu propio grupo usa la lista del juego. Los detalles de grupos remotos se cargan desde otros usuarios de QuestTogether actualizados cuando hace falta, con resultados en caché y solicitudes espaciadas para mantener bajo el tráfico del canal. Los clientes antiguos conservan sus puntos normales y la información básica del tamaño del grupo; los detalles completos de grupos remotos requieren que el otro usuario esté actualizado.

### Las solicitudes para unirse pueden llegar al líder del grupo

- Puedes solicitar unirte a través de un miembro del grupo que no pueda invitarte. Si su líder usa QuestTogether y está disponible para invitar, la solicitud se redirige al líder usando los ajustes habituales de confirmación y aprobación automática.
- Si no se sabe si el líder usa QuestTogether, el miembro puede anunciar “[QT] PlayerName solicita unirse al grupo.” en el chat de grupo cuando los anuncios en el chat de grupo estén activados. Entonces alguien con permiso para invitar deberá invitarte manualmente.
- El solicitante y el miembro que reenvía la solicitud necesitan esta actualización para las solicitudes redirigidas. Se siguen aplicando las comprobaciones existentes de grupo completo, restricciones, ignorados, caducidad y frecuencia de solicitudes.

### Descripciones emergentes de jugadores más claras

- La información del grupo ahora aparece justo debajo de la línea de nivel, raza y clase, con filas de miembros compactas y espacio entre secciones. Las insignias de la Alianza y la Horda son el doble de grandes.
- La versión del addon aparece al final con el formato más corto vX.Y.Z. Cuando se muestra la antigüedad de una ubicación, Última actualización aparece justo encima de la versión.
- Se han eliminado los recuentos de misiones seguidas de las descripciones emergentes de jugadores y del botón del minimapa. Se sigue mostrando el título de la misión activa de los jugadores que buscan compañeros para misiones.

## 6.0.2

Explora las actualizaciones anteriores de QuestTogether en tu idioma, con mejor recuperación de nombres de misiones para los anuncios de finalización.

### Ver notas del parche anteriores

- La ventana de bienvenida ahora tiene botones Anteriores y Siguientes, un acceso directo a la última versión y un selector de historial que muestra las versiones y fechas de lanzamiento. Al abrir las notas del parche, se empieza en la versión más reciente.
- El historial incluye todas las versiones publicadas anteriormente, incluidas las primeras betas. Todas las notas históricas están traducidas a todos los idiomas de WoW compatibles y se incluyen en los registros de cambios correspondientes del repositorio.
- Los botones de navegación se desactivan cuando no hay adónde ir. Ver notas más antiguas no cambia qué actualización has reconocido; las ventanas emergentes automáticas siguen apareciendo solo para actualizaciones mayores y menores. Abre la ventana en cualquier momento con /qt notes.

### Títulos al completar misiones

- Cuando una misión desaparece de tu registro antes de que QuestTogether tenga un título utilizable, los anuncios de finalización ahora intentan usar la búsqueda de títulos de misión disponible en el juego antes de recurrir a un ID de misión. El título recuperado se conserva independientemente del orden de los eventos de entrega y eliminación.
- Los anuncios siguen usando el texto del remitente cuando tu cliente no puede resolver un título local. Si ningún cliente tiene un nombre disponible, el ID de misión sigue siendo la alternativa. La recuperación mejorada en el lado del remitente se aplica cuando el remitente actualiza.

## 6.0.1

Las celebraciones ahora permanecen con los jugadores que realmente puedes ver cerca.

### Correcciones de celebraciones cercanas

- Las reacciones a que otro jugador complete una misión o suba de nivel ahora requieren una unidad de jugador coincidente y visible. Las coordenadas del mapa o solo un nombre ya no activan un gesto, incluso cuando devlogall está activado.
- Los gestos entrantes deben coincidir con la propia lista de celebraciones de QuestTogether. Los gestos no incluidos en la lista, incluidos mountspecial y los vítores de facción, se ignoran sin elegir un sustituto.
- Tus propias celebraciones por completar misiones y subir de nivel mantienen su comportamiento y ajustes actuales.

## 6.0.0

QuestTogether 6.0 se prepara para el lanzamiento de Forever con un sistema de comunicación diseñado para reducir el tráfico en segundo plano a medida que crece la comunidad.

### Actividad local, descubrimiento mundial

- Los anuncios de misiones y las actualizaciones frecuentes de jugadores ahora usan canales de zona. Los anuncios de grupo siguen llegando a tu grupo aunque crucéis límites de zona.
- Los puntos de jugadores siguen estando disponibles por todo el mundo, con actualizaciones en segundo plano más lentas. Al abrir otra zona en el mapa del mundo, te suscribes temporalmente a sus actualizaciones.
- El chat de texto de QT permanece en el canal global de QuestTogether. Tu ajuste de chat Global o Solo zona sigue controlando qué mensajes ves.

### Menos tráfico en segundo plano

- La presencia, la versión, los recuentos de misiones, el estado del compañero y la ubicación se agrupan en actualizaciones compactas. Las zonas abarrotadas se actualizan con menos frecuencia para reducir el tráfico.
- Los anuncios se dosifican y tienen prioridad sobre las actualizaciones en segundo plano. Las respuestas a ping se reparten para evitar una ráfaga de respuestas. WoW aún puede retrasar la entrega por canal; esta actualización no garantiza mensajes instantáneos.
- Las descripciones emergentes de jugadores muestran la antigüedad de las ubicaciones antiguas. El diagnóstico ahora informa de recuentos de mensajes, limitación y retrasos de anuncios comunicados por el remitente.

### Una actualización importante durante la beta

- Estamos realizando ahora este cambio de comunicación más grande de cara al lanzamiento de Forever. La beta es el mejor momento para tomar estas decisiones fundamentales, antes de que más jugadores dependan del comportamiento anterior.
- La versión 6.0 abandona QuestTogetherAnnounce1 y ya no envía ni recibe en ese canal obsoleto. Usa QuestTogether para el chat y el descubrimiento globales, además de canales de zona para la actividad local.
- QuestTogether mantiene sus canales después de tus otros canales de chat, con el canal principal de chat antes que sus canales de zona. Se conservan tus preferencias de compartir ubicación, lista de ignorados y anuncios.

### Compatibilidad con versiones anteriores

- Actualizad todos a la vez. Las versiones anteriores no pueden leer las nuevas actualizaciones de jugadores agrupadas ni escuchar los nuevos canales de zona, así que los jugadores con versiones mezcladas pueden perderse puntos del mapa, el estado del compañero y anuncios de misiones cercanas.
- Los jugadores que solo usan el canal obsoleto ya no son detectables a través de ese canal en 6.0. Algunos intercambios con versiones 5.x más recientes todavía pueden funcionar a través del canal global compartido o de un grupo, pero esto es compatibilidad parcial, no la experiencia completa.
- El /qt ping manual sigue usando el canal global. Puede oír allí a clientes antiguos compatibles, pero es una herramienta de descubrimiento orientativa, no un recuento completo de todos los que usan QuestTogether.

## 5.17.2

El chat de QT es más fácil de distinguir de los anuncios de misiones.

### Texto blanco en el chat de QT

- Los mensajes de los jugadores en el chat de QT ahora usan texto blanco en el registro de chat y en los bocadillos sobre la cabeza.
- Los nombres de los jugadores conservan los colores de su clase, y los anuncios de misiones conservan su texto amarillo.

## 5.17.1

Consulta más información sobre tus compañeros de misiones y comprueba el estado de las misiones directamente desde los tooltips del chat.

### Tooltips de jugador más útiles

- Los tooltips de nombres de jugador y puntos del mapa ahora muestran cuántas misiones está monitorizando QuestTogether, además de Solo o Grupo de N. Tu propio tooltip usa tu estado local actual.
- El tooltip del minimapa ahora cuenta las misiones monitorizadas por QuestTogether, coincidiendo con el anuncio de inicio en lugar de contar solo las misiones seguidas en el seguimiento de WoW.
- Los recuentos de misiones remotas y los tamaños de grupo requieren un par actualizado. Se actualizan aproximadamente cada 80 segundos mediante los mensajes de latido existentes, sin mensajes adicionales; los informes ausentes o desactualizados se muestran como desconocidos. Las versiones anteriores siguen recibiendo anuncios de versión compatibles.

### Estado de la misión al pasar el cursor

- Pasa el cursor sobre el nombre de una misión en los registros de QT para ver el estado de tu misión, si se puede compartir, el ID de misión y el progreso de objetivos seguidos localmente en un tooltip junto al cursor.
- Se ha eliminado el elemento de menú Estado. Al hacer clic en el nombre de una misión, se siguen abriendo Compartir, Abrir en el registro de misiones, Comparar misiones de grupo y la acción de destino de la ventana de registro.
- Las nuevas etiquetas de tooltip están traducidas a todos los idiomas compatibles. Los detalles de misión reflejan tu propio progreso, no la fase de misión del remitente.

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

## 5.13.1

Esta actualización de mantenimiento mejora la recuperación de las placas de misión, elimina burbujas y logotipos de jugadores obsoletos, y mantiene los ajustes y la ventana de depuración funcionando de forma coherente.

### Placas de misión e indicadores de jugadores

- Los iconos de misión y los tintes de salud se recuperan correctamente al cerrarse las vistas restringidas. Los escaneos de misiones retrasados conservan su tiempo de asentamiento, y los datos de descripción emergente que falten temporalmente mantienen su margen de reintentos.
- Las burbujas de anuncio se limpian cuando la placa de un jugador desaparece o se reutiliza durante el combate. Los marcos protegidos o prohibidos esperan a una limpieza segura.
- Las ubicaciones del mapa y la presencia de jugadores se recuperan tras desactivar QuestTogether, cambiar de zona y volver a activarlo. Los jugadores que se han marchado ya no vuelven a recibir un logotipo de QT por retiradas tardías de ubicación o estado de compañero.

### Correcciones de ajustes y ventanas

- La casilla Buscando compañeros para misiones permanece sincronizada cuando el estado cambia mediante comandos, menús o ajustes de perfil.
- La ventana de depuración finaliza de forma segura los gestos de arrastrar y redimensionar interrumpidos cuando se levantan las restricciones, incluso después de haberse ocultado.

### Mejoras de fiabilidad

- Las pruebas reforzadas detectan accesos a marcos prohibidos incluso cuando un error se captura internamente.
- Las comprobaciones de lanzamiento ahora se niegan a publicar mientras queden cambios de implementación sin confirmar, lo que ayuda a garantizar que las correcciones lleguen realmente a la descarga.

## 5.13.0

Encuentra compañeros para misiones de un vistazo con puntos del mapa y logotipos de jugadores resaltados, ajustes de ubicación más sencillos y recordatorios cuando otro jugador tenga una versión estable más reciente de QuestTogether.

### Encuentra compañeros para misiones

- Los jugadores que buscan compañeros para misiones tienen un suave resplandor dorado alrededor de sus puntos del mapa y el minimapa, coloreados por clase.
- Su logotipo de QuestTogether en la placa de nombre recibe un suave resplandor dorado. Los resaltados desaparecen cuando el estado se desactiva o caduca.
- Los ajustes de Ubicaciones de jugadores incluyen Mostrar solo jugadores que buscan compañeros para misiones. Empieza desactivado y, al activarlo, filtra ambos mapas.
- La ventana Novedades del juego muestra logotipos y puntos de mapa normales y con resplandor uno junto a otro. El resplandor dorado significa que se buscan compañeros para misiones.

### Ajustes de ubicación más sencillos

- Compartir mi ubicación y Mostrar otros jugadores se aplican tanto al mapa del mundo como al minimapa.
- Ambas opciones empiezan activadas en los perfiles nuevos. Las exclusiones existentes de compartir ubicación se conservan al actualizar.

### Recordatorios de nueva versión

- QuestTogether detecta cuando otro jugador informa de una versión estable más reciente del addon y muestra un recordatorio de actualización en la ventana de chat de QuestTogether que hayas elegido.
- El recordatorio se guarda entre personajes y aparece una vez en cada recarga hasta que instales la versión detectada o una más reciente. Las versiones alfa y beta no activan recordatorios.
- Los anuncios de versión son pequeños y poco frecuentes. QuestTogether también reconoce información de versión en respuestas de ping existentes.

## 5.12.0

Encuentra gente con la que hacer misiones usando el nuevo estado Buscando compañeros para misiones. Esta actualización también mejora la visibilidad de las descripciones emergentes del minimapa y separa el comportamiento del Modo de guerra y el reino de Retail del de Forever.

### Buscando compañeros para misiones

- Haz saber a otros usuarios de QuestTogether que quieres compañía. Tu estado aparece en tu menú de jugador y en las descripciones emergentes de los puntos del mapa; no activa el uso compartido de ubicación ni envía invitaciones.
- Activa o desactiva el estado desde el menú del minimapa, Ajustes > Varios o /qt lfg. Usa /qt lfg on, off o status para configurarlo o consultarlo. Empieza desactivado y se guarda por perfil.
- El estado de compañero caduca cuando dejan de recibirse actualizaciones. Los jugadores ignorados quedan excluidos, y desactivar QuestTogether pausa tu anuncio.

### Retail y Forever

- Forever ya no muestra el Modo de guerra en las descripciones emergentes de los puntos de jugadores, en los detalles de ubicación de misiones ni en la salida de ping. Los pings de Forever también omiten las etiquetas de reino, conservando los nombres completos de los jugadores.
- Las actualizaciones de misiones cercanas en Forever ya no requieren información del Modo de guerra de Retail. Los puntos del mapa siguen visibles entre fases para que puedas encontrar gente con la que formar grupo.
- Retail usa el estado activo del Modo de guerra cuando está disponible. El Modo de guerra desconocido o no admitido ya no se informa como Desactivado.

### Puntos de jugadores más estables

- La falta breve de coordenadas ya no elimina tu punto de inmediato. Las últimas posiciones comunicadas se mantienen hasta dos minutos, y los informes más antiguos muestran su antigüedad en la descripción emergente. Las exclusiones de compartir ubicación siguen retirándose de inmediato cuando hay comunicación disponible.
- Las emisiones de movimiento están limitadas a una vez cada diez segundos, lo que reduce el tráfico de ubicación. Los latidos estacionarios permanecen cada veinte segundos para que los clientes antiguos sigan siendo compatibles.
- La caché de ubicaciones ahora conserva hasta 512 jugadores. Cada mapa sigue dibujando como máximo 128 puntos visibles, y los jugadores fuera del mapa mostrado ya no consumen ese límite de dibujo.

### Logotipos de jugadores fiables

- Corrige logotipos ausentes en las placas de nombre de jugadores amistosos en los clientes actuales de Forever y Retail leyendo el ajuste actual de visibilidad de jugadores amistosos.
- Los logotipos colocados a la izquierda se desplazan hacia fuera para dejar sitio a beneficios visibles, y vuelven a su posición habitual cuando los beneficios desaparecen.
- Todos los mensajes admitidos de QuestTogether ahora identifican a su remitente. Una caché limitada recuerda a los jugadores durante la sesión actual de la IU, de modo que los latidos perdidos ya no eliminan sus logotipos. Las salidas explícitas y los jugadores ignorados se siguen borrando; no se envían mensajes adicionales.

### Pulido del minimapa

- La descripción emergente del minimapa de QuestTogether ahora usa una capa de descripción emergente independiente para que pueda aparecer sobre la IU de la barra de acción. Se oculta cuando el botón deja de estar disponible o comienzan las restricciones.

## 5.11.0

QuestTogether ahora añade ubicaciones de jugadores, logotipos en placas de jugadores, comparaciones de misiones centradas y formas más sencillas de enviar comentarios y recibir asistencia en Discord. Los ajustes te permiten elegir qué compartes y qué ves mientras el progreso de las misiones se mantiene coordinado con otros usuarios de QuestTogether.

### Encuentra jugadores de QuestTogether cerca

- Muestra el logotipo del pergamino junto a jugadores amistosos de QuestTogether cuando las placas de nombre amistosas de WoW están activadas. Las placas de jugadores están activadas por defecto, con una posición izquierda con margen; elige Izquierda, Derecha, Arriba o Prefijo sin cambiar los colores de la barra de salud.
- Pueden aparecer puntos de jugadores coloreados por clase en el mapa del mundo y el minimapa para los jugadores que comparten su ubicación. Pasa el cursor sobre un punto para ver nombre, facción, raza, clase y nivel; haz clic en él para abrir el menú de jugador de QuestTogether.
- Ubicaciones de jugadores tiene interruptores separados para compartir y ver en el mapa del mundo y el minimapa, y los cuatro empiezan activados. La presencia para los logotipos de placas de jugadores puede continuar aunque ambos interruptores de compartir ubicación estén desactivados.
- Las ubicaciones se actualizan periódicamente y desaparecen cuando caducan. Ambos jugadores necesitan el addon actualizado; un punto no garantiza que compartáis la misma fase o capa.

### Compara un jugador o todo el grupo

- La acción Comparar misiones del menú de jugador ahora compara solo a ti y al jugador seleccionado, incluidos compañeros de QuestTogether alcanzables que no estén en el grupo. La comparación de todo el grupo sigue disponible desde el menú del minimapa, los menús de nombres de misión y /qt compare.
- Compartir misiones y las solicitudes para compartir siguen siendo solo para el grupo. Las comparaciones dirigidas explican cuándo se necesita un grupo para compartir y cuándo el jugador seleccionado necesita QuestTogether para responder.
- Si una solicitud para compartir ya está esperando a otro jugador, la comparación ahora muestra a quién está esperando después de que cambies de objetivo.

### Comentarios y asistencia

- La ventana de bienvenida y la página principal de ajustes ahora incluyen Discord — comentarios y asistencia. Abre una invitación copiable cuando está disponible, o imprime la invitación en el chat si no se puede abrir la ventana del enlace.

### Correcciones y pulido

- Los jugadores ignorados ahora se filtran de forma más completa. Se suprimen nuevos registros, burbujas, puntos, comparaciones y acciones de compartir, mientras que las burbujas y ubicaciones existentes se eliminan cuando cambia la lista de ignorados.
- Se han corregido falsas placas de misión causadas por límites de descripción emergente no disponibles que coincidían con el texto de objetivo de otra misión.
- Desactivar compartir en el mapa o minimapa ahora reintenta la actualización tras fallos temporales de comunicación. Desactivar ambas opciones de compartir también elimina los detalles de ubicación de otras actualizaciones del addon.
- Los logotipos de jugadores se eliminan correctamente cuando la presencia de un jugador caduca justo antes de que se vaya. Susurrar desde los puntos del mapa abre tu ventana de chat, y cambiar el destino del registro desde Ajustes no está disponible durante las restricciones.

## 5.10.0

QuestTogether comparte el progreso de las misiones con tu grupo y con jugadores cercanos. Usa el botón del minimapa para ver ajustes, comparaciones de misiones de grupo, tu registro de misiones y estas últimas notas.

### Compara y comparte misiones de grupo

- Abre Comparar misiones de grupo desde el minimapa o los menús de misiones y jugadores, o escribe /qt compare. Mira quién tiene cada misión y cuánto ha progresado cada uno.
- Todas las misiones de grupo aparecen por defecto. Marca Ocultar misiones que no tengo para centrarte en las misiones de tu propio registro.
- Solicita misiones compartibles a miembros del grupo que usen el addon actualizado. Las solicitudes piden permiso por defecto; compartir automáticamente es un ajuste opcional.
- Las comparaciones se recuperan tras restricciones de mapa o combate. Las actualizaciones sustituyen a respuestas anteriores, y los tiempos de reutilización y fallos de solicitudes explican cuándo puedes volver a intentarlo.

### Atajos y menús de misiones

- Arrastra el botón del minimapa con forma de pergamino para recolocarlo. Su menú abre ajustes, comparaciones, el registro de misiones, notas de parche y el control de destino de la ventana de registro. Ocúltalo desde el menú y restáuralo en los ajustes de Varios.
- Los menús de nombres de misión ofrecen Estado, Compartir, Abrir en el registro de misiones y Comparar misiones de grupo. Las acciones de compartir y de registro vuelven a comprobar la misión actual y las restricciones al hacer clic.
- Los enlaces de estado de misión mantienen sus títulos intactos después de que una misión salga de tu registro. La casilla de compartir automáticamente ahora sigue los ajustes guardados y los cambios de perfil.

### Ayuda y últimas notas

- Lee la bienvenida y las últimas notas de parche en su propia ventana en lugar de mensajes de chat repetidos. Elige Notas de parche en el menú del minimapa o en la página principal de Ajustes, o usa /qt notes, /qt changelog o /qt patchnotes.
- La ventana de notas se abre automáticamente para actualizaciones mayores y menores. Las actualizaciones de parche siguen incluyendo notas nuevas sin abrir la ventana automáticamente.
- Usa /qt help para comandos normales y /qt help debug para vistas previas, diagnósticos y comandos de desarrollador.

## 5.9.2

Haz clic izquierdo o derecho en el nombre de una misión en el registro de QuestTogether para abrir su menú, con Estado primero y Compartir segundo. Compartir usa la entrada actual del registro de misiones sin cambiar la misión seleccionada por Blizzard, y no está disponible cuando juegas en solitario, está restringida o la misión no se puede compartir. Tras un separador, la opción final mueve los registros de QuestTogether entre la ventana principal y la separada, coincidiendo con el menú de nombre de jugador de QT.

### Cambios de esta versión

- Haz que los nombres de misión en los mensajes de estado sean clicables, incluidos los títulos de respaldo de los registros de otros jugadores. Conserva los enlaces de misión existentes al formatear comparaciones de misiones completadas para que los detalles de estado no pasen a formar parte de un segundo enlace roto.
- Validación: 521 pruebas superadas en orden normal e inverso en Lua 5.1 y 5.2. Los seis perfiles de API de cliente, las comprobaciones de sintaxis de Lua y shell, la verificación exacta de libchev y las comprobaciones de diff pasan. El comportamiento de menús en el cliente en vivo, la entrega de compartir misión y la validación de taint a nivel de motor siguen siendo independientes.

## 5.9.1

Corrige el seguimiento de misiones, la visibilidad de placas de misión, los anuncios de áreas de tarea, la fiabilidad de la comunicación y las acciones de usuario identificadas en la auditoría exhaustiva.

### Cambios de esta versión

- Evita que bloques de misión de tooltip no relacionados tomen prestado texto de objetivo compartido. Conserva el progreso válido del grupo y recupera placas tras cambios de mapa, estancia, lista de miembros y misiones.
- Mantén las misiones recién aceptadas y los escaneos iniciales pendientes hasta que lleguen datos legibles. Conserva los hitos de objetivos, la clasificación de tareas y el estado de ubicación desconocida sin salidas falsas ni entradas duplicadas.
- Mejora los anuncios localizados y las comparaciones de misiones, incluidos los límites de carga útil, el ritmo, los reintentos, la cancelación y el informe de si se puede compartir.
- Respeta los fallos nativos de puntos de ruta sin seguir un marcador antiguo. Rechaza los clics restringidos mientras esté desactivado en lugar de perder trabajo en cola.
- Convierte las pruebas de burbujas en vistas previas locales y acepta nombres completos de Forever o nombres entrecomillados, conservando la identidad exacta del jugador.
- Corrige el manejo de activar/desactivar y perfiles, la apertura del Modo edición del HUD, los gestos de celebración aprobados y los diagnósticos.
- Refuerza el aislamiento de pruebas seguro para cliente en vivo y la cobertura de regresiones, corrige suposiciones de prueba erróneas y hace que CI propague los fallos de sintaxis de Lua.
- Validación: 516 pruebas superadas en orden normal e inverso en Lua 5.1 y 5.2. Los seis perfiles de API de cliente, las comprobaciones de sintaxis, la verificación exacta de libchev y las comprobaciones de diff pasan. El renderizado en cliente en vivo, la entrega entre dos clientes y la validación de taint a nivel de motor siguen siendo independientes.

## 5.9.0

Celebra tus subidas de nivel y las de jugadores de QuestTogether cercanos con gestos sincronizados. Añade opciones independientes de gesto de subida de nivel, activadas por defecto, junto a los ajustes de gesto de completar misión en Miscelánea. Las reacciones cercanas respetan las reglas existentes de alcance de jugadores y proximidad.

### Cambios de esta versión

- Recuerda la finalización confirmada de objetivos de misión por tipo de criatura además de por aparición individual. Los enemigos que aparecen durante el combate permanecen sin marcar cuando los datos del tooltip no están disponibles, aunque una aparición anterior estuviera en caché como necesaria. Los objetivos recientes sin terminar pueden restaurar el resaltado; los cambios de estado de la misión borran la memoria de finalización. Los datos parciales o inaccesibles del tooltip nunca se tratan como prueba de que todos hayan terminado.
- Borra los iconos de misión de las placas de nombre y el tinte de salud de inmediato cuando se deniegue el derecho sobre un enemigo, incluso durante el combate. Escucha cambios de propiedad y vuelve a comprobar los derechos en actualizaciones de salud y amenaza.
- Detecta enemigos de misión recién encontrados durante el combate normal en mundo abierto usando datos legibles del tooltip de unidad. Actualiza las placas cuando vuelven de detrás de la cámara, pasan a ser tu objetivo o se pasa el ratón por encima. Reintenta fotogramas retrasados, GUID y líneas de misión del tooltip con un presupuesto acotado por unidad, cancela el trabajo obsoleto cuando se eliminan unidades y restaura el tinte y el icono juntos. Conserva las protecciones de mapa, estancia, datos inaccesibles y marcos protegidos; el descubrimiento en combate no invoca Questie ni la IU de tooltip oculta.
- Validación: 374 pruebas sin conexión superadas en orden normal e inverso en Lua 5.1 y 5.2. Seis perfiles de API de cliente, comprobaciones de sintaxis de Lua, verificación exacta de bibliotecas y comprobaciones de diff pasan. Las regresiones de la caché de finalización reprodujeron el error antes de la corrección. El juego en vivo y la validación de taint a nivel de motor siguen siendo independientes.

## 5.8.6

Protege nombres de personaje, nombres de clase, títulos de misión y colores de clase personalizados frente a valores de API inaccesibles o mal formados. Valida los datos opcionales de integración con TomTom y Questie antes de usarlos, y deja de leer las líneas de tooltip de Questie ante datos inaccesibles. Normaliza la visibilidad de burbujas y el estado del modo edición a booleanos antes de pasarlos a controles de IU.

### Cambios de esta versión

- Consolida el manejador de evento de pantalla de carga, elimina argumentos privados sin usar y una rama de enumeración de restricción sin usar, y aclara el manejo de callbacks y valores de retorno. Mantén intactas las alternativas para clientes modernos/antiguos y la revisión exacta de la biblioteca privada.
- Validación: 336 pruebas superadas en orden normal e inverso en Lua 5.1 y 5.2, con comprobaciones ampliadas de adaptadores en seis perfiles de cliente. Las nuevas regresiones fallan frente a la implementación anterior. El análisis de Lua, la verificación exacta de bibliotecas y las comprobaciones de diff pasan. Revisados los diagnósticos restantes de Ketho WoW API/LuaLS, incluida una pasada separada sin mocks de cliente sin conexión; los hallazgos conservados tienen motivos específicos de compatibilidad, protección, callback, biblioteca o fixture. La validación de juego en vivo en Retail y Forever sigue siendo independiente.

## 5.8.5

Corrige el descubrimiento de tareas/misiones del mundo en el mapa en clientes modernos leyendo questID de C_TaskQuest.GetQuestsOnMap, mientras conserva la API antigua y el campo questId para clientes antiguos. Prefiere C_ChatInfo.PerformEmote para que los gestos de finalización funcionen cuando los globales obsoletos están desactivados; maneja de forma segura API de gestos ausentes o fallidas.

### Cambios de esta versión

- Elimina un cálculo de huella de lista de grupo sin usar y variables locales sin usar. Amplía las comprobaciones de cliente sin conexión para cubrir API modernas y antiguas de tareas/gestos, precedencia de API, datos de misión inaccesibles y API ausentes/fallidas. Validación: 334 pruebas superadas en orden normal e inverso en Lua 5.1 y 5.2, además de las comprobaciones de API ampliadas en seis perfiles de cliente, análisis de Lua y verificación exacta de bibliotecas. La validación de juego en Retail y Forever sigue siendo independiente de las comprobaciones sin conexión.

## 5.8.4

Mantenimiento del repositorio: mantén las notas de desarrollo locales fuera del código fuente con seguimiento y de los paquetes de lanzamiento. El comportamiento de juego no cambia.

### Cambios de esta versión

- Mantenimiento del repositorio: mantén las notas de desarrollo locales fuera del código fuente con seguimiento y de los paquetes de lanzamiento. El comportamiento de juego no cambia.

## 5.8.3

Anuncia la versión instalada, los clientes compatibles y el comando de ajustes una vez por inicio de sesión o recarga de IU. Incluye enlaces de comentarios específicos del addon para CurseForge y GitHub; al hacer clic en un enlace se abre una ventana de copia de estilo nativo. Comparte el comportamiento de mensajes y la IU de copia segura mediante libchev 1.2.0 privada. Si el registro de enlaces o la ventana de copia no están disponibles, muestra la URL completa en el chat. Un asistente de bienvenida no disponible no puede interrumpir el inicio normal del addon.

### Cambios de esta versión

- Validación: 334 pruebas superadas en ambos órdenes en Lua 5.1 y 5.2, con comprobaciones de API de cliente, análisis de Lua y verificación exacta del proveedor de bibliotecas. Las simulaciones de humo de NoPoizen ejercitan ambos enlaces de comentarios en los siete perfiles de cliente/conjunto de reglas. El renderizado en vivo sigue siendo una comprobación independiente.

## 5.8.2

Aísla las búsquedas de GUID de fixtures de prueba de los jugadores cercanos. Corrige dos fallos falsos en /qt test cuando una unidad real ocupa el token de placa de nombre usado por las comprobaciones de tooltip e icono en caché. El comportamiento de placas de nombre en el juego no cambia.

### Cambios de esta versión

- El entorno sin conexión ahora incluye esa colisión de token y reproduce ambos fallos sin la corrección del fixture. Las 333 pruebas pasan en ambos órdenes en Lua 5.1 y 5.2 tras la corrección; seis perfiles de API de cliente también pasan. La confirmación dentro del juego sigue siendo independiente.

## 5.8.1

Muestra el marcador de misión de Blizzard junto a QuestTogether en la lista de AddOns en lugar del signo de interrogación predeterminado.

### Cambios de esta versión

- Muestra el marcador de misión de Blizzard junto a QuestTogether en la lista de AddOns en lugar del signo de interrogación predeterminado.

## 5.8.0

Admite los clientes actuales de Classic con cargas útiles correctas de aceptación de misiones, alternativas protegidas de API de objetivos, indicación honesta de compartibilidad desconocida, metadatos de estilo y comprobaciones de regresión de API de seis clientes. Conserva el comportamiento de Retail/Forever y las utilidades de depuración compartidas.

### Cambios de esta versión

- Validación: 333 pruebas superadas en ambos órdenes en Lua 5.1 y 5.2, con seis perfiles de cliente, análisis de Lua y comprobaciones exactas de proveedor de bibliotecas privadas. Las comprobaciones de humo del cliente NoPoizen y la verificación de paquetes también pasan. La validación en vivo de los nuevos adaptadores sigue pendiente.
- Consulta CLIENT_COMPATIBILITY.md para ver las pruebas de origen, el alcance y los límites de validación.

## 5.7.7

Mantén las consolas de depuración solapadas y sus controles en un único grupo de apilamiento nativo mediante libchev 1.1.3 privada. Los menús de categoría permanecen con su consola propietaria.

### Cambios de esta versión

- Coloca por defecto los iconos de objetivo de misión a la izquierda de la placa de nombre. Las posiciones de icono guardadas existentes no cambian.
- Respeta el ajuste “My Last Name” de Forever al mostrar el nombre de tu personaje. Mantén visibles los apellidos de otros jugadores, coincidiendo con el alcance del ajuste nativo. Usa nombres completos de forma coherente para comunicaciones, pertenencia a grupo, coincidencia de placas de nombre y acciones sociales, conservando las claves existentes de perfil y de posición de burbuja personal.
- Corrige anuncios locales de misión duplicados causados por recibir tu propio mensaje de canal con un formato de nombre completo diferente. La cobertura de regresión ejercita el anuncio local seguido de sus ecos de canal y grupo, incluido otro personaje con el mismo nombre de pila.
- Validación: 331 pruebas superadas en ambos órdenes bajo Lua 5.1/5.2. La confirmación en vivo del nuevo valor predeterminado de iconos y la interacción multiventana sigue siendo independiente.

## 5.7.6

Usa la misma consola de depuración privada de libchev 1.1.2 en los tres addons, incluidos filtros de categoría/búsqueda, controles de copia, resultados de pruebas, informes de diagnóstico, marcas de tiempo cuando estén disponibles y un único resumen final de pruebas. Corrige los gráficos estirados del marco nativo con límites de textura explícitos.

### Cambios en esta versión

- QuestTogether proporciona sus propios diagnósticos de misiones y pruebas aisladas, mientras que la biblioteca compartida se encarga de la consola y del comportamiento genérico de depuración. Ejecuta /qt test, /qt debug o /qt diagnostics.
- Validación: 324 pruebas superadas en ambos órdenes en Lua 5.1/5.2. El usuario confirmó en el juego el aspecto corregido del marco. La validación de otras restricciones en vivo y de jugabilidad sigue siendo independiente.

## 5.7.6-beta.3

QuestTogether 5.7.6-beta.3 actualiza la consola de depuración compartida integrada a libchev 1.1.1.

### Cambios en esta versión

- Restaura el aspecto de ventana nativo de estilo WoW en la consola compartida de los addons.
- Elimina la línea duplicada del resumen de pruebas mientras conserva el resumen final en el historial acotado.
- Mantiene la búsqueda común, categoría, copia, desplazamiento, pruebas, diagnóstico y comportamiento existentes de guardas de restricción.
- El usuario informó de que las 324 pruebas de QT se superaban en Forever 1.60.1 build 70009 en beta.2. Los siete archivos de prueba cargados en vivo de QT también fueron auditados en busca de aritmética no válida; no se encontraron casos de generación de NaN ni de división por cero. Ese resultado anterior de prueba en vivo no valida este nuevo cambio de apariencia.
- Tras /reload, abre /qtd, ejecuta /qt test y comprueba el aspecto de la ventana y el resumen único. El renderizado en vivo y el comportamiento de restricción/contaminación de esta revisión aún necesitan verificación en el cliente.
- Validación: los 324 casos se superan en orden directo/inverso en Lua 5.1.5 y 5.2.4 reales, cada ejecución de CLI emite un resumen, y el ZIP instalable extraído de 26 archivos pasa en ambas versiones. Los 23 archivos Lua se analizan correctamente; se verifican las 22 entradas TOC y el manifiesto de proveedores. Las comprobaciones de formato y diferencias pasan. Pin de biblioteca: 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. No hay CI de GitHub configurado para QT; el CI de la biblioteca de origen pasó.

## 5.7.6-beta.2

QuestTogether 5.7.6-beta.2 reemplaza su ventana de depuración separada por la consola compartida libchev v1.1 usada en todos los addons. La biblioteca integrada está incluida; no hace falta instalación separada.

### Cambios en esta versión

- Filtrado compartido por categorías, búsqueda difusa/entrecomillada, copiar/seleccionar, borrar, recargar, pruebas, diagnósticos y comportamiento de seguimiento del desplazamiento.
- /qt test abre los resultados actuales; las ejecuciones repetidas reemplazan el historial TEST antiguo y borran filtros de búsqueda obsoletos.
- /qt diagnostics [questID] y /qt diag [questID] reconstruyen el informe actual en caché en la misma consola, conservando eventos recientes dentro del límite compartido de exportación.
- Las guardas compartidas de restricción y de marcos propios reemplazan las antiguas retrollamadas de la consola de QT y la implementación del menú desplegable.
- El estado de misiones, anuncios, placas de nombre, comunicaciones y aislamiento de pruebas específico de QT siguen perteneciendo a QuestTogether.
- Esta es una versión beta. El renderizado y el comportamiento de contaminación en vivo de Retail/Forever aún necesitan verificación. Tras /reload, ejecuta /qt test y /qt diagnostics; luego prueba categoría/búsqueda, copiar, borrar, redimensionar, desplazamiento, ejecuciones repetidas de pruebas y cambios entre informes y registros. Incluye transiciones de combate/restricción y tu conjunto habitual de addons.
- Validación: 324/324 pruebas superadas en ambos órdenes con Lua 5.1.5 y 5.2.4. Los 23 archivos Lua se analizan correctamente, las 22 entradas TOC se validan y el manifiesto de la biblioteca fijada se verifica. El ZIP instalable fue extraído y superó los 324 casos usando el arnés sin conexión separado. Pin de biblioteca: 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

QuestTogether 5.7.6-beta.1 integra libchev v1.0.0 para compartir registro, diagnósticos, guardas de retrollamada, mecánicas de trabajo diferido y ejecución de pruebas con los otros addons Together. La biblioteca está incluida; no hace falta instalar un addon separado.

### Cambios en esta versión

- Los informes de diagnóstico incluyen información común de cliente/addon/biblioteca y conservan los eventos más recientes cuando se llena la ventana de copia.
- El comportamiento de misiones, grupo, placas de nombre y restricciones sigue perteneciendo a QuestTogether, con almacenes de ejecución aislados por addon.
- Los enlaces de coordenadas siguen siendo utilizables mientras QT está desactivado cuando las restricciones lo permiten; el trabajo en segundo plano en cola permanece pausado y los temporizadores obsoletos se descartan.
- /qt test ahora incluye 315 casos: los 300 existentes, diez comprobaciones de la biblioteca compartida y cinco regresiones de integración.
- Validación: las 315 pruebas se superan en ambos órdenes con Lua 5.1.5 y 5.2.4; pasan la sintaxis Lua, el orden de carga TOC y el manifiesto integrado de revisión/hash. Fuente de libchev integrada: 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- Esta es una versión beta. El renderizado de IU y el comportamiento de contaminación en vivo en Retail/Forever tras esta extracción aún necesitan verificación. Tras recargar, ejecuta /qt test y /qt diagnostics; luego prueba misiones, burbujas de progreso, placas de nombre y enlaces de coordenadas en combate, cambios de zona, desactivación/reactivación y recarga con tus addons habituales. La confirmación anterior de 300 pruebas en Retail se aplicaba a v5.7.5.
