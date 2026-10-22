# QuestTogether — Journal des modifications

<!-- Generated from canonical release notes; do not edit by hand. -->

## 8.0.2

Les notes de mise à jour de QuestTogether sont plus claires, et l’historique des versions retrouve une entrée manquante.

### Notes de mise à jour et historique des versions

- Les notes de mise à jour actuelles et anciennes ont été réécrites dans les dix langues prises en charge autres que l’anglais, pour une lecture plus fluide et plus claire.
- L’entrée manquante de la version 7.4.4 a été rétablie dans l’historique des versions consultable et dans les journaux des modifications.

## 8.0.1

Naviguez au clavier sans passer par un bouton supplémentaire.

### Journal de quêtes du groupe

- À l’ouverture du journal de quêtes du groupe, ou après un clic sur une quête, la liste reçoit automatiquement le focus clavier. Le bouton Clavier a été retiré. Déplacez-vous avec les flèches et appuyez sur Entrée pour afficher ou replier les objectifs.
- Tabulation permet de passer de la liste à la recherche et inversement. Depuis la liste, Échap ferme la fenêtre ; un clic à l’extérieur libère le clavier. Les mises à jour des quêtes ne reprennent pas le focus.

## 8.0.0

QuestTogether accueille les récompenses VIP.

### Une apparence VIP

- Les joueurs VIP apparaissent sur la carte sous la forme d’une étoile aux couleurs de leur classe. Une étoile dorée orne leur préfixe QT dans la discussion et leur bouton de minicarte, et leur infobulle individuelle porte la mention QuestTogether VIP. Ces récompenses sont purement visuelles : elles ne donnent aucun accès aux fonctions du développeur.

**Forever**

![Une apparence VIP — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v8.0.0/Media/ReleaseNotes/VIPCosmetics.png)

### Comment devenir VIP

- Partagez le lien de téléchargement de QuestTogether avec vos amis, votre guilde, sur un serveur Discord approprié ou sur les réseaux sociaux. Faites une capture de votre message envoyé ou de votre publication : le lien QT et l’endroit où vous l’avez partagé doivent être visibles. Envoyez cette capture en message privé sur Discord à @chevcast pour validation. Rejoignez d’abord le serveur Discord de QT ou envoyez une demande d’ami à @chevcast pour pouvoir lui écrire. La fenêtre VIP contient le lien à copier et les étapes d’activation à suivre après son accord.

### Activer votre récompense

- Ouvrez la fenêtre VIP depuis le menu de la minicarte, les paramètres ou /qt vip. Attendez que @chevcast confirme l’attribution du statut VIP à votre compte Discord : la commande Discord /qt claim ne fonctionne qu’une fois cette attribution effectuée.

Copiez ensuite votre code de demande avec Ctrl+C et envoyez-le à @chevcast, ou utilisez /qt claim sur le serveur Discord de QT. Collez le code d’activation privé reçu dans la fenêtre VIP, puis choisissez Activer VIP. Vous pouvez refaire la procédure sur Retail ou Forever pour y utiliser la même récompense.

### Une récompense permanente, un affichage facultatif

- La récompense est liée à votre compte Discord et s’applique à tous les personnages d’une même installation. Récupérez-la séparément sur Retail et Forever. Vous pouvez désactiver Afficher mes éléments visuels VIP pour garder la récompense sans la montrer. Les boutons de minicarte standard, VIP et développeur ont désormais une bordure dorée qui épouse la forme de leur icône. L’apparence développeur reste prioritaire sur l’apparence VIP.

## 7.4.4

Retrouvez une mise à jour et tous ses correctifs sur la même page.

### Historique regroupé

- La fenêtre des notes rassemble désormais chaque version mineure et ses correctifs sur une seule page. La version mineure apparaît en premier, suivie des correctifs dans l’ordre, chacun sous un titre indiquant sa version et sa date. La navigation dans l’historique passe d’une page regroupée à l’autre.
- Les anciennes notes de correctifs ont été allégées pour ne décrire que leurs propres changements, sans répéter les guides, astuces ou captures de la version précédente. Une mise à jour contenant seulement des correctifs n’ouvre toujours pas la fenêtre automatiquement ; vous pouvez la consulter à tout moment avec /qt notes.

## 7.4.3

Des noms et des réglages plus clairs pour les quêtes en groupe.

### Quêtes en groupe

- Suivi de quête prend le nom de Suivi des objectifs du groupe (Party Objective Tracker, ou POT). Vos réglages d’affichage et la position de la fenêtre sont conservés.
- La commande /qt pql ouvre le journal de quêtes du groupe. /qt compare reste utilisable comme alias ; l’aide et les astuces indiquent désormais /qt pql.
- Masquer hors groupe est accessible à la fois en mode Édition de l’ATH et dans Paramètres > Groupes et partage > Suivi des objectifs du groupe. Les deux cases règlent la même option. Elle est activée pour les nouveaux profils et lors d’une réinitialisation aux valeurs par défaut ; vos choix déjà enregistrés sont conservés.

## 7.4.2

Correction de l’affichage des notes de version.

### Texte des notes de version

- Les séparateurs que la police ne pouvait pas afficher ont été remplacés par du texte simple. Ils n’apparaissent donc plus sous forme de cases vides.

## 7.4.1

Corrections et réglages de disposition du suivi des objectifs du groupe.

### Suivi des objectifs du groupe

- Sur Forever, certains objectifs à une seule étape, comme Use Walk on Air, affichaient 1/1 avant même d’être accomplis. Ce problème est corrigé dans le suivi des objectifs du groupe et le journal de quêtes du groupe.

### Choisir quand afficher le suivi

- L’option Masquer hors groupe, dans le mode Édition de l’ATH, permet de cacher le suivi quand vous jouez en solo. Elle est désactivée par défaut ; l’aperçu de placement reste accessible en mode Édition.

### Adapter la fenêtre à votre interface

- L’option Aligner sur le suivi des objectifs de Blizzard est activée par défaut : la fenêtre QT se place contre son bord extérieur. Si vous la déplacez, l’alignement se désactive et le redimensionnement par les coins devient disponible. Réactiver cette option réinitialise sa position. Les curseurs de largeur et de hauteur maximale restent utilisables dans les deux modes.
- La fenêtre adapte sa hauteur au contenu, jusqu’à la limite que vous avez réglée ; au-delà, le contenu défile. La hauteur maximale par défaut passe à 600. Les dimensions déjà enregistrées sont conservées.
- Le fond aux couleurs des classes garde une opacité constante de 25 % dans chaque section de joueur, quel que soit le réglage du fond de la fenêtre.

## 7.4.0

Gardez la progression de votre groupe à portée de vue avec le suivi des objectifs du groupe.

### Suivi des objectifs du groupe

- Une petite fenêtre aux couleurs des classes présente les compteurs d’objectifs et les barres de progression de votre groupe. Les autres membres doivent utiliser QuestTogether pour transmettre leur progression.
- Les valeurs s’actualisent dès réception des annonces du groupe, même si vous avez désactivé leur affichage dans la discussion ou les bulles. Lorsqu’une quête n’a pas de compteur d’objectifs, la fenêtre indique son état, par exemple si elle est prête à être rendue.

**Forever**

![Suivi des objectifs du groupe — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTracker.png)

### Choisir la quête affichée

- Quatre modes sont proposés : Masqué, Quête ciblée, Quête survolée et Ciblage et survol. Ce dernier est sélectionné par défaut : le suivi affiche temporairement la quête survolée dans le suivi des objectifs de Blizzard, puis revient à votre quête ciblée.
- Si aucune quête ne correspond au mode choisi, la fenêtre reste masquée. Vous pouvez changer de mode dans le mode Édition de l’ATH ou dans les paramètres, sous Groupes et partage > Suivi des objectifs du groupe.

**Forever**

![Choisir la quête affichée — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTrackerDisplay.png)

### Adapter la fenêtre à votre interface

- Dans le mode Édition de l’ATH, sélectionnez le suivi des objectifs du groupe pour le déplacer, le redimensionner ou régler l’opacité de son fond. Les boutons Enregistrer les modifications, Annuler les modifications et Rétablir les valeurs par défaut prennent en compte à la fois sa disposition et son mode d’affichage.
- Les sections des joueurs occupent toute la largeur disponible et leur contenu défile si nécessaire. Les thèmes clair et sombre sont pris en charge ; même avec une opacité nulle, le texte reste lisible et un fond discret distingue les joueurs.

**Forever**

![Adapter la fenêtre à votre interface — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTrackerEditMode.png)

## 7.3.5

Des repères plus lisibles, une navigation plus directe et des informations de groupe plus fraîches.

### Carte et informations des joueurs

- Survolez le bouton QT de la carte pour consulter une légende illustrée des icônes et de leurs états.
- Sur la carte du monde, un clic gauche sur le point d’un joueur le met en évidence et ouvre la carte la plus détaillée disponible pour sa position. Une fois ce dernier niveau atteint, le clic gauche ouvre son menu. Le clic droit ouvre toujours ce menu.
- Rechercher sur la carte ouvre également la carte la plus précise disponible. La lueur verte reste sur le joueur lorsque vous changez de carte ; elle disparaît au bout d’une minute, à la fermeture de la carte ou dès que vous sélectionnez un autre joueur.
- Survoler un joueur, un regroupement ou un repère partagé assombrit la carte et les marqueurs sans rapport avec la sélection, tout en gardant les marqueurs concernés bien visibles. Le survol du bouton QT n’assombrit plus la carte.
- Les différentes lueurs des joueurs utilisent désormais le même effet visuel. Les infobulles et les regroupements exploitent des informations de groupe plus récentes et récupèrent mieux les réponses retardées.
- Les diagnostics destinés au développeur ont été améliorés. Vos préférences de partage des diagnostics et la confidentialité de votre position publique restent respectées.

## 7.3.4

Des infobulles plus claires et des indicateurs QuestTogether plus cohérents.

### Infobulles des joueurs et discussion

- Les listes de membres du groupe affichent l’icône QT dès que des données de position valides permettent de reconnaître un utilisateur de l’addon, y compris après un rechargement de l’interface.
- Les listes de membres, dans les groupes comme dans les regroupements sur la carte, conservent des indicateurs compacts. Pour lire les explications du statut de développeur ou d’une position masquée, il faut survoler directement le joueur concerné. Les indicateurs de position masquée restent réservés au développeur.
- Les annonces du développeur authentifié portent une icône associant un parchemin à une roue dentée. Elle s’entoure d’une lueur dorée lorsqu’il recherche des partenaires de quête.

## 7.3.3

Des infobulles de regroupement plus sobres.

### Joueurs sur la carte

- Dans un regroupement de joueurs, le développeur de QuestTogether est représenté par une roue dentée de la couleur de sa classe, sans mention supplémentaire. Le texte qui explique ce statut reste dans son infobulle individuelle.

## 7.3.2

Les informations de groupe sont plus cohérentes et la navigation sur les cartes plus précise.

### Cartes des joueurs

- Infobulles individuelles, regroupements et mise en évidence des compagnons partagent désormais les mêmes informations connues sur les groupes. Cela réduit les chargements répétés et les compositions contradictoires.
- Les infobulles de regroupement affichent l’effectif total du groupe à côté de son icône blanche.
- Depuis la carte du monde entier, un clic ouvre maintenant la carte la plus détaillée contenant tous les joueurs du regroupement, puis le déplie si nécessaire.

## 7.3.1

Les regroupements expliquent mieux les groupes, et le bouton de carte reste facile à retrouver.

### Cartes des joueurs

