# QuestTogether — Journal des modifications

<!-- Generated from canonical release notes; do not edit by hand. -->

## 6.2.3

Un nouveau journal de quêtes du groupe, des destinations partagées et le suivi facultatif d'une quête facilitent les aventures ensemble.

### Journal de quêtes du groupe

- Le comparateur devient le journal de quêtes du groupe. Développez plusieurs quêtes à la fois pour voir les objectifs et la progression de chacun, avec un bilan des quêtes prêtes à être rendues dans le groupe.
- Recherchez des quêtes et combinez les filtres de possession, de progression et de partage. Actualiser met à jour les données des autres joueurs ; les anciens clients peuvent toujours comparer les listes, mais pas fournir les détails des objectifs.
- Redimensionnez la fenêtre en parchemin et faites défiler son contenu en douceur. Les colonnes aux couleurs des classes, les en-têtes cliquables et espacés et les panneaux d'objectifs arrondis améliorent la lisibilité.

### Quête active et points de passage partagés

- La quête active de chaque membre apparaît sous son nom. Choisissez de suivre sa quête depuis son en-tête ou son menu QT pour activer les quêtes que vous possédez. Une quête absente ou désélectionnée conserve votre navigation ; naviguer manuellement, quitter le groupe ou recharger l'interface arrête le suivi.
- Les points de passage Blizzard des autres membres apparaissent aux couleurs des classes sur la carte du monde et, à proximité, sur la minicarte. Les marqueurs superposés indiquent tous les propriétaires ; Naviguer ici utilise TomTom ou la navigation native. Recevoir un point ne vous redirige jamais et ne garantit pas une phase commune.
- Partager ma quête active, Partager mon point de passage et Afficher les points du groupe sont activés par défaut dans Groupes et partage, indépendamment de la position publique et de la recherche de partenaires. Le suivi exige un choix explicite. Ces fonctions nécessitent des clients à jour dans un groupe de cinq au maximum, donjons compris, hors raids.

### Fenêtres et menus

- Les notes de mise à jour adoptent aussi le parchemin sombre, avec un mode clair facultatif. Déplacez ou redimensionnez la fenêtre, parcourez un historique plus lisible et utilisez les flèches pour changer de version ou atteindre une extrémité. Discord et Paramètres sont dans le pied de page.
- Les infobulles des joueurs s'ajustent mieux au contenu. Le menu de la minicarte sépare les outils de quête des notes, de l'emplacement du journal et de la visibilité de l'icône. Paramètres et Envoyer un message QT en sont retirés ; les paramètres restent accessibles avec /qt options.

## 6.2.2

Une progression de quête lisible dans toutes les langues.

### Conserver les détails des objectifs

- La progression des quêtes, expéditions et objectifs bonus conserve désormais le texte et les compteurs d’origine de l’expéditeur dans le chat et les bulles, au lieu de les remplacer par un texte générique comme « Objectif 1 : 5/5 ».
- Les annonces de quêtes acceptées et terminées utilisent toujours des libellés traduits et les titres de quête disponibles localement.

## 6.2.1

Un contrôle plus clair des annonces dans le canal de groupe.

### Savoir quand QT écrit dans le canal de groupe

- Le réglage sous Où annoncer indique désormais clairement que QT écrit aussi dans le canal de groupe si un membre n’est pas reconnu comme utilisateur de QT. Il reste activé par défaut.
- Une nouvelle fenêtre avec le logo QT apparaît après un court délai de détection. Choisissez Laisser activé ou Désactiver les annonces avant le début de la transmission. Ne plus me le rappeler enregistre votre confirmation pour le profil actuel.
- Le rappel traduit nomme les membres concernés et peut revenir lorsque de nouveaux membres non identifiés rejoignent le groupe. Il disparaît s’ils sont reconnus comme utilisateurs de QT. Les événements retenus pendant l’attente ne sont pas renvoyés.

## 6.2.0

Des points proches plus fluides, des détails de joueur plus rapides et une communication plus fiable.

### Des déplacements plus fluides sur la minicarte

- Les joueurs proches peuvent échanger leurs positions par des chuchotements d’addon cadencés. Les déplacements fluides privilégient jusqu’à quatre joueurs admissibles parmi les plus proches et respectent le partage, les filtres, les joueurs ignorés et les limites de trafic.
- Les deux joueurs doivent installer cette mise à jour pour les flux de position et les réponses directes au survol. Les anciennes versions conservent leurs diffusions habituelles ; les délais et restrictions du serveur peuvent toujours affecter la réception.

### Découverte et détails de groupe plus rapides

- Survoler un nom ou un point peut demander directement des détails récents. La fréquence des demandes est limitée et les listes de membres inchangées n’expirent plus après deux minutes.
- Les positions récentes, le statut de recherche de partenaires et les détails de groupe connus survivent à /reload pendant trois minutes au maximum depuis leur relevé initial. Entrer dans une zone demande aussi une actualisation de découverte échelonnée.
- Les infobulles utilisent le statut solo ou en groupe connu en attendant la taille exacte du groupe. Un petit logo identifie désormais les utilisateurs de QT dans la liste des membres, tout en gardant les noms alignés.

### Traduction et présentation améliorées

- Les noms de race, détails de ping, données de quête et davantage de textes d’interface utilisent les traductions locales disponibles. Sinon, le texte lisible de l’expéditeur est conservé ; la progression n’emprunte pas de descriptions d’objectifs locaux sans rapport.
- Les annonces génériques utilisent désormais le logo QT. La recherche de partenaires de quête est la première option du menu de la minicarte.

### Communication et fiabilité

- Les comparaisons, listes de groupe, demandes pour rejoindre ou partager et réponses au ping privilégient les chuchotements directs avec les joueurs compatibles. Le regroupement des messages périodiques et la réduction des mises à jour de positions inchangées allègent le trafic public.
- Correction des analyses de quêtes répétées, des vérifications excessives des barres de nom, des fenêtres impossibles à fermer pendant les restrictions et de /qt set acceptant des réglages autres que marche/arrêt. Désactiver le partage de position ne supprime plus les autres demandes en attente.

## 6.1.2

Points des joueurs à proximité plus réactifs et annonces traduites plus claires.

### Points des joueurs sur la minicarte

- Correction des points de joueurs QT manquants lorsque la minicarte ne fournit pas d’ID de carte. QT utilise désormais votre carte actuelle si nécessaire.

### Mises à jour de position locales plus rapides

- Les mises à jour de position ciblent désormais une fois par seconde avec moins de 10 utilisateurs QT connus dans votre zone, 5 à 10 secondes avec 10 à 19, et 15 à 20 secondes à 100. Les intervalles s’allongent progressivement entre ces paliers ; les timings à 500 ou plus restent inchangés.
- Les mises à jour rapides envoient des positions compactes et fraîchement échantillonnées, tandis que les autres détails des joueurs conservent leur battement plus lent. Les limites de trafic existantes s’appliquent toujours, la congestion peut donc retarder la livraison. Les autres joueurs doivent disposer de cette mise à jour pour envoyer des positions plus rapides.

### Annonces traduites plus claires

- Les libellés d’événements de quête, comme Quête acceptée, utilisent désormais votre langue même lorsqu’un titre de quête local ou des métadonnées de traduction facultatives sont indisponibles.
- Lorsque WoW ne peut pas fournir de titre de quête local, QT conserve le titre lisible de l’expéditeur. Les messages de progression conservent toujours leur texte d’origine lorsqu’ils ne peuvent pas être reconstruits en toute sécurité.

## 6.1.1

Menus contextuels plus clairs pour les joueurs et les quêtes.

### Nettoyage des menus contextuels

- Les menus de noms de joueurs et de quêtes n’incluent plus le raccourci vers la fenêtre de journal. Déplacez les journaux de QuestTogether entre la fenêtre de discussion principale et une fenêtre séparée via le menu de la minicarte ou les paramètres.

