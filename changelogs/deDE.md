# QuestTogether — Änderungsprotokoll

<!-- Generated from canonical release notes; do not edit by hand. -->

## 8.0.2

Die Versionshinweise wurden sprachlich überarbeitet. Außerdem haben wir einen fehlenden Eintrag im Versionsverlauf ergänzt.

### Versionshinweise und Versionsverlauf

- Die aktuellen und älteren Versionshinweise wurden in allen zehn unterstützten Sprachen außer Englisch sprachlich überarbeitet, damit sie sich natürlicher lesen und leichter verständlich sind.
- Der bisher fehlende Eintrag zu 7.4.4 ist wieder im Versionsverlauf und in den Änderungsprotokollen enthalten.

## 8.0.1

Das Gruppenquestlog lässt sich direkt per Tastatur bedienen, ohne vorher einen zusätzlichen Knopf anzuklicken.

### Tastaturbedienung im Gruppenquestlog

- Beim Öffnen des Gruppenquestlogs oder beim Anklicken einer Quest erhält die Liste automatisch den Tastaturfokus. Der bisherige Tastaturknopf entfällt. Mit den Pfeiltasten wählst du eine Quest, mit Enter klappst du ihre Ziele auf oder zu.
- Tab wechselt zwischen Liste und Suche. Aus der Liste schließt Escape das Fenster. Ein Klick außerhalb gibt den Tastaturfokus frei; eingehende Questaktualisierungen holen ihn nicht zurück.

## 8.0.0

QuestTogether führt VIP ein: eine dauerhafte kosmetische Auszeichnung für Unterstützer.

### Das VIP-Aussehen

- VIP-Spieler erscheinen auf der Karte als Stern in Klassenfarbe. Im QT-Chat und am Minimapknopf tragen sie ein QT-Logo mit goldenem Stern; ihr individueller Spielertooltip zeigt „QuestTogether VIP“. Die Auszeichnung ist rein kosmetisch und verleiht keinen Entwicklerzugriff.

**Forever**

![Das VIP-Aussehen — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v8.0.0/Media/ReleaseNotes/VIPCosmetics.png)

### So wirst du VIP

- Teile den Downloadlink von QuestTogether mit Freunden, deiner Gilde, in einem passenden Discord oder in sozialen Medien. Mache einen Screenshot deiner abgesendeten Nachricht oder deines veröffentlichten Beitrags, auf dem der QT-Link und der Ort der Veröffentlichung erkennbar sind. Schicke das Bild zur Prüfung per Discord-Direktnachricht an @chevcast. Tritt vorher dem QT-Discord bei oder sende @chevcast eine Freundschaftsanfrage, damit deine Nachricht ankommt. Im VIP-Fenster findest du den kopierbaren Link und die Schritte zur Aktivierung nach der Freigabe.

### Die Auszeichnung aktivieren

- Öffne das VIP-Fenster über das Minimapmenü, die Einstellungen oder /qt vip. Warte zuerst auf die Bestätigung von @chevcast, dass deinem Discord-Konto VIP gewährt wurde. Der Discord-Befehl /qt claim funktioniert erst danach.

Kopiere anschließend deinen Anforderungscode mit Strg+C und sende ihn an @chevcast oder verwende /qt claim auf dem QT-Discord. Den privat erhaltenen Aktivierungscode fügst du ins VIP-Fenster ein und wählst „VIP aktivieren“. Wiederhole die Aktivierung auf Retail beziehungsweise Forever, wenn du die Auszeichnung auch dort nutzen möchtest.

### Dauerhaft und freiwillig sichtbar

- Die Auszeichnung ist an dein Discord-Konto gebunden und gilt für alle Charaktere der jeweiligen Installation. Für Retail und Forever forderst du sie separat an. Mit „Meine VIP-Kosmetik anzeigen“ kannst du die Darstellung abschalten, ohne VIP zu verlieren. Normale, VIP- und Entwickler-Minimapknöpfe haben jetzt goldene Ränder entlang ihrer Symbolform. Das Entwickleraussehen hat Vorrang vor VIP.

## 7.4.4

Neue Funktionen und die dazugehörigen Korrekturen stehen in den Versionshinweisen jetzt gemeinsam auf einer Seite.

### Zusammengehörige Updates gemeinsam lesen

- Das Hinweisfenster beginnt jede Seite mit einer Nebenversion und hängt deren Patches in Reihenfolge darunter an, jeweils mit Versionsnummer und Datum. Die Verlaufsauswahl wechselt zwischen diesen zusammengefassten Seiten.
- Ältere Patchhinweise wurden von wiederholten Funktionsanleitungen, Tipps und Bildern bereinigt und beschreiben nur ihre eigenen Änderungen. Reine Patchupdates öffnen das Fenster weiterhin nicht automatisch. Mit /qt notes kannst du es jederzeit aufrufen.

## 7.4.3

Die Gruppenwerkzeuge haben passendere Namen und leichter erreichbare Einstellungen.

### Quests gemeinsam verfolgen

- Aus der Questverfolgung wird die Gruppen-Zielverfolgung (Party Objective Tracker, POT). Deine bisherigen Anzeigeeinstellungen und die Fensterposition bleiben erhalten.
- /qt pql öffnet das Gruppenquestlog. /qt compare funktioniert weiterhin als Alias; Hilfe und Tipps verwenden jetzt /qt pql.
- „Außerhalb einer Gruppe ausblenden“ findest du sowohl im HUD-Bearbeitungsmodus als auch unter Einstellungen > Gruppen & Teilen > Gruppen-Zielverfolgung. Beide Schalter ändern denselben Wert. Neue Profile und „Standardwerte wiederherstellen“ schalten die Option ein; vorhandene gespeicherte Entscheidungen bleiben erhalten.

## 7.4.2

Die Versionshinweise verwenden zuverlässig darstellbare Trennzeichen.

### Textdarstellung in Versionshinweisen

- Nicht unterstützte Trennzeichen wurden durch einfachen Text ersetzt, damit keine leeren Kästchen mehr erscheinen.

## 7.4.1

Die Gruppen-Zielverfolgung erhält neue Anordnungsoptionen und zeigt unvollständige Einzelschritte korrekt an.

### Zielfortschritt korrigiert

- Unfertige einstufige Ziele in Forever erscheinen nicht mehr fälschlich als 1/1, darunter „Use Walk on Air“. Die Korrektur gilt für Gruppen-Zielverfolgung und Gruppenquestlog.

### Allein ausblenden

- Im HUD-Bearbeitungsmodus kannst du „Außerhalb einer Gruppe ausblenden“ einschalten. Die Option ist zunächst aus. Die Platzierungsvorschau bleibt im Bearbeitungsmodus auch ohne Gruppe verfügbar.

### Größe und Verankerung

- Die Verankerung an Blizzards Zielverfolgung ist standardmäßig aktiv. QT liegt bündig an deren äußerem Rand. Ziehst du das Fenster weg, wird die Verankerung ausgeschaltet und die Größenänderung an den Ecken freigegeben. Erneutes Einschalten setzt die Position zurück. Breite und maximale Höhe lassen sich in beiden Modi per Regler ändern.
- Das Fenster schrumpft auf die benötigte Inhaltshöhe, bis zur eingestellten maximalen Höhe; darüber wird gescrollt. Der neue Standard für die maximale Höhe ist 600. Bereits gespeicherte Größen bleiben erhalten.
- Die klassenfarbigen Spielerbereiche haben konstant 25 % Deckkraft, unabhängig vom Regler für den Fensterhintergrund.

## 7.4.0

Die neue Gruppen-Zielverfolgung hält den Questfortschritt deiner Gruppe direkt auf dem Bildschirm sichtbar.

### Gruppen-Zielverfolgung

- Ein kompaktes Fenster mit Klassenfarben zeigt Zielzähler und Fortschrittsbalken deiner Gruppe. Andere Mitglieder benötigen QuestTogether, um ihren Fortschritt zu teilen.
- Eingehende Gruppenmeldungen aktualisieren die Anzeige sofort, unabhängig von der Anzeige im Chat oder in Blasen. Hat eine Quest keine Zielzähler, erscheint stattdessen ihr Status, etwa die Bereitschaft zur Abgabe.

**Forever**

![Gruppen-Zielverfolgung — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTracker.png)

### Welche Quest angezeigt wird

- Du kannst „Ausgeblendet“, „Fokussierte Quest“, „Quest unter dem Mauszeiger“ oder „Fokus und Mauszeiger“ wählen. Letzteres ist voreingestellt: Das Fenster zeigt die Quest unter dem Mauszeiger in Blizzards Zielverfolgung und kehrt danach zur Fokusquest zurück.
- Ohne passende Quest bleibt das Fenster verborgen. Den Anzeigemodus änderst du im HUD-Bearbeitungsmodus oder unter Einstellungen > Gruppen & Teilen > Gruppen-Zielverfolgung.

**Forever**

![Welche Quest angezeigt wird — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTrackerDisplay.png)

### An deine Oberfläche anpassen

- Wähle die Gruppen-Zielverfolgung im HUD-Bearbeitungsmodus aus, um sie zu verschieben, ihre Größe zu ändern oder die Hintergrunddeckkraft einzustellen. „Änderungen speichern“, „Änderungen verwerfen“ und „Standardwerte wiederherstellen“ berücksichtigen Anzeigemodus und Anordnung.
- Die Spielerbereiche nutzen die verfügbare Breite und lassen sich bei Bedarf scrollen. Helles und dunkles Design werden unterstützt. Auch bei null Hintergrunddeckkraft bleiben der Text lesbar und die Spielerbereiche leicht hinterlegt.

**Forever**

![An deine Oberfläche anpassen — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTrackerEditMode.png)

## 7.3.5

Kartenmarkierungen sind klarer lesbar, Spieler leichter zu finden und Gruppenangaben besser auf dem aktuellen Stand.

### Karten und Spielerdaten

- Der Tooltip des QT-Kartenknopfs enthält eine bebilderte Legende der Symbole und Zustände.
- Ein Linksklick auf einen Weltkartenpunkt hebt den Spieler hervor und öffnet die detaillierteste verfügbare Karte seines Standorts. Auf der letzten Kartenebene öffnet Linksklick das Spielermenü; Rechtsklick öffnet es immer.
- Auch „Auf Karte finden“ führt zur detailliertesten verfügbaren Karte. Der grüne Schimmer bleibt beim Kartenwechsel erhalten und endet nach einer Minute, beim Schließen der Karte oder bei der Auswahl eines anderen Spielers.
- Beim Überfahren eines Spielers, einer Punktgruppe oder eines geteilten Wegpunkts werden Karte und unbeteiligte Markierungen abgedunkelt. Die hervorgehobenen Markierungen bleiben hell. Der QT-Knopf dunkelt die Karte beim Überfahren nicht mehr ab.
- Alle Spielerschimmer verwenden denselben Effekt. Spielertooltips und Punktgruppen nutzen aktuellere Mitgliedschaftsdaten und erholen sich besser von verspäteten Anfragen.
- Die Entwicklerdiagnosen wurden verbessert. Diagnosefreigaben und der Schutz nicht öffentlich geteilter Standorte bleiben gewahrt.

## 7.3.4

Spielertooltips zeigen QT-Nutzung schneller an und halten Statushinweise in Mitgliederlisten kompakt.

### Spielertooltips und Chat

- Sobald gültige Standortdaten eines Spielers vorliegen, erscheint sein QT-Symbol in Gruppenlisten – auch nach dem Neuladen.
- Gruppen- und Punktgruppenlisten verwenden kompakte Statussymbole. Erläuterungen zum Entwicklerstatus oder zu einem verborgenen Standort stehen nur beim direkten Überfahren des jeweiligen Spielers. Hinweise auf verborgene Standorte sind weiterhin ausschließlich für den Entwickler sichtbar.
- Meldungen eines bestätigten Entwicklers erhalten ein Schriftrollen-Zahnrad-Symbol. Bei aktiver Partnersuche leuchtet es golden.

## 7.3.3

Die Listen in Punktgruppen-Tooltips kommen mit weniger Zusatztext aus.

### Entwicklersymbol im Tooltip

- In Punktgruppen kennzeichnet nur das klassenfarbige Zahnrad den QuestTogether-Entwickler. Der erläuternde Text bleibt im individuellen Spielertooltip erhalten.

## 7.3.2

Gruppendaten werden auf der Karte einheitlicher verwendet. Auch aus der Weltansicht führen Punktgruppen zur passenden Detailkarte.

### Einheitliche Gruppenangaben und Kartennavigation

- Spielertooltips, Punktgruppen-Tooltips und Gruppenhervorhebung verwenden dieselben bekannten Gruppenangaben. Das vermeidet wiederholtes Laden und widersprüchliche Zuordnungen.
- Neben dem weißen Gruppensymbol steht die Gesamtgröße der Gruppe.
- Auch auf der vollständigen Weltkarte öffnet ein Klick auf eine Punktgruppe nun die detaillierteste Karte mit allen enthaltenen Spielern. Falls nötig, klappt die Gruppe dort anschließend auf.

## 7.3.1

Gruppenzugehörigkeit und ausgeblendete Kartenmarkierungen sind leichter zu erkennen.

### Gruppen und Kartenschalter

- In Tooltips von Punktgruppen stehen Mitglieder derselben bekannten Gruppe gemeinsam in einem weißen Rahmen mit abgerundeten Ecken und Gruppensymbol. Ein einzelner Spieler behält den Gruppenhinweis auch dann, wenn seine Gefährten außerhalb der Punktgruppe sind.
- Der QT-Knopf auf der Weltkarte bleibt beim Ausblenden der Markierungen gut sichtbar und trägt ein rotes X.
- Sind QT-Markierungen ausgeblendet, dunkelt das Überfahren des Knopfs die Karte nicht mehr ab.

## 7.3.0

Volle Karten bleiben übersichtlich, frühere Questgefährten sind leichter wiederzufinden und schnelle Fortschrittsschritte ergeben weniger einzelne Meldungen.

### Spieler auf der Karte finden

- Überlappende Weltkartenpunkte werden zu Gruppen zusammengefasst. Das ist standardmäßig eingeschaltet und lässt sich unter „Spielerstandorte“ deaktivieren.
- Ein Klick auf eine Punktgruppe öffnet die detaillierteste Karte, auf der alle enthaltenen Spieler liegen. Bleibt dort eine Gruppe übrig, klappt sie in einzelne Punkte mit den üblichen Tooltips und Menüs auf. Bei größeren Gruppen blätterst du mit dem Mausrad darüber.
- Der QT-Knopf oben rechts auf der Weltkarte schaltet QT-Spielermarkierungen und geteilte Wegpunkte um. Beim Überfahren wird die Karte dahinter abgedunkelt. Minimap-Markierungen und Standortfreigabe bleiben davon unberührt.
- „Auf Karte finden“ öffnet den zuletzt freigegebenen aktuellen Standort eines Spielers und hebt seinen Punkt hervor.