- Dans l’infobulle d’un regroupement, les joueurs du même groupe connu sont entourés d’un cadre blanc arrondi avec une icône de groupe. Un joueur dont les compagnons sont ailleurs garde cet indicateur.
- Lorsque les marqueurs QT sont masqués, le bouton de la carte reste pleinement visible avec une croix rouge.
- Son survol n’assombrit plus la carte lorsque les marqueurs sont masqués.

## 7.3.0

Retrouvez les joueurs sur les cartes chargées, renouez avec d’anciens compagnons et suivez la progression avec moins d’annonces répétées.

### Cartes des joueurs

- Les points qui se superposent sur la carte du monde se regroupent. Cette fonction est activée par défaut et peut être coupée dans les réglages de position.
- Cliquez sur un regroupement pour ouvrir la carte la plus détaillée contenant tous ses joueurs. S’il reste groupé, il se déplie en points individuels avec infobulles et menus ; la molette permet de parcourir les ensembles plus importants.
- Le bouton QT en haut à droite affiche ou masque les joueurs et points de passage partagés. Son survol assombrit la carte derrière eux. Ni la minicarte ni le partage de position ne changent.
- L’action pour trouver un joueur sur la carte ouvre sa position partagée récente et met son point en évidence.

### Compagnons récents

- Ouvrez /qt companions ou le menu de minicarte pour consulter l’historique privé de vos anciens groupes. Les menus des joueurs permettent de chuchoter, inviter ou prendre une note.
- L’historique est commun à vos personnages sur le même client et royaume. Il garde jusqu’à 100 compagnons pendant 90 jours ; vous pouvez retirer des entrées ou tout effacer.

### Progression et détails des joueurs

- Les mises à jour rapides d’un même objectif sont regroupées en une annonce avec le dernier progrès. La fin d’un objectif est toujours annoncée rapidement.
- Les développeurs QuestTogether authentifiés par signature ont un marqueur en forme d’engrenage, coloré par classe, et une mention dans les infobulles. Les listes des regroupements utilisent les mêmes couleurs de classe, logos QT et statuts de recherche que les listes de groupe.

## 7.2.1

Corrections des notes privées et des colonnes repliées du journal de groupe.

### Corrections et présentation

- Le curseur de saisie réapparaît dans les notes privées et le cadre signalant le champ actif est plus discret.
- Le défilement pendant l’édition des notes longues est amélioré.
- Les colonnes repliées utilisent des icônes fiables pour les quêtes prêtes ou terminées, au lieu de caractères qui pouvaient apparaître comme des carrés vides.

## 7.2.0

Gardez des notes privées sur les joueurs et profitez d’un journal de groupe plus pratique.

### Notes privées sur les joueurs

- Depuis le menu QT d’un joueur, ajoutez, modifiez ou supprimez une note. Elle apparaît lorsque vous survolez ce joueur.
- Les notes sont communes à vos personnages et restent sur votre ordinateur. Elles ne sont jamais envoyées à d’autres joueurs ni incluses dans les diagnostics.

### Améliorations du journal de groupe

- Repliez les colonnes individuelles pour gagner de la place, puis rouvrez-les quand les détails vous sont utiles.
- Le bouton Clavier active la navigation dans les quêtes avec les flèches. Entrée déplie les objectifs, Espace ouvre les actions de quête et Échap rend les commandes habituelles.
- Les quêtes terminées se distinguent des quêtes absentes si l’addon à jour de l’autre joueur peut confirmer son historique. Sinon, elles restent indiquées comme absentes du journal.
- Les explications de partage précisent pourquoi une demande n’a pas abouti. Les infobulles de joueurs montrent aussi les résultats récents de partage signalés par WoW.

### Astuces et infobulles

- De nombreuses astuces dans le chat proposent des raccourcis cliquables vers la fenêtre ou le réglage concerné.
- Survoler un joueur éloigné demande des informations fraîches et la liste complète de son petit groupe, avec de nouvelles tentatives tant que le survol continue.

> <img src="https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.2.0/Media/QuestTogetherTipIcon.png" width="20" height="20" alt=""> Astuce : Tapez /qt tip ou /qt hint, puis utilisez les raccourcis cliquables de l’astuce pour découvrir QuestTogether.

## 7.1.3

Les textes de quête disponibles dans votre langue sont récupérés plus sûrement.

### Textes des quêtes

- Annonces, journal de groupe et messages de suivi retrouvent mieux les titres locaux disponibles.
- Les mises à jour restent dans l’ordre pendant le chargement des titres. La fenêtre de détails récupère aussi correctement le texte d’infobulle arrivé tardivement.
- La gestion des noms de quêtes reçus d’autres joueurs est améliorée.

## 7.1.2

Choisissez si vous souhaitez une astuce au démarrage et retrouvez des réglages simplifiés.

### Astuces QuestTogether

- Les options générales de la page principale permettent de désactiver les astuces automatiques. /qt tip et /qt hint restent disponibles.
- La page principale des réglages est allégée et le choix du thème clair ou sombre utilise désormais une liste déroulante.

## 7.1.1

Les astuces ont une icône et des couleurs plus lisibles.

### Astuces QuestTogether

- Une icône QT avec une ampoule remplace l’emoji non pris en charge. Le libellé est doré et le texte de l’astuce couleur crème.

## 7.1.0

Découvrez les fonctions de QuestTogether grâce à des astuces.

### Astuces QuestTogether

- QT affiche une astuce à la connexion ou au rechargement de l’interface. Elles sont tirées d’une liste mélangée, sans répétition avant d’en avoir fait le tour.

> 💡 Astuce : Tapez /qt tip ou /qt hint pour afficher une autre astuce QuestTogether quand vous le souhaitez.

## 7.0.2

Quelques améliorations pour consulter les quêtes et utiliser les diagnostics facultatifs.

### Améliorations

- Une fenêtre de détails permet de lire les textes de quête disponibles.
- Les diagnostics facultatifs du développeur et la fiabilité des échanges sont améliorés. Votre choix de partage diagnostique reste respecté.

## 7.0.1

Les contrôles QuestTogether se rapprochent de l’interface actuelle de Blizzard.

### Contrôles de style Blizzard

- Les curseurs des réglages ont des flèches pour les ajustements fins et affichent leur valeur à côté de la piste.
- Cases à cocher, couleurs, barres de défilement et boutons standard adoptent l’apparence actuelle de Blizzard.
- Les recherches du journal de groupe et du débogage disposent d’une loupe et d’un bouton d’effacement.

### Défilement

- Le défilement est amélioré dans les réglages, le journal de groupe, les notes et la fenêtre de débogage, y compris lors du redimensionnement et pour l’alignement des lignes de quêtes.
- Les flèches et le déplacement des barres de défilement natives s’arrêtent correctement à la fermeture d’une fenêtre.

## 7.0.0

Les communications de QuestTogether ont été reconstruites en préparation de la sortie de WoW Forever. Ce changement majeur de protocole exige que tous les joueurs mettent leur addon à jour ensemble.

### Important : incompatibilité avec les anciennes versions

- QuestTogether 7.x utilise un nouveau protocole et ne peut pas échanger positions, progression de quêtes, journal de groupe ou autres messages d’addon avec les versions 6.x et antérieures. Pensez à faire mettre à jour vos compagnons.

### Préparer la sortie de WoW Forever

- Nous effectuons ces changements importants, qui rompent la compatibilité, avant la sortie de WoW Forever pour donner aux communications de QT des bases plus solides.
- Après le lancement de Forever, nous veillerons davantage à préserver la compatibilité entre versions et à éviter les mises à jour obligatoires perturbant le jeu. Si une autre rupture de protocole devenait nécessaire, elle serait clairement annoncée.

### Trouver les joueurs là où vous regardez

- Les mises à jour privilégient votre zone actuelle et celle que vous gardez ouverte sur la carte. Les positions plus lointaines sont actualisées en arrière-plan.
- Les mouvements proches utilisent de petits messages ciblés. Les demandes de découverte sont regroupées et échelonnées pour limiter le trafic dans les lieux fréquentés.

### Des échanges plus fiables

- Progression, journal de groupe, détails des joueurs et diagnostics partagent une livraison à cadence contrôlée : les grosses réponses laissent de la place aux autres échanges.
- Les réponses volumineuses peuvent récupérer les morceaux manquants sans recommencer entièrement. Les positions retardées gardent leur âge d’origine et ne remplacent ni une position plus récente ni un retrait.
- Changer le partage de position annule les coordonnées publiques déjà en attente. À la déconnexion ou au chargement d’une zone, QT tente un dernier message de départ ; l’expiration reste le recours si celui-ci n’arrive pas.

## 6.5.11

De nouveaux raccourcis clavier donnent accès aux outils QT et à la recherche de compagnons.

### Raccourcis clavier

- QuestTogether apparaît correctement dans les raccourcis du jeu, à la place de l’entrée incorrecte HEADER_QUESTTOGETHER.
- Vous pouvez attribuer des touches au menu QT, au journal de groupe, à la recherche de compagnons, à l’arrêt du suivi de quête, au chat QT et aux réglages.
- Votre touche existante du journal de groupe est conservée. Les nouvelles actions n’ont aucune touche par défaut ; celle du menu fonctionne même si le bouton de minicarte est masqué.

## 6.5.10

Des actualisations plus fluides du journal de groupe, des demandes et cartes plus fiables, et des corrections pour les profils et les bulles.

### Journal de quêtes du groupe

- Avec l’actualisation automatique, une liste inchangée consomme moins de trafic. Le bouton Actualiser demande toujours une mise à jour complète.
- Les listes se rétablissent après un changement d’objectif ou l’ajout puis le retrait d’un joueur ignoré, sans conserver une progression ancienne ni rester bloquées en attente.

### Fenêtres et profils

- Changer, copier ou réinitialiser un profil applique ses dispositions enregistrées ou les valeurs par défaut. Un changement d’écran garde les fenêtres visibles sans oublier vos tailles et positions préférées.
- Fermer une confirmation de demande d’entrée ou de partage fait correctement apparaître la demande suivante.
- Ouvrir les réglages pendant le mode Édition Blizzard n’empêche plus le rétablissement de la disposition initiale de votre bulle.
- Les fenêtres d’aide ouvertes continuent à s’adapter au thème et à l’écran même si QuestTogether est désactivé.

### Suivi et communications

- Les demandes d’entrée ou de partage expirées ou devenues inutiles sont annulées avant envoi.
- Les fins d’objectifs bonus et d’expéditions gardent le bon type d’annonce même si la quête disparaît du journal avant l’événement de complétion.
- Une actualisation manuelle des positions exploite les réponses publiques d’anciens QT pour les points ordinaires, sans remplacer une position plus récente ni ignorer les choix de partage.

## 6.5.9

Les mises à jour du groupe sont plus fiables, les cartes plus propres et le masquage de l’interface avec Alt+Z conserve mieux l’état des fenêtres.

### Journal de groupe et fenêtres

- Masquer puis rétablir l’interface avec Alt+Z conserve les confirmations de changement de quête en attente et les fonds aux couleurs de classe derrière les noms.
- Les demandes du journal se remettent mieux des rechargements, écrans de chargement et pages de message perdues, au lieu de laisser un joueur bloqué en attente.
- Dispositions et bulles personnelles s’adaptent mieux aux petits écrans. Réinitialiser la disposition conserve les choix en attente dans les dialogues.

### Cartes et informations du groupe

- Les messages de position, groupe et quête active trop anciens sont refusés : une réponse retardée ne peut plus faire réapparaître un joueur parti ni écraser des données récentes.
- QT annonce son départ en quittant le monde. Si le message arrive, les autres peuvent retirer votre point plus tôt ; sinon, l’expiration habituelle s’applique. La disponibilité pour rejoindre un groupe se rétablit après les écrans de chargement.
- Votre groupe utilise les marqueurs natifs de Blizzard sans doublons QT. Le filtre de carte propose tous les joueurs QuestTogether, ceux qui cherchent des compagnons ou personne ; le partage de votre propre position reste séparé.