## 6.1.0

Trouvez des groupes sur la carte, voyez qui fait des quêtes ensemble et demandez à rejoindre le groupe via n’importe quel membre. Les infobulles des personnages-joueurs mettent désormais les détails du groupe en évidence.

### Voir qui fait des quêtes ensemble

- Les joueurs groupés ont désormais un petit badge à deux personnes sur leurs points de carte et de minicarte. Survolez un membre du groupe pour afficher un contour blanc autour de ses compagnons, estomper les points sans rapport et afficher une couronne sur le chef. Les lueurs dorées de Recherche de partenaires de quête restent visibles.
- Les infobulles des personnages-joueurs listent les membres du groupe avec des points et des noms aux couleurs de classe, le chef couronné en premier. Les groupes jusqu’à cinq membres les affichent tous ; les groupes plus grands n’affichent que le chef. Ces détails apparaissent aussi quand vous survolez les noms de joueurs dans le journal QuestTogether.
- Votre propre groupe utilise la liste de membres du jeu. Les détails des groupes distants sont chargés depuis les pairs QuestTogether mis à jour lorsque nécessaire, avec des résultats en cache et des requêtes espacées pour limiter le trafic du canal. Les anciens clients conservent leurs points normaux et les informations de base sur la taille du groupe ; les détails complets des groupes distants nécessitent un pair à jour.

### Les demandes pour rejoindre peuvent parvenir au chef de groupe

- Vous pouvez demander à rejoindre via un membre du groupe qui ne peut pas vous inviter. Si son chef utilise QuestTogether et peut inviter, la demande est redirigée vers le chef avec les réglages habituels de confirmation et d’approbation automatique.
- Si le chef n’est pas connu comme utilisateur de QuestTogether, le membre peut annoncer « [QT] PlayerName demande à rejoindre le groupe. » dans la discussion de groupe lorsque les annonces en discussion de groupe sont activées. Quelqu’un ayant la permission d’inviter doit alors vous inviter manuellement.
- Le demandeur et le membre qui transfère la demande doivent disposer de cette mise à jour pour les demandes redirigées. Les vérifications existantes de groupe complet, de restriction, d’ignore, d’expiration et de fréquence des demandes s’appliquent toujours.

### Infobulles de joueurs plus claires

- Les informations de groupe se trouvent désormais juste sous la ligne de niveau, de race et de classe, avec des lignes de membres compactes et de l’espace entre les sections. Les insignes de l’Alliance et de la Horde sont deux fois plus grands.
- La version de l’addon apparaît en dernier au format abrégé vX.Y.Z. Quand l’ancienneté d’un emplacement est affichée, Dernière mise à jour se trouve directement au-dessus de la version.
- Les nombres de quêtes suivies ont été retirés des infobulles des joueurs et du bouton de la minicarte. Le titre de la quête active des joueurs qui recherchent des partenaires de quête est toujours affiché.

## 6.0.2

Parcourez les anciennes mises à jour de QuestTogether dans votre langue, avec une meilleure récupération des noms de quêtes pour les annonces d’achèvement.

### Parcourir les anciennes notes de mise à jour

- La fenêtre d’accueil comporte maintenant des boutons Anciennes et Récentes, un raccourci Dernière et un sélecteur d’historique affichant les versions et dates de publication. L’ouverture des notes de mise à jour commence à la dernière version.
- L’historique comprend toutes les versions publiées précédemment, y compris les premières bêtas. Toutes les notes historiques sont traduites dans chaque langue de WoW prise en charge et incluses dans les journaux des modifications des dépôts correspondants.
- Les boutons de navigation se désactivent lorsqu’il n’y a nulle part où aller. Parcourir d’anciennes notes ne change pas la mise à niveau que vous avez confirmée ; les fenêtres automatiques n’apparaissent toujours que pour les mises à niveau majeures et mineures. Ouvrez la fenêtre à tout moment avec /qt notes.

### Titres des quêtes terminées

- Lorsqu’une quête quitte votre journal avant que QuestTogether ne dispose d’un titre utilisable, les annonces d’achèvement essaient désormais la recherche de titre de quête disponible en jeu avant de se rabattre sur un ID de quête. Un titre récupéré est conservé quel que soit l’ordre des événements de rendu et de suppression.
- Les annonces utilisent toujours le texte de l’expéditeur lorsque votre client ne peut pas résoudre un titre local. Si aucun des deux clients n’a de nom disponible, l’ID de quête reste la solution de repli. La récupération améliorée côté expéditeur s’applique lorsque l’expéditeur effectue la mise à jour.

## 6.0.1

Les célébrations restent désormais associées aux joueurs que vous pouvez réellement voir à proximité.

### Correctifs des célébrations à proximité

- Les réactions à un autre joueur qui termine une quête ou gagne un niveau nécessitent désormais une unité de joueur correspondante et visible. Les coordonnées de la carte ou un nom seul ne déclenchent plus d’emote, y compris lorsque devlogall est activé.
- Les emotes entrantes doivent correspondre à la propre liste de célébrations de QuestTogether. Les emotes non répertoriées, y compris mountspecial et les acclamations de faction, sont ignorées sans choisir de substitut.
- Vos propres célébrations de fin de quête et de gain de niveau conservent leur comportement et leurs paramètres existants.

## 6.0.0

QuestTogether 6.0 prépare le lancement de Forever avec un système de communication conçu pour réduire le trafic en arrière-plan à mesure que la communauté grandit.

### Activité locale, découverte mondiale

- Les annonces de quêtes et les mises à jour fréquentes des joueurs utilisent désormais les canaux de zone. Les annonces de groupe atteignent toujours votre groupe au-delà des limites de zone.
- Les points des joueurs restent disponibles dans le monde entier, avec des mises à jour en arrière-plan plus lentes. Ouvrir une autre zone sur la carte du monde vous abonne temporairement à ses mises à jour.
- La discussion texte de QT reste sur le canal global QuestTogether. Votre réglage de discussion Globale ou Zone uniquement contrôle toujours les messages que vous voyez.

### Moins de trafic en arrière-plan

- La présence, la version, le nombre de quêtes, le statut de partenaire et la position sont regroupés dans des mises à jour compactes. Les zones très fréquentées sont mises à jour moins souvent afin de réduire le trafic.
- Les annonces sont régulées et prioritaires par rapport aux mises à jour en arrière-plan. Les réponses aux pings sont réparties afin d’éviter une rafale de réponses. WoW peut toujours retarder la distribution des messages de canal ; cette mise à jour ne garantit pas des messages instantanés.
- Les infobulles des joueurs indiquent l’âge des positions plus anciennes. Les diagnostics signalent désormais le nombre de messages, la limitation et les délais d’annonce indiqués par l’expéditeur.

### Une mise à jour majeure pendant la bêta

- Nous effectuons maintenant ce changement de communication plus important en prévision du lancement de Forever. La bêta est le meilleur moment pour prendre ces décisions fondamentales, avant que davantage de joueurs ne dépendent de l’ancien comportement.
- La version 6.0 quitte QuestTogetherAnnounce1 et n’envoie ni ne reçoit plus sur cet ancien canal. Elle utilise QuestTogether pour la discussion et la découverte globales, ainsi que des canaux de zone pour l’activité locale.
- QuestTogether conserve ses canaux après vos autres canaux de discussion, avec le canal de discussion principal avant ses canaux de zone. Vos préférences de partage de position, de liste d’ignorés et d’annonces sont conservées.

### Compatibilité avec les anciennes versions