### Frühere Gefährten wiederfinden

- /qt companions oder das Minimapmenü öffnet eine private Liste früherer Gruppenmitglieder. Ihre Spielermenüs bieten Flüstern, Einladen und private Notizen.
- Die Liste gilt gemeinsam für deine Charaktere auf demselben Client und Realm. Sie speichert höchstens 100 Gefährten für 90 Tage. Einzelne Einträge oder die gesamte Liste kannst du jederzeit löschen.

### Fortschritt und Spielerstatus

- Rasche Änderungen desselben Ziels werden zu einer Meldung mit dem neuesten Stand zusammengefasst. Abgeschlossene Ziele werden weiterhin zügig gemeldet.
- Durch Signatur bestätigte QT-Entwickler erhalten ein Zahnrad in Klassenfarbe und einen Entwicklerhinweis im Tooltip. Die Listen über Punktgruppen verwenden dieselben Klassenfarben, QT-Symbole und Suchstatusanzeigen wie Gruppenlisten.

## 7.2.1

Private Notizen lassen sich angenehmer bearbeiten, und eingeklappte Questspalten zeigen verlässliche Symbole.

### Korrekturen an Notizen und Questspalten

- Der fehlende Textcursor im Notizeditor ist behoben. Der Fokusrahmen ist dezenter.
- Beim Bearbeiten längerer Notizen wurde das Scrollverhalten verbessert.
- Eingeklappte Spalten im Gruppenquestlog verwenden für abgabebereite und abgeschlossene Quests Symbole statt Schriftzeichen, die als leere Kästchen erscheinen konnten.

## 7.2.0

Private Spielernotizen, übersichtlichere Questspalten und hilfreiche Direktlinks ergänzen QuestTogether.

### Private Notizen zu Spielern

- Im QT-Menü eines Spielers kannst du eine persönliche Notiz anlegen, bearbeiten oder löschen. Sie erscheint, wenn du den Spieler überfährst.
- Die Notizen gelten für deine Charaktere gemeinsam und bleiben auf deinem Computer. Sie werden weder anderen Spielern gesendet noch in Diagnosen aufgenommen.

### Mehr Übersicht im Gruppenquestlog

- Klappe einzelne Spielerspalten ein, um Platz zu schaffen. Bei Bedarf kannst du sie jederzeit wieder ausklappen.
- Mit dem Knopf „Tastatur“ aktivierst du die Bedienung per Pfeiltasten. Enter klappt Ziele auf, die Leertaste öffnet Questaktionen. Escape kehrt zur normalen Steuerung zurück.
- Kann das aktualisierte Addon eines Mitspielers dessen Questhistorie bestätigen, unterscheidet QT abgeschlossene von fehlenden Quests. Bei unbekannter Historie bleibt die Angabe „Nicht im Questlog“.
- Verständlichere Erklärungen zeigen, warum eine Teilanfrage nicht möglich war. Spielertooltips enthalten außerdem die jüngsten vom Spiel gemeldeten Ergebnisse des Teilens.

### Tipps und Spielertooltips

- Viele Chat-Tipps enthalten anklickbare Verknüpfungen zum passenden Fenster oder zur Einstellung.
- Beim Überfahren eines entfernten Spielers fordert QT aktuelle Angaben und die vollständige Liste seiner kleinen Gruppe an. Solange du dort verweilst, werden nötige Anfragen wiederholt.

> <img src="https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.2.0/Media/QuestTogetherTipIcon.png" width="20" height="20" alt=""> Tipp: Mit /qt tip oder /qt hint erhältst du einen Tipp. Seine anklickbaren Verknüpfungen führen dich direkt zu den passenden QT-Funktionen.

## 7.1.3

QT findet Questtexte in deiner Client-Sprache zuverlässiger, auch wenn die Daten etwas später eintreffen.

### Questtexte zuverlässiger laden

- Questmeldungen, Gruppenquestlog und Hinweise zur Questfolge übernehmen lokal verfügbare Questnamen zuverlässiger.
- Während Namen laden, bleibt die Reihenfolge der Questmeldungen erhalten. Auch das Questdetailfenster erholt sich korrekt, wenn Tooltiptexte verspätet eintreffen.
- Die Verarbeitung von Questnamen anderer Spieler wurde verbessert.

## 7.1.2

Du kannst Starttipps abschalten. Die Hauptseite der Einstellungen ist übersichtlicher geworden.

### Tipps und Einstellungen

- Automatische Tipps lassen sich unter „Allgemein“ auf der QT-Hauptseite ausschalten. /qt tip und /qt hint funktionieren weiterhin.
- Die Hauptseite wurde vereinfacht; zwischen hellem und dunklem Design wählst du jetzt in einem Dropdown.

## 7.1.1

Tipps haben ein besser lesbares Symbol und neue Textfarben.

### Symbol und Farben für Tipps

- Ein QT-Glühbirnensymbol ersetzt das nicht unterstützte Emoji. Die Beschriftung ist golden, der Tipptext cremefarben.

## 7.1.0

Mit kurzen Tipps lernst du weitere Möglichkeiten von QuestTogether kennen.

### Tipps von QuestTogether

- Beim Einloggen oder Neuladen zeigt QT einen Tipp aus einem gemischten Vorrat. Erst wenn alle einmal erschienen sind, beginnt die Auswahl von vorn.

> 💡 Tipp: Mit /qt tip oder /qt hint kannst du dir jederzeit einen weiteren QuestTogether-Tipp anzeigen lassen.

## 7.0.2

Questtexte sind leichter zugänglich; die optionalen Entwicklerdiagnosen arbeiten zuverlässiger.

### Verbesserungen

- Ein neues Questdetailfenster zeigt verfügbare Questtexte an.
- Die optionalen Entwicklerdiagnosen und die Kommunikation wurden verbessert. Deine Einstellung zur Diagnosefreigabe wird berücksichtigt.

## 7.0.1

Die Bedienelemente von QuestTogether passen sich enger an Blizzards aktuelle Oberfläche an.

### Bedienelemente im Blizzard-Stil

- Schieberegler haben Pfeilknöpfe für kleine Anpassungen und zeigen ihren Wert neben der Leiste.
- Kontrollkästchen, Farbfelder, Scrollleisten und Standardknöpfe verwenden Blizzards aktuelles Erscheinungsbild.
- Die Suche im Gruppenquestlog und Debugfenster bietet ein Suchsymbol und einen Knopf zum Leeren.

### Scrollen und Größenänderungen

- Das Scrollverhalten in Einstellungen, Gruppenquestlog, Versionshinweisen und Debugfenster wurde überarbeitet, einschließlich Größenänderungen und Ausrichtung der Questzeilen.
- Beim Schließen eines Fensters enden auch laufende Pfeil- und Ziehaktionen an der nativen Scrollleiste sauber.

## 7.0.0

Für den Start von WoW Forever haben wir die Kommunikation von QuestTogether neu aufgebaut. Diese Hauptversion wechselt das Protokoll; bitte aktualisiert gemeinsam.

### Wichtig: keine Kommunikation mit älteren Versionen

- QuestTogether 7.x kann mit 6.x und älteren Versionen weder Standorte und Questfortschritt noch Gruppenquestlog-Daten oder andere Addon-Nachrichten austauschen. Bitte deine Questpartner deshalb ebenfalls um ein Update.

### Vorbereitung auf den Forever-Start

- Wir nehmen diese größeren, nicht abwärtskompatiblen Änderungen bewusst vor dem Start von WoW Forever vor, um die Kommunikation auf eine verlässlichere Grundlage zu stellen.
- Nach dem Start werden wir stärker auf Abwärtskompatibilität zwischen Addon-Versionen achten und störende gemeinsame Updatepflichten vermeiden. Sollte ein weiterer Protokollbruch nötig werden, kündigen wir ihn klar an.

### Aktuelle Daten dort, wo du hinsiehst

- Dein aktuelles Gebiet und ein länger auf der Karte geöffnetes Gebiet werden bevorzugt aktualisiert. Weiter entfernte Standorte erneuert QT langsamer im Hintergrund.
- Nahe Bewegung verwendet kurze, gezielte Meldungen. Suchanfragen werden zusammengefasst und zeitlich verteilt, damit volle Gebiete weniger Nachrichten auslösen.

### Zuverlässiger Daten austauschen

- Questmeldungen, Gruppenquestlog-Übertragungen, Spielerdetails und Diagnosen nutzen einen gemeinsamen getakteten Versand. Große Antworten lassen so Platz für andere Aktivitäten.
- Fehlende Teile großer Antworten können nachgefordert werden, ohne alles neu zu übertragen. Verspätete Standorte behalten ihr ursprüngliches Alter und überschreiben weder neuere Positionen noch zurückgezogene Freigaben.
- Änderungen der Standortfreigabe entfernen wartende öffentliche Koordinaten. Beim Ausloggen oder vor einem Ladebildschirm versucht QT eine letzte Abmeldung; trifft sie nicht ein, bleibt die Ablaufzeit die Absicherung.

## 6.5.11

Neue Tastenbelegungen öffnen QT-Werkzeuge und schalten die Questpartnersuche direkt um.

### QT-Aktionen einer Taste zuweisen

- Unter Einstellungen > Tastenbelegung erscheint QuestTogether jetzt mit korrekter Überschrift statt HEADER_QUESTTOGETHER.
- Du kannst Tasten für das QT-Menü, das Gruppenquestlog, die Partnersuche, das Beenden der Questfolge, den QT-Chat und die QT-Einstellungen vergeben.
- Deine bisherige Belegung für das Gruppenquestlog bleibt erhalten. Neue Aktionen sind zunächst unbelegt. Die Menütaste funktioniert auch bei ausgeblendetem Minimaplogo.

## 6.5.10

Queststände bleiben besser aktuell. Profilwechsel, Dialoge und Fortschrittsblasen berücksichtigen gespeicherte Einstellungen zuverlässiger.

### Aktualisierungen im Gruppenquestlog

- Bei automatischer Aktualisierung verursachen unveränderte Questlisten weniger Addon-Verkehr. Ein manuelles „Aktualisieren“ fordert weiterhin den vollständigen Stand an.
- Nach Zieländerungen sowie dem Ignorieren und erneuten Zulassen eines Spielers erholen sich Questlisten korrekt, statt alten Fortschritt zu behalten oder dauerhaft zu laden.

### Fenster und Profile

- Beim Wechseln, Kopieren oder Zurücksetzen eines Profils werden dessen Fensteranordnung oder die Standardwerte wiederhergestellt. Änderungen der Bildschirmgröße halten Fenster weiter sichtbar, ohne deine bevorzugte Größe und Position zu verwerfen.
- Nach dem Schließen einer Beitritts- oder Teilbestätigung wird die nächste wartende Anfrage angezeigt.
- Öffnest du während Blizzards Bearbeitungsmodus die Einstellungen, kann „Zurücksetzen“ anschließend trotzdem die ursprüngliche Anordnung deiner Fortschrittsblase wiederherstellen.
- Offene Hilfsfenster passen sich auch bei deaktiviertem QT weiter an Design- und Anzeigeänderungen an.

### Quests und Kommunikation

- Abgelaufene oder nicht mehr benötigte Beitritts- und Teilanfragen werden vor dem Versand verworfen.
- Abschlüsse von Bonuszielen und Weltquests behalten ihren richtigen Meldungstyp, auch wenn die Quest schon vor dem Abschlussereignis aus dem Log verschwindet.
- Bei einer manuellen Standortaktualisierung können öffentliche Antworten älterer QT-Versionen nun normale Kartenpunkte erneuern. Neuere Koordinaten und die Standortfreigaben bleiben dabei maßgeblich.

## 6.5.9

Gruppendaten erholen sich besser nach Unterbrechungen. Kartenpunkte und Fenster bleiben auch beim Ausblenden der Oberfläche stimmig.

### Gruppenquestlog und Fenster

- Das Aus- und Einblenden der Oberfläche mit Alt+Z erhält offene Fokusbestätigungen und die klassenfarbigen Hintergründe der Spielernamen.
- Anfragen des Gruppenquestlogs erholen sich zuverlässiger nach Neuladen, Ladebildschirmen oder fehlenden Nachrichtenteilen. Spieler bleiben dadurch seltener auf „Lädt“ stehen.
- Fenster und persönliche Fortschrittsblasen passen sich kleineren Bildschirmen besser an. Das Zurücksetzen der Fensteranordnung verwirft keine offenen Dialogentscheidungen.

### Karten und Gruppenzustand

- Veraltete Standort-, Gruppen- und Fokusmeldungen werden abgewiesen. Verspätete Antworten können dadurch weder ausgeschiedene Spieler zurückbringen noch neuere Daten überschreiben.
- Beim Verlassen der Spielwelt versucht QT eine Abmeldung zu senden. Erreicht sie andere Spieler, können diese deinen Punkt früher entfernen; andernfalls greift weiter die normale Ablaufzeit. Auch die Verfügbarkeit für Gruppenbeitritte erholt sich nach Ladebildschirmen.
- Mitglieder deiner eigenen Gruppe verwenden Blizzards Karten- und Minimap-Markierungen, ohne doppelte QT-Punkte. Der Kartenfilter bietet alle QT-Spieler, Spieler auf Partnersuche oder niemand. Deine Standortfreigabe bleibt unabhängig davon.

### Questerfassung und Nachrichten

- QT erholt sich von einem beim Login unvollständigen Questlog. Viele Questereignisse schieben eine bereits anstehende Aktualisierung nicht mehr immer weiter auf.
- Ausgehende Nachrichten teilen sich eine getaktete Warteschlange. Entwickleranfragen werden in kleinen Schritten geprüft, um Bildruckler zu reduzieren. Das Abschalten der Diagnosefreigabe bricht wartende Diagnosearbeit ab.
- Große Diagnoseantworten haben mehr Zeit zum Abschluss. Passt ein Bericht für einen älteren Anfragenden nicht in die erlaubte Größe, erhält dieser ausdrücklich eine Größenbegrenzungsantwort statt eines stillen Zeitablaufs.

## 6.5.8

Native WoW-Dropdowns vereinheitlichen die Einstellungen. Kartenfilter werden einfacher, Entwicklerdiagnosen erhalten einen eigenen Bereich.