### Suivi et communications

- Le suivi des quêtes reprend même si le journal est incomplet à la connexion. Une succession d’événements ne repousse plus sans cesse une actualisation en attente.
- Les messages sortants partagent une file à cadence contrôlée. La vérification des demandes du développeur avance par petites étapes pour réduire les blocages d’image. Désactiver le partage diagnostique annule les tâches diagnostiques en attente.
- Les gros rapports ont plus de temps pour arriver. Les anciens demandeurs reçoivent une réponse explicite de dépassement de taille lorsqu’un rapport ne tient pas, au lieu d’attendre sans explication.

## 6.5.8

Des listes déroulantes natives, des réglages de carte plus clairs et une option de diagnostic pour le développeur.

### Réglages et cartes des joueurs

- Les neuf listes déroulantes utilisent les contrôles WoW : sélection dorée, menus noirs et boutons précédent/suivant.
- Le choix des joueurs affichés remplace les cases de visibilité et d’exception du groupe. Choisissez tous les joueurs QT, ceux qui cherchent des compagnons avec ou sans votre groupe, votre groupe seul, ou personne. Vos préférences sont conservées ; le partage de votre position reste distinct.
- Le nouveau volet Développeur rassemble l’ouverture du débogage, la relecture du journal de quêtes et le partage de diagnostics.

### Réponses de diagnostic

- Le partage de diagnostics avec le développeur est activé par défaut. Il autorise des demandes authentifiées portant sur les diagnostics QT, les réglages de l’addon et les informations en jeu du personnage, du groupe et de position, même lorsque le partage public de votre position est désactivé. Désactivez cette option dans Développeur pour arrêter ce partage.
- Les réponses passent par des chuchotements privés d’addon, découpés en pages et espacés pour préserver tous les champs des gros rapports. Les deux joueurs doivent utiliser 6.5.8 ou une version ultérieure ; les clients publiés en 6.5.7 ne savent pas répondre à ces demandes.

## 6.5.7

Ciblez un joueur depuis la minicarte et distinguez mieux les icônes du groupe.

### Points et icônes de groupe

- Hors combat, un clic gauche sur un point de minicarte cible le joueur lorsque le jeu le permet. Le clic droit ouvre toujours le menu, dont la première action est le ciblage. Les menus de la carte du monde ne changent pas.
- Les icônes de recherche de compagnons ont un contour doré nettement renforcé. Les listes de groupe dans les infobulles montrent aussi le logo lumineux des membres qui cherchent actuellement des compagnons.
- Les symboles de quête active du journal de groupe sont dessinés sur leur propre couche au premier plan pour ne plus être recouverts par le fond des boutons.

## 6.5.6

Repérez dans le journal les joueurs qui cherchent des compagnons.

### Recherche de compagnons

- L’icône de recherche reçoit un contour doré plus vif et une lueur plus forte, plus lisibles en petit dans le journal.
- Le logo QT en début de message brille désormais lorsque son auteur cherche des compagnons. Les icônes propres aux quêtes et les bulles de dialogue gardent leur aspect.

## 6.5.5

Correction d’icônes de quête absentes du journal de groupe.

### Icônes des quêtes

- Après un défilement ou une actualisation, certains boutons de quête pouvaient devenir des cercles vides. Les boutons réutilisés réinitialisent maintenant leur image et utilisent une icône de secours si l’image demandée ne peut pas être appliquée.

## 6.5.3

Trois rubriques illustrées complètent le guide du journal de groupe. Le fonctionnement ne change pas ; les captures montrent des compagnons simulés sur Forever.

### Le groupe en un coup d’œil

- Une capture d’ensemble du journal de groupe a été ajoutée au guide.

**Forever**

![Le groupe en un coup d’œil — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestOverviewForever.png)

### Choisir une quête ou suivre un compagnon

- Une capture présente les commandes de suivi des quêtes.

**Forever**

![Choisir une quête ou suivre un compagnon — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestFollowingForever.png)

### Confirmer un changement de quête

- Une capture illustre la confirmation avant de changer de quête active.

**Forever**

![Confirmer un changement de quête — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestFocusWarningForever.png)

## 6.5.2

Correction du suivi après un aperçu.

### Essayer avec vos quêtes

- Fermer l’aperçu du journal de groupe reprend désormais le suivi déjà actif dans votre vrai groupe.

## 6.5.1

Des boutons de quête plus lisibles, une confirmation avant de quitter un suivi et des icônes cohérentes avec le suivi natif de WoW.

### Lire les choix de quête

- Pendant un suivi, seul le bouton de la quête active du compagnon suivi reste coloré. Sinon, vos boutons et les quêtes actives des autres sont colorés. Les autres boutons sont gris, sans atténuation. Les quêtes actives des compagnons restent cliquables pour démarrer ou changer le suivi.

### Confirmer un changement

- Choisir votre quête ou un autre compagnon demande confirmation avant d’arrêter le suivi actuel. Changer ou effacer la quête dans le suivi Blizzard fait de même : QT rétablit la quête suivie pendant votre décision. Annuler poursuit le suivi ; changer applique votre choix. /qt preview unfollow permet de voir le dialogue.

### Des icônes assorties à WoW

- L’état de remise utilise la même vérification que le suivi Blizzard. Les quêtes de livraison qui avaient une icône de progression affichent ainsi correctement un point d’interrogation. L’état prêt corrigé est aussi transmis dans les relevés du journal de groupe.

### Essayer avec vos quêtes

- L’aperçu de comparaison utilise votre vrai journal, quatre compagnons simulés et des quêtes supplémentaires absentes de votre journal. Les boutons changent réellement la navigation Blizzard ; le partage reste simulé. Le menu d’un compagnon fait avancer sa quête active. Les quêtes non partageables affichent une mention centrée de non-partage ou d’état inconnu au lieu d’une colonne d’action vide.

## 6.5.0

Choisissez la quête active depuis le journal de groupe et conservez le suivi d’un compagnon après un rechargement.

### Boutons de quête active

- Des boutons de style Blizzard apparaissent dans chaque colonne, à la place des titres de quêtes actives dans les en-têtes. Cliquez dans votre colonne pour changer votre quête suivie en priorité. Les boutons sélectionnés indiquent le choix des compagnons ; cliquez dessus pour les suivre.

### Un suivi qui dure

- Le compagnon suivi est enregistré par personnage et conservé après rechargement ou pendant une interruption temporaire des données. Les nouvelles informations du groupe ajustent votre quête si vous la possédez. Choisir votre propre navigation arrête le suivi, tout comme le départ du compagnon, la dissolution du groupe ou sa conversion en raid.

### Si vous ne possédez pas la quête

- Si le compagnon choisit une quête absente de votre journal, le suivi s’arrête sans changer votre navigation. Un dialogue au thème QT explique la situation et ouvre le journal de groupe pour demander la quête puis reprendre le suivi. /qt preview focus montre ce dialogue ; /qt preview compare permet d’essayer les boutons et des changements simulés.

## 6.4.3

Corrections de la quête active et des infobulles de groupe, avec un réglage de carte simplifié.

### Votre quête active

- Votre en-tête du journal de groupe lit directement votre quête active, même en solo ou lorsque son partage est désactivé. Changer la quête suivie en priorité l’actualise sans devoir cliquer sur Actualiser.

### Composition du groupe dans les infobulles

- Dans un petit groupe, le joueur survolé apparaît immédiatement avec le chef pendant le chargement du reste. Le message d’attente ne s’affiche que si d’autres membres manquent encore. Au-delà de cinq membres, seul le chef reste listé.

### Réglage des cartes simplifié

- Une seule case contrôle désormais l’affichage des autres joueurs sur la carte et la minicarte. Le partage de votre position reste indépendant. Après mise à jour, l’affichage reste actif si au moins l’une des cartes l’était, et inactif si les deux étaient désactivées.

## 6.4.2

Réglez plus finement les relevés de progression, les joueurs affichés sur les cartes et l’accessibilité des fenêtres. Pour vos retours ou de l’aide, retrouvez-nous sur Discord.

### Journal de quêtes du groupe

- Les en-têtes indiquent l’ancienneté des données de chaque joueur. Leur menu permet de n’actualiser que ce joueur.
- Une option des filtres active l’actualisation automatique, environ toutes les 30 secondes tant que la véritable fenêtre est ouverte.
- Les nouvelles données conservent si possible votre recherche, les quêtes dépliées, le défilement horizontal et la quête visible.
- Les mentions de quête active distinguent attente, expiration et données non prises en charge. Si QT ne peut pas différencier absence de partage et indisponibilité, il l’indique. Le menu avertit aussi d’une boucle de suivi possible.

### Accessibilité et disposition

- Les options d’accessibilité proposent une échelle de fenêtre de 80 % à 150 % et une réduction des animations pour un défilement et une ouverture des objectifs instantanés.
- L’échelle agrandit textes et contrôles ensemble, mais peut être limitée pour garder la fenêtre entière à l’écran.
- Le journal du groupe et l’accueil enregistrent leur taille et leur position relative à l’écran par profil. Les fenêtres QT sont réajustées après un changement d’écran ou d’échelle d’interface.
- Réinitialisez les dispositions dans Accessibilité ou avec /qt resetlayout pour effacer les positions sauvegardées et recentrer les fenêtres.

### Affichage des positions

- Carte et minicarte peuvent être affichées ou masquées séparément du partage : cacher vos points locaux ne change pas ce que vous envoyez.
- Le filtre propose tous les joueurs QT, ceux qui cherchent des compagnons ou votre groupe uniquement.
- L’affichage permanent de votre groupe est activé par défaut. Ses membres restent donc visibles avec le filtre de recherche de compagnons, si leurs autorisations de position le permettent.

### Autres améliorations

- La détection expérimentale de couche conserve ses options et son interface, mais gère mieux les demandes lorsque les indices locaux changent ou que des candidats proches doivent attendre.
- Échap ferme les dialogues QT par leur action normale. Le journal de quêtes du groupe peut recevoir une touche dans les raccourcis du jeu ; aucune n’est attribuée par défaut.
- Survolez les lignes de quêtes et d’objectifs pour lire le texte entier. Les curseurs d’échelle et de proximité ont une piste plus claire bordée de sombre.

## 6.4.1

Une détection expérimentale peut signaler qu’un joueur QT proche se trouve probablement sur une autre couche de monde.

### Détection expérimentale des couches

- Elle est activée par défaut dans les réglages expérimentaux de QuestTogether. Désactiver la détection des couches différentes arrête les comparaisons et masque les indicateurs de phase déduits.
- Dans le monde ouvert de Forever, les clients QT compatibles proches comparent leurs observations de PNJ et de joueurs visibles. Une icône de déphasage signale une différence probable ; survolez-la pour les détails. Le partage de position doit être actif.
- L’estimation peut se tromper. L’absence d’un joueur ne suffit pas à conclure ; se voir mutuellement ou voir un même joueur prend le dessus sur l’estimation fondée sur les PNJ. Les preuves anciennes s’effacent automatiquement. Les vieux clients QT ne participent pas.

### Captures des notes

- Les captures intégrées aux notes sont maintenant envoyées directement à Discord pour rester visibles dans les publications de changements.

## 6.4.0

Les fenêtres QT sont plus soignées et le journal de quêtes du groupe s’ouvre plus rapidement.

### Journal de quêtes du groupe