- Veuillez mettre à jour ensemble. Les anciennes versions ne peuvent pas lire les nouvelles mises à jour groupées des joueurs ni écouter les nouveaux canaux de zone ; les joueurs utilisant des versions différentes peuvent donc manquer des points sur la carte, le statut de partenaire et les annonces de quêtes à proximité.
- Les joueurs utilisant uniquement l’ancien canal ne sont plus détectables via ce canal en 6.0. Certains échanges avec les versions 5.x plus récentes peuvent encore fonctionner via le canal global partagé ou un groupe, mais il s’agit d’une compatibilité partielle, pas de l’expérience complète.
- La commande manuelle /qt ping utilise toujours le canal global. Elle peut y entendre les anciens clients compatibles, mais c’est un outil de découverte au mieux, pas un décompte complet de toutes les personnes utilisant QuestTogether.

## 5.17.2

Le chat QT est plus facile à distinguer des annonces de quêtes.

### Texte blanc pour le chat QT

- Les messages des joueurs dans le chat QT utilisent désormais du texte blanc dans la fenêtre de discussion et les bulles au-dessus des personnages.
- Les noms des joueurs conservent la couleur de leur classe, et les annonces de quêtes conservent leur texte jaune.

## 5.17.1

Découvrez-en plus sur vos compagnons de quête et consultez l’état des quêtes directement depuis les infobulles de discussion.

### Infobulles de joueur plus utiles

- Les infobulles des noms de joueur et des points sur la carte indiquent désormais combien de quêtes QuestTogether surveille, ainsi que Solo ou Groupe de N. Votre propre infobulle utilise votre état local actuel.
- L’infobulle de la minicarte compte désormais les quêtes surveillées par QuestTogether, comme l’annonce au démarrage, au lieu de ne compter que les quêtes suivies dans le suivi de WoW.
- Le nombre de quêtes distantes et la taille des groupes nécessitent un pair mis à jour. Ils sont actualisés environ toutes les 80 secondes via les messages de pulsation existants, sans messages supplémentaires ; les rapports manquants ou obsolètes s’affichent comme inconnus. Les anciennes versions continuent de recevoir les annonces de version compatibles.

### État de la quête au survol

- Survolez un nom de quête dans les journaux QT pour voir votre état de quête, si elle peut être partagée, l’ID de quête et la progression des objectifs suivis localement dans une infobulle à côté du curseur.
- L’élément de menu État a été supprimé. Cliquer sur un nom de quête ouvre toujours Partager, Ouvrir dans le journal des quêtes, Comparer les quêtes du groupe et l’action de destination de la fenêtre de journal.
- Les nouveaux libellés d’infobulle sont traduits dans toutes les langues prises en charge. Les détails de quête reflètent votre propre progression, pas l’étape de quête de l’expéditeur.

## 5.17.0

Dites bonjour dans la discussion QT, trouvez des partenaires de quête dans toute votre zone et découvrez des informations et paramètres de joueur plus clairs.

### Discutez avec d’autres joueurs de QuestTogether

- Tapez /qt <text>, ou choisissez Envoyer un message de discussion QT dans le menu de la minicarte. Les conversations apparaissent dans les journaux QT et dans les bulles au-dessus des joueurs à proximité avec une icône de bulle de dialogue ; les commandes obliques existantes fonctionnent toujours.
- Choisissez la discussion globale (par défaut), Zone uniquement, ou masquez entièrement la discussion QT. Zone uniquement nécessite une position partagée récente de l’expéditeur ; la discussion globale n’en a pas besoin.
- Le nouveau canal QuestTogether fonctionne en parallèle de QuestTogetherAnnounce1 pendant la transition. QT place les deux après vos autres canaux lorsque c’est pris en charge, avec QuestTogether en premier ; la discussion saisie utilise uniquement le nouveau canal.

### Trouvez des partenaires de quête

- Activer Recherche de partenaires de quête annonce votre recherche dans toute votre zone avec une icône QT dorée lumineuse et un smiley. La diffusion à l’échelle de la zone nécessite le partage de position et respecte les préférences d’annonce ; la désactiver reste silencieux.
- Contrôlez ces messages dans Quoi annoncer. Un temps de recharge de 30 secondes limite les annonces répétées tandis que votre statut et la lueur se mettent quand même à jour immédiatement. Vous pouvez aussi choisir d’arrêter automatiquement la recherche en rejoignant un groupe ; cette option est désactivée au départ.
- Maj-clic sur le bouton de la minicarte pour activer ou désactiver votre recherche de partenaires. Un anneau doré plus vif et pulsant met en évidence votre recherche active sans rogner le logo.

### Choisissez votre portée et voyez plus d’informations sur les joueurs

- La portée de proximité va désormais de 5 % à Toute la zone, avec une valeur par défaut de 25 %. Elle ajuste la distance sur l’ensemble de votre zone actuelle ; les membres du groupe et les joueurs directement visibles conservent leur comportement existant.
- Survolez les noms dans les journaux QT pour afficher la même infobulle améliorée que sur les points de la carte : nom coloré selon la classe, niveau, race, classe, emblème de faction, statut de partenaire, quête suivie si disponible et version de QT. Les infobulles de nom apparaissent désormais à côté de votre curseur.
- L’infobulle de votre propre nom affiche désormais votre quête suivie prioritairement actuelle lorsque vous recherchez des partenaires. Les clients mis à jour annoncent leurs versions environ toutes les 40 secondes via les messages de battement existants ; les anciens clients conservent leur fréquence précédente.

### Contrôles et annonces plus clairs

- L’infobulle de la minicarte affiche désormais votre version de QT, votre statut de partenaire, la portée de la discussion, le nombre de quêtes surveillées, la portée de proximité et l’état du partage de position.
- Les contrôles des paramètres disposent désormais d’explications traduites au survol, y compris pour les menus déroulants, les curseurs, les actions de profil et les contrôles de couleur.
- Lorsque votre client ne parvient pas à résoudre un titre de quête localisé, les annonces conservent le texte d’origine de l’expéditeur dans les journaux comme dans les bulles au lieu d’afficher un numéro de quête générique. L’affichage localisé reprend pour les annonces suivantes une fois le titre disponible.

## 5.16.7

Lisez les mêmes notes de version de QuestTogether en jeu, sur Discord et dans votre langue préférée dans les fichiers du journal des modifications.

### Journaux des modifications cohérents et multilingues

- Le journal des modifications anglais reprend désormais les mêmes résumés de version et listes à puces que la fenêtre d’accueil et les annonces Discord.
- Des fichiers de journal des modifications sont disponibles pour toutes les langues prises en charge, avec l’historique des versions traduit existant et une copie conservée des anciennes notes anglaises rédigées à la main.
- Les vérifications de version maintiennent les fichiers du journal des modifications synchronisés avec les notes et traductions de référence.

## 5.16.6

Voyez d’un coup d’œil quand vous cherchez des partenaires de quête.

### Un rappel lumineux sur la minicarte

- Le bouton QuestTogether de votre minicarte clignote désormais avec la même lueur dorée du logo que les barres d’info des personnages-joueurs tant que Recherche de partenaires de quête est activée.
- La lueur suit votre statut de partenaire et s’arrête quand QT est désactivé ou quand le bouton de la minicarte est masqué. Votre bouton et le logo conservent leur taille actuelle.

## 5.16.5

Un préfixe plus court rend les annonces de groupe plus compactes.

### Annonces de groupe compactes

- La progression des quêtes publiée aux membres du groupe sans QuestTogether commence désormais par [QT] au lieu de [QuestTogether].
- Les annonces respectent toujours la limite des messages de discussion et préservent les caractères complets dans toutes les langues.

## 5.16.4

Conservez vos réglages de bulle en quittant le mode Édition et trouvez des compagnons de quête à proximité sur les cartes bondées.

### Les réglages de bulle restent enregistrés