### Einstellungen und Kartenfilter

- Alle neun Dropdowns in den Einstellungen verwenden native WoW-Bedienelemente mit goldener Auswahl, schwarzen Menüs und Vor-/Zurück-Knöpfen.
- „Auf Karten angezeigte Spieler“ ersetzt die getrennten Schalter für Sichtbarkeit und Gruppenausnahme. Zur Wahl stehen alle QT-Spieler, Spieler auf Partnersuche mit oder ohne eigene Gruppe, nur die Gruppe oder niemand. Bisherige Vorgaben werden übernommen. Die Freigabe deines eigenen Standorts bleibt separat.
- Die neue Kategorie „Entwickler“ enthält das Debugfenster, das erneute Einlesen des Questlogs und die Diagnosefreigabe.

### Private Antworten auf Diagnoseanfragen

- „Diagnosedaten mit dem Entwickler teilen“ ist standardmäßig eingeschaltet. Nach einer authentifizierten Entwickleranfrage dürfen QT-Diagnosen, Addon-Einstellungen sowie Charakter-, Gruppen- und Standortdaten aus dem Spiel übertragen werden – auch bei ausgeschalteter öffentlicher Standortfreigabe. Unter „Entwickler“ kannst du diese Freigabe abschalten.
- Die Antworten laufen über private Addon-Flüsternachrichten. Größere Antworten werden in zeitlich verteilte Seiten aufgeteilt, damit ihre Felder erhalten bleiben. Beide Seiten benötigen mindestens 6.5.8; veröffentlichte 6.5.7-Clients können diese Anfragen nicht beantworten.

## 6.5.7

Minimap-Punkte lassen sich zum Anwählen verwenden. Gruppen- und Fokussymbole sind klarer erkennbar.

### Spieler anwählen und Status erkennen

- Außerhalb des Kampfes kannst du einen Spieler per Linksklick auf seinen Minimap-Punkt anwählen, sofern das Spiel ihn als Ziel zulässt. Rechtsklick öffnet weiterhin das Menü; „Anvisieren“ steht darin zuerst. Weltkartenmenüs verhalten sich unverändert.
- Partnersuchsymbole haben einen deutlich kräftigeren Goldrand. Auch in Gruppenlisten innerhalb von Tooltips erscheint bei aktiver Suche das leuchtende QT-Logo.
- Die Questsymbole der Fokusknöpfe im Gruppenquestlog liegen auf einer eigenen Vordergrundebene, damit der Knopfhintergrund sie nicht verdeckt.

## 6.5.6

Im QT-Protokoll erkennst du leichter, wer gerade Questpartner sucht.

### Partnersuche im Protokoll hervorheben

- Das Partnersuchsymbol hat einen helleren goldenen Umriss und einen kräftigeren Schimmer, damit es auch klein gut erkennbar bleibt.
- Beginnt eine Meldung mit dem QT-Logo, leuchtet dieses bei aktiver Partnersuche des Spielers. Questspezifische Symbole und Sprechblasensymbole behalten ihr bisheriges Aussehen.

## 6.5.5

Die Fokusknöpfe im Gruppenquestlog zeigen ihre Questsymbole nach dem Scrollen wieder zuverlässig.

### Leere Symbolkreise behoben

- Wiederverwendete Fokusknöpfe setzen ihre Grafik beim Scrollen oder Aktualisieren der Liste korrekt zurück. So bleiben keine leeren Kreise zurück. Kann die angeforderte Grafik nicht dargestellt werden, verwendet QT ein Ersatzsymbol.

## 6.5.3

Drei bebilderte Abschnitte ergänzen die Anleitung zum Gruppenquestlog. Am Spielverhalten ändert sich nichts; die Bilder zeigen simulierte Forever-Mitspieler.

### Die Gruppe auf einen Blick

- Die Anleitung enthält jetzt eine Übersichtsaufnahme des Gruppenquestlogs.

**Forever**

![Die Gruppe auf einen Blick — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestOverviewForever.png)

### Eine Quest wählen oder einem Mitspieler folgen

- Ein neues Bild zeigt die Bedienelemente für die Questfolge.

**Forever**

![Eine Quest wählen oder einem Mitspieler folgen — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestFollowingForever.png)

### Fokuswechsel bestätigen

- Ein weiteres Bild zeigt die Rückfrage beim Ändern des Fokus.

**Forever**

![Fokuswechsel bestätigen — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestFocusWarningForever.png)

## 6.5.2

Das Folgen deiner echten Gruppe setzt nach der Vorschau wieder ein.

### Korrektur an der Vergleichsvorschau

- Wenn du die Vorschau des Gruppenquestlogs schließt, wird dein bereits bestehendes Folgen eines echten Gruppenmitglieds fortgesetzt.

## 6.5.1

Die Fokusknöpfe sind eindeutiger, ein Wechsel beim Folgen wird bestätigt und die Questsymbole passen zu Blizzards Zielverfolgung.

### Farbige und graue Fokusknöpfe

- Beim Folgen bleibt nur die aktive Quest des verfolgten Spielers farbig. Ohne Folgen sind deine eigenen Knöpfe und die aktiven Quests der Mitspieler farbig. Alle übrigen Knöpfe sind grau, ohne Verblassen. Aktive Quests der Mitspieler bleiben anklickbar, um das Folgen zu beginnen oder zu wechseln.

### Fokuswechsel bestätigen

- Wählst du eine eigene Quest oder einen anderen Mitspieler, fragt QT vor dem Ende des bisherigen Folgens nach. Das gilt auch beim Ändern oder Löschen des Fokus in Blizzards Zielverfolgung: Bis zur Entscheidung stellt QT den verfolgten Fokus wieder her. Abbrechen setzt das Folgen fort, „Fokus ändern“ übernimmt deine Wahl. /qt preview unfollow zeigt den Dialog.

### Passende Symbole für abgabebereite Quests

- QT nutzt für die Abgabebereitschaft nun dieselbe Abschlussabfrage wie Blizzards Zielverfolgung. Lieferquests zeigen dadurch korrekt ein Fragezeichen statt eines Fortschrittssymbols. Der korrigierte Status wird auch im Gruppenquestlog geteilt.

### Vorschau mit deinen eigenen Quests

- Die Vergleichsvorschau verwendet dein echtes Questlog mit vier simulierten Mitspielern und zusätzlich fehlenden Quests. Fokusaktionen verändern dabei deine echte Blizzard-Navigation; das Teilen bleibt simuliert. Im Namensmenü eines Mitspielers kannst du dessen Fokus weiterschalten. Bei nicht teilbaren Quests steht mittig „Nicht teilbar“ oder „Teilbarkeit unbekannt“, statt eine leere Aktionsspalte zu zeigen.

## 6.5.0

Du steuerst den Questfokus jetzt direkt im Gruppenquestlog. Das Folgen eines Mitspielers bleibt auch nach dem Neuladen erhalten.

### Questfokus über die Spalten wählen

- Questknöpfe im Blizzard-Stil ersetzen die Fokustitel in den Spielerüberschriften. In deiner Spalte wählst du damit deine hervorgehobene Quest. Die ausgewählten Knöpfe der Mitspieler zeigen deren Fokus; ein Klick darauf beginnt das Folgen.

### Folgen über Unterbrechungen hinweg

- Deine Auswahl wird pro Charakter gespeichert und übersteht das Neuladen sowie vorübergehende Datenlücken. Frische Gruppenmeldungen gleichen deinen Fokus an, sofern du die Quest besitzt. Eigene Navigation, das Ausscheiden des verfolgten Mitglieds, die Auflösung der Gruppe oder die Umwandlung in einen Schlachtzug beenden das Folgen.

### Wenn dir die nächste Quest fehlt

- Wechselt der verfolgte Spieler zu einer Quest, die du nicht besitzt, endet das Folgen, ohne deine Navigation zu ändern. Ein Dialog erklärt den Grund und öffnet das Gruppenquestlog, damit du die Quest anfragen und danach erneut folgen kannst. Mit /qt preview focus siehst du den Dialog; /qt preview compare lässt dich Knöpfe und simulierte Fokuswechsel ausprobieren.

## 6.4.3

Dein Questfokus wird zuverlässiger angezeigt. Gruppenlisten reagieren schneller, und die Kartenanzeige hat eine einfachere Einstellung.

### Dein eigener Questfokus

- Die Überschrift im Gruppenquestlog liest deine hervorgehobene Quest direkt aus dem Spiel, auch allein oder bei ausgeschalteter Fokusfreigabe. Ein Fokuswechsel erscheint ohne manuelle Aktualisierung.

### Gruppenmitglieder im Tooltip

- Während die vollständige Liste einer kleinen Gruppe lädt, stehen der überfahrene Spieler und der Leiter bereits darin. Der Ladehinweis erscheint nur, solange weitere Mitglieder fehlen. Gruppen über fünf Spielern zeigen weiterhin nur den Leiter.

### Ein Schalter für beide Karten

- „Andere Spieler auf Karte und Minimap anzeigen“ steuert jetzt beide Ansichten gemeinsam. Deine eigene Standortfreigabe bleibt davon unabhängig. War bisher mindestens eine Kartenanzeige eingeschaltet, bleibt die Anzeige aktiv; waren beide aus, bleibt sie aus.

## 6.4.2

Du kannst Queststände gezielter aktualisieren, Kartenanzeigen getrennt steuern und QT-Fenster besser an deine Darstellung anpassen. Für Rückmeldungen und Hilfe erreichst du uns weiterhin auf Discord.

### Queststände gezielt erneuern

- Die Spielerüberschriften zeigen, wie aktuell die jeweilige Questliste ist. Im Menü eines Spielers kannst du nur dessen Daten neu anfordern.
- Unter „Filter“ lässt sich eine automatische Aktualisierung einschalten. Solange das echte Gruppenquestlog geöffnet ist, fordert sie etwa alle 30 Sekunden einen neuen Stand an.
- Suche, aufgeklappte Quests, horizontale Position und möglichst auch die sichtbare Questposition bleiben beim Eintreffen neuer Daten erhalten.
- Fokusangaben unterscheiden nun wartende, abgelaufene und nicht unterstützte Daten. Kann QT fehlende Freigabe und fehlende Verfügbarkeit nicht auseinanderhalten, wird das ausdrücklich so benannt. Das Menü warnt außerdem vor einer Schleife beim Folgen.

### Fenstergröße und Barrierefreiheit

- Die neuen Barrierefreiheitsoptionen bieten eine Fensterskalierung von 80 % bis 150 % und reduzierte Bewegung. Letztere ersetzt weiches Scrollen und Aufklappen durch sofortige Änderungen.
- Die Skalierung vergrößert Text und Bedienelemente gemeinsam. Falls nötig, begrenzt QT sie so, dass das gesamte Fenster auf den Bildschirm passt.
- Gruppenquestlog und Willkommensfenster speichern Größe und relative Bildschirmposition je Profil. Nach Änderungen an Auflösung oder UI-Skalierung werden QT-Fenster wieder eingepasst.
- Mit „Fensteranordnung zurücksetzen“ unter Barrierefreiheit oder /qt resetlayout löschst du gespeicherte QT-Fensterpositionen und zentrierst die Fenster erneut.

### Standortanzeigen auswählen

- Weltkarten- und Minimap-Anzeige lassen sich unabhängig voneinander und von der Standortfreigabe schalten. Das Ausblenden deiner Anzeige ändert also nicht, was du selbst freigibst.
- Der Spielerfilter bietet alle QT-Spieler, Questpartner oder nur die eigene Gruppe.
- „Meine Gruppe immer anzeigen“ ist standardmäßig aktiv. Dadurch bleibt sie auch beim Questpartnerfilter sichtbar, soweit die Standortfreigaben der Mitglieder das zulassen.

### Weitere Verbesserungen

- Die experimentelle Ebenenerkennung behält ihre Einstellungen und Oberfläche. Ändern sich lokale Beobachtungen oder warten nahe Kandidaten noch auf eine neue Anfrage, läuft die Anfrageverwaltung gleichmäßiger.
- QT-Dialoge schließen mit Escape über ihren normalen Schließvorgang. Dem Gruppenquestlog kannst du in WoWs Tastenbelegung eine Taste zuweisen; voreingestellt ist keine.
- Überfahre Quest- und Zielzeilen, um ihren vollständigen Text zu lesen. Die Regler für Fensterskalierung und Umkreis haben hellere Leisten mit dunklem Umriss.

## 6.4.1

QT kann versuchsweise erkennen, ob nahe Spieler wahrscheinlich auf einer anderen Ebene spielen.

### Experimentelle Ebenenerkennung

- Die Erkennung ist unter Einstellungen > QuestTogether > Experimentell standardmäßig eingeschaltet. Schaltest du „Unterschiedliche Ebenen erkennen“ aus, beendet QT die Vergleiche und blendet abgeleitete Phasensymbole aus.
- In Forevers offener Welt vergleichen nahe kompatible QT-Clients ihre NPC-Beobachtungen und sichtbaren Spieler. Ein Phasensymbol weist auf eine wahrscheinlich andere Ebene hin; der Tooltip erklärt Näheres. Dafür muss die Standortfreigabe aktiv sein.
- Die Einschätzung kann falsch sein. Ein nicht sichtbarer Spieler allein genügt nicht als Nachweis. Sehen sich beide Spieler oder sehen sie denselben weiteren Spieler, hat das Vorrang vor dem NPC-Vergleich. Veraltete Beobachtungen verfallen automatisch. Ältere QT-Clients nehmen nicht teil.

### Abbildungen auf Discord

- Bilder aus den Versionshinweisen werden direkt zu Discord hochgeladen, damit sie in den Changelog-Beiträgen sichtbar bleiben.

## 6.4.0

Das Gruppenquestlog ist schneller erreichbar, zeigt kompaktere Zielbereiche und fügt sich mit den übrigen QT-Fenstern in ein einheitliches Design ein.

### Die Gruppe im Questlog überblicken

- Das mit 6.3 eingeführte Gruppenquestlog vergleicht bis zu fünf Spieler in klassenfarbigen Spalten. Du siehst, wer eine Quest besitzt, wem sie fehlt und ob alle abgabebereit sind. Suche und kombiniere Besitz-, Fortschritts- und Aktionsfilter. Wo möglich, stehen Teilen und Teilanfrage bereit.
- Die Spielerüberschrift zeigt die Fokusquest. Über den Namen eines Mitspielers kannst du seinem Fokus folgen; das ist freiwillig und lässt deine Navigation unangetastet, wenn dir die Quest fehlt. „Aktualisieren“ lädt einen neuen Stand der anderen Spieler. Die Abbildungen verwenden erfundene Vorschaudaten.
- Bei eigenen Quests öffnet ein kleiner Buchknopf die Details in Blizzards Questlog. Ein Klick auf die Zeile klappt weiterhin die Ziele auf.
- Eine Krone kennzeichnet den Gruppenleiter und folgt einem Leiterwechsel. Deine eigene Spalte steht immer zuerst.