- Découvrez le journal introduit en 6.3 : jusqu’à cinq joueurs dans des colonnes aux couleurs de classe, les quêtes possédées ou manquantes et la disponibilité du groupe pour les rendre. Combinez recherche et filtres de possession, progression et action ; partage et demande de partage sont proposés lorsque possible.
- L’en-tête de chaque joueur montre sa quête active. Cliquez sur le nom d’un compagnon pour choisir de suivre sa quête ; si vous ne la possédez pas, votre navigation reste intacte. Actualiser demande un nouveau relevé du progrès distant. Les captures utilisent des données fictives.
- Un petit bouton en forme de livre ouvre les quêtes que vous possédez dans le journal Blizzard. Cliquer sur la ligne continue de déplier les objectifs.
- Une couronne suit le chef lors des changements de direction du groupe. Votre colonne reste la première.

**Retail**

![Journal de quêtes du groupe — Retail](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogRetail.png)

**Forever**

![Journal de quêtes du groupe — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogForever.png)

### Déplier les objectifs de chacun

- Cliquez sur une quête pour afficher quantités, barres de progression et étapes terminées de chaque membre ; plusieurs quêtes peuvent rester ouvertes. Les panneaux sont plus compacts, avec en-têtes et corps assortis aux couleurs de classe. Une quête typique de cinq joueurs avec deux objectifs chacun tient dans la fenêtre par défaut ; les quêtes longues peuvent encore nécessiter du défilement.

**Forever**

![Déplier les objectifs de chacun — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestObjectivesForever.png)

### Fenêtres et minicarte

- Clic gauche sur le bouton de minicarte : ouvrir ou fermer le journal de groupe. Clic droit : ouvrir le menu. Les réglages y sont de retour et l’infobulle explique les raccourcis.
- Rappels de chat de groupe, demandes de partage ou d’entrée, réglages de bulles et invitation Discord utilisent le cadre parchemin et les thèmes clair et sombre de QT, avec plus d’espace et de place pour les valeurs des curseurs.
- Déplacer une fenêtre conserve l’écart initial du curseur, y compris dans l’aperçu de comparaison. Menus et infobulles désignent désormais systématiquement la fenêtre Blizzard comme le journal de quêtes.

### Commandes d’aperçu

- /qt preview liste les aperçus de fenêtres et d’annonces. Les anciennes commandes fonctionnent encore ; les actions simulées n’invitent personne, ne partagent pas de quête et n’envoient pas de message.
- L’aperçu de comparaison montre cinq membres, dont un chasseur et un voleur, avec des objectifs variés, des quêtes actives et une couronne de chef.

## 6.3.1

Les objectifs du journal de quêtes du groupe sont mieux espacés.

### Espace autour des objectifs

- Une marge supplémentaire en bas des panneaux dépliés évite que les barres de progression touchent le cadre. Le défilement et les animations d’ouverture tiennent compte de cet espace.
- Les messages indiquant par exemple l’absence de détails d’objectif sont centrés verticalement à côté du nom, au lieu d’être collés au bord supérieur.

## 6.3.0

Un journal de quêtes de groupe, des destinations partagées et le suivi facultatif d’un compagnon facilitent les quêtes à plusieurs.

### Journal de quêtes du groupe

- La comparaison devient le journal de quêtes du groupe. Dépliez plusieurs quêtes à la fois pour consulter objectifs et progression de chaque membre, avec un résumé indiquant si le groupe est prêt.
- Recherchez une quête et combinez les filtres de possession, progression et partage. Actualiser demande de nouveaux relevés aux autres joueurs. Les anciens clients peuvent comparer les listes, mais ne fournissent pas les objectifs détaillés.
- La fenêtre de parchemin se redimensionne et défile de façon fluide. Colonnes aux couleurs de classe, en-têtes de joueur cliquables et espacés, et panneaux d’objectifs arrondis facilitent la lecture.

### Quête active et points de passage du groupe

- La quête active de chaque membre figure sous son nom. Choisissez de suivre sa quête depuis son en-tête ou son menu QT : seules les quêtes que vous possédez sont suivies. Une quête absente ou retirée laisse votre navigation intacte. Une navigation manuelle, quitter le groupe ou recharger l’interface met fin au suivi.
- Les points de passage Blizzard des membres apparaissent sur la carte et la minicarte à proximité, aux couleurs de classe. Les points superposés listent tous leurs propriétaires. L’action pour y naviguer utilise TomTom ou la navigation native. Recevoir un point ne change jamais votre destination et ne garantit pas une phase commune.
- Dans Groupes et partage, le partage de la quête active, celui du point de passage et l’affichage des points du groupe sont activés par défaut, indépendamment des positions publiques et de la recherche de compagnons. Le suivi reste volontaire. Ces fonctions demandent des clients à jour dans un groupe de cinq au maximum, y compris en donjon ; les raids sont exclus.

### Fenêtres et menus

- Les notes adoptent le thème parchemin sombre, avec un mode clair facultatif. Déplacez ou redimensionnez la fenêtre, parcourez des lignes d’historique plus lisibles et utilisez les flèches pour avancer, reculer ou atteindre une extrémité. Discord et les réglages figurent en bas.
- Les infobulles de joueurs épousent mieux leur contenu. Le menu de minicarte sépare les outils de quête des notes, de l’emplacement du journal et de la visibilité du bouton. Les réglages et l’envoi de chat QT quittent ce menu ; les réglages restent accessibles par /qt options.

## 6.2.3

Les annonces indiquant qu’une quête est prête à être rendue se répètent moins souvent.

### Annonce de quête prête

- Une quête déjà prête ou terminée au début du suivi est enregistrée sans annonce. Des données de disponibilité manquantes ou des actualisations ultérieures ne rejouent plus une annonce déjà observée.
- Les nouvelles fins de quête sont toujours annoncées. Accepter de nouveau une quête remet son historique d’annonces à zéro. Le joueur qui envoie doit installer cette correction ; les anciennes versions peuvent encore produire des séries d’annonces.

## 6.2.2

Les messages de progression gardent leurs détails, quelle que soit la langue.

### Conserver le texte des objectifs

- Dans le chat et les bulles, la progression des quêtes, expéditions et objectifs bonus conserve les mots et les valeurs de l’expéditeur, au lieu d’un texte générique comme « Objectif 1 : 5/5 ».
- Les annonces d’acceptation et de fin de quête continuent d’utiliser des libellés traduits et les titres locaux disponibles.

## 6.2.1

Le fonctionnement des annonces dans le chat de groupe est plus clair.

### Savoir quand QT écrit au groupe

- Le réglage des destinations indique explicitement que QT écrit aussi dans le chat lorsqu’un membre n’est pas reconnu comme utilisateur QT. Il reste activé par défaut.
- Après un court délai de découverte, un dialogue portant le logo QT vous laisse conserver l’option ou couper les annonces avant leur envoi. Le choix de ne plus rappeler enregistre votre confirmation pour le profil actuel.
- Le rappel localisé nomme les membres concernés et peut revenir si de nouveaux joueurs non identifiés rejoignent le groupe. Il disparaît lorsqu’ils sont reconnus comme utilisateurs QT. Les événements retenus pendant l’attente ne sont pas rejoués.

## 6.2.0

Les points proches se déplacent plus régulièrement, les détails des joueurs arrivent plus vite et les échanges sont plus fiables.

### Déplacement plus fluide sur la minicarte

- Les joueurs proches peuvent échanger leurs positions par chuchotements d’addon espacés. Jusqu’à quatre correspondants éligibles les plus proches sont privilégiés, dans le respect du partage, des filtres, des ignorés et des limites de trafic.
- Les deux joueurs doivent être à jour pour ces flux et les réponses directes au survol. Les anciennes versions conservent les diffusions ordinaires ; retards serveur et restrictions peuvent toujours gêner la réception.

### Découverte et composition des groupes

- Survoler un nom ou un point peut demander directement des détails frais. La fréquence des demandes est limitée et une liste de groupe inchangée n’expire plus après deux minutes.
- Les positions récentes, le statut de recherche et les groupes connus survivent à /reload jusqu’à trois minutes après leur relevé d’origine. Entrer dans une zone demande aussi une actualisation de découverte échelonnée.
- En attendant la taille exacte, les infobulles utilisent le statut solo ou groupé connu. Un petit logo indique les membres utilisant QT, sans désaligner les noms.

### Localisation et présentation

- Noms de races, détails des pings, données de quêtes et davantage de textes utilisent la langue locale lorsqu’elle est disponible. À défaut, les textes reçus restent lisibles ; les annonces de progression n’empruntent pas la description d’un autre objectif local.
- Les annonces génériques utilisent le logo QT. La recherche de compagnons devient le premier choix du menu de minicarte.

### Échanges et fiabilité

- Comparaisons, listes de groupe, demandes d’entrée et de partage, et réponses aux pings privilégient les chuchotements directs entre clients compatibles. Les signaux regroupés et la réduction des positions inchangées allègent les diffusions publiques.
- Corrections des lectures répétées de quêtes, des tentatives excessives sur les barres de nom, des dialogues impossibles à fermer sous restriction et de /qt set qui acceptait des réglages autres que des interrupteurs. Couper le partage de position ne supprime plus les demandes sans rapport dans la file.

## 6.1.2

Les points des joueurs proches sont plus réactifs et les annonces localisées plus claires.

### Points de la minicarte

- Si la minicarte ne fournit pas d’identifiant de carte, QT utilise votre carte actuelle. Cela corrige des points de joueurs absents.

### Positions locales plus fréquentes

- Avec moins de 10 utilisateurs QT connus dans la zone, les positions visent un envoi par seconde. Pour 10 à 19, l’intervalle est de 5 à 10 secondes ; à 100, de 15 à 20 secondes. Il augmente progressivement entre ces niveaux. À partir de 500, les délais ne changent pas.
- Ces envois rapides contiennent des positions compactes fraîchement relevées ; les autres renseignements gardent leur cadence plus lente. Les limites de trafic s’appliquent toujours et l’encombrement peut retarder la réception. Les autres joueurs doivent être à jour pour envoyer plus souvent.

### Annonces localisées plus claires

- Les libellés d’événement, comme l’acceptation d’une quête, utilisent votre langue même sans titre local ou métadonnées facultatives de traduction.
- Si WoW ne donne pas de titre local, QT conserve celui, lisible, de l’expéditeur. Un message de progression garde son texte d’origine lorsqu’il ne peut pas être reconstitué de façon sûre.

## 6.1.1

Les menus de joueurs et de quêtes sont allégés.

### Menus contextuels

- Le raccourci de changement de fenêtre du journal a été retiré de ces menus. Pour déplacer les messages QT entre le chat principal et une fenêtre séparée, utilisez le menu de la minicarte ou les réglages.

## 6.1.0

Repérez les groupes sur la carte, découvrez qui joue ensemble et demandez à rejoindre un groupe depuis n’importe lequel de ses membres.

### Voir les compagnons d’un joueur

- Les points des joueurs groupés portent un petit symbole de deux personnes. Survolez un membre pour entourer ses compagnons de blanc, atténuer les autres points et couronner le chef. Les lueurs dorées de recherche de compagnons restent visibles.
- Les infobulles listent les membres avec points et noms aux couleurs de classe, le chef couronné en tête. Jusqu’à cinq membres, tout le monde est listé ; pour les groupes plus grands, seul le chef apparaît. Ces détails sont aussi accessibles depuis les noms du journal QT.
- Votre groupe utilise la liste du jeu. Les détails d’un autre groupe sont demandés au besoin à des clients QT à jour, avec cache et demandes espacées pour limiter le trafic. Les anciens clients gardent leurs points et la taille de groupe de base ; les détails complets nécessitent un correspondant à jour.

### Faire parvenir une demande au chef