- La fermeture du mode Édition de l’ATH conserve désormais la taille de police, la durée d’affichage et la position de votre bulle QT au lieu de les réinitialiser.
- Le panneau de bulle QT dispose désormais de son propre bouton Enregistrer les modifications et d’un message d’état enregistré. Les réglages s’appliquent automatiquement ; Enregistrer les modifications définit le point auquel Rétablir les modifications revient.
- Après avoir enregistré puis effectué d’autres ajustements, Rétablir les modifications restaure vos derniers réglages QT enregistrés.

### Les joueurs à proximité sont prioritaires

- Lorsque plus de 128 points éligibles se disputent l’espace sur la carte ou la minicarte, les joueurs les plus proches sont prioritaires en fonction de leur distance par rapport à votre personnage.
- Lorsque le cache de 512 emplacements se remplit, les joueurs les plus proches sont conservés avant les arrivants plus éloignés. Le déplacement et le zoom de la carte ne modifient pas la priorité de proximité.
- Ces changements conservent les limites existantes de points et de cache sans envoyer de messages de communication supplémentaires.

## 5.16.3

Trouvez plus facilement les paramètres dont vous avez besoin et consultez vos préférences QuestTogether d’un coup d’œil.

### Paramètres organisés autour de votre façon de jouer

- Groupes et partage remplace Divers, en regroupant la disponibilité des partenaires, les demandes de participation et les approbations de partage de quêtes.
- Les emotes de célébration se trouvent désormais dans Où annoncer. La visibilité de la minicarte se trouve dans Général sur la page principale, avec les outils de débogage et la nouvelle analyse du journal des quêtes dans Dépannage.
- Comparer les quêtes du groupe et Trouver des partenaires de quête sont désormais les premières actions rapides. Vos préférences existantes sont conservées.

### Un état rapide plus utile

- Consultez l’état de vos partenaires, le partage de position et les préférences d’affichage, les approbations de demandes, la sortie des annonces, ainsi que les paramètres des barres d’info des quêtes et des joueurs dans les sections liées.
- Vérifiez votre profil actif, la version installée et toute version plus récente détectée. Lorsque QT est désactivé, le résumé indique clairement que les paramètres sont des préférences enregistrées.
- Cliquez sur l’en-tête d’une section pour ouvrir ses paramètres. Le résumé s’agrandit pour s’adapter à son texte et reste à jour tant que la page est ouverte.

## 5.16.2

Reconnaissez les joueurs de QuestTogether grâce à leurs infobulles et repérez plus facilement des partenaires de quête.

### Infobulles des joueurs QuestTogether

- Survolez le personnage, la barre d’identification ou le cadre d’unité d’un joueur QT pour voir « Ce joueur utilise QuestTogether. » Les joueurs qui cherchent des partenaires de quête affichent également ce statut et un logo QT lumineux.
- La section QT correspond à la largeur et à l’échelle de l’infobulle, reste à l’écart de sa barre de vie et se déplace au-dessus de l’infobulle quand l’espace en dessous est limité.

### Une lueur de partenaire plus visible

- La lueur dorée de la barre d’identification s’étend désormais deux fois plus loin autour du logo, tout en conservant la même taille pour le logo lui-même.
- Les icônes et les lueurs reflètent les vrais utilisateurs de QT et leur statut actuel de recherche de partenaire.

## 5.16.1

Trouvez plus facilement des partenaires de quête et voyez sur quelle quête ils se concentrent.

### Une lueur de partenaire plus lumineuse

- Les joueurs qui cherchent des partenaires de quête ont désormais une lueur dorée plus lumineuse autour du logo QT sur leur barre d’info, avec une légère pulsation. Le logo lui-même reste stable.

### Voir leur quête actuelle

- Survolez le point sur la carte ou la minicarte d’un joueur qui cherche des partenaires de quête pour voir sa quête super-suivie — la quête unique sélectionnée pour la navigation. Les deux joueurs doivent disposer de cette mise à jour.
- Les informations de quête s’actualisent environ toutes les 20 secondes. Elles ne sont partagées que lorsque la recherche de partenaires de quête et le partage de position sont activés.
- Les noms des quêtes utilisent la langue de votre client lorsqu’elle est disponible, avec le titre ou l’ID de quête de l’expéditeur comme solution de repli. Les anciennes versions de QT conservent leurs points et indicateurs de partenaire existants.

## 5.16.0

QuestTogether prend désormais en charge toutes les langues de WoW et peut afficher les mises à jour de quête des autres joueurs dans la langue de votre client.

### Jouez dans plus de langues

- Les menus, paramètres et notes de mise à jour prennent désormais en charge toutes les langues locales de WoW : anglais, allemand, français, espagnol européen, espagnol latino-américain, portugais brésilien, russe, italien, coréen, chinois simplifié et chinois traditionnel.
- L’espagnol latino-américain dispose désormais de ses propres textes au lieu de partager ceux de l’espagnol européen.

### Progression de quête localisée

- Les événements de quête pris en charge provenant de joueurs QT à jour peuvent apparaître dans la langue de votre client dans les journaux de discussion et bulles QT, en utilisant les titres de quête locaux lorsqu’ils sont disponibles et les nombres de progression réels de l’expéditeur.
- Lorsqu’une description d’objectif traduite ne peut pas être choisie de manière fiable, QT utilise à la place un numéro d’objectif localisé avec le nombre, le pourcentage, l’état d’achèvement ou l’état de progression.
- Les anciennes versions de QT et la discussion de groupe publique conservent la formulation de l’expéditeur. Lorsque WoW ne peut pas fournir de titre de quête local, QT conserve le titre source ou affiche l’ID de quête. Les événements dans la même langue conservent leur formulation native détaillée.

### Amélioration des titres de quête

- La comparaison de quêtes privilégie désormais votre titre de quête local lorsqu’il est disponible.
- Les titres de quête localisés contenant une ponctuation non ASCII restent cliquables de manière plus fiable.

## 5.15.0

Demandez à rejoindre un groupe de quête directement depuis le menu d’un joueur QuestTogether.

### Rejoindre un groupe de quête

- Les joueurs QT déjà en groupe affichent désormais Demander à rejoindre au lieu d’Inviter lorsque des informations récentes sont disponibles. Les deux joueurs doivent disposer de cette mise à jour ; le demandeur doit être seul.
- Le destinataire peut envoyer une invitation WoW normale ou refuser. Il doit avoir le droit d’inviter et une place dans un groupe normal. Vous devez toujours accepter l’invitation normale pour rejoindre.

### Invitations automatiques facultatives

- Deux nouvelles options approuvent automatiquement les demandes des amis de votre personnage, ou des autres joueurs pendant votre recherche de partenaires de quête. Désactivées par défaut, elles figurent dans la fenêtre de demande et les paramètres Divers. Les amis de compte Battle.net ne sont pas inclus.
- Les demandes expirent et respectent les joueurs ignorés, les changements de groupe et les restrictions du jeu. QT ne quitte jamais votre groupe actuel et n’accepte pas d’invitations à votre place.

## 5.14.1

Les annonces de groupe affichent désormais le nom complet de QuestTogether.

### Canal de groupe

- Le préfixe des annonces dans le canal de groupe passe de [QT] à [QuestTogether] pour permettre aux autres joueurs de trouver plus facilement l’addon.

## 5.14.0

QuestTogether parle désormais cinq langues supplémentaires et vous aide à tenir informés les membres du groupe qui n’utilisent pas QT.

### Jouez dans votre langue

- L’interface est désormais disponible en allemand, français, espagnol, portugais brésilien et russe. QuestTogether utilise la langue du jeu, avec l’anglais comme langue de secours.
- Les paramètres, menus, infobulles, comparaisons de quêtes et notes de mise à jour sont traduits. Les noms de quêtes et les textes de progression reçus des autres joueurs restent dans leur langue d’origine.
- Retrouvez les annonces de mise à jour traduites dans les cinq salons dédiés aux différentes langues sur notre Discord.