**Retail**

![Die Gruppe im Questlog überblicken — Retail](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogRetail.png)

**Forever**

![Die Gruppe im Questlog überblicken — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogForever.png)

### Alle Ziele einer Quest aufklappen

- Ein Klick auf die Quest zeigt die Zähler, Fortschrittsbalken und abgeschlossenen Schritte aller Mitglieder. Mehrere Quests können offen bleiben. Die Bereiche sind jetzt kompakter; Überschrift und Inhalt verwenden passende Klassenfarben. Eine typische Fünfergruppe mit je zwei Zielen passt bei Standardgröße ins Fenster. Längere Quests können weiterhin Scrollen erfordern.

**Forever**

![Alle Ziele einer Quest aufklappen — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestObjectivesForever.png)

### Fenster und Minimapbedienung

- Ein Linksklick auf das Minimaplogo öffnet oder schließt das Gruppenquestlog, ein Rechtsklick das Menü. Die Einstellungen sind wieder im Menü enthalten; der Tooltip erklärt die Tastenkombinationen.
- Gruppenchat-Hinweise, Teil- und Beitrittsanfragen, Blaseneinstellungen und der Discord-Linkdialog nutzen nun QTs Schriftrollenrahmen und helles oder dunkles Design. Mehr Innenabstand schafft auch Platz für Reglerwerte.
- Beim Verschieben bleibt der Abstand zum Mauszeiger erhalten, auch in der Vergleichsvorschau. Menüs und Tooltips nennen Blizzards Fenster jetzt einheitlich Questlog.

### Vorschauen ausprobieren

- /qt preview listet die Fenster- und Meldungsvorschauen auf. Die bisherigen Vorschau-Befehle funktionieren weiter. Simulierte Aktionen laden niemanden ein, teilen keine Quests und versenden keine Nachrichten.
- Die Vergleichsvorschau enthält jetzt eine volle Fünfergruppe mit Jäger und Schurke, verschiedenen Zielen, Fokusquests und Leiterkrone.

## 6.3.1

Die Zielbereiche im Gruppenquestlog haben mehr Luft zum Rand.

### Besserer Abstand in aufgeklappten Quests

- Unter den Fortschrittsbalken bleibt jetzt zusätzlicher Platz, damit sie nicht am Rahmen anliegen. Scrollen und Aufklappanimation berücksichtigen den Abstand.
- Hinweise wie „Keine Zieldetails verfügbar“ stehen neben dem Spielernamen vertikal mittig statt dicht am oberen Rand.

## 6.3.0

Mit dem Gruppenquestlog, geteilten Wegpunkten und optionaler Questfolge behält deine Gruppe ihre gemeinsamen Ziele besser im Blick.

### Das Gruppenquestlog

- Aus dem Gruppenquestvergleich wird das Gruppenquestlog. Du kannst mehrere Quests gleichzeitig aufklappen und die Ziele sowie den Fortschritt jedes Mitglieds sehen. Eine Zusammenfassung zeigt, wie weit die Gruppe insgesamt ist.
- Suche nach Quests und kombiniere Filter für Questbesitz, Fortschritt und Teilen. „Aktualisieren“ fordert neue Daten der anderen Spieler an. Ältere Clients können weiterhin Questlisten vergleichen, liefern aber keine Zieldetails.
- Das Pergamentfenster lässt sich skalieren und weich scrollen. Klassenfarbige Spalten, großzügigere anklickbare Spielerüberschriften und abgerundete Zielbereiche erleichtern das Lesen.

### Questfokus und gemeinsame Wegpunkte

- Unter jedem Namen steht die aktive Quest. Über die Spielerüberschrift oder das QT-Menü kannst du dem Questfokus dieses Mitglieds folgen, sofern du die jeweilige Quest besitzt. Fehlende oder gelöschte Quests verändern deine Navigation nicht. Eigene Navigation, Verlassen der Gruppe oder Neuladen beenden das Folgen.
- Blizzard-Wegpunkte anderer Mitglieder erscheinen in ihrer Klassenfarbe auf der Weltkarte und in der Nähe auf der Minimap. Überlappende Punkte nennen alle Besitzer. „Hierhin navigieren“ verwendet TomTom oder die Spielnavigation. Ein empfangener Punkt ändert dein Ziel nicht automatisch und bestätigt keine gemeinsame Phase.
- Unter „Gruppen & Teilen“ sind das Teilen der eigenen Fokusquest und des eigenen Wegpunkts sowie das Anzeigen von Gruppenwegpunkten zunächst eingeschaltet. Sie sind unabhängig von öffentlicher Standortfreigabe und Partnersuche. Das Folgen muss ausdrücklich aktiviert werden. Die Funktionen benötigen aktualisierte Clients und Gruppen mit höchstens fünf Spielern, auch in Dungeons; Schlachtzüge sind ausgeschlossen.

### Fenster und Menüs

- Versionshinweise nutzen jetzt ebenfalls das dunkle Pergamentdesign; ein helles Design ist wählbar. Du kannst das Fenster verschieben und vergrößern, den übersichtlicheren Verlauf verwenden und per Pfeil zwischen Versionen oder an dessen Anfang und Ende springen. Discord und Einstellungen findest du in der Fußzeile.
- Spielertooltips passen sich ihrem Inhalt enger an. Das Minimapmenü trennt Questwerkzeuge von Versionshinweisen, Protokollplatzierung und Iconsichtbarkeit. Einstellungen und das Senden einer QT-Chatnachricht entfallen dort; die Einstellungen erreichst du weiter über /qt options.

## 6.2.3

QT meldet die Abgabebereitschaft einer Quest nicht mehr wiederholt, wenn sich nur die Datenlage aktualisiert.

### Abgabebereitschaft ohne Wiederholungen

- Ist eine Quest beim Beginn der Erfassung schon abgabebereit oder abgeschlossen, wird sie still vermerkt. Fehlende Statusangaben und spätere Aktualisierungen lösen keine bereits beobachtete Bereitschaftsmeldung erneut aus.
- Neue Abschlüsse werden weiter gemeldet. Nimmst du dieselbe Quest erneut an, beginnt ihre Meldungshistorie von vorn. Die Korrektur muss beim Absender installiert sein; ältere Versionen können weiterhin mehrere Meldungen auslösen.

## 6.2.2

Fortschrittsmeldungen behalten ihre verständliche Zielbeschreibung, auch wenn die Gruppe unterschiedliche Sprachen verwendet.

### Zieltext und Zähler bleiben erhalten

- Fortschritt von Quests, Weltquests und Bonuszielen verwendet im Chat und in Blasen wieder den ursprünglichen Text samt Zähler des Absenders. Allgemeine Ersatztexte wie „Ziel 1: 5/5“ entfallen.
- Beim Annehmen und Abschließen von Quests bleiben die Ereignisbezeichnungen übersetzt; verfügbare lokale Questtitel werden weiterhin verwendet.

## 6.2.1

Du erkennst leichter, wann QT zusätzlich in den normalen Gruppenchat schreibt, und kannst vorher darüber entscheiden.

### Gruppenchatmeldungen bewusst einschalten

- Die Einstellung unter „Wo ankündigen“ erklärt nun ausdrücklich: QT schreibt auch in den Gruppenchat, wenn ein Mitglied nicht als QT-Nutzer erkannt wird. Die Option bleibt standardmäßig eingeschaltet.
- Nach einer kurzen Erkennungsphase erscheint ein Dialog mit QT-Logo. Bevor die Weiterleitung beginnt, kannst du sie eingeschaltet lassen oder ausschalten. „Nicht erneut erinnern“ speichert deine Bestätigung im aktuellen Profil.
- Der übersetzte Hinweis nennt die betroffenen Mitglieder und kann bei neuen, noch nicht erkannten Mitgliedern wieder erscheinen. Sobald sie als QT-Nutzer erkannt werden, verschwindet er. Während des Wartens zurückgehaltene Ereignisse werden nicht nachträglich gesendet.

## 6.2.0

Nahe Kartenpunkte bewegen sich flüssiger, Spielerdetails laden schneller und die Kommunikation arbeitet zuverlässiger.

### Flüssigere Bewegung auf der Minimap

- Nahe Spieler können ihre Positionen nun über zeitlich begrenzte Addon-Flüsternachrichten austauschen. Bis zu vier der nächsten geeigneten Spieler werden bevorzugt. Freigaben, Filter, Ignorierliste und Verkehrsgrenzen gelten auch für diesen Austausch.
- Für diese Standortübertragung und direkte Antworten auf Hover-Anfragen brauchen beide Seiten das Update. Ältere Versionen senden weiterhin ihre normalen Meldungen. Verzögerungen und Einschränkungen des Servers können die Zustellung nach wie vor beeinflussen.

### Spieler und Gruppen schneller kennenlernen

- Beim Überfahren eines Namens oder Punkts kann QT aktuelle Angaben direkt anfordern. Die Anfragehäufigkeit ist begrenzt. Unveränderte Gruppenlisten verfallen nicht mehr schon nach zwei Minuten.
- Aktuelle Standorte, Suchstatus und bekannte Gruppenangaben bleiben über /reload hinweg erhalten, höchstens jedoch drei Minuten ab ihrer ursprünglichen Erfassung. Beim Gebietswechsel fragt QT außerdem zeitlich verteilte Aktualisierungen an.
- Während die genaue Gruppengröße noch fehlt, nutzt der Tooltip den bekannten Allein- oder Gruppenstatus. Ein kleines Logo kennzeichnet QT-Nutzer in der Mitgliederliste; die Namen bleiben bündig.

### Verständliche Texte und Symbole

- Volksnamen, Ping-Angaben, Questdaten und weitere Oberflächentexte verwenden verfügbare lokale Übersetzungen. Fehlen Questübersetzungen, bleibt der lesbare Absendertext erhalten. Fortschrittsmeldungen übernehmen keine unpassenden lokalen Zielbeschreibungen.
- Allgemeine Meldungen tragen jetzt das QT-Logo. Die Questpartnersuche steht im Minimapmenü an erster Stelle.

### Zuverlässiger und mit weniger Wiederholungen

- Questvergleiche, Gruppenlisten, Beitritts- und Teilanfragen sowie Ping-Antworten bevorzugen bei kompatiblen Clients direkte Flüsternachrichten. Zusammengefasste Statusmeldungen und weniger Wiederholungen unveränderter Standorte entlasten die öffentlichen Kanäle.
- Behoben wurden wiederholte Questdurchläufe, übermäßig viele erneute Versuche an Namensplaketten und Dialoge, die sich bei Spielbeschränkungen nicht schließen ließen. /qt set akzeptiert nur noch Ein-Aus-Einstellungen. Das Abschalten der Standortfreigabe verwirft keine anderen wartenden Anfragen mehr.

## 6.1.2

Nahe Spielerpunkte werden schneller aktualisiert. Questmeldungen verwenden auch bei fehlenden Questdaten die Ereignisbezeichnung in deiner Sprache.

### Fehlende Minimap-Punkte

- Liefert die Minimap keine Karten-ID, greift QT auf deine aktuelle Karte zurück. Dadurch erscheinen Spielerpunkte, die in diesem Fall bisher fehlten.

### Häufigere Standortmeldungen in kleinen Gruppen

- Bei weniger als 10 bekannten QT-Nutzern im Gebiet liegt das Zielintervall nun bei einer Sekunde, bei 10–19 bei 5–10 Sekunden und bei 100 bei 15–20 Sekunden. Dazwischen steigen die Abstände schrittweise an. Ab 500 Nutzern bleibt der Rhythmus unverändert.
- Die schnellen Meldungen enthalten kompakte, frisch erfasste Koordinaten. Andere Spielerdetails werden weiterhin seltener übertragen. Die bisherigen Verkehrsgrenzen gelten weiter, sodass volle Kanäle die Zustellung verzögern können. Für häufigere Standortmeldungen müssen die jeweiligen Absender aktualisieren.

### Meldungen in deiner Sprache

- Bezeichnungen wie „Quest angenommen“ verwenden deine Sprache auch dann, wenn ein lokaler Questtitel oder zusätzliche Übersetzungsangaben fehlen.
- Findet WoW keinen lokalen Questnamen, bleibt der lesbare Titel des Absenders erhalten. Fortschrittstexte werden ebenfalls unverändert übernommen, wenn sie sich nicht verlässlich neu zusammensetzen lassen.

## 6.1.1

Die Menüs für Spieler- und Questnamen enthalten weniger Umwege.

### Aufgeräumte Kontextmenüs

- Die Auswahl des Protokollfensters entfällt in den Menüs für Spieler- und Questnamen. Ob QT im Hauptchat oder in einem eigenen Fenster protokolliert, stellst du weiterhin im Minimapmenü oder in den Einstellungen ein.

## 6.1.0

Auf der Karte erkennst du jetzt, wer zusammen questet. Spielertooltips zeigen die Gruppe, und Beitrittsanfragen können über ein beliebiges Mitglied an den Leiter gelangen.

### Gruppen auf der Karte erkennen

- Gruppierte Spieler tragen ein kleines Zweipersonensymbol an ihren Weltkarten- und Minimap-Punkten. Beim Überfahren eines Mitglieds erhalten seine Gefährten einen weißen Umriss, andere Punkte werden abgedunkelt und der Leiter bekommt eine Krone. Der goldene Schimmer der Partnersuche bleibt sichtbar.
- Im Tooltip stehen die Gruppenmitglieder mit klassenfarbigen Punkten und Namen; der Leiter erscheint mit Krone zuerst. Bis fünf Mitglieder werden alle aufgeführt, bei größeren Gruppen nur der Leiter. Diese Angaben erscheinen auch über Spielernamen im QT-Protokoll.
- Für deine eigene Gruppe nutzt QT die Spielerliste des Spiels. Angaben zu anderen Gruppen werden bei Bedarf von aktualisierten QT-Clients angefordert und zwischengespeichert; die Anfragen sind begrenzt. Ältere Clients behalten ihre normalen Punkte und die einfache Gruppengröße. Für vollständige Angaben muss die Gegenstelle aktualisiert sein.

### Beitrittsanfragen weiterleiten