- Vous pouvez demander à rejoindre le groupe via un membre qui n’a pas le droit d’inviter. Si son chef utilise QT et peut inviter, la demande lui est transmise avec les règles habituelles de confirmation ou d’approbation automatique.
- Si le chef n’est pas connu comme utilisateur QT et que les annonces de groupe sont activées, le membre peut signaler dans le chat « [QT] PlayerName demande à rejoindre le groupe. ». Une personne autorisée doit ensuite envoyer l’invitation manuellement.
- Le demandeur et le membre intermédiaire doivent avoir cette mise à jour. Les contrôles de groupe complet, restrictions, ignorés, expiration et fréquence des demandes restent appliqués.

### Infobulles plus lisibles

- Le groupe apparaît juste sous niveau, race et classe, avec des lignes compactes et des sections espacées. Les emblèmes Alliance et Horde sont deux fois plus grands.
- La version de l’addon est affichée en dernier sous la forme courte vX.Y.Z. L’âge d’une position, lorsqu’il est affiché, se trouve juste au-dessus.
- Le nombre de quêtes suivies a été retiré des infobulles de joueurs et du bouton de minicarte. La quête active d’un joueur qui cherche des compagnons reste visible.

## 6.0.2

Consultez les anciens changements de QuestTogether dans votre langue. Les annonces de fin de quête retrouvent aussi plus facilement leur titre.

### Parcourir les anciennes notes

- La fenêtre propose des boutons vers les versions plus anciennes et plus récentes, un raccourci vers la dernière, et un historique avec versions et dates. Elle s’ouvre toujours sur la dernière publication.
- Toutes les publications précédentes sont incluses, même les premières bêtas, dans chaque langue de WoW prise en charge. Elles figurent aussi dans les journaux de changements du dépôt.
- Les boutons se désactivent lorsqu’aucune version ne suit dans leur direction. Parcourir l’historique ne change pas la mise à jour déjà reconnue ; seules les mises à jour majeures et mineures ouvrent automatiquement la fenêtre. Vous pouvez l’ouvrir avec /qt notes.

### Titres des quêtes terminées

- Si une quête quitte votre journal avant que QT dispose de son titre, l’annonce de fin essaie les fonctions de recherche de titre du jeu avant de se rabattre sur l’identifiant. Le titre retrouvé est conservé quel que soit l’ordre des événements de remise et de retrait.
- Si votre client ne trouve pas de titre local, le texte de l’expéditeur est conservé. Si aucun des deux clients n’a de titre, l’identifiant reste le dernier recours. L’amélioration de récupération côté expéditeur exige sa mise à jour.

## 6.0.1

Les célébrations des autres joueurs concernent désormais ceux que vous voyez réellement près de vous.

### Réactions aux joueurs proches

- Pour réagir à une fin de quête ou un passage de niveau, QT exige une unité de joueur visible et correspondant à l’expéditeur. Un nom ou des coordonnées seuls ne déclenchent plus d’emote, même avec devlogall.
- Les emotes reçues doivent appartenir à la liste de célébrations de QT. Celles qui n’y figurent pas, dont mountspecial et les cris de faction, sont ignorées sans remplacement.
- Vos propres célébrations de fin de quête et de niveau gardent leurs réglages et leur comportement.

## 6.0.0

QuestTogether prépare le lancement de Forever avec des communications conçues pour limiter le trafic de fond à mesure que la communauté grandit.

### Activité locale et découverte mondiale

- Les annonces de quêtes et les mises à jour fréquentes des joueurs passent par des canaux de zone. Les annonces destinées au groupe lui parviennent toujours au-delà des frontières de zone.
- Les points restent disponibles dans le monde entier, avec des actualisations de fond moins fréquentes. Ouvrir une autre zone sur la carte vous abonne temporairement à ses mises à jour.
- Les conversations QT restent sur le canal global QuestTogether. Votre choix de chat global ou limité à la zone continue de filtrer les messages affichés.

### Moins de trafic de fond

- Présence, version, nombre de quêtes, recherche de compagnons et position sont regroupés dans des mises à jour compactes. Leur fréquence diminue dans les zones très peuplées.
- Les annonces sont espacées et prioritaires sur les mises à jour de fond. Les réponses aux pings sont réparties pour éviter un afflux simultané. WoW peut encore retarder les messages : leur réception instantanée n’est pas garantie.
- Les infobulles indiquent l’âge des positions anciennes. Les diagnostics montrent les nombres de messages, les limitations d’envoi et les délais d’annonces mesurés par l’expéditeur.

### Un changement majeur pendant la bêta

- Cette réorganisation prépare le lancement de Forever. La bêta permet de prendre ces décisions de fond avant que davantage de joueurs ne dépendent de l’ancien fonctionnement.
- QuestTogether quitte QuestTogetherAnnounce1 et n’y envoie ni n’y reçoit plus de messages. QuestTogether sert au chat et à la découverte globale ; les canaux de zone transportent l’activité locale.
- Les canaux QT restent après vos autres canaux, avec le principal avant ceux des zones. Vos choix de partage de position, d’ignorés et d’annonces sont conservés.

### Compatibilité avec les anciennes versions

- Mettez l’addon à jour ensemble. Les anciens clients ne lisent pas les nouvelles données regroupées ni les canaux de zone : entre versions différentes, points, recherche de compagnons et annonces proches peuvent manquer.
- Les joueurs présents uniquement sur l’ancien canal ne sont plus découverts par celui-ci. Certains échanges avec les versions 5.x récentes restent possibles sur le canal global commun ou en groupe, mais cette compatibilité est partielle.
- /qt ping utilise toujours le canal global et peut y entendre d’anciens clients compatibles. Il aide à découvrir des joueurs, sans constituer un décompte exhaustif des utilisateurs QT.

## 5.17.2

Les conversations QT se distinguent plus facilement des annonces de quêtes.

### Texte blanc pour le chat QT

- Les messages des joueurs dans le chat QT sont désormais blancs dans le journal et les bulles au-dessus des personnages.
- Les noms gardent la couleur de leur classe et les annonces de quêtes restent jaunes.

## 5.17.1

Les infobulles donnent davantage d’informations sur vos compagnons et permettent de vérifier une quête directement dans le chat.

### Mieux connaître les joueurs

- Les infobulles des noms et points de carte indiquent le nombre de quêtes surveillées par QT ainsi que le statut solo ou la taille du groupe. Votre propre infobulle utilise vos données locales actuelles.
- L’infobulle de minicarte compte désormais les quêtes surveillées par QuestTogether, comme l’annonce au démarrage, plutôt que les seules quêtes épinglées dans le suivi de WoW.
- Pour les autres joueurs, ces nombres nécessitent un client à jour. Ils sont actualisés environ toutes les 80 secondes dans les messages périodiques existants, sans trafic supplémentaire. Une donnée absente ou ancienne est indiquée comme inconnue. Les anciennes versions reçoivent toujours des annonces de version compatibles.

### État d’une quête au survol

- Survolez un nom de quête dans le journal QT : près du curseur, l’infobulle présente votre état, la possibilité de partage, l’identifiant et votre progression d’objectifs suivie localement.
- L’entrée État a été retirée du menu. Le clic propose toujours le partage, l’ouverture dans le journal, la comparaison du groupe et le choix de fenêtre du journal QT.
- Les nouvelles mentions sont localisées dans toutes les langues prises en charge. Elles décrivent votre propre progression, pas l’étape atteinte par l’expéditeur.

## 5.17.0

Discutez dans le chat QT, trouvez des compagnons dans votre zone et consultez des informations de joueur plus complètes.

### Discuter avec les joueurs QuestTogether

- Tapez /qt <text> ou choisissez l’envoi d’un message QT dans le menu de la minicarte. Les conversations apparaissent dans le journal QT et les bulles des joueurs proches, avec une icône de dialogue. Les commandes existantes restent utilisables.
- Le chat global est sélectionné au départ. Vous pouvez limiter les messages à votre zone ou masquer le chat QT. Le filtre de zone exige une position récente partagée par l’expéditeur ; le chat global n’en a pas besoin.
- Pendant la transition, le nouveau canal QuestTogether fonctionne avec QuestTogetherAnnounce1. Quand le client le permet, QT place ces deux canaux après vos autres canaux, QuestTogether en premier. Les conversations saisies utilisent uniquement le nouveau canal.

### Trouver des compagnons de quête

- Activer la recherche annonce votre disponibilité dans la zone avec un logo QT doré et un sourire. Cette diffusion exige le partage de position et respecte les préférences d’annonces. Désactiver la recherche reste silencieux.
- Les réglages des événements à annoncer contrôlent ces messages. Une pause de 30 secondes limite les annonces répétées, sans retarder votre statut ni sa lueur. Une option permet d’arrêter la recherche en rejoignant un groupe ; elle est désactivée au départ.
- Maj-clic sur le bouton de minicarte active ou désactive la recherche. Un anneau doré plus lumineux et pulsant signale qu’elle est active, sans couper le logo.

### Portée et informations des joueurs

- La portée de proximité va de 5 % à toute la zone et commence à 25 %. Elle adapte la distance à la zone actuelle ; les membres du groupe et les joueurs directement visibles gardent leur fonctionnement habituel.
- Survoler un nom dans le journal QT affiche la même infobulle enrichie qu’un point de carte : nom coloré par classe, niveau, race, classe, emblème de faction, recherche de compagnons, quête suivie si connue et version QT. Les infobulles de noms apparaissent près du curseur.
- Votre propre infobulle indique la quête suivie en priorité lorsque vous cherchez des compagnons. Les clients à jour annoncent leur version environ toutes les 40 secondes dans les signaux existants ; les anciens gardent leur cadence.

### Commandes et annonces plus claires

- L’infobulle du bouton de minicarte indique version QT, statut de recherche, portée du chat, nombre de quêtes suivies, portée de proximité et partage de position.
- Les contrôles des réglages disposent d’explications traduites au survol, y compris les listes déroulantes, curseurs, actions de profil et couleurs.
- Si votre client ne retrouve pas le titre local d’une quête, journal et bulles conservent le texte de l’expéditeur plutôt qu’un numéro générique. Les annonces suivantes sont de nouveau localisées dès que le titre est disponible.

## 5.16.7

Retrouvez les mêmes notes de QuestTogether en jeu, sur Discord et dans les fichiers de changements de votre langue.

### Des notes multilingues cohérentes

- Le journal des changements anglais utilise les mêmes résumés et points que l’accueil en jeu et les annonces Discord.
- Des fichiers sont disponibles pour toutes les langues prises en charge, avec l’historique déjà traduit. Les anciennes notes anglaises rédigées à la main sont conservées séparément.
- Les contrôles de publication vérifient que ces fichiers restent synchronisés avec les notes de référence et leurs versions localisées.

## 5.16.6

Votre bouton de minicarte vous rappelle quand vous cherchez des compagnons de quête.

### Un rappel lumineux

- Lorsque la recherche est active, le bouton QT pulse avec la même lueur dorée que les logos des joueurs.
- La lueur suit votre statut et s’arrête si QT est désactivé ou si le bouton est masqué. Ni le bouton ni le logo ne changent de taille.

## 5.16.5

Les annonces de groupe deviennent plus compactes grâce à un préfixe court.

### Annonces plus courtes

- La progression envoyée aux membres du groupe sans QuestTogether commence désormais par [QT] plutôt que [QuestTogether].
- Les annonces respectent toujours la limite des messages du chat sans couper les caractères, quelle que soit la langue.

## 5.16.4

Vos réglages de bulles restent en place à la fermeture du mode Édition, et les cartes encombrées privilégient les joueurs proches.

### Conserver les réglages des bulles