### Informez tout votre groupe

- Une nouvelle option dans les canaux d’annonce envoie vos annonces d’événements activées dans le canal de groupe lorsqu’un membre n’a pas été reconnu comme utilisateur de QT. Elle est activée par défaut et peut être désactivée dans les paramètres.
- Cela fonctionne aussi dans les groupes d’instance constitués automatiquement. Le jeu en solo et les raids sont exclus, et les annonces des autres joueurs ne sont jamais retransmises.

## 5.13.1

Cette mise à jour de maintenance améliore la récupération des plaques de quête, supprime les bulles et logos de joueurs obsolètes, et garantit un comportement cohérent des paramètres et de la fenêtre de débogage.

### Plaques de quête et indicateurs de joueurs

- Les icônes de quête et les teintes des barres de vie se rétablissent correctement après la fermeture des vues restreintes. Les analyses de quêtes différées conservent leur temps de stabilisation, et les données d’infobulle temporairement manquantes gardent leur nombre de nouvelles tentatives.
- Les bulles d’annonce sont nettoyées quand la plaque d’un joueur disparaît ou est réutilisée pendant le combat. Les cadres protégés ou interdits attendent un nettoyage sûr.
- Les positions sur la carte et la présence des joueurs se rétablissent après avoir désactivé QuestTogether, changé de zone, puis l’avoir réactivé. Les joueurs partis ne récupèrent plus un logo QT à cause de retraits tardifs de position ou de statut de partenaire.

### Correctifs des paramètres et des fenêtres

- La case Recherche de partenaires de quête reste synchronisée quand le statut change via les commandes, les menus ou les paramètres de profil.
- La fenêtre de débogage termine en toute sécurité les déplacements et redimensionnements interrompus quand les restrictions sont levées, même après avoir été masquée.

### Améliorations de fiabilité

- Des tests renforcés détectent l’accès aux cadres interdits même lorsqu’une erreur est interceptée en interne.
- Les contrôles de publication refusent désormais de publier tant que des changements d’implémentation ne sont pas validés, afin de garantir que les correctifs atteignent bien le téléchargement.

## 5.13.0

Trouvez des partenaires de quête d’un coup d’œil grâce aux points de carte et logos de joueurs mis en évidence, à des paramètres de position simplifiés et à des rappels quand un autre joueur possède une version stable plus récente de QuestTogether.

### Repérer les partenaires de quête

- Les joueurs recherchant des partenaires de quête ont une douce lueur dorée autour de leurs points de carte et de minicarte aux couleurs de leur classe.
- Leur logo QuestTogether sur la barre d’info reçoit une douce lueur dorée. Les surbrillances disparaissent quand le statut est désactivé ou expire.
- Les paramètres Positions des joueurs incluent Afficher uniquement les joueurs recherchant des partenaires de quête. Cette option commence désactivée et filtre les deux cartes lorsqu’elle est activée.
- La fenêtre Nouveautés en jeu affiche côte à côte les logos et points de carte normaux et lumineux. La lueur dorée signifie rechercher des partenaires de quête.

### Paramètres de position simplifiés

- Partager ma position et Afficher les autres joueurs s’appliquent chacun à la carte du monde et à la minicarte.
- Les deux options sont activées par défaut pour les nouveaux profils. Les désactivations existantes du partage de position sont conservées lors de la mise à niveau.

### Rappels de nouvelle version

- QuestTogether détecte quand un autre joueur signale une version stable plus récente de l’addon et affiche un rappel de mise à jour dans la fenêtre de discussion QuestTogether de votre choix.
- Le rappel est conservé entre les personnages et apparaît une fois à chaque rechargement jusqu’à ce que vous installiez la version détectée ou une version plus récente. Les versions alpha et bêta ne déclenchent pas de rappels.
- Les annonces de version sont légères et peu fréquentes. QuestTogether reconnaît aussi les informations de version dans les réponses de ping existantes.

## 5.12.0

Trouvez des personnes avec qui faire des quêtes grâce au nouveau statut Recherche de partenaires de quête. Cette mise à jour améliore aussi la visibilité des infobulles de la minicarte et sépare le comportement du Mode Guerre et des royaumes de Retail de celui de Forever.

### Recherche de partenaires de quête

- Faites savoir aux autres utilisateurs de QuestTogether que vous voulez de la compagnie. Votre statut apparaît dans votre menu de joueur et dans les infobulles des points de carte ; il n’active pas le partage de position et n’envoie pas d’invitations.
- Activez ou désactivez le statut depuis le menu de la minicarte, Paramètres > Divers, ou /qt lfg. Utilisez /qt lfg on, off ou status pour le définir ou le vérifier. Il commence désactivé et est enregistré par profil.
- Le statut de partenaire expire lorsque les mises à jour s’arrêtent. Les joueurs ignorés sont exclus, et désactiver QuestTogether met votre annonce en pause.

### Retail et Forever

- Forever n’affiche plus le Mode Guerre dans les infobulles des points de joueurs, les détails de position de quête ou la sortie de ping. Les pings de Forever omettent aussi les libellés de royaume tout en conservant les noms complets des joueurs.
- Les mises à jour de quêtes à proximité sur Forever ne nécessitent plus les informations de Mode Guerre de Retail. Les points de carte restent visibles entre les phases afin que vous puissiez trouver des personnes avec qui grouper.
- Retail utilise l’état actif du Mode Guerre lorsqu’il est disponible. Un Mode Guerre inconnu ou non pris en charge n’est plus indiqué comme Désactivé.

### Points de joueurs plus stables

- Des coordonnées brièvement manquantes ne retirent plus immédiatement votre point. Les dernières positions signalées restent jusqu’à deux minutes, et les signalements plus anciens affichent leur âge dans l’infobulle. Les désactivations du partage se retirent toujours immédiatement lorsque la communication est disponible.
- Les diffusions de déplacement sont limitées à une fois toutes les dix secondes, ce qui réduit le trafic de position. Les signaux de présence immobiles restent envoyés toutes les vingt secondes pour maintenir la compatibilité avec les anciens clients.
- Le cache de position conserve désormais jusqu’à 512 joueurs. Chaque carte affiche toujours au maximum 128 points visibles, et les joueurs hors de la carte affichée ne consomment plus cette limite d’affichage.

### Logos de joueurs fiables

- Corrige les logos manquants sur les barres d’info des joueurs amicaux dans les clients Forever et Retail actuels en lisant le paramètre actuel de visibilité des joueurs amicaux.
- Les logos placés à gauche se déplacent vers l’extérieur pour laisser de la place aux améliorations visibles, puis reviennent à leur position habituelle lorsque celles-ci disparaissent.
- Tous les messages QuestTogether pris en charge identifient désormais leur expéditeur. Un cache limité mémorise les joueurs pour la session d’interface actuelle, afin que les signaux de présence manqués ne retirent plus leurs logos. Les départs explicites et les joueurs ignorés sont toujours effacés ; aucun message supplémentaire n’est envoyé.

### Finitions de la minicarte

- L’infobulle de la minicarte QuestTogether utilise désormais une couche d’infobulle indépendante afin de pouvoir apparaître au-dessus de l’interface des barres d’actions. Elle se masque lorsque le bouton devient indisponible ou que les restrictions commencent.

## 5.11.0

QuestTogether ajoute désormais les positions des joueurs, les logos sur les barres des joueurs, les comparaisons de quêtes ciblées et un accès plus simple aux retours et à l’assistance via Discord. Les paramètres vous permettent de choisir ce que vous partagez et ce que vous voyez pendant que la progression des quêtes reste coordonnée avec les autres utilisateurs de QuestTogether.

### Trouver des joueurs QuestTogether à proximité