- Du kannst den Beitritt auch über jemanden anfragen, der selbst nicht einladen darf. Nutzt dessen Gruppenleiter QT und kann er einladen, wird die Anfrage mit den üblichen Bestätigungs- und Freigabeeinstellungen an ihn weitergeleitet.
- Ist beim Leiter keine QT-Nutzung bekannt, kann das Mitglied bei eingeschalteten Gruppenchatmeldungen stattdessen im Gruppenchat auf deine Anfrage hinweisen. Jemand mit Einladungsrecht muss dich dann von Hand einladen.
- Für die Weiterleitung brauchen sowohl der Anfragende als auch das weiterleitende Mitglied diese Version. Die bisherigen Prüfungen auf volle Gruppen, Einschränkungen, ignorierte Spieler, abgelaufene Anfragen und Anfragehäufigkeit gelten weiterhin.

### Übersichtlichere Spielertooltips

- Die Gruppe steht direkt unter Stufe, Volk und Klasse. Die Mitgliederzeilen sind kompakter, die Abschnitte haben mehr Abstand. Allianz- und Hordezeichen sind doppelt so groß.
- Die Addon-Version steht am Ende in der Kurzform vX.Y.Z. Wird das Alter des Standorts angezeigt, steht die letzte Aktualisierung direkt darüber.
- Die Zahl erfasster Quests entfällt in Spieler- und Minimapknopf-Tooltips. Die aktive Quest von Spielern auf Partnersuche bleibt sichtbar.

## 6.0.2

Du kannst ältere Versionshinweise jetzt direkt im Spiel und in deiner Sprache durchblättern. Außerdem findet QT Questnamen nach der Abgabe zuverlässiger wieder.

### Frühere Versionen nachlesen

- Das Willkommensfenster bietet Knöpfe für ältere und neuere Hinweise, einen Sprung zur neuesten Version sowie eine Verlaufsauswahl mit Versionsnummern und Datum. Beim Öffnen beginnst du mit der neuesten Ausgabe.
- Der Verlauf umfasst alle bisherigen Veröffentlichungen einschließlich der frühen Betas. Die Hinweise sind für alle unterstützten WoW-Sprachen enthalten und stehen auch in den jeweiligen Changelogs des Repositorys.
- Am Ende des Verlaufs werden die entsprechenden Navigationsknöpfe deaktiviert. Das Lesen älterer Hinweise ändert nicht, welches Upgrade du bereits bestätigt hast. Automatisch öffnet sich das Fenster weiterhin nur bei Haupt- und Nebenversionen; mit /qt notes erreichst du es jederzeit.

### Questnamen nach der Abgabe

- Verschwindet eine Quest aus deinem Log, bevor QT einen brauchbaren Namen erfasst hat, fragt die Abschlussmeldung nun zunächst die verfügbaren Questtitel-Funktionen des Spiels ab. Ein gefundener Name bleibt erhalten, unabhängig von der Reihenfolge der Abgabe- und Entfernen-Ereignisse.
- Kann dein Client keinen lokalen Titel ermitteln, bleibt der Text des Absenders erhalten. Haben beide Seiten keinen Namen, dient weiterhin die Quest-ID als Ersatz. Die bessere Erfassung beim Absender setzt dessen Aktualisierung voraus.

## 6.0.1

QT feiert den Fortschritt anderer Spieler nur noch mit, wenn du sie tatsächlich in deiner Nähe sehen kannst.

### Feier-Emotes für sichtbare Spieler

- Eine Reaktion auf den Questabschluss oder Stufenaufstieg eines anderen Spielers setzt jetzt eine passende sichtbare Spielereinheit voraus. Ein Name oder Kartenkoordinaten allein lösen kein Emote mehr aus, auch nicht mit devlogall.
- Empfangene Emotes müssen in QTs eigener Liste für Feieraktionen stehen. Andere Emotes, darunter mountspecial und Fraktionsrufe, werden ohne Ersatz ignoriert.
- Deine eigenen Feieraktionen bei Questabschluss und Stufenaufstieg funktionieren samt Einstellungen wie bisher.

## 6.0.0

QuestTogether 6.0 bereitet die Kommunikation auf den Start von Forever und eine wachsende Spielergemeinschaft vor. Lokale Aktivitäten verursachen dadurch weniger Verkehr außerhalb ihres Gebiets.

### Aktuelles aus dem Gebiet, Spieler aus aller Welt

- Questmeldungen und häufige Spieleraktualisierungen laufen jetzt über Gebietskanäle. Gruppenmeldungen erreichen deine Gruppe weiterhin über Gebietsgrenzen hinweg.
- Kartenpunkte bleiben weltweit verfügbar, werden außerhalb deines Gebiets aber seltener erneuert. Öffnest du ein anderes Gebiet auf der Weltkarte, empfängst du vorübergehend auch dessen Aktualisierungen.
- Der geschriebene QT-Chat bleibt im globalen Kanal QuestTogether. Ob du globale oder nur gebietsbezogene Chatnachrichten siehst, bestimmst du weiterhin selbst.

### Weniger Nachrichten im Hintergrund

- Anwesenheit, Version, Questzahl, Suchstatus und Standort werden in kompakten Meldungen gebündelt. In vollen Gebieten werden sie seltener gesendet.
- Questmeldungen werden dosiert versendet und vor Hintergrundaktualisierungen eingeordnet. Ping-Antworten verteilen sich zeitlich, damit nicht alle gleichzeitig eintreffen. WoW kann die Zustellung trotzdem verzögern; sofortige Übertragung ist damit nicht garantiert.
- Spielertooltips zeigen das Alter älterer Standorte. In Diagnosen findest du jetzt Nachrichtenzahlen, Drosselungen und vom Absender gemeldete Verzögerungen bei Ankündigungen.

### Die Umstellung erfolgt während der Beta

- Wir nehmen diese größere Änderung im Vorfeld des Forever-Starts vor. In der Beta lassen sich solche Grundlagen noch anpassen, bevor sich mehr Spieler auf das bisherige Verhalten verlassen.
- Version 6.0 verlässt QuestTogetherAnnounce1 und sendet oder empfängt dort nicht mehr. Globale Gespräche und Spielersuche verwenden QuestTogether, lokale Aktivitäten die Gebietskanäle.
- Die QT-Kanäle stehen hinter deinen übrigen Chatkanälen, mit dem Hauptkanal vor den Gebietskanälen. Standortfreigabe, Ignorierliste und Meldungseinstellungen bleiben erhalten.

### Bitte gemeinsam aktualisieren

- Ältere Versionen verstehen die gebündelten Spielerdaten nicht und hören nicht auf den neuen Gebietskanälen mit. Bei unterschiedlichen Versionen können deshalb Kartenpunkte, Suchstatus und nahe Questmeldungen fehlen.
- Spieler, die nur den alten Kanal verwenden, werden darüber von 6.0 nicht mehr erkannt. Mit neueren 5.x-Versionen können einzelne Nachrichten über den gemeinsamen globalen Kanal oder die Gruppe noch funktionieren; das ist jedoch nur eine teilweise Kompatibilität.
- Der manuelle Befehl /qt ping verwendet weiterhin den globalen Kanal und kann dort kompatible ältere Clients erreichen. Er hilft bei der Suche, liefert aber keine vollständige Zählung aller QT-Spieler.

## 5.17.2

Chatnachrichten und Questmeldungen lassen sich farblich leichter auseinanderhalten.

### QT-Chat in Weiß

- Geschriebene QT-Chatnachrichten erscheinen im Protokoll und in den Blasen jetzt in Weiß.
- Spielernamen behalten ihre Klassenfarbe, Questmeldungen ihren gelben Text.

## 5.17.1

Spielertooltips geben mehr Auskunft über deine Questgefährten. Deinen eigenen Queststand kannst du direkt im Chat nachsehen.

### Mehr Angaben zu Spielern

- Bei Spielernamen und Kartenpunkten siehst du jetzt die Zahl der von QT erfassten Quests sowie „Allein“ oder die Gruppengröße. Dein eigener Tooltip verwendet die aktuellen lokalen Daten.
- Auch der Minimaptooltip zählt nun die von QT erfassten Quests, passend zur Startmeldung. Bisher zählte er nur die Quests in WoWs Zielverfolgung.
- Questzahl und Gruppengröße anderer Spieler benötigen einen aktualisierten Client. Sie werden etwa alle 80 Sekunden in den vorhandenen Statusmeldungen erneuert, ohne zusätzliche Nachrichten. Fehlende oder veraltete Angaben erscheinen als unbekannt. Ältere Versionen erhalten weiterhin kompatible Versionsmeldungen.

### Queststand beim Überfahren

- Über einem Questnamen im QT-Protokoll zeigt ein Tooltip neben dem Mauszeiger deinen Status, die Teilbarkeit, die Quest-ID und deinen lokal erfassten Zielfortschritt.
- Der bisherige Menüpunkt „Status“ entfällt. Mit einem Klick auf den Questnamen erreichst du weiterhin Teilen, Öffnen im Questlog, Gruppenquestvergleich und die Auswahl des Protokollfensters.
- Die neuen Beschriftungen sind in allen unterstützten Sprachen verfügbar. Der angezeigte Queststand ist deiner, nicht der des Absenders.

## 5.17.0

Unterhalte dich im QT-Chat, finde Questpartner in deinem Gebiet und erfahre mehr über andere Spieler direkt im Tooltip.

### Mit anderen QT-Spielern chatten

- Mit /qt <text> schreibst du in den QT-Chat. Alternativ kannst du im Minimapmenü „QT-Chatnachricht senden“ wählen. Nachrichten erscheinen mit einem Sprechblasensymbol im QT-Protokoll und bei nahen Spielern über dem Kopf. Die bisherigen Befehle bleiben verfügbar.
- Du kannst zwischen globalem Chat, nur deinem Gebiet und ausgeblendetem QT-Chat wählen. Standard ist global. Für die Gebietsauswahl braucht QT einen aktuellen freigegebenen Standort des Absenders; beim globalen Chat ist das nicht nötig.
- Der neue Kanal QuestTogether läuft während der Umstellung neben QuestTogetherAnnounce1. Soweit der Client es unterstützt, stehen beide hinter deinen anderen Kanälen, mit QuestTogether zuerst. Geschriebene Chatnachrichten verwenden ausschließlich den neuen Kanal.

### Questpartner finden

- Wenn du die Questpartnersuche einschaltest, meldet QT deine Suche im gesamten Gebiet mit golden leuchtendem Logo und einem Smiley. Dafür muss die Standortfreigabe eingeschaltet sein; deine Meldungseinstellungen werden berücksichtigt. Beim Ausschalten wird keine Meldung versendet.
- Unter „Was ankündigen“ legst du fest, ob diese Meldungen erscheinen. Zwischen wiederholten Suchmeldungen liegen mindestens 30 Sekunden; Status und Schimmer ändern sich trotzdem sofort. Auf Wunsch endet die Suche beim Gruppenbeitritt automatisch. Diese Option ist zunächst ausgeschaltet.
- Mit Umschalt-Klick auf den Minimapknopf schaltest du die Suche um. Solange sie aktiv ist, hebt ein hellerer, pulsierender Goldring den Knopf hervor, ohne das Logo abzuschneiden.

### Reichweite und Spielerdetails

- Die Einstellung für nahe Spieler reicht nun von 5 % bis zum gesamten Gebiet; voreingestellt sind 25 %. Sie bemisst die Entfernung anhand der Gebietsgröße. Für Gruppenmitglieder und direkt sichtbare Spieler gelten weiterhin die bisherigen Regeln.
- Überfahre einen Namen im QT-Protokoll, um denselben erweiterten Tooltip wie bei Kartenpunkten zu sehen: klassenfarbiger Name, Stufe, Volk, Klasse, Fraktionswappen, Suchstatus, gegebenenfalls die verfolgte Quest und QT-Version. Der Tooltip steht jetzt neben dem Mauszeiger.
- Bei aktiver Partnersuche zeigt dein eigener Namenstooltip deine aktuell hervorgehobene Quest. Aktualisierte Clients übermitteln ihre Version etwa alle 40 Sekunden in den vorhandenen Statusmeldungen; ältere Clients behalten ihren bisherigen Rhythmus.

### Bessere Erläuterungen und Questnamen

- Der Minimaptooltip zeigt QT-Version, Suchstatus, Chatbereich, Zahl der verfolgten Quests, Umkreis und Standortfreigabe.
- In den Einstellungen erklären übersetzte Tooltips auch Dropdowns, Schieberegler, Profilaktionen und Farbauswahl.
- Findet dein Client keinen Questtitel in deiner Sprache, behalten Protokoll und Blasen den lesbaren Titel des Absenders bei. Sobald ein lokaler Titel verfügbar ist, verwenden spätere Meldungen wieder diesen.

## 5.16.7

Die Versionshinweise sind jetzt im Spiel, auf Discord und in den Changelog-Dateien aufeinander abgestimmt – auch in deiner Sprache.

### Einheitliche Versionshinweise in allen Sprachen

- Das englische Changelog verwendet dieselben Zusammenfassungen und Punkte wie das Willkommensfenster und die Discord-Beiträge.
- Für jede unterstützte Sprache gibt es eine Changelog-Datei mit den bereits übersetzten früheren Versionen. Die älteren, von Hand geschriebenen englischen Hinweise bleiben separat erhalten.
- Die Release-Prüfungen gleichen die Dateien mit den maßgeblichen Versionshinweisen und ihren Sprachfassungen ab.

## 5.16.6

Am Minimapknopf erkennst du sofort, ob deine Questpartnersuche eingeschaltet ist.

### Goldener Hinweis auf die Partnersuche

- Während du nach Questpartnern suchst, pulsiert dein QT-Minimapknopf mit demselben goldenen Logoschimmer wie die Spieler-Namensplaketten.
- Der Schimmer folgt deinem Suchstatus und endet, wenn QT deaktiviert oder der Knopf ausgeblendet wird. Knopf und Logo behalten ihre bisherige Größe.

## 5.16.5

Gruppenmeldungen nehmen mit einem kürzeren Präfix weniger Platz ein.

### Kompakte Gruppenmeldungen

- Questfortschritt für Gruppenmitglieder ohne QuestTogether beginnt wieder mit [QT] statt [QuestTogether].
- Die Nachrichten halten weiterhin die Chatlängengrenze ein und schneiden in keiner Sprache einzelne Zeichen ab.

## 5.16.4

Deine Blaseneinstellungen bleiben nach dem Bearbeitungsmodus erhalten. Auf vollen Karten bekommen Spieler in deiner Nähe Vorrang.

### Blaseneinstellungen behalten