- Quitter le mode Édition du HUD n’annule plus la taille du texte, la durée d’affichage ou la position de votre bulle QT.
- Le panneau de la bulle dispose de son bouton d’enregistrement et d’un message de confirmation. Les modifications s’appliquent automatiquement ; enregistrer définit le point auquel revient l’action de rétablissement.
- Si vous faites d’autres essais après l’enregistrement, rétablir les modifications retrouve vos derniers réglages QT enregistrés.

### Priorité aux joueurs proches

- Lorsque plus de 128 points peuvent apparaître sur une carte ou la minicarte, les joueurs les plus proches de votre personnage sont prioritaires.
- Quand le cache de 512 positions est plein, les joueurs proches sont conservés avant les nouvelles positions plus éloignées. Déplacer ou zoomer la carte ne change pas cette priorité.
- Ces améliorations conservent les limites de points et de cache sans envoyer de messages supplémentaires.

## 5.16.3

Les réglages sont réorganisés pour trouver plus vite une option et consulter vos préférences d’un coup d’œil.

### Des réglages regroupés par usage

- Groupes et partage remplace les réglages divers et réunit la recherche de compagnons, les demandes pour rejoindre un groupe et les autorisations de partage de quêtes.
- Les emotes de célébration se trouvent avec les destinations des annonces. La visibilité du bouton de minicarte rejoint les options générales de l’accueil ; outils de débogage et nouvelle lecture du journal sont regroupés dans le dépannage.
- La comparaison des quêtes du groupe et la recherche de compagnons arrivent en tête des actions rapides. Vos préférences existantes sont conservées.

### Un récapitulatif plus utile

- Les sections du récapitulatif montrent recherche de compagnons, partage et affichage des positions, autorisations des demandes, destinations des annonces et réglages des indicateurs de quêtes et de joueurs.
- Vous y retrouvez aussi le profil actif, la version installée et une éventuelle version plus récente détectée. Si QT est désactivé, il précise qu’il s’agit des préférences enregistrées.
- Cliquez sur un titre pour ouvrir les réglages correspondants. Le récapitulatif adapte sa hauteur au texte et se met à jour tant que la page reste ouverte.

## 5.16.2

Les infobulles permettent désormais de reconnaître les utilisateurs de QuestTogether et de repérer ceux qui cherchent des compagnons.

### Informations QT dans les infobulles

- Survolez le personnage, la barre de nom ou le cadre d’un joueur QT : l’infobulle indique qu’il utilise QuestTogether. S’il cherche des compagnons, ce statut et un logo QT lumineux apparaissent également.
- La partie QT suit la largeur et l’échelle de l’infobulle, évite sa barre de vie et passe au-dessus lorsque la place manque en dessous.

### Une lueur de recherche plus étendue

- La lueur dorée autour du logo de la barre de nom s’étend deux fois plus loin, sans agrandir le logo.
- Icônes et lueurs correspondent aux véritables utilisateurs QT et à leur statut actuel de recherche de compagnons.

## 5.16.1

Repérez plus facilement les compagnons disponibles et découvrez la quête sur laquelle ils se concentrent.

### Une lueur plus visible

- Le logo QT des joueurs qui cherchent des compagnons reçoit une lueur dorée plus vive, avec une pulsation douce. Le logo lui-même reste stable.

### Voir leur quête actuelle

- Survolez leur point sur la carte ou la minicarte pour voir leur quête suivie en priorité, celle choisie pour la navigation. Les deux joueurs doivent disposer de cette mise à jour.
- Ces informations sont actualisées environ toutes les 20 secondes et partagées uniquement lorsque la recherche de compagnons et le partage de position sont activés.
- Le titre utilise votre langue si possible, puis celui de l’expéditeur ou l’identifiant de quête. Les anciennes versions de QT conservent leurs points et indicateurs de recherche de compagnons habituels.

## 5.16.0

QuestTogether prend en charge toutes les langues de WoW et peut présenter les nouvelles de quête d’autres joueurs dans la langue de votre client.

### Toutes les langues de WoW

- Menus, réglages et notes prennent en charge l’anglais, l’allemand, le français, l’espagnol européen et latino-américain, le portugais du Brésil, le russe, l’italien, le coréen, le chinois simplifié et le chinois traditionnel.
- L’espagnol latino-américain dispose de ses propres textes au lieu de reprendre ceux d’Espagne.

### Progression localisée

- Les événements pris en charge et envoyés par un QT à jour peuvent être affichés dans votre langue dans le journal QT et les bulles. Ils utilisent le titre local lorsqu’il est disponible et les véritables valeurs de progression de l’expéditeur.
- Lorsqu’une description traduite d’objectif ne peut pas être choisie avec certitude, QT affiche un numéro d’objectif localisé avec les quantités, le pourcentage ou l’état de progression ou de complétion.
- Les anciennes versions de QT et le chat de groupe public conservent le texte de l’expéditeur. Si WoW ne fournit pas de titre local, QT garde le titre reçu ou l’identifiant de quête. Les événements dans la même langue conservent leur formulation détaillée.

### Titres des quêtes

- La comparaison privilégie désormais le titre local quand il est disponible.
- Les titres localisés contenant une ponctuation non ASCII restent plus souvent correctement cliquables.

## 5.15.0

Demandez à rejoindre un groupe de quête directement depuis le menu d’un joueur QuestTogether.

### Demander à rejoindre un groupe

- Lorsqu’un joueur QT est déjà groupé et que ces informations sont récentes, son menu propose de demander à le rejoindre plutôt que de l’inviter. Les deux joueurs doivent disposer de cette mise à jour et le demandeur doit être seul.
- Le destinataire peut refuser ou envoyer une invitation normale de WoW. Il doit avoir le droit d’inviter et une place libre dans un groupe ordinaire. Vous acceptez ensuite l’invitation habituelle.

### Invitations automatiques facultatives

- Deux options permettent d’approuver automatiquement les demandes des amis de personnage, ou celles des autres joueurs pendant que vous cherchez des compagnons. Elles sont désactivées au départ et figurent dans la demande et les réglages divers. Les amis de compte Battle.net ne sont pas concernés.
- Les demandes expirent et respectent les ignorés, les changements de groupe et les restrictions du jeu. QT ne quitte jamais votre groupe et n’accepte pas d’invitation à votre place.

## 5.14.1

Les annonces de groupe affichent le nom complet de QuestTogether.

### Chat de groupe

- Le préfixe [QT] devient [QuestTogether] afin que les autres joueurs puissent retrouver plus facilement l’addon.

## 5.14.0

QuestTogether ajoute cinq langues et aide à tenir informés les membres du groupe qui n’utilisent pas QT.

### Jouer dans votre langue

- L’interface est disponible en allemand, français, espagnol, portugais du Brésil et russe. QT suit la langue du jeu et utilise l’anglais en secours.
- Réglages, menus, infobulles, comparaisons et notes sont localisés. Les titres de quêtes et les textes de progression reçus d’autres joueurs restent dans leur langue d’origine.
- Les annonces de version sont aussi disponibles dans les cinq salons de notes de mise à jour de notre Discord, un par langue.

### Informer tout le groupe

- Une nouvelle option de destination des annonces envoie vos événements activés dans le chat de groupe lorsqu’au moins un membre n’a pas été reconnu comme utilisateur QT. Elle est activée par défaut et peut être désactivée dans les réglages.
- Cela fonctionne également dans les groupes d’instance formés par l’outil de recherche. Le jeu en solo et les raids sont exclus ; QT ne relaie jamais les annonces d’autres joueurs.

## 5.13.1

Ce correctif améliore le rétablissement des indicateurs de quête, nettoie les anciennes bulles et les logos, et rend les réglages et la fenêtre de débogage plus cohérents.

### Indicateurs de quêtes et de joueurs

- Icônes de quête et teintes de vie reviennent correctement après la fermeture des vues soumises à restriction. Les lectures de quêtes retardées conservent leur délai de stabilisation ; l’absence temporaire de données d’infobulle n’épuise pas leurs tentatives.
- Une bulle est retirée si sa barre de nom disparaît ou est réutilisée en combat. Pour une fenêtre protégée ou interdite, le nettoyage attend un moment sûr.
- Positions et présence se rétablissent après désactivation de QT, changement de zone et réactivation. Les retraits tardifs de position ou de statut ne redonnent plus de logo à un joueur parti.

### Réglages et fenêtres

- La case de recherche de compagnons reste synchronisée avec les changements effectués par commande, menu ou profil.
- La fenêtre de débogage termine sans risque les déplacements et redimensionnements interrompus lorsque les restrictions cessent, même si elle a été masquée entre-temps.

### Fiabilité

- Les tests détectent l’accès aux fenêtres interdites même lorsqu’une erreur est interceptée en interne.
- La publication refuse désormais des modifications du code qui ne sont pas enregistrées dans un commit Git, afin que les corrections annoncées soient bien dans le téléchargement.

## 5.13.0

Repérez les joueurs qui cherchent des compagnons grâce à une lueur dorée, réglez plus simplement le partage de position et recevez un rappel lorsqu’une version stable plus récente est détectée.

### Reconnaître les joueurs disponibles

- Les points de carte et de minicarte gardent leur couleur de classe et sont entourés d’une douce lueur dorée lorsque le joueur cherche des compagnons. Son logo QT sur la barre de nom reçoit la même lueur.
- Ces effets disparaissent à l’arrêt ou à l’expiration du statut. Dans les réglages de position, un filtre facultatif permet de ne montrer que les joueurs qui cherchent des compagnons ; il est désactivé au départ et s’applique aux deux cartes.
- La fenêtre des nouveautés montre côte à côte logos et points ordinaires ou lumineux. La lueur dorée signifie que le joueur cherche des compagnons de quête.

### Réglages de position simplifiés

- Partager ma position et afficher les autres joueurs s’appliquent chacun à la carte et à la minicarte.
- Ces deux options sont activées sur les nouveaux profils. Les refus de partage déjà enregistrés sont conservés lors de la mise à jour.

### Rappels de nouvelle version

- Si un joueur annonce une version stable plus récente, QT affiche un rappel dans la fenêtre de chat que vous avez choisie.
- Le rappel est conservé entre personnages et apparaît une fois par rechargement jusqu’à l’installation de cette version ou d’une plus récente. Les versions alpha et bêta ne déclenchent pas de rappel.
- Les annonces de version sont légères et espacées. QT reconnaît aussi les versions déjà présentes dans les réponses aux pings.

## 5.12.0

Un nouveau statut permet de signaler que vous cherchez des compagnons de quête. Cette mise à jour améliore aussi les infobulles de la minicarte et distingue mieux les particularités de Retail et Forever.

### Chercher des compagnons de quête

- Votre statut apparaît dans le menu de joueur et les infobulles des points de carte. Il n’active pas le partage de position et n’envoie aucune invitation.
- Activez-le depuis le menu de la minicarte, les réglages divers ou /qt lfg. Utilisez /qt lfg on pour l’activer ; les arguments off et status servent à le désactiver ou à le consulter. Il est désactivé par défaut et enregistré par profil.
- Le statut expire si les mises à jour cessent. Les joueurs ignorés sont exclus, et désactiver QuestTogether suspend votre annonce.

### Retail et Forever

- Forever n’affiche plus le mode Guerre dans les infobulles de joueurs, les détails de position des quêtes ni les réponses aux pings. Ces dernières n’indiquent plus de royaume, tout en conservant les noms complets.
- Les mises à jour de quêtes proches sur Forever ne dépendent plus du mode Guerre de Retail. Les points restent visibles entre phases pour faciliter la recherche de compagnons.
- Retail utilise le mode Guerre réellement actif lorsqu’il est connu. Un état inconnu ou non pris en charge n’est plus présenté comme désactivé.