- Affiche le logo de parchemin à côté des joueurs QuestTogether amicaux lorsque les barres d’info amicales de WoW sont activées. Les barres des joueurs sont activées par défaut, avec une position Gauche avec marge ; choisissez Gauche, Droite, Haut ou Préfixe sans modifier les couleurs des barres de vie.
- Des points de joueurs aux couleurs de classe peuvent apparaître sur la carte du monde et la minicarte pour les joueurs qui partagent leur position. Survolez un point pour voir le nom, la faction, la race, la classe et le niveau ; cliquez dessus pour ouvrir le menu de joueur QuestTogether.
- Positions des joueurs possède des interrupteurs distincts pour le partage et l’affichage sur la carte du monde et la minicarte, et les quatre sont activés par défaut. La présence des logos sur les barres des joueurs peut continuer même lorsque les deux interrupteurs de partage de position sont désactivés.
- Les positions se rafraîchissent périodiquement et disparaissent lorsqu’elles expirent. Les deux joueurs doivent utiliser l’addon mis à jour ; un point ne garantit pas que vous partagez la même phase ou couche.

### Comparer un joueur ou tout le groupe

- L’action Comparer les quêtes du menu de joueur compare désormais seulement vous et le joueur sélectionné, y compris les pairs QuestTogether joignables qui ne sont pas dans le groupe. La comparaison de tout le groupe reste disponible depuis le menu de la minicarte, les menus de noms de quête et /qt compare.
- Le partage de quêtes et les demandes de partage restent réservés au groupe. Les comparaisons ciblées indiquent quand un groupe est nécessaire pour le partage et quand le joueur sélectionné doit utiliser QuestTogether pour répondre.
- Si une demande de partage est déjà en attente auprès d’un autre joueur, la comparaison indique désormais de qui elle attend une réponse après votre changement de cible.

### Retours et assistance

- La fenêtre d’accueil et la page principale des paramètres incluent désormais Discord — Retours et assistance. Cela ouvre une invitation copiable lorsqu’elle est disponible, ou affiche l’invitation dans la discussion si la fenêtre de lien ne peut pas s’ouvrir.

### Correctifs et finitions

- Les joueurs ignorés sont désormais filtrés plus complètement. Les nouveaux journaux, bulles, points, comparaisons et opérations de partage sont bloqués, tandis que les bulles et positions existantes sont effacées lorsque la liste des ignorés change.
- Correction de fausses plaques de quête causées par des limites d’infobulle indisponibles correspondant au texte d’objectif d’une autre quête.
- Désactiver le partage sur la carte ou la minicarte relance désormais la mise à jour après des échecs temporaires de communication. Désactiver les deux options de partage retire aussi les détails de position des autres mises à jour de l’addon.
- Les logos de joueurs s’effacent correctement lorsque la présence d’un joueur expire juste avant son départ. Chuchoter depuis les points de carte ouvre votre fenêtre de discussion, et changer la destination du journal depuis les Paramètres est indisponible pendant les restrictions.

## 5.10.0

QuestTogether partage la progression des quêtes avec votre groupe et les joueurs à proximité. Utilisez le bouton de la minicarte pour les paramètres, les comparaisons de quêtes de groupe, votre journal des quêtes et ces dernières notes.

### Comparer et partager les quêtes du groupe

- Ouvrez Comparer les quêtes du groupe depuis la minicarte ou les menus de quêtes et de joueurs, ou tapez /qt compare. Voyez qui possède chaque quête et la progression de chacun.
- Toutes les quêtes du groupe apparaissent par défaut. Cochez Masquer les quêtes que je n’ai pas pour vous concentrer sur les quêtes de votre propre journal.
- Demandez les quêtes partageables aux membres du groupe qui utilisent l’addon mis à jour. Les demandes sollicitent l’autorisation par défaut ; le partage automatique est un paramètre optionnel.
- Les comparaisons se rétablissent après les restrictions de carte ou de combat. Les actualisations remplacent les anciennes réponses, et les temps de recharge et échecs des demandes indiquent quand vous pouvez réessayer.

### Raccourcis et menus de quête

- Faites glisser le bouton de minicarte en forme de parchemin pour le repositionner. Son menu ouvre les paramètres, les comparaisons, le journal des quêtes, les notes de mise à jour et le contrôle de destination de la fenêtre du journal. Masquez-le depuis le menu et restaurez-le dans les paramètres Divers.
- Les menus de noms de quête proposent Statut, Partager, Ouvrir dans le journal des quêtes et Comparer les quêtes du groupe. Les actions de partage et de journal revérifient la quête actuelle et les restrictions au moment du clic.
- Les liens de statut de quête conservent leurs titres intacts après qu’une quête quitte votre journal. La case de partage automatique suit désormais les paramètres enregistrés et les changements de profil.

### Aide et dernières notes

- Lisez l’accueil et les dernières notes de mise à jour dans leur propre fenêtre au lieu de messages de discussion répétés. Choisissez Notes de mise à jour depuis le menu de la minicarte ou la page principale des Paramètres, ou utilisez /qt notes, /qt changelog ou /qt patchnotes.
- La fenêtre des notes s’ouvre automatiquement pour les mises à niveau majeures et mineures. Les mises à jour de correctif incluent toujours de nouvelles notes sans ouvrir automatiquement la fenêtre.
- Utilisez /qt help pour les commandes normales et /qt help debug pour les aperçus, diagnostics et commandes développeur.

## 5.9.2

Faites un clic gauche ou droit sur le nom d’une quête dans le journal QuestTogether pour ouvrir son menu, avec État en premier et Partager en second. Partager utilise l’entrée actuelle du journal des quêtes sans modifier la quête sélectionnée par Blizzard, et n’est pas disponible si vous êtes en solo, si elle est restreinte ou si la quête ne peut pas être partagée. Après un séparateur, la dernière option déplace les journaux QuestTogether entre la fenêtre principale et la fenêtre séparée, comme le menu des noms de joueurs de QT.

### Changements de cette version

- Rendre les noms de quêtes cliquables dans les messages d’état, y compris les titres de secours issus des journaux d’autres joueurs. Préserver les liens de quête existants lors de la mise en forme des comparaisons de quêtes terminées afin que les détails d’état ne fassent pas partie d’un second lien cassé.
- Validation : 521 tests réussissent dans l’ordre normal et inverse sous Lua 5.1 et 5.2. Les six profils d’API client, les vérifications de syntaxe Lua et shell, la vérification exacte de libchev et les contrôles de diff réussissent. Le comportement des menus sur client réel, la distribution du partage de quêtes et la validation du taint au niveau du moteur restent séparés.

## 5.9.1

Corrige le suivi des quêtes, la visibilité des barres d’info de quêtes, les annonces de zones d’objectifs, la fiabilité de la communication et les actions utilisateur identifiées lors de l’audit complet.

### Changements de cette version

- Empêcher les blocs de quêtes d’infobulles sans rapport d’emprunter le texte d’objectif partagé. Préserver la progression de groupe valide et récupérer les barres d’info après les changements de carte, d’instance, de composition de groupe et de quêtes.
- Garder les quêtes nouvellement acceptées et les analyses initiales en attente jusqu’à l’arrivée de données lisibles. Préserver les jalons d’objectifs, la classification des tâches et l’état d’emplacement inconnu sans sorties erronées ni entrées en double.
- Améliorer les annonces localisées et les comparaisons de quêtes, notamment les limites de charge utile, le rythme, les nouvelles tentatives, l’annulation et le signalement de la possibilité de partage.
- Respecter les échecs de points de passage natifs sans suivre un ancien repère. Refuser les clics restreints pendant la désactivation au lieu de perdre le travail en file d’attente.
- Faire des tests de bulles des aperçus locaux et accepter les noms Forever complets ou les noms entre guillemets, tout en préservant l’identité exacte du joueur.
- Corriger l’activation/désactivation et la gestion des profils, l’ouverture du mode Édition de l’ATH, les emotes de célébration approuvées et les diagnostics.
- Renforcer l’isolation des tests sûrs pour le client réel et la couverture de régression, corriger les hypothèses de test erronées et faire propager les échecs de syntaxe Lua par la CI.
- Validation : 516 tests réussissent dans l’ordre normal et inverse sous Lua 5.1 et 5.2. Les six profils d’API client, les vérifications de syntaxe, la vérification exacte de libchev et les contrôles de diff réussissent. Le rendu sur client réel, la distribution entre deux clients et la validation du taint au niveau du moteur restent séparés.