- Beim Schließen des HUD-Bearbeitungsmodus bleiben Schriftgröße, Anzeigedauer und Position deiner QT-Blase erhalten, statt zurückgesetzt zu werden.
- Das QT-Blasenfenster hat einen eigenen Knopf zum Speichern und einen Hinweis auf den Speicherstand. Änderungen werden sofort angewendet; „Änderungen speichern“ legt fest, wohin „Änderungen verwerfen“ zurückkehrt.
- Wenn du nach dem Speichern weiter anpasst, stellt das Zurücksetzen die zuletzt gespeicherten QT-Einstellungen wieder her.

### Nahe Spieler bevorzugen

- Kommen mehr als 128 passende Kartenpunkte infrage, zeigt die Weltkarte beziehungsweise Minimap bevorzugt die Spieler mit der geringsten Entfernung zu deinem Charakter.
- Ist der Cache mit 512 Standorten voll, bleiben nahe Spieler vor weiter entfernten Neuankömmlingen gespeichert. Verschieben und Zoomen der Karte ändern diese Entfernungspriorität nicht.
- Die bisherigen Obergrenzen bleiben bestehen. Für diese Auswahl werden keine zusätzlichen Nachrichten gesendet.

## 5.16.3

Die Einstellungen sind übersichtlicher angeordnet. Eine verlinkte Statusübersicht zeigt dir die wichtigsten gespeicherten Vorgaben.

### Einstellungen nach Aufgabe geordnet

- „Gruppen & Teilen“ ersetzt „Verschiedenes“ und bündelt Partnersuche, Beitrittsanfragen und die Erlaubnis zum Teilen von Quests.
- Feier-Emotes findest du unter „Wo ankündigen“. Die Sichtbarkeit des Minimapknopfs liegt auf der Hauptseite unter „Allgemein“; Debugwerkzeuge und erneute Questerfassung sind unter „Fehlerbehebung“ zusammengefasst.
- Gruppenquestvergleich und Questpartnersuche stehen bei den Schnellaktionen an erster Stelle. Deine bisherigen Einstellungen bleiben erhalten.

### Statusübersicht mit direkten Links

- Die Übersicht zeigt Partnersuche, Standortfreigabe und -anzeige, Anfrageregeln, Meldungsausgabe sowie Einstellungen für Quest- und Spieler-Namensplaketten.
- Du siehst das aktive Profil, die installierte Version und gegebenenfalls eine erkannte neuere Version. Bei deaktiviertem QT ist ausdrücklich erkennbar, dass die Übersicht gespeicherte Vorgaben zeigt.
- Ein Klick auf eine Abschnittsüberschrift öffnet die zugehörigen Einstellungen. Die Übersicht wächst mit dem Text und hält sich bei geöffneter Seite aktuell.

## 5.16.2

Spielertooltips zeigen jetzt, wer QuestTogether verwendet. Der goldene Schimmer macht Spieler auf Partnersuche deutlicher sichtbar.

### QT im Spielertooltip

- Wenn du den Charakter, die Namensplakette oder den Einheitenrahmen eines QT-Spielers überfährst, zeigt der Tooltip einen Hinweis auf QuestTogether. Bei aktiver Partnersuche kommen der Suchstatus und ein leuchtendes QT-Logo hinzu.
- Der QT-Bereich passt sich Breite und Skalierung des Tooltips an und hält Abstand zu dessen Gesundheitsleiste. Ist unten zu wenig Platz, erscheint er oberhalb des Tooltips.

### Deutlichere Partnersuche

- Der goldene Schimmer an Namensplaketten reicht jetzt doppelt so weit um das Logo; das Logo selbst bleibt gleich groß.
- Symbole und Schimmer zeigen tatsächliche QT-Nutzer und ihren aktuellen Suchstatus an.

## 5.16.1

Spieler auf Questpartnersuche sind besser erkennbar. Auf der Karte kannst du außerdem sehen, welche Quest sie gerade verfolgen.

### Leuchtende Spielerlogos

- Das Namensplakettenlogo von Spielern auf Partnersuche erhält einen kräftigeren goldenen Schimmer, der sanft pulsiert. Das Logo selbst bleibt ruhig.

### Die aktuell verfolgte Quest

- Überfahre den Weltkarten- oder Minimap-Punkt eines suchenden Spielers, um seine für die Navigation ausgewählte Quest zu sehen. Beide Spieler benötigen dieses Update.
- Die Questangabe wird ungefähr alle 20 Sekunden erneuert und nur geteilt, solange sowohl Questpartnersuche als auch Standortfreigabe aktiv sind.
- Wenn möglich, erscheint der Titel in deiner Sprache; andernfalls wird der Titel des Absenders oder die Quest-ID verwendet. Ältere QT-Versionen behalten ihre vorhandenen Punkte und Suchstatusanzeigen.

## 5.16.0

QT unterstützt jetzt alle WoW-Sprachen. Unterstützte Questereignisse anderer Spieler können in deiner Spielsprache erscheinen.

### Alle WoW-Sprachvarianten

- Menüs, Einstellungen und Versionshinweise gibt es auf Englisch, Deutsch, Französisch, europäischem und lateinamerikanischem Spanisch, brasilianischem Portugiesisch, Russisch, Italienisch, Koreanisch sowie in vereinfachtem und traditionellem Chinesisch.
- Lateinamerikanisches Spanisch hat eigene Texte und verwendet nicht mehr die europäische Variante.

### Questfortschritt in deiner Sprache

- Unterstützte Ereignisse aktualisierter QT-Clients können in Chatprotokollen und Blasen in deiner Sprache erscheinen. Wo verfügbar, werden lokale Questtitel verwendet; die Fortschrittszahlen stammen weiterhin vom Absender.
- Lässt sich ein übersetzter Zieltext nicht sicher zuordnen, zeigt QT stattdessen eine lokalisierte Zielnummer mit Anzahl, Prozentwert, Abschluss- oder Fortschrittsstatus.
- Bei älteren QT-Versionen und im öffentlichen Gruppenchat bleibt die Formulierung des Absenders erhalten. Liefert WoW keinen lokalen Questtitel, verwendet QT den ursprünglichen Titel oder die Quest-ID. Gleichsprachige Meldungen behalten ihren ausführlichen Wortlaut.

### Questtitel

- Der Questvergleich bevorzugt verfügbare Titel in deiner Sprache. Lokalisierte Questlinks mit Satzzeichen außerhalb des ASCII-Zeichensatzes bleiben zuverlässiger anklickbar.

## 5.15.0

Über das QT-Spielermenü kannst du anfragen, ob du einer Questgruppe beitreten darfst.

### Einer Gruppe beitreten

- Liegt eine aktuelle Gruppeninformation vor, zeigt das Menü gruppierter QT-Spieler „Beitritt anfragen“ statt „Einladen“. Beide Spieler brauchen dieses Update; der anfragende Spieler muss allein sein.
- Der Empfänger kann ablehnen oder eine gewöhnliche WoW-Einladung schicken, sofern er einladen darf und in einer normalen Gruppe noch Platz ist. Zum Beitritt nimmst du die WoW-Einladung wie üblich selbst an.

### Einladungen auf Wunsch automatisieren

- Zwei neue Optionen erlauben automatische Einladungen: für Charakterfreunde oder für andere Spieler, solange du nach Questpartnern suchst. Beide sind standardmäßig aus und im Anfragedialog sowie unter „Verschiedenes“ verfügbar. Battle.net-Accountfreunde zählen nicht dazu.
- Anfragen laufen ab und berücksichtigen Ignorierlisten, Gruppenwechsel und Spielbeschränkungen. QT verlässt deine Gruppe nicht und nimmt keine Einladungen für dich an.

## 5.14.1

Gruppenmeldungen nennen das Addon jetzt ausgeschrieben.

### Gruppenchat

- Vor Meldungen im Gruppenchat steht [QuestTogether] statt [QT]. So können andere Spieler das Addon leichter finden.

## 5.14.0

QuestTogether ist in fünf weiteren Sprachen verfügbar. Außerdem kannst du Gruppenmitglieder ohne QT über den Gruppenchat auf dem Laufenden halten.

### Deine Spielsprache

- Die Oberfläche unterstützt jetzt Deutsch, Französisch, Spanisch, brasilianisches Portugiesisch und Russisch. QT richtet sich nach deiner Spielsprache; fehlt ein Text, wird Englisch verwendet.
- Einstellungen, Menüs, Tooltips, Questvergleiche und Versionshinweise sind lokalisiert. Questnamen und Fortschrittstexte anderer Spieler bleiben in deren Originalsprache.
- Auf unserem Discord gibt es die Versionsmeldungen auch in fünf eigenen Sprachkanälen.

### Auch Gruppenmitglieder ohne QT informieren

- Unter „Wo ankündigen“ kannst du deine eingeschalteten Ereignismeldungen zusätzlich im Gruppenchat ausgeben lassen, wenn mindestens ein Gruppenmitglied noch nicht als QT-Nutzer erkannt wurde. Die Option ist anfangs aktiv und lässt sich abschalten.
- Das gilt auch für automatisch zusammengestellte Instanzgruppen, nicht aber für Schlachtzüge oder Solospiel. Meldungen anderer Spieler werden nicht weitergeleitet.

## 5.13.1

Diese Wartung verbessert die Erholung von Questmarkierungen und entfernt veraltete Blasen und Spielerlogos. Einstellungen und Debugfenster reagieren ebenfalls zuverlässiger.

### Questmarkierungen und Spieleranzeigen

- Nach dem Schließen gesperrter Ansichten kehren Questsymbole und Gesundheitsleistenfarben korrekt zurück. Verzögerte Questerfassungen behalten ihre Wartezeit; bei kurzzeitig fehlenden Tooltipdaten bleiben die vorgesehenen Wiederholungsversuche erhalten.
- Meldungsblasen werden entfernt, wenn eine Spieler-Namensplakette im Kampf verschwindet oder anderweitig verwendet wird. Bei geschützten oder unzugänglichen Frames wartet die Bereinigung, bis sie zulässig ist.
- Standorte und Anwesenheitsdaten erholen sich nach Deaktivierung von QT, Gebietswechsel und erneuter Aktivierung. Späte Rücknahmen von Standort- oder Suchstatusmeldungen geben bereits abgemeldeten Spielern kein neues QT-Logo mehr.

### Einstellungen und Fenster

- Die Option zur Questpartnersuche bleibt mit Änderungen durch Befehle, Menüs und Profile synchron.
- Das Debugfenster beendet unterbrochenes Ziehen und Größenändern korrekt, sobald Beschränkungen enden – auch wenn das Fenster inzwischen ausgeblendet wurde.

### Prüfungen und Veröffentlichung

- Die Tests erkennen unzulässige Framezugriffe auch dann, wenn ein Fehler intern abgefangen wird.
- Die Veröffentlichungsprüfung bricht ab, solange Implementierungsänderungen noch nicht eingecheckt sind. So landen die vorgesehenen Korrekturen auch im Download.

## 5.13.0

Ein goldener Schimmer kennzeichnet Spieler auf Partnersuche. Dazu kommen einfachere Standortoptionen und ein Hinweis, wenn andere Spieler bereits eine neuere stabile QT-Version nutzen.

### Questpartner auf einen Blick

- Wer nach Questpartnern sucht, erhält einen sanften goldenen Schimmer um seinen klassenfarbigen Punkt auf Weltkarte und Minimap sowie um sein QT-Namensplakettenlogo. Wird der Status beendet oder läuft er ab, verschwinden die Hervorhebungen.
- Unter „Spielerstandorte“ kannst du beide Karten auf Spieler beschränken, die nach Questpartnern suchen. Dieser Filter ist standardmäßig aus.
- Das Neuigkeitenfenster im Spiel stellt normale und leuchtende Logos und Kartenpunkte nebeneinander dar. Gold bedeutet: Dieser Spieler sucht Questpartner.

### Einfachere Standortfreigabe

- „Meinen Standort teilen“ und „Andere Spieler anzeigen“ gelten jeweils gemeinsam für Weltkarte und Minimap.
- In neuen Profilen sind beide Optionen aktiv. Bereits abgeschaltete Standortfreigaben bleiben beim Update abgeschaltet.

### Hinweise auf neuere Versionen

- Meldet ein anderer Spieler eine neuere stabile QT-Version, erscheint in deinem gewählten QT-Chatfenster ein Updatehinweis.
- Die erkannte Version wird charakterübergreifend gespeichert. Der Hinweis erscheint einmal pro Neuladen, bis du diese oder eine neuere Version installierst. Alpha- und Betaversionen lösen ihn nicht aus.
- Versionsmeldungen sind klein und werden selten gesendet. QT erkennt Versionsangaben auch in vorhandenen Pingantworten.

## 5.12.0

Mit „Suche nach Questpartnern“ zeigst du anderen, dass du Gesellschaft suchst. Standortanzeigen und Minimap-Tooltips wurden ebenfalls überarbeitet; Forever und Retail behandeln Kriegsmodus und Realms jetzt getrennt.

### Gesellschaft zum Questen suchen

- Dein Suchstatus erscheint im Spielermenü und in den Tooltips deiner Kartenpunkte. Er schaltet weder Standortfreigaben ein noch verschickt er Einladungen.
- Umschalten kannst du ihn im Minimapmenü, unter „Verschiedenes“ oder mit /qt lfg. Mit /qt lfg on, off oder status setzt oder prüfst du ihn gezielt. Er ist anfangs aus und wird pro Profil gespeichert.
- Bleiben Aktualisierungen aus, verfällt der Status. Ignorierte Spieler werden ausgeschlossen; bei deaktiviertem QT wird deine Suchmeldung pausiert.

### Retail und Forever

- In Forever entfallen Kriegsmodusangaben in Spielerpunkt-Tooltips, Queststandorten und Pingausgaben. Pings lassen dort auch Realmnamen weg, behalten aber vollständige Spielernamen bei.
- Nahe Questmeldungen benötigen in Forever keine Retail-Kriegsmodusdaten mehr. Kartenpunkte bleiben auch über Phasengrenzen sichtbar, damit du Spieler zum Gruppieren finden kannst.
- In Retail wird der aktive Kriegsmodus verwendet, sofern er bekannt ist. Unbekannter oder nicht unterstützter Kriegsmodus erscheint nicht mehr fälschlich als ausgeschaltet.

### Stabilere Kartenpunkte