### Des points de joueur plus stables

- Une brève absence de coordonnées n’efface plus immédiatement votre point. La dernière position reste jusqu’à deux minutes ; l’infobulle indique l’âge des rapports plus anciens. Le retrait du partage reste immédiat lorsque les communications le permettent.
- Les envois de mouvement sont limités à un toutes les dix secondes. À l’arrêt, le signal périodique reste à vingt secondes pour conserver la compatibilité avec les anciens clients.
- Le cache peut garder 512 joueurs. Chaque carte affiche au maximum 128 points visibles ; les joueurs hors de la carte consultée ne consomment plus cette limite.

### Des logos de joueur plus fiables

- La lecture du réglage actuel des barres de nom amicales corrige des logos absents sur les clients Forever et Retail récents.
- Un logo placé à gauche se décale pour laisser la place aux améliorations visibles, puis revient quand elles disparaissent.
- Tous les messages QT pris en charge identifient désormais leur expéditeur. Un cache limité retient les joueurs pendant la session de l’interface : un signal périodique manqué ne retire plus leur logo. Les départs explicites et les joueurs ignorés restent supprimés, sans messages supplémentaires.

### Infobulle de la minicarte

- L’infobulle du bouton QT utilise sa propre couche d’affichage et peut passer devant les barres d’action. Elle disparaît si le bouton devient indisponible ou si des restrictions commencent.

## 5.11.0

Repérez les joueurs QuestTogether, comparez vos quêtes avec une personne précise et trouvez plus facilement de l’aide sur Discord. Les réglages vous laissent choisir les informations partagées et affichées.

### Repérer les joueurs QuestTogether

- Lorsque les barres de nom amicales de WoW sont visibles, un logo en forme de parchemin peut accompagner les joueurs QT. Cette fonction est activée par défaut, à gauche avec un espacement. Vous pouvez choisir gauche, droite, haut ou préfixe, sans modifier la couleur des barres de vie.
- Les joueurs qui partagent leur position peuvent apparaître sous forme de points colorés selon leur classe sur la carte et la minicarte. Survolez un point pour voir nom, faction, race, classe et niveau ; cliquez pour ouvrir le menu du joueur.
- Les positions disposent de quatre réglages distincts : partage et affichage pour la carte, puis pour la minicarte. Tous sont activés au départ. La présence nécessaire aux logos de joueurs peut continuer à être annoncée même si les deux partages de position sont désactivés.
- Les positions sont actualisées périodiquement et disparaissent à expiration. Les deux joueurs doivent avoir l’addon à jour ; un point ne garantit pas une phase ou une couche de monde commune.

### Comparer avec un joueur ou tout le groupe

- L’action de comparaison du menu d’un joueur ne concerne que vous et cette personne, y compris un utilisateur QT joignable hors de votre groupe. La comparaison du groupe entier reste accessible depuis la minicarte, les menus de quêtes et /qt compare.
- Le partage de quêtes et les demandes de partage restent réservés au groupe. Une comparaison ciblée précise quand il faut être groupé et quand le joueur doit disposer de QT pour répondre.
- Si une demande de partage attend déjà la réponse de quelqu’un, son nom reste indiqué après un changement de cible.

### Aide et retours

- L’accueil et la page principale des réglages proposent un accès à Discord pour l’aide et les retours. Il ouvre une invitation à copier ou affiche celle-ci dans le chat si la fenêtre ne peut pas s’ouvrir.

### Corrections

- Les joueurs ignorés sont mieux filtrés : nouveaux messages, bulles, points, comparaisons et tâches de partage sont bloqués. Les bulles et positions déjà présentes sont retirées lors d’une modification de la liste d’ignorés.
- Des limites d’infobulle inaccessibles pouvaient associer à tort le texte d’un objectif d’une autre quête et afficher un indicateur de quête. Ce cas est corrigé.
- La désactivation du partage sur la carte ou la minicarte est réessayée après un échec temporaire de communication. Désactiver les deux retire aussi les détails de position des autres mises à jour de l’addon.
- Le logo disparaît correctement lorsqu’une présence expire juste avant le départ du joueur. Chuchoter depuis un point de carte ouvre votre fenêtre de chat ; le changement de destination du journal depuis les réglages est indisponible sous restriction.

## 5.10.0

QuestTogether partage la progression des quêtes avec votre groupe et les joueurs proches. Le bouton de la minicarte donne accès aux réglages, à la comparaison du groupe, à votre journal de quêtes et aux notes de mise à jour.

### Comparer et partager les quêtes du groupe

- Ouvrez la comparaison depuis la minicarte, le menu d’une quête ou d’un joueur, ou avec /qt compare. Vous voyez qui possède chaque quête et la progression de chacun.
- Toutes les quêtes du groupe apparaissent par défaut. L’option de masquage des quêtes absentes de votre journal permet de limiter la liste aux vôtres.
- Vous pouvez demander aux membres du groupe de partager une quête s’ils utilisent l’addon à jour. Leur autorisation est demandée par défaut ; le partage automatique est facultatif.
- Les comparaisons reprennent après les restrictions de carte ou de combat. Une actualisation remplace les anciennes réponses ; les délais entre demandes et les échecs indiquent quand réessayer.

### Raccourcis et menus des quêtes

- Faites glisser le bouton en forme de parchemin pour le déplacer sur la minicarte. Son menu ouvre les réglages, la comparaison, le journal de quêtes, les notes et le choix de fenêtre du journal QT. Vous pouvez le masquer depuis ce menu et le rétablir dans les réglages divers.
- Le menu d’un nom de quête propose son état, son partage, son ouverture dans le journal et la comparaison du groupe. Le partage et l’ouverture vérifient à nouveau la quête actuelle et les restrictions au moment du clic.
- Les liens d’état conservent leur titre après le retrait d’une quête de votre journal. La case de partage automatique suit désormais les préférences sauvegardées et les changements de profil.

### Aide et notes de mise à jour

- L’accueil et les dernières notes ont leur propre fenêtre, au lieu de messages répétés dans le chat. Ouvrez-la par les notes de mise à jour du menu de la minicarte ou de la page principale des réglages, ou avec /qt notes, /qt changelog ou /qt patchnotes.
- Cette fenêtre s’ouvre automatiquement lors des mises à jour majeures et mineures. Les correctifs ont eux aussi des notes, mais ne déclenchent pas l’ouverture automatique.
- /qt help présente les commandes courantes ; /qt help debug couvre les aperçus, les diagnostics et les commandes du développeur.

## 5.9.2

Un clic gauche ou droit sur un nom de quête dans le journal QT ouvre maintenant son menu. Vous y trouverez d’abord l’état de la quête, puis le partage.

### Menus et liens des quêtes

- Le partage utilise l’entrée actuelle du journal sans changer la quête sélectionnée dans l’interface Blizzard. Il est indisponible en solo, sous restriction ou si la quête ne peut pas être partagée. Après un séparateur, la dernière option déplace le journal QT entre la fenêtre principale et une fenêtre séparée, comme dans le menu des joueurs.
- Les noms de quêtes sont cliquables dans les messages d’état, y compris les titres de remplacement provenant du journal d’un autre joueur. Lors d’une comparaison de quêtes terminées, les liens existants sont conservés : les détails d’état ne créent plus un second lien cassé.
- Les 521 tests passent dans les deux ordres sur Lua 5.1 et 5.2. Les six profils API, les syntaxes Lua et shell, libchev et les différences de fichiers sont vérifiés. Les menus en jeu, la réception des partages et le taint du moteur restent à valider séparément.

## 5.9.1

Une revue complète a permis de corriger le suivi des quêtes, les barres de nom, les annonces de zones d’objectif, les communications et plusieurs actions de l’interface.

### Corrections issues de la revue

- Les blocs de quêtes sans rapport dans une infobulle ne récupèrent plus le texte d’un objectif commun. La progression valide du groupe est conservée, et les barres retrouvent leur état après un changement de carte, d’instance, de groupe ou de quête.
- Une quête fraîchement acceptée ou une première lecture reste en attente jusqu’à réception de données lisibles. Les étapes de progression, le type de tâche et une position encore inconnue sont préservés, sans fausse sortie de zone ni entrée en double.
- Les annonces localisées et les comparaisons de quêtes gèrent mieux les limites de message, la cadence, les nouvelles tentatives, l’annulation et l’indication de partage possible.
- Si WoW refuse un point de passage, QT ne suit pas une ancienne épingle. Les clics soumis à restriction sont refusés lorsque QT est désactivé, sans perdre les tâches en attente.
- Les essais de bulles restent des aperçus locaux. Ils acceptent les noms complets de Forever ou les noms entre guillemets, en conservant l’identité exacte du joueur.
- Corrections de l’activation, de la désactivation et des profils, de l’ouverture du mode Édition du HUD, des emotes de célébration autorisées et des diagnostics.
- Les tests sont mieux isolés du client en cours de jeu, les cas de régression sont renforcés et les hypothèses erronées corrigées. La CI signale désormais correctement les erreurs de syntaxe Lua.
- Les 516 tests passent dans les deux ordres sous Lua 5.1 et 5.2. Les six profils API, la syntaxe, la révision exacte de libchev et les différences de fichiers sont vérifiés. Rendu réel, livraison entre deux clients et taint du moteur restent à valider séparément.

## 5.9.0

Fêtez vos passages de niveau et ceux des joueurs QuestTogether proches avec des emotes synchronisées. Deux options distinctes, activées par défaut, rejoignent les emotes de fin de quête dans les réglages divers. Les réactions aux joueurs proches respectent vos choix de joueurs et les règles de distance habituelles.

### Progression et barres de nom

- La fin confirmée d’un objectif est mémorisée pour le type de créature, et plus seulement pour un exemplaire. En combat, un nouvel ennemi reste sans marque si son infobulle est inaccessible, même si un ancien exemplaire était encore nécessaire. Un objectif non terminé fraîchement lu peut rétablir le marquage ; un changement d’état des quêtes efface cette mémoire. Des données partielles ou inaccessibles ne prouvent jamais que tout le monde a fini.
- Si un ennemi est réservé à d’autres joueurs, l’icône de quête et la teinte de sa barre de vie disparaissent immédiatement, même en combat. QT surveille les changements de propriétaire et revérifie cette situation lors des mises à jour de vie et de menace.
- En combat dans le monde ouvert, QT peut reconnaître de nouveaux ennemis de quête à partir des données lisibles de leur infobulle. Les barres sont actualisées lorsqu’elles reviennent à l’écran, deviennent votre cible ou sont survolées. Les données retardées font l’objet de nouvelles tentatives limitées par unité ; les tâches devenues inutiles sont annulées au retrait de l’unité. Icône et couleur sont rétablies ensemble.
- Les protections liées à la carte, aux instances, aux données inaccessibles et aux fenêtres protégées sont conservées. Cette détection en combat ne fait appel ni à Questie ni à une infobulle cachée.
- Les 374 tests hors ligne passent dans les deux ordres sur Lua 5.1 et 5.2. Les six profils d’API client, la syntaxe Lua, la bibliothèque et les différences de fichiers sont vérifiés ; les tests de mémoire de complétion reproduisaient le problème avant correction. Le jeu réel et le taint au niveau du moteur restent à valider séparément.

## 5.8.6

QuestTogether vérifie mieux les données reçues des API avant de les afficher : noms de personnages et de classes, titres de quêtes et couleurs de classe personnalisées résistent aux valeurs illisibles ou mal formées.

### Vérification des données