## 5.9.0

Célébrez vos propres montées de niveau et celles des joueurs QuestTogether proches avec des emotes synchronisées. Ajoutez des options d’emotes de montée de niveau séparées, activées par défaut, à côté des réglages d’emote de fin de quête dans Divers. Les réactions à proximité respectent les règles existantes de portée des joueurs et de proximité.

### Changements de cette version

- Mémoriser la fin confirmée des objectifs de quête par type de créature ainsi que par apparition individuelle. Les monstres qui apparaissent pendant le combat restent non marqués lorsque les données d’infobulle sont indisponibles, même si une ancienne apparition avait été mise en cache comme nécessaire. Les nouveaux objectifs inachevés peuvent rétablir la mise en évidence ; les changements d’état de quête effacent la mémoire d’achèvement. Les données d’infobulle partielles ou inaccessibles ne sont jamais considérées comme la preuve que tout le monde a terminé.
- Effacer immédiatement les icônes de quête et la teinte de santé des barres d’info lorsque le tag d’un monstre est refusé, y compris en combat. Écouter les changements de propriétaire et revérifier les tags lors des mises à jour de santé et de menace.
- Détecter les nouveaux monstres de quête rencontrés pendant le combat ordinaire en extérieur à l’aide de données lisibles de l’infobulle d’unité. Actualiser les barres d’info lorsqu’elles reviennent de derrière la caméra, deviennent votre cible ou sont survolées par la souris. Réessayer les cadres, GUID et lignes de quête d’infobulle retardés avec un budget borné par unité, annuler le travail obsolète lorsque les unités sont supprimées, et restaurer la teinte et l’icône ensemble. Préserver les protections de carte, d’instance, de données inaccessibles et de cadres protégés ; la découverte en combat n’invoque pas Questie ni l’interface d’infobulle cachée.
- Validation : 374 tests hors ligne réussissent dans l’ordre normal et inverse sous Lua 5.1 et 5.2. Les six profils d’API client, les vérifications de syntaxe Lua, la vérification exacte de la bibliothèque et les contrôles de diff réussissent. Les régressions du cache d’achèvement ont reproduit le bug avant la correction. Le jeu en direct et la validation du taint au niveau du moteur restent séparés.

## 5.8.6

Renforcer les noms de personnages, noms de classes, titres de quêtes et couleurs de classe personnalisées contre les valeurs d’API inaccessibles ou mal formées. Valider les données d’intégration optionnelles de TomTom et Questie avant de les utiliser, et arrêter de lire les lignes d’infobulle Questie aux données inaccessibles. Normaliser la visibilité des bulles et l’état du mode édition en booléens avant de les transmettre aux contrôles d’interface.

### Changements de cette version

- Consolider le gestionnaire d’événements de l’écran de chargement, supprimer les arguments privés inutilisés et une branche d’énumération de restriction inutilisée, et clarifier la gestion des callbacks et des valeurs de retour. Conserver les solutions de repli des clients modernes/anciens et la révision exacte de la bibliothèque privée intacte.
- Validation : 336 tests réussissent dans l’ordre normal et inverse sous Lua 5.1 et 5.2, avec des vérifications d’adaptateurs étendues sur six profils client. Les nouvelles régressions échouent avec l’implémentation précédente. L’analyse Lua, la vérification exacte de la bibliothèque et les contrôles de diff réussissent. Les diagnostics restants de l’API WoW Ketho/LuaLS ont été examinés, y compris une passe séparée sans mocks de client hors ligne ; les constats conservés ont des raisons spécifiques de compatibilité, de garde, de callback, de bibliothèque ou de fixture. La validation du gameplay Retail et Forever en direct reste séparée.

## 5.8.5

Corriger la découverte des tâches/expéditions sur la carte des clients modernes en lisant questID depuis C_TaskQuest.GetQuestsOnMap, tout en conservant l’ancienne API et le champ questId pour les clients plus anciens. Privilégier C_ChatInfo.PerformEmote afin que les emotes de fin fonctionnent lorsque les variables globales obsolètes sont désactivées ; gérer en toute sécurité les API d’emote manquantes ou défaillantes.

### Changements de cette version

- Supprimer un calcul d’empreinte de composition de groupe inutilisé et des variables locales inutilisées. Étendre les vérifications hors ligne des clients pour couvrir les API modernes et anciennes de tâches/emotes, la priorité des API, les données de quêtes inaccessibles et les API manquantes/défaillantes. Validation : 334 tests réussissent dans l’ordre normal et inverse sous Lua 5.1 et 5.2, plus les vérifications d’API étendues sur six profils client, l’analyse Lua et la vérification exacte de la bibliothèque. La validation du gameplay dans Retail et Forever reste séparée des vérifications hors ligne.

## 5.8.4

Entretien du dépôt : garder les notes de développement locales hors du code source suivi et des paquets de version. Le comportement en jeu est inchangé.

### Changements de cette version

- Entretien du dépôt : garder les notes de développement locales hors du code source suivi et des paquets de version. Le comportement en jeu est inchangé.

## 5.8.3

Annoncer la version installée, les clients pris en charge et la commande des réglages une fois par connexion ou rechargement de l’interface. Inclure des liens de retour CurseForge et GitHub propres à l’addon ; cliquer sur un lien ouvre une fenêtre de copie de style natif. Partager le comportement des messages et l’interface de copie sûre via libchev 1.2.0 privée. Si l’enregistrement des liens ou la fenêtre de copie est indisponible, afficher l’URL complète dans la discussion. Un assistant de bienvenue indisponible ne peut pas interrompre le démarrage normal de l’addon.

### Changements de cette version

- Validation : 334 tests réussissent dans les deux ordres sous Lua 5.1 et 5.2, avec les vérifications d’API client, l’analyse Lua et la vérification exacte du fournisseur de bibliothèque. Les simulations rapides NoPoizen exercent les deux liens de retour sur les sept profils client/règles. Le rendu en direct reste une vérification séparée.

## 5.8.2

Isoler les recherches de GUID des fixtures de test des joueurs à proximité. Corriger deux faux échecs dans /qt test lorsqu’une unité réelle occupe le jeton de barre d’info utilisé par les vérifications d’infobulle et d’icône en cache. Le comportement des barres d’info en jeu est inchangé.

### Changements de cette version

- L’environnement hors ligne inclut désormais cette collision de jeton et reproduit les deux échecs sans la correction de fixture. Les 333 tests réussissent dans les deux ordres sous Lua 5.1 et 5.2 après la correction ; six profils d’API client réussissent également. La confirmation en jeu reste séparée.

## 5.8.1

Afficher le marqueur de quête de Blizzard à côté de QuestTogether dans la liste des AddOns au lieu du point d’interrogation par défaut.

### Changements de cette version

- Afficher le marqueur de quête de Blizzard à côté de QuestTogether dans la liste des AddOns au lieu du point d’interrogation par défaut.

## 5.8.0

Prendre en charge les clients Classic actuels avec des charges utiles d’acceptation de quête correctes, des solutions de repli d’API d’objectifs protégées, une possibilité de partage inconnue signalée honnêtement, des métadonnées d’ambiance et des vérifications de régression d’API sur six clients. Préserver le comportement Retail/Forever et les utilitaires de débogage partagés.