- Kurzzeitig fehlende Koordinaten lassen deinen Punkt nicht sofort verschwinden. Die letzte gemeldete Position bleibt bis zu zwei Minuten erhalten; ältere Angaben zeigen ihr Alter im Tooltip. Widerrufene Standortfreigaben werden bei verfügbarer Kommunikation weiterhin sofort zurückgezogen.
- Bewegungsmeldungen werden höchstens alle zehn Sekunden gesendet. Für unbewegte Spieler bleiben die Anwesenheitsmeldungen im Abstand von zwanzig Sekunden erhalten, damit ältere Clients kompatibel bleiben.
- Der Standortcache fasst bis zu 512 Spieler. Pro Karte werden weiterhin höchstens 128 Punkte gezeichnet. Spieler außerhalb des angezeigten Kartenausschnitts verbrauchen dafür keinen Platz mehr.

### Zuverlässigere Spielerlogos

- QT liest die aktuelle Einstellung für freundliche Spieler-Namensplaketten und behebt dadurch fehlende Logos in aktuellen Forever- und Retail-Clients.
- Links platzierte Logos rücken bei sichtbaren Buffs nach außen und kehren zurück, sobald die Buffs verschwinden.
- Alle unterstützten QT-Nachrichten identifizieren ihren Absender. Ein begrenzter Cache merkt sich QT-Spieler bis zum Neuladen der Oberfläche; verpasste Anwesenheitsmeldungen allein entfernen ihr Logo daher nicht mehr. Ausdrückliche Abmeldungen und ignorierte Spieler werden weiterhin entfernt. Zusätzliche Nachrichten sind dafür nicht nötig.

### Minimap-Tooltip

- Der QT-Minimap-Tooltip verwendet eine eigene Darstellungsebene und kann dadurch über Aktionsleisten erscheinen. Er verschwindet, wenn der Knopf nicht mehr verfügbar ist oder Spielbeschränkungen einsetzen.

## 5.11.0

Finde QT-Spieler auf der Karte, erkenne sie an Namensplaketten und vergleiche gezielt ihre Quests. Du entscheidest selbst, welche Standortdaten du teilst und welche du sehen möchtest.

### QuestTogether-Spieler finden

- Bei eingeschalteten freundlichen WoW-Namensplaketten kann neben QT-Spielern das Rollenlogo erscheinen. „Spieler-Namensplaketten“ ist standardmäßig aktiv; das Logo sitzt mit Abstand links. Du kannst auch rechts, oben oder vor dem Namen wählen, ohne die Gesundheitsleisten einzufärben.
- Spieler, die ihren Standort teilen, erscheinen auf Weltkarte und Minimap als klassenfarbige Punkte. Darüberfahren zeigt Name, Fraktion, Volk, Klasse und Stufe; ein Klick öffnet das QT-Spielermenü.
- Unter „Spielerstandorte“ sind Teilen und Anzeigen für Weltkarte und Minimap getrennt einstellbar. Alle vier Optionen sind anfangs aktiv. Die Anwesenheit für Namensplakettenlogos kann weiterhin gemeldet werden, auch wenn beide Standortfreigaben aus sind.
- Standorte werden regelmäßig erneuert und nach Ablauf entfernt. Beide Spieler brauchen das aktualisierte Addon. Ein Kartenpunkt bestätigt nicht, dass ihr euch in derselben Phase oder auf demselben Layer befindet.

### Einzelne Spieler oder die ganze Gruppe vergleichen

- „Quests vergleichen“ im Spielermenü vergleicht nun nur dich mit dem ausgewählten Spieler – auch mit erreichbaren QT-Spielern außerhalb deiner Gruppe. Den Gruppenvergleich findest du weiterhin im Minimapmenü, in Questnamen-Menüs und unter /qt compare.
- Quests teilen und anfordern bleibt Gruppenmitgliedern vorbehalten. Der Einzelvergleich erklärt, wann dafür eine Gruppe nötig ist oder der ausgewählte Spieler QT benötigt, um antworten zu können.
- Wartet bereits eine Teilanfrage auf einen anderen Spieler, zeigt der Vergleich auch nach einem Zielwechsel an, von wem die Antwort aussteht.

### Feedback und Unterstützung

- Begrüßungsfenster und Einstellungsstartseite bieten einen Discord-Link für Feedback und Hilfe. Er öffnet eine kopierbare Einladung. Kann das Linkfenster nicht erscheinen, wird die Einladung im Chat ausgegeben.

### Fehlerbehebungen

- Ignorierte Spieler werden umfassender ausgefiltert: Neue Protokolleinträge, Blasen, Kartenpunkte, Vergleiche und Teilanfragen werden unterdrückt. Bei Änderungen an der Ignorierliste verschwinden bereits angezeigte Blasen und Standorte.
- Fehlende Questblockgrenzen in Tooltips führen nicht mehr dazu, dass Zieltexte einer anderen Quest fälschlich eine Namensplakette markieren.
- Nach vorübergehenden Kommunikationsfehlern wird das Abschalten einer Standortfreigabe erneut gemeldet. Sind beide Freigaben aus, enthalten auch andere Addonmeldungen keine Standortangaben mehr.
- Spielerlogos werden korrekt entfernt, wenn eine Anwesenheitsmeldung kurz vor dem Weggang abläuft. „Flüstern“ an Kartenpunkten öffnet deinen Chat. Das Protokollziel lässt sich während Spielbeschränkungen nicht über die Einstellungen wechseln.

## 5.10.0

Behalte den Questfortschritt deiner Gruppe und naher Spieler im Blick. Über den Minimapknopf erreichst du Einstellungen, Questvergleich, Questjournal und die neuesten Versionshinweise.

### Quests vergleichen und teilen

- Öffne den Gruppenvergleich über die Minimap, ein Quest- oder Spielermenü oder mit /qt compare. Du siehst, wer welche Quest hat und wie weit die einzelnen Spieler sind.
- Zunächst werden alle Quests der Gruppe angezeigt. Mit der Option zum Ausblenden von Quests, die du nicht hast, beschränkst du die Ansicht auf dein eigenes Journal.
- Bei Gruppenmitgliedern mit dem aktualisierten Addon kannst du teilbare Quests anfordern. Standardmäßig wird um Erlaubnis gefragt; automatisches Teilen lässt sich auf Wunsch einschalten.
- Vergleiche erholen sich nach Karten- oder Kampfbeschränkungen. Neuere Antworten ersetzen ältere. Hinweise zu Wartezeiten und Fehlern erklären, wann eine erneute Anfrage möglich ist.

### Schnellzugriffe und Questmenüs

- Den rollenförmigen Minimapknopf kannst du an eine andere Stelle ziehen. Sein Menü öffnet Einstellungen, Vergleiche, Questjournal und Versionshinweise und lässt dich das Zielfenster des Protokolls ändern. Du kannst den Knopf im Menü ausblenden und unter „Verschiedenes“ wieder einblenden.
- Das Menü eines Questnamens bietet Status, Teilen, Öffnen im Questjournal und den Gruppenvergleich. Beim Teilen oder Öffnen werden die aktuelle Quest und mögliche Spielbeschränkungen erneut geprüft.
- Questtitel in Statuslinks bleiben erhalten, wenn die Quest dein Log verlässt. Die Option zum automatischen Teilen folgt jetzt auch gespeicherten Einstellungen und Profilwechseln.

### Hilfe und Versionshinweise

- Begrüßung und aktuelle Änderungen erscheinen in einem eigenen Fenster statt wiederholt im Chat. Du erreichst es über „Versionshinweise“ im Minimapmenü oder auf der Einstellungsstartseite sowie mit /qt notes, /qt changelog oder /qt patchnotes.
- Bei größeren Versionssprüngen und neuen Funktionsversionen öffnet sich das Fenster automatisch. Kleine Patchupdates enthalten ebenfalls neue Hinweise, öffnen das Fenster aber nicht von selbst.
- Mit /qt help siehst du die normalen Befehle; /qt help debug zeigt Vorschauen, Diagnosen und Entwicklerbefehle.

## 5.9.2

Questnamen im QT-Protokoll öffnen ihr Menü mit einem Links- oder Rechtsklick. Dort stehen zuerst „Status“ und dann „Teilen“.

### Questmenüs im Protokoll

- „Teilen“ verwendet den aktuellen Questlogeintrag, ohne Blizzards ausgewählte Quest zu ändern. Allein, bei Spielbeschränkungen oder bei nicht teilbaren Quests ist die Aktion nicht verfügbar.
- Nach einer Trennlinie lässt sich das QuestTogether-Protokoll zwischen Hauptchat und eigenem Fenster verschieben. Das entspricht der Funktion im Spielernamen-Menü von QT.
- Auch Questnamen in Statusmeldungen sind anklickbar, einschließlich Ersatztiteln aus den Logs anderer Spieler. Beim Formatieren abgeschlossener Questvergleiche bleiben vorhandene Questlinks erhalten; Statusangaben landen nicht mehr in einem zweiten, defekten Link.
- Alle 521 Tests bestehen in beiden Reihenfolgen unter Lua 5.1 und 5.2. Sechs Clientprofile, Lua- und Shell-Syntax, die exakte libchev-Revision und Diff-Prüfungen sind erfolgreich. Menüverhalten im Spiel, Zustellung geteilter Quests und Taint auf Engine-Ebene müssen zusätzlich geprüft werden.

## 5.9.1

Eine umfassende Prüfung hat Fehler bei Questerfassung, Namensplaketten, Gebietsaufgaben, Kommunikation und Spieleraktionen behoben.

### Korrekturen aus der Prüfung

- Getrennte Questblöcke in Tooltips übernehmen nicht mehr versehentlich denselben Zieltext. Gültiger Gruppenfortschritt bleibt erhalten; Namensplaketten erholen sich nach Karten-, Instanz-, Gruppen- und Queständerungen.
- Neu angenommene Quests und die erste Erfassung warten auf lesbare Daten. Fortschrittsschritte, die Einordnung von Gebietsaufgaben und unbekannte Standorte bleiben erhalten, ohne falsche Gebietsabgänge oder doppelte Einträge auszulösen.
- Lokalisierte Meldungen und Questvergleiche wurden überarbeitet, einschließlich Nachrichtengrößen, Sendetakt, Wiederholungen, Abbruch und Angaben zur Teilbarkeit.
- Schlägt ein nativer Wegpunkt fehl, folgt QT keinem alten Marker mehr. Während QT deaktiviert ist, werden gesperrte Klickaktionen abgelehnt, ohne wartende Aufgaben zu verlieren.
- Blasentests sind lokale Vorschauen. Sie akzeptieren vollständige Forever-Namen und Namen in Anführungszeichen, ohne die genaue Spieleridentität zu verändern.
- Ein- und Ausschalten, Profilwechsel, das Öffnen des HUD-Bearbeitungsmodus, zulässige Feier-Emotes und Diagnosen wurden korrigiert.
- Die im Spiel verwendbaren Tests sind besser isoliert. Fehlerhafte Testannahmen wurden berichtigt und die Regressionstests erweitert. Lua-Syntaxfehler führen nun auch in der CI zu einem Fehlschlag.
- Alle 516 Tests bestehen in beiden Reihenfolgen unter Lua 5.1 und 5.2. Auch die sechs Clientprofile, Syntax, exakte libchev-Revision und Diff-Prüfungen sind erfolgreich. Darstellung im Spiel, Zustellung zwischen zwei Clients und Taint auf Engine-Ebene bleiben gesondert zu prüfen.

## 5.9.0

Feiere Stufenaufstiege gemeinsam mit QuestTogether-Spielern in deiner Nähe. Außerdem reagieren Questmarkierungen zuverlässiger auf Kämpfe und abgeschlossene Ziele.

### Emotes und Questmarkierungen

- Eigene Stufenaufstiege und die von QT-Spielern in der Nähe lösen abgestimmte Emotes aus. Unter „Verschiedenes“ stehen dafür eigene, standardmäßig eingeschaltete Optionen neben den Emotes zum Questabschluss. Die bisherigen Vorgaben zur Spielerauswahl und Entfernung gelten weiterhin.
- Bestätigte Questzielabschlüsse werden sowohl für einzelne Kreaturen als auch für deren Kreaturentyp gemerkt. Taucht im Kampf eine neue Kreatur auf und sind ihre Tooltipdaten nicht verfügbar, bleibt sie unmarkiert – auch wenn ein früheres Exemplar noch als benötigt gespeichert war. Neue offene Ziele können die Markierung wiederherstellen; Änderungen am Queststatus löschen die Abschlussmerker. Unvollständige oder gesperrte Tooltipdaten bedeuten niemals automatisch, dass alle fertig sind.
- Ist die Beutezuordnung einer Kreatur für dich gesperrt, verschwinden Questsymbol und Gesundheitsleistenfärbung sofort, auch im Kampf. QT reagiert auf Besitzerwechsel und prüft die Zuordnung erneut bei Gesundheits- und Bedrohungsänderungen.
- Neue Questgegner lassen sich während gewöhnlicher Kämpfe in der offenen Welt anhand lesbarer Einheitentooltips erkennen. Namensplaketten werden beim Zurückkehren ins Kamerabild, beim Anvisieren und beim Überfahren mit der Maus erneuert. Verzögerte Frames, GUIDs und Questzeilen werden begrenzt erneut geprüft; beim Entfernen einer Einheit wird alte Arbeit verworfen. Symbol und Färbung kehren gemeinsam zurück.
- Die bisherigen Schutzprüfungen für Karten, Instanzen, unzugängliche Daten und geschützte Frames bleiben erhalten. Die Erkennung im Kampf ruft weder Questie noch versteckte Tooltipfenster auf.
- Alle 374 Offline-Tests bestehen in beiden Reihenfolgen unter Lua 5.1 und 5.2. Sechs Clientprofile, Lua-Syntax, die exakte Bibliotheksrevision und Diff-Prüfungen sind erfolgreich; die Abschlusscache-Tests reproduzierten zuvor den Fehler. Spielverhalten und Taint müssen zusätzlich im Client geprüft werden.

## 5.8.6

QT geht robuster mit unzugänglichen oder fehlerhaften Namen, Questtiteln, Klassenangaben und eigenen Klassenfarben um.

### Abgesicherte Daten und Bereinigung