- Les données des intégrations facultatives TomTom et Questie sont contrôlées avant utilisation. La lecture des lignes d’une infobulle Questie s’arrête dès qu’une donnée devient inaccessible. La visibilité des bulles et l’état du mode Édition sont convertis en vrais booléens avant d’être transmis aux contrôles de l’interface.
- Le traitement des événements d’écran de chargement est regroupé. Des arguments privés inutilisés et une branche inutilisée des types de restriction ont été retirés ; la gestion des rappels et des valeurs de retour est clarifiée. Les solutions de repli pour les clients récents et anciens, ainsi que la révision exacte de la bibliothèque interne, restent inchangées.
- Les 336 tests passent dans les ordres normal et inverse sur Lua 5.1 et 5.2, avec des contrôles d’adaptateurs étendus à six profils client. Les nouveaux tests reproduisent les erreurs de l’ancienne implémentation. Syntaxe Lua, bibliothèque et différences de fichiers sont vérifiées.
- Les diagnostics restants de Ketho WoW API/LuaLS ont été examinés, y compris sans simulations de client hors ligne. Chaque diagnostic conservé a une raison précise liée à la compatibilité, aux protections, aux rappels, à la bibliothèque ou aux données de test. Le fonctionnement réel sur Retail et Forever reste à vérifier séparément.

## 5.8.5

La détection des quêtes de zone et des expéditions sur la carte utilise désormais le champ questID de C_TaskQuest.GetQuestsOnMap sur les clients récents. Les anciens clients conservent leur API et le champ questId.

### Compatibilité et corrections

- Les emotes de fin de quête passent en priorité par C_ChatInfo.PerformEmote : elles peuvent ainsi fonctionner quand les anciennes fonctions globales sont désactivées. Une API d’emote absente ou défaillante est gérée sans erreur.
- Suppression d’un calcul inutilisé d’empreinte du groupe et de variables locales inutiles. Les tests couvrent les API récentes et anciennes de quêtes de zone et d’emotes, leur ordre de priorité, les données de quête inaccessibles et les API absentes ou en échec.
- Les 334 tests passent dans les ordres normal et inverse sur Lua 5.1 et 5.2. Les contrôles étendus sur six profils client, la syntaxe Lua et la révision exacte de la bibliothèque sont validés. Le fonctionnement en jeu sur Retail et Forever reste à vérifier séparément.

## 5.8.4

Cette mise à jour concerne uniquement l’entretien du dépôt.

### Organisation des fichiers

- Les notes de développement locales restent en dehors des sources suivies et des paquets distribués. Le fonctionnement en jeu ne change pas.

## 5.8.3

À chaque connexion ou rechargement de l’interface, un message unique indique la version installée, les clients compatibles et la commande des réglages.

### Accueil et liens utiles

- Les liens propres à l’addon vers CurseForge et GitHub ouvrent une fenêtre de copie au style WoW. S’il est impossible d’enregistrer le lien ou d’ouvrir cette fenêtre, l’adresse complète est affichée dans le chat.
- libchev 1.2.0 fournit le message d’accueil et la fenêtre de copie protégée communs aux addons. Même si cette fonction d’accueil est indisponible, le démarrage normal de QT continue.
- Les 334 tests passent dans les deux ordres sur Lua 5.1 et 5.2, avec les vérifications d’API client, de syntaxe Lua et de révision exacte de la bibliothèque. Les simulations NoPoizen exercent les deux liens sur les sept profils de client et de règles. Le rendu réel reste à vérifier séparément.

## 5.8.2

Deux faux échecs de /qt test sont corrigés. Un joueur proche pouvait occuper l’identifiant de barre de nom utilisé par les tests des infobulles et des icônes en cache ; la recherche des GUID de test est maintenant isolée. Les barres de nom en jeu ne changent pas.

### Fiabilité des tests

- L’environnement hors ligne reproduit cette collision et les deux échecs avant correction. Après correction, les 333 tests passent dans les deux ordres sous Lua 5.1 et 5.2, ainsi que les six profils d’API client. La confirmation en jeu reste une étape distincte.

## 5.8.1

QuestTogether est plus facile à reconnaître dans la liste des addons.

### Icône de l’addon

- Le point d’interrogation par défaut laisse place au marqueur de quête de Blizzard à côté du nom QuestTogether.

## 5.8.0

QuestTogether prend en charge les clients Classic actuels : événements d’acceptation de quête adaptés, recours aux API d’objectifs disponibles avec vérifications, métadonnées propres à chaque édition et six profils de client testés. Lorsqu’on ne sait pas si une quête peut être partagée, ce doute reste affiché comme tel.

### Compatibilité des clients

- Le comportement sur Retail et Forever ainsi que les outils communs de débogage sont conservés.
- Les 333 tests réussissent dans les deux ordres sur Lua 5.1 et 5.2. Les vérifications couvrent six profils de client, la syntaxe Lua et les révisions exactes de la bibliothèque interne. Les vérifications de base des clients NoPoizen et des paquets passent également. Les nouveaux adaptateurs restent à valider en jeu.
- CLIENT_COMPATIBILITY.md détaille les sources examinées, le périmètre couvert et les limites de la validation.

## 5.7.7

Avec libchev 1.1.3, les consoles de débogage superposées et leurs commandes restent dans le même groupe d’affichage natif. Chaque menu de catégories reste attaché à sa console.

### Noms et affichage

- Les icônes d’objectifs apparaissent désormais à gauche des barres de nom par défaut. Les positions déjà enregistrées sont conservées.
- Sur Forever, l’affichage de votre nom respecte le réglage « My Last Name ». Le nom de famille des autres joueurs reste visible, conformément au réglage natif. Les communications, l’appartenance au groupe, la correspondance avec les barres de nom et les actions sociales utilisent toujours le nom complet ; les identifiants de profils et de positions de bulle personnelle ne changent pas.
- Une annonce locale ne se répète plus lorsque votre message revient du canal avec une autre présentation du nom complet. Les tests couvrent l’annonce puis ses échos de canal et de groupe, y compris en présence d’un autre personnage ayant le même prénom.
- Les 331 tests passent dans les deux ordres sous Lua 5.1 et 5.2. Le placement initial des icônes et l’interaction entre plusieurs fenêtres restent à confirmer en jeu.

## 5.7.6

Les trois addons utilisent désormais la même console interne libchev 1.1.2. L’illustration étirée du cadre natif est corrigée grâce à des limites de texture explicites.

### La console commune

- Vous y retrouvez les filtres de catégorie et de recherche, la copie, les résultats de tests et les diagnostics, avec des horodatages lorsqu’ils sont disponibles et un seul résumé final des tests.
- La bibliothèque gère la console et ses fonctions générales ; QuestTogether fournit ses diagnostics de quêtes et ses tests isolés. Pour y accéder, utilisez /qt test, /qt debug ou /qt diagnostics.
- Les 324 tests passent dans les deux ordres sous Lua 5.1 et 5.2. L’apparence corrigée a été confirmée en jeu par l’utilisateur ; les autres vérifications de restrictions et de fonctionnement en jeu restent distinctes.

## 5.7.6-beta.3

La console de débogage intégrée passe à libchev 1.1.1 et retrouve l’apparence habituelle des fenêtres de WoW.

### Dans cette bêta

- Le style natif est rétabli dans la console commune aux addons. Le résumé des tests n’apparaît plus deux fois ; sa version finale reste dans l’historique de taille limitée.
- Recherche, catégories, copie, défilement, tests, diagnostics et protections liées aux restrictions fonctionnent comme auparavant.
- Un utilisateur a confirmé les 324 tests de QT sur Forever 1.60.1, build 70009, avec beta.2. Les sept fichiers de tests chargés en jeu ont aussi été examinés : aucun test ne génère de NaN ni de division par zéro. Ces résultats antérieurs ne valident pas la nouvelle apparence.
- Après /reload, ouvrez /qtd et lancez /qt test pour vérifier le style de la fenêtre et l’unique résumé. Le rendu, les restrictions et le taint de cette révision nécessitent encore une vérification en jeu.
- Les 324 tests passent dans les ordres normal et inverse avec les interpréteurs Lua 5.1.5 et 5.2.4 ; chaque exécution en ligne de commande affiche un résumé. Le ZIP installable de 26 fichiers, une fois extrait, passe aussi sur les deux versions. Les 23 fichiers Lua, les 22 entrées TOC, le manifeste des dépendances, le formatage et les différences de fichiers sont vérifiés.
- Révision de la bibliothèque : 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. QT n’a pas encore de CI GitHub ; celle de la bibliothèque a réussi.

## 5.7.6-beta.2

La console commune de libchev v1.1 remplace la fenêtre de débogage propre à QuestTogether. Elle est fournie avec l’addon et utilisée par les autres addons Together : rien à installer en plus.

### Dans cette bêta

- La console réunit filtres par catégorie, recherche approximative ou entre guillemets, sélection et copie, effacement, rechargement, tests et diagnostics. Le suivi du défilement est lui aussi commun aux addons.
- /qt test affiche les résultats actuels. Relancer les tests remplace l’ancien historique TEST et retire les filtres de recherche qui pourraient masquer les nouveaux résultats.
- /qt diagnostics [questID] et /qt diag [questID] reconstruisent le rapport en cache dans cette même console. Les événements récents sont conservés dans la limite commune prévue pour l’export.
- Les protections partagées pour les restrictions et les fenêtres de l’addon remplacent les anciens gestionnaires de la console et des menus déroulants de QT. Quêtes, annonces, barres de nom, communications et isolation des tests de QT restent sous la responsabilité de QuestTogether.
- Le rendu et le taint restent à vérifier en jeu sur Retail et Forever. Après /reload, lancez /qt test et /qt diagnostics. Essayez catégories, recherche, copie, effacement, redimensionnement, défilement, relances des tests et passage des rapports aux journaux, avec vos addons habituels et lors des transitions de combat ou de restrictions.
- Validation : 324/324 tests réussissent dans les deux ordres avec Lua 5.1.5 et 5.2.4. Les 23 fichiers Lua, les 22 entrées TOC et le manifeste de la bibliothèque sont vérifiés. Le ZIP installable a également passé les 324 tests après extraction, dans le banc de test hors ligne séparé. Révision de la bibliothèque : 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

QuestTogether intègre désormais libchev v1.0.0, déjà incluse dans l’addon. Elle fournit aux addons Together une base commune pour les journaux, les diagnostics, les appels protégés, les tâches différées et les tests. Aucune installation supplémentaire n’est nécessaire.

### Dans cette bêta

- Les rapports de diagnostic regroupent les informations sur le client, l’addon et la bibliothèque. Si la fenêtre de copie atteint sa limite, elle conserve les événements les plus récents.
- QuestTogether garde la gestion des quêtes, du groupe, des barres de nom et des restrictions. Les données en mémoire de chaque addon restent séparées.
- Lorsque QT est désactivé, les liens de coordonnées restent utilisables si les restrictions de WoW l’autorisent. Les tâches en attente restent suspendues et les anciens minuteurs sont abandonnés.
- /qt test comprend 315 cas : les 300 précédents, dix vérifications de la bibliothèque commune et cinq tests de non-régression pour son intégration.
- Les 315 tests réussissent dans les deux ordres d’exécution avec Lua 5.1.5 et 5.2.4. La syntaxe Lua, l’ordre de chargement du TOC et le manifeste des révisions et empreintes sont également vérifiés. Révision libchev intégrée : 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- Le rendu en jeu et les éventuels problèmes de taint sur Retail et Forever restent à vérifier après cette réorganisation. Après un rechargement, lancez /qt test et /qt diagnostics, puis essayez les quêtes, les bulles de progression, les barres de nom et les liens de coordonnées avec vos addons habituels, en combat, lors des changements de zone, après désactivation/réactivation et après rechargement. La validation des 300 tests sur Retail concernait v5.7.5.