### Changements de cette version

- Validation : 333 tests réussissent dans les deux ordres sous Lua 5.1 et 5.2, avec six profils client, l’analyse Lua et les vérifications exactes du fournisseur de bibliothèque privée. Les vérifications rapides de client NoPoizen et la vérification des paquets réussissent également. La validation en direct des nouveaux adaptateurs reste en attente.
- Consultez CLIENT_COMPATIBILITY.md pour les preuves sources, la portée et les limites de validation.

## 5.7.7

Garder les consoles de débogage superposées et leurs contrôles dans un seul groupe d’empilement natif grâce à libchev 1.1.3 privée. Les menus de catégories restent avec leur console propriétaire.

### Changements de cette version

- Placer par défaut les icônes d’objectifs de quête à gauche de la barre d’info. Les positions d’icônes enregistrées existantes restent inchangées.
- Respecter le réglage “My Last Name” de Forever lors de l’affichage du nom de votre personnage. Garder les noms de famille des autres joueurs visibles, conformément à la portée du réglage natif. Utiliser systématiquement les noms complets pour les communications, l’appartenance au groupe, la correspondance des barres d’info et les actions sociales, tout en préservant les clés existantes de profil et de position de bulle personnelle.
- Corriger les annonces de quêtes locales en double causées par la réception de votre propre message de canal sous un format de nom complet différent. La couverture de régression teste l’annonce locale suivie de ses échos de canal et de groupe, y compris un autre personnage ayant le même prénom.
- Validation : 331 tests réussissent dans les deux ordres sous Lua 5.1/5.2. La confirmation en direct du nouveau réglage par défaut des icônes et de l’interaction entre plusieurs fenêtres reste séparée.

## 5.7.6

Utilise la même console de débogage privée libchev 1.1.2 pour les trois addons, avec filtres de catégorie/recherche, contrôles de copie, résultats de tests, rapports de diagnostic, horodatages lorsqu’ils sont disponibles, et un seul résumé final des tests. Corrige les éléments graphiques de cadre natifs étirés avec des limites de texture explicites.

### Changements de cette version

- QuestTogether fournit ses propres diagnostics de quêtes et tests isolés, tandis que la bibliothèque partagée gère la console et le comportement de débogage générique. Exécutez /qt test, /qt debug ou /qt diagnostics.
- Validation : 324 tests réussissent dans les deux ordres sous Lua 5.1/5.2. L’utilisateur a confirmé en jeu l’apparence corrigée des cadres. La validation des autres restrictions en conditions réelles et du gameplay reste distincte.

## 5.7.6-beta.3

QuestTogether 5.7.6-beta.3 met à jour la console de débogage partagée intégrée vers libchev 1.1.1.

### Changements de cette version

- Restaure l’apparence de fenêtre native de style WoW dans la console partagée des addons.
- Supprime la ligne de résumé de tests en double tout en conservant le résumé final dans l’historique limité.
- Conserve la recherche, les catégories, la copie, le défilement, les tests, les diagnostics et les protections contre les restrictions déjà en place.
- L’utilisateur a signalé que les 324 tests de QT réussissaient dans Forever 1.60.1 build 70009 sur beta.2. Les sept fichiers de test de QT chargés en jeu ont aussi été audités pour détecter toute arithmétique invalide ; aucun cas générant NaN ni division par zéro n’a été trouvé. Ce résultat de test en conditions réelles antérieur ne valide pas ce nouveau changement d’apparence.
- Après /reload, ouvrez /qtd, exécutez /qt test, puis vérifiez l’apparence de la fenêtre et le résumé unique. Le rendu en conditions réelles et le comportement des restrictions/taint de cette révision doivent encore être vérifiés côté client.
- Validation : les 324 cas réussissent en ordre normal/inverse sur de vrais Lua 5.1.5 et 5.2.4, chaque exécution CLI émet un seul résumé, et le ZIP installable extrait de 26 fichiers réussit sur les deux versions. Les 23 fichiers Lua s’analysent correctement ; les 22 entrées TOC et le manifeste vendeur sont vérifiés. Les vérifications de formatage et de diff réussissent. Version épinglée de la bibliothèque : 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. Aucune CI GitHub de QT n’est configurée ; la CI de la bibliothèque amont a réussi.

## 5.7.6-beta.2

QuestTogether 5.7.6-beta.2 remplace sa fenêtre de débogage séparée par la console partagée libchev v1.1 utilisée par les addons. La bibliothèque intégrée est incluse ; aucune installation séparée n’est requise.

### Changements de cette version

- Filtrage partagé par catégorie, recherche approximative/entre guillemets, copie/sélection, effacement, rechargement, tests, diagnostics et comportement de suivi du défilement.
- /qt test ouvre les résultats actuels ; les exécutions répétées remplacent l’ancien historique TEST et effacent les filtres de recherche obsolètes.
- /qt diagnostics [questID] et /qt diag [questID] régénèrent le rapport actuel en cache dans la même console, en conservant les événements récents dans la limite du budget d’export partagé.
- Les protections partagées de restriction et de cadres possédés remplacent les anciens rappels de console et l’implémentation de menu déroulant de QT.
- L’état des quêtes, les annonces, les barres de nom, les communications et l’isolation des tests propre à QT restent gérés par QuestTogether.
- Il s’agit d’une version bêta. Le rendu en conditions réelles Retail/Forever et le comportement de taint doivent encore être vérifiés. Après /reload, exécutez /qt test et /qt diagnostics, puis testez les catégories/recherche, la copie, l’effacement, le redimensionnement, le défilement, les exécutions répétées de tests et le passage entre rapports et journaux. Incluez les transitions de combat/restrictions et votre ensemble habituel d’addons.
- Validation : 324/324 tests réussissent dans les deux ordres sous Lua 5.1.5 et 5.2.4. Les 23 fichiers Lua s’analysent correctement, les 22 entrées TOC sont validées et le manifeste de la bibliothèque épinglée est vérifié. Le ZIP installable a été extrait et a réussi les 324 cas avec le banc de test hors ligne séparé. Version épinglée de la bibliothèque : 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

QuestTogether 5.7.6-beta.1 intègre libchev v1.0.0 pour partager la journalisation, les diagnostics, les protections de rappels, les mécanismes de tâches différées et l’exécution des tests avec les autres addons Together. La bibliothèque est incluse ; aucune installation d’addon séparée n’est nécessaire.

### Changements de cette version

- Les rapports de diagnostic incluent des informations communes sur le client, l’addon et la bibliothèque, et conservent les événements les plus récents lorsque la fenêtre de copie se remplit.
- Le comportement des quêtes, du groupe, des barres de nom et des restrictions reste géré par QuestTogether, avec des espaces de stockage d’exécution isolés par addon.
- Les liens de coordonnées restent utilisables lorsque QT est désactivé si les restrictions les autorisent ; les tâches d’arrière-plan en file d’attente restent en pause et les minuteries obsolètes sont supprimées.
- /qt test inclut désormais 315 cas : les 300 existants, dix vérifications de bibliothèque partagée et cinq régressions d’intégration.
- Validation : les 315 tests réussissent dans les deux ordres sous Lua 5.1.5 et 5.2.4 ; la syntaxe Lua, l’ordre de chargement TOC et le manifeste de révision/hash intégré réussissent. Source libchev intégrée : 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- Il s’agit d’une version bêta. Le rendu de l’interface Retail/Forever en conditions réelles et le comportement de taint après cette extraction doivent encore être vérifiés. Après rechargement, exécutez /qt test et /qt diagnostics, puis testez les quêtes, les bulles de progression, les barres de nom et les liens de coordonnées pendant le combat, les changements de zone, la désactivation/réactivation et le rechargement, avec vos addons habituels. La confirmation antérieure des 300 tests sur Retail s’appliquait à v5.7.5.