- Optionale Daten aus TomTom und Questie werden vor der Verwendung geprüft. Beim Lesen von Questie-Tooltips bricht QT ab, sobald Daten nicht zugänglich sind. Blasensichtbarkeit und Bearbeitungsmodus werden vor der Übergabe an Bedienelemente auf eindeutige Wahrheitswerte normalisiert.
- Der Handler für Ladebildschirme wurde zusammengeführt. Ungenutzte private Argumente und ein ungenutzter Zweig für Beschränkungswerte wurden entfernt; Rückrufe und Rückgabewerte sind klarer behandelt. Die Ausweichwege für moderne und ältere Clients sowie die festgelegte private Bibliotheksrevision bleiben bestehen.
- Alle 336 Tests bestehen in beiden Reihenfolgen unter Lua 5.1 und 5.2, einschließlich erweiterter Anpassungsprüfungen für sechs Clientprofile. Neue Regressionstests schlagen mit der vorherigen Implementierung fehl. Lua-Syntax, Bibliotheksrevision und Diff-Prüfungen sind erfolgreich.
- Die verbleibenden Ketho-WoW-API-/LuaLS-Hinweise wurden auch ohne simulierte Offline-Clients geprüft. Beibehaltene Hinweise sind jeweils durch Kompatibilität, Schutzprüfungen, Rückrufe, Bibliotheksverhalten oder Testdaten begründet. Die Spielprüfung in Retail und Forever bleibt davon getrennt.

## 5.8.5

Gebietsaufgaben und Weltquests werden auf modernen Clients wieder richtig auf der Karte erkannt. Auch Abschluss-Emotes kommen besser mit unterschiedlichen Spiel-APIs zurecht.

### API-Kompatibilität und Prüfung

- Auf modernen Clients liest QT questID aus C_TaskQuest.GetQuestsOnMap; für ältere Clients bleiben die frühere API und das Feld questId erhalten. Abschluss-Emotes verwenden bevorzugt C_ChatInfo.PerformEmote und funktionieren damit auch bei abgeschalteten veralteten globalen Funktionen. Fehlende oder fehlschlagende Emote-APIs werden abgefangen.
- Eine ungenutzte Fingerprint-Berechnung für die Gruppenliste und ungenutzte lokale Variablen wurden entfernt. Die Offline-Prüfungen decken moderne und ältere Aufgaben-/Emote-APIs, deren Vorrang, unzugängliche Questdaten sowie fehlende oder fehlerhafte APIs ab.
- Alle 334 Tests bestehen in normaler und umgekehrter Reihenfolge unter Lua 5.1 und 5.2. Die erweiterten API-Prüfungen für sechs Clientprofile, Lua-Syntax und die exakte Bibliotheksrevision sind ebenfalls geprüft. Das tatsächliche Spielverhalten in Retail und Forever muss gesondert bestätigt werden.

## 5.8.4

Diese Wartung betrifft nur die Ablage der Entwicklungsunterlagen.

### Repository aufgeräumt

- Lokale Entwicklungsnotizen gehören nicht mehr zum versionierten Quellcode oder zu den Veröffentlichungspaketen. Am Spielverhalten ändert sich nichts.

## 5.8.3

Beim Einloggen oder Neuladen der Oberfläche zeigt QT einmalig seine Version, die unterstützten Clients und den Befehl zum Öffnen der Einstellungen an.

### Startmeldung und Feedbacklinks

- Die Meldung enthält passende Links zu CurseForge und GitHub für Feedback. Ein Klick öffnet ein Kopierfenster im WoW-Stil. Falls die Linkregistrierung oder das Kopierfenster nicht verfügbar ist, steht die vollständige Adresse direkt im Chat.
- Meldungsverhalten und abgesichertes Kopierfenster werden über die private Bibliothek libchev 1.2.0 bereitgestellt. Ein nicht verfügbarer Helfer für die Startmeldung unterbricht den normalen Addonstart nicht.
- Alle 334 Tests bestehen in beiden Reihenfolgen unter Lua 5.1 und 5.2. Client-APIs, Lua-Syntax und die exakte Bibliotheksrevision wurden geprüft. NoPoizen-Smoke-Simulationen prüfen beide Feedbacklinks in sieben Client-/Regelprofilen. Die Darstellung muss zusätzlich im Spiel überprüft werden.

## 5.8.2

Zwei Fehlalarme in /qt test sind behoben. Die Namensplaketten im normalen Spielbetrieb verhalten sich unverändert.

### Isolierte Testdaten

- Die GUID-Abfragen der Testdaten sind von echten Spielern in der Nähe getrennt. Dadurch schlagen Tooltip- und Symbolcache-Prüfungen nicht mehr fälschlich fehl, wenn eine reale Einheit gerade denselben Namensplaketten-Token belegt.
- Die Offline-Testumgebung bildet diesen Zusammenstoß nun nach und reproduziert beide Fehler ohne die Korrektur. Mit der Korrektur bestehen alle 333 Tests in beiden Reihenfolgen unter Lua 5.1 und 5.2 sowie die API-Prüfungen für sechs Clientprofile. Die Bestätigung im Spiel bleibt eine eigene Prüfung.

## 5.8.1

QuestTogether ist in der Addon-Liste leichter zu erkennen.

### Symbol in der Addon-Liste

- Neben QuestTogether erscheint jetzt Blizzards Questsymbol statt des allgemeinen Fragezeichens.

## 5.8.0

QuestTogether unterstützt die aktuellen Classic-Clients zuverlässiger. Das Verhalten in Retail und Forever sowie die gemeinsamen Debugfunktionen bleiben erhalten.

### Classic-Kompatibilität

- QT verarbeitet die Ereignisdaten beim Annehmen von Quests passend zum Client und nutzt abgesicherte Ausweichwege für Questziel-APIs. Ist unbekannt, ob sich eine Quest teilen lässt, wird diese Unsicherheit beibehalten. Hinzu kommen Metadaten für die jeweiligen Spielvarianten und API-Regressionstests für sechs Clients.
- Alle 333 Tests bestehen in beiden Reihenfolgen unter Lua 5.1 und 5.2. Geprüft wurden außerdem sechs Clientprofile, Lua-Syntax, die exakte eingebettete Bibliotheksrevision sowie NoPoizen-Smoke-Tests und das Paket. Die neuen API-Anpassungen müssen noch im Spiel bestätigt werden.
- CLIENT_COMPATIBILITY.md enthält die zugrunde liegenden Quellen, den Geltungsbereich und die Grenzen der bisherigen Prüfungen.

## 5.7.7

Überlappende Debugfenster und ihre Bedienelemente bleiben mit libchev 1.1.3 in einer gemeinsamen WoW-Stapelgruppe. Kategoriemenüs gehören dadurch sichtbar zu ihrer Konsole.

### Namensplaketten und Charakternamen

- Neue Einstellungen platzieren Questzielsymbole links an der Namensplakette. Bereits gespeicherte Positionen werden nicht verändert.
- Bei deinem eigenen Namen berücksichtigt QT in Forever die Einstellung „My Last Name“. Die Nachnamen anderer Spieler bleiben wie im Spiel selbst sichtbar. Für Kommunikation, Gruppenabgleich, Namensplaketten und Spieleraktionen werden weiterhin vollständige Namen verwendet; vorhandene Profil- und Positionsschlüssel deiner persönlichen Blase bleiben erhalten.
- Eigene Questmeldungen erscheinen nicht mehr doppelt, wenn der Kanal deinen vollständigen Namen in einem anderen Format zurückliefert. Regressionstests decken die lokale Meldung samt Kanal- und Gruppenecho sowie einen anderen Charakter mit gleichem Vornamen ab.
- Alle 331 Tests bestehen in beiden Reihenfolgen unter Lua 5.1/5.2. Die neue Standardposition der Symbole und das Zusammenspiel mehrerer Fenster müssen zusätzlich im Spiel bestätigt werden.

## 5.7.6

Alle drei Addons verwenden dieselbe private Debugkonsole aus libchev 1.1.2. Ihre WoW-Fenstergrafik wird jetzt ohne Verzerrung dargestellt.

### Debugkonsole und Prüfung

- Die gemeinsame Konsole bietet Kategorie- und Suchfilter, Kopierfunktionen, Testergebnisse, Diagnoseberichte und, soweit verfügbar, Zeitstempel. Am Ende eines Testlaufs erscheint genau eine Zusammenfassung. Explizite Texturgrenzen beheben die gestreckte Rahmengrafik.
- QuestTogether liefert weiterhin seine eigenen Questdiagnosen und isolierten Tests; die Bibliothek übernimmt Konsole und allgemeine Debugfunktionen. Die Befehle dafür sind /qt test, /qt debug und /qt diagnostics.
- Alle 324 Tests bestehen in beiden Reihenfolgen unter Lua 5.1/5.2. Die korrigierte Fenstergestaltung wurde im Spiel bestätigt. Weitere Prüfungen von Spielbeschränkungen und tatsächlichem Spielverhalten stehen davon getrennt.

## 5.7.6-beta.3

Die gemeinsame Debugkonsole verwendet jetzt libchev 1.1.1 und erhält wieder die vertraute WoW-Fenstergestaltung.

### Darstellung und Testergebnisse

- Die Konsole sieht in allen beteiligten Addons wieder wie ein WoW-Fenster aus. Die doppelte Testzusammenfassung entfällt; die abschließende Zusammenfassung bleibt im begrenzten Verlauf erhalten.
- Suche, Kategorien, Kopieren, Scrollen, Tests und Diagnosen funktionieren weiterhin gemeinsam. Die vorhandenen Prüfungen auf Spielbeschränkungen bleiben bestehen.
- Für beta.2 wurden alle 324 QT-Tests in Forever 1.60.1, Build 70009, als bestanden gemeldet. Die sieben im Spiel geladenen Testdateien wurden außerdem auf ungültige Rechenoperationen untersucht: Es gab weder absichtliche NaN-Erzeugung noch Divisionen durch null. Dieses frühere Spielergebnis bestätigt jedoch nicht die neue Fenstergestaltung.
- Bitte nach /reload die Konsole mit /qtd öffnen, /qt test ausführen und Fenstergestaltung sowie die einmalige Zusammenfassung prüfen. Darstellung und Beschränkungs-/Taint-Verhalten dieser Revision müssen weiterhin im Spiel bestätigt werden.
- Alle 324 Tests bestehen vorwärts und rückwärts unter Lua 5.1.5 und 5.2.4; jeder Kommandozeilendurchlauf liefert genau eine Zusammenfassung. Das entpackte Installations-ZIP mit 26 Dateien besteht die Tests unter beiden Versionen. Die 23 Lua-Dateien, 22 TOC-Einträge, das Bibliotheksmanifest sowie Formatierungs- und Diff-Prüfungen sind ebenfalls geprüft.
- Verwendete Bibliotheksrevision: 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. Für QT ist noch keine GitHub-CI eingerichtet; die CI der Bibliothek ist erfolgreich durchgelaufen.

## 5.7.6-beta.2

Das bisherige Debugfenster weicht der gemeinsamen Konsole aus libchev v1.1. Die Bibliothek wird mitgeliefert und braucht keine eigene Installation.

### Die gemeinsame Debugkonsole

- Die Konsole bietet für alle Addons dieselben Kategoriefilter, eine Suche mit unscharfen Treffern oder exakten Ausdrücken in Anführungszeichen sowie Auswählen, Kopieren, Leeren, Neuladen, Tests und Diagnosen. Auch das automatische Mitrollen des Protokolls ist vereinheitlicht.
- Mit /qt test öffnest du die aktuellen Ergebnisse. Ein weiterer Durchlauf ersetzt die alten TEST-Einträge und entfernt überholte Suchfilter.
- Mit /qt diagnostics [questID] oder /qt diag [questID] wird der aktuelle zwischengespeicherte Bericht in derselben Konsole neu aufgebaut. Innerhalb der gemeinsamen Exportgrenze bleiben die jüngsten Ereignisse erhalten.
- Die Bibliothek übernimmt die bisherigen Konsolen-Rückrufe und Dropdowns von QT samt Prüfungen auf Spielbeschränkungen und addon-eigene Fenster. Questdaten, Ankündigungen, Namensplaketten, Kommunikation und die Isolation der QT-Tests bleiben bei QuestTogether.
- Darstellung und Taint-Verhalten dieser Beta sind in Retail und Forever noch zu prüfen. Nach /reload bitte /qt test und /qt diagnostics ausführen und Filter, Suche, Kopieren, Leeren, Größenänderung, Scrollen, wiederholte Tests sowie den Wechsel zwischen Berichten und Protokollen ausprobieren – mit den üblichen Addons und auch bei Kampf- und Beschränkungswechseln.
- Alle 324/324 Tests bestehen in beiden Reihenfolgen unter Lua 5.1.5 und 5.2.4. Die 23 Lua-Dateien, 22 TOC-Einträge und das Manifest der festgelegten Bibliotheksrevision wurden geprüft. Auch das entpackte Installations-ZIP besteht sämtliche 324 Tests in der separaten Offline-Testumgebung. Bibliotheksrevision: 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

Die Together-Addons nutzen künftig gemeinsame Hilfsfunktionen aus libchev v1.0.0. Die Bibliothek ist bereits enthalten; du musst nichts zusätzlich installieren.

### Änderungen dieser Beta

- Protokolle, Diagnosen, abgesicherte Rückrufe, aufgeschobene Aufgaben und die Testausführung werden über libchev gemeinsam bereitgestellt. QuestTogether verwaltet Quests, Gruppen, Namensplaketten und den Umgang mit gesperrten Spielaktionen weiterhin selbst. Die Laufzeitdaten der einzelnen Addons bleiben getrennt.
- Diagnoseberichte enthalten Angaben zu Spielclient, Addon und Bibliothek. Wird das Kopierfenster voll, bleiben die neuesten Ereignisse erhalten.
- Koordinatenlinks lassen sich auch bei deaktiviertem QT verwenden, soweit das Spiel es zulässt. Hintergrundaufgaben bleiben angehalten; veraltete Timer werden verworfen.
- Mit /qt test stehen 315 Prüfungen bereit: die bisherigen 300, zehn Prüfungen der gemeinsamen Bibliothek und fünf zusätzliche Regressionstests für die Einbindung.
- Alle 315 Tests bestehen in beiden Ausführungsreihenfolgen unter Lua 5.1.5 und 5.2.4. Auch Lua-Syntax, Ladereihenfolge in der TOC und das Manifest der eingebetteten Revision samt Prüfsummen wurden geprüft. Verwendeter libchev-Stand: 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- Diese Fassung ist eine Beta. Darstellung und Taint-Verhalten nach der Auslagerung müssen noch in Retail und Forever geprüft werden. Lade die Oberfläche neu, führe /qt test und /qt diagnostics aus und probiere Quests, Fortschrittsblasen, Namensplaketten und Koordinatenlinks mit deinen üblichen Addons aus – auch im Kampf, beim Gebietswechsel, nach Aus- und Einschalten von QT und nach dem Neuladen.
- Die frühere Bestätigung der 300 Tests in Retail bezog sich auf v5.7.5; sie bestätigt nicht die Änderungen dieser Beta.
