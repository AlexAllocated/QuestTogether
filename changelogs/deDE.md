# QuestTogether — Änderungsprotokoll

<!-- Generated from canonical release notes; do not edit by hand. -->

## 6.5.3

Das Gruppen-Questlog im Detail: Vergleiche Quests, plane das nächste Ziel und folge dem Questfokus eines Mitspielers. Dieser Patch erweitert die Anleitung um drei Screenshots; das Spielverhalten bleibt unverändert. Die Bilder zeigen Forever-Vorschaudaten mit simulierten Mitspielern.

### Deine Gruppe auf einen Blick

- Ein Linksklick auf das QT-Minimap-Symbol öffnet oder schließt das Gruppen-Questlog. Deine Spalte bleibt vorn, Klassenfarben unterscheiden Mitspieler und eine Krone kennzeichnet den Anführer. Jede Quest zeigt Besitz, fehlende Teilnehmer und die Anzahl der abgabebereiten Spieler. Teilen und Teilen anfordern erscheinen, wenn unterstützt; Nicht teilbar und Teilbarkeit unbekannt erklären fehlende Aktionen. Es gelten weiterhin Blizzards Regeln und die Voraussetzungen des Empfängers.

**Forever**

![Deine Gruppe auf einen Blick — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestOverviewForever.png)

### Eigene Quest wählen oder Mitspielern folgen

- Die kleinen Questschaltflächen zeigen den Fokus jedes Spielers. Klicke in deiner Spalte, um Blizzards Navigationsquest zu wechseln, oder auf die aktive Quest eines Mitspielers, um ihm zu folgen. Beim Folgen bleibt nur dessen aktive Schaltfläche farbig; aktive Quests anderer Mitspieler bleiben zum Wechseln anklickbar. Neue Fokusdaten werden übernommen, wenn du die Quest hast; Folgen übersteht Neuladen. Fehlt dir die nächste Quest, endet das Folgen und QT bietet das Öffnen des Gruppen-Questlogs an.

**Forever**

![Eigene Quest wählen oder Mitspielern folgen — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestFollowingForever.png)

### Fokus bewusst wechseln

- Die Anzeige Folgen: nennt dein Ziel, daneben steht Folgen beenden. Eine eigene Quest oder ein anderer Mitspieler erfordert eine Bestätigung. Auch das Wechseln oder Aufheben des Fokus in Blizzards Questverfolgung fragt nach: QT stellt den bisherigen Fokus während der Entscheidung wieder her. Abbrechen behält das Folgen bei; Fokus ändern übernimmt die Wahl. Hebt der verfolgte Spieler seinen Fokus auf, bleibt deine Quest erhalten. Gruppenaustritt oder Schlachtzugumwandlung beendet das Folgen.

**Forever**

![Fokus bewusst wechseln — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestFocusWarningForever.png)

### Fortschritt aufklappen und Quests finden

- Klicke eine Questzeile an, um Ziele, Zähler und Fortschrittsbalken jedes Mitglieds aufzuklappen. Mehrere Quests können gleichzeitig offen bleiben. Suche und Filter grenzen nach Besitz, Fortschritt und Aktionen ein. Das Buchsymbol öffnet eine eigene Quest in Blizzards Questlog. Fremder Fortschritt ist eine Momentaufnahme: Prüfe das Alter unter dem Namen und nutze Aktualisieren.

### Folgen ohne echte Gruppe testen

- /qt preview compare kombiniert dein echtes Questlog mit vier simulierten Mitspielern und zusätzlichen fehlenden Quests. Die Fokusschaltflächen ändern deine echte Navigation; Teilen bleibt simuliert. Wähle im Namensmenü eines Mitspielers die nächste Vorschauquest, um Folgen und fehlende Quests zu testen. Blizzards Questverfolgung löst ebenfalls die Bestätigung aus. Beim Schließen wird ein bestehendes Folgen in der echten Gruppe fortgesetzt. /qt preview unfollow zeigt nur den Warndialog.

## 6.5.2

Klarere Questfokus-Schaltflächen, sichere Wechsel beim Folgen und passende Symbole zur Blizzard-Questverfolgung.

### Klarer Questfokus

- Beim Folgen bleibt nur die aktive Quest des verfolgten Spielers farbig. Ohne Folgen bleiben deine Schaltflächen und die aktiven Quests deiner Mitspieler farbig. Alle anderen sind grau, ohne Transparenz. Aktive Quests von Mitspielern bleiben anklickbar, um das Folgen zu starten oder das Ziel zu wechseln.

### Fokuswechsel bestätigen

- Die Wahl einer eigenen Quest oder eines anderen Mitspielers fragt vor dem Ende des bisherigen Folgens nach. Auch Fokuswechsel oder das Aufheben des Fokus über Blizzards Questverfolgung fragen jetzt nach: QT stellt den bisherigen Fokus während der Entscheidung wieder her. Abbrechen behält das Folgen bei; Fokus ändern übernimmt die Auswahl. Vorschau: /qt preview unfollow.

### Passende Questsymbole

- Der Queststatus nutzt jetzt dieselbe Abschlussabfrage wie Blizzards Questverfolgung. Dadurch zeigen Lieferquests ein Fragezeichen statt eines Fortschrittssymbols. Der korrigierte Bereit-Status wird auch mit dem Gruppen-Questlog geteilt.

### Mit eigenen Quests testen

- Die Vergleichsvorschau nutzt dein echtes Questlog mit vier simulierten Mitspielern und zusätzlichen fehlenden Quests. Fokuswechsel ändern deine echte Blizzard-Navigation; Teilen bleibt simuliert. Über das Namensmenü eines Mitspielers wechselst du dessen Fokus weiter. Statt einer leeren Aktionsspalte zeigen nicht teilbare Quests nun zentriert Nicht teilbar oder Teilbarkeit unbekannt. Beim Schließen der Vorschau wird ein bestehendes Folgen in der echten Gruppe fortgesetzt.

## 6.5.1

Klarere Questfokus-Schaltflächen, sichere Wechsel beim Folgen und passende Symbole zur Blizzard-Questverfolgung.

### Klarer Questfokus

- Beim Folgen bleibt nur die aktive Quest des verfolgten Spielers farbig. Ohne Folgen bleiben deine Schaltflächen und die aktiven Quests deiner Mitspieler farbig. Alle anderen sind grau, ohne Transparenz. Aktive Quests von Mitspielern bleiben anklickbar, um das Folgen zu starten oder das Ziel zu wechseln.

### Fokuswechsel bestätigen

- Die Wahl einer eigenen Quest oder eines anderen Mitspielers fragt vor dem Ende des bisherigen Folgens nach. Auch Fokuswechsel oder das Aufheben des Fokus über Blizzards Questverfolgung fragen jetzt nach: QT stellt den bisherigen Fokus während der Entscheidung wieder her. Abbrechen behält das Folgen bei; Fokus ändern übernimmt die Auswahl. Vorschau: /qt preview unfollow.

### Passende Questsymbole

- Der Queststatus nutzt jetzt dieselbe Abschlussabfrage wie Blizzards Questverfolgung. Dadurch zeigen Lieferquests ein Fragezeichen statt eines Fortschrittssymbols. Der korrigierte Bereit-Status wird auch mit dem Gruppen-Questlog geteilt.

### Mit eigenen Quests testen

- Die Vergleichsvorschau nutzt dein echtes Questlog mit vier simulierten Mitspielern und zusätzlichen fehlenden Quests. Fokuswechsel ändern deine echte Blizzard-Navigation; Teilen bleibt simuliert. Über das Namensmenü eines Mitspielers wechselst du dessen Fokus weiter. Statt einer leeren Aktionsspalte zeigen nicht teilbare Quests nun zentriert Nicht teilbar oder Teilbarkeit unbekannt.

## 6.5.0

Steuere den Questfokus direkt im Gruppen-Questlog und folge deiner Gruppe auch nach dem Neuladen weiter.

### Schaltflächen für den Questfokus

- Questschaltflächen im Blizzard-Stil erscheinen jetzt in der Questspalte jedes Spielers und ersetzen die Questtitel in den Kopfzeilen. Klicke in deiner Spalte, um deine Navigationsquest zu ändern. Ausgewählte Schaltflächen zeigen den Fokus deiner Mitspieler; klicke darauf, um ihnen zu folgen.

### Dauerhaft folgen

- Deine Auswahl wird pro Charakter über das Neuladen hinaus gespeichert und bleibt bei vorübergehenden Datenlücken erhalten. Neue Gruppendaten passen deinen Fokus an, wenn du die Quest besitzt. Eine eigene Navigationsauswahl, das Verlassen des Mitspielers, die Auflösung der Gruppe oder die Umwandlung in einen Schlachtzug beendet das Folgen.

### Wenn dir die Quest fehlt

- Wählt der Spieler, dem du folgst, eine Quest, die du nicht hast, endet das Folgen, ohne deine Navigation zu ändern. Ein Dialog im QT-Design erklärt dies und öffnet das Gruppen-Questlog, damit du die Quest anfordern und erneut folgen kannst. Teste den Dialog mit /qt preview focus oder die Schaltflächen und simulierte Fokuswechsel mit /qt preview compare.

## 6.4.3

Korrekturen am Quest-Fokus und an Gruppen-Tooltips sowie einfachere Karteneinstellungen.

### Dein Quest-Fokus

- Deine Überschrift im Gruppen-Questlog liest die aktuell fokussierte Quest jetzt direkt aus, auch wenn du allein bist oder die Freigabe des Quest-Fokus deaktiviert ist. Änderungen an deiner Navigationsquest aktualisieren die Überschrift ohne manuelles Aktualisieren.

### Gruppenlisten in Tooltips

- Bei Gruppen mit bis zu fünf Spielern zeigt der Tooltip sofort den Spieler unter dem Mauszeiger neben dem Anführer, während die vollständige Liste geladen wird. Der Ladehinweis erscheint nur, solange weitere Mitglieder fehlen. Bei größeren Gruppen wird weiterhin nur der Anführer angezeigt.

### Einfachere Karteneinstellungen

- Ein einziges Kontrollkästchen zum Anzeigen anderer Spieler auf Karte und Minimap steuert jetzt beide Ansichten. Die Freigabe deines eigenen Standorts bleibt unabhängig davon. War zuvor mindestens eine Ansicht aktiviert, bleiben beide sichtbar; waren beide deaktiviert, bleibt die Anzeige aus.

## 6.4.2

Danke, dass du QuestTogether verwendest! Dieses Update bietet mehr Kontrolle über Quest-Fortschritts-Schnappschüsse, Spielerstandort-Anzeigen und die Zugänglichkeit von Fenstern. Einstellungen lassen sich leichter anpassen, und Discord ist weiterhin der beste Ort für Feedback und Support.

### Aktualisierungen am Gruppen-Questlog

- Spielerüberschriften zeigen jetzt an, wie aktuell jeder Quest-Schnappschuss ist. Öffne das Menü einer Spielerüberschrift, um nur diesen Spieler zu aktualisieren, ohne alle anderen zu aktualisieren.
- Filter enthalten jetzt eine optionale Einstellung zur automatischen Aktualisierung. Wenn sie aktiviert ist, wird das Gruppen-Questlog etwa alle 30 Sekunden aktualisiert, während das eigentliche Fenster geöffnet ist.
- Beim Aktualisieren bleiben deine Suche, aufgeklappte Quests, horizontale Position und sichtbare Questposition nach Möglichkeit erhalten, während neue Schnappschussdaten eintreffen.
- Die Quest-Fokus-Anzeige erklärt jetzt wartende, abgelaufene und nicht unterstützte Daten. Wenn QT die Ursache nicht unterscheiden kann, zeigt sie „Nicht geteilt oder nicht verfügbar“. Das Menü warnt außerdem vor Schleifen beim Folgen.

### Zugänglichkeit und Fensterlayout

- Einstellungen enthalten jetzt Zugänglichkeitsoptionen für eine Fensterskalierung von 80 % bis 150 % sowie reduzierte Bewegung für sofortiges Scrollen und sofortiges Aufklappen von Zielen.
- Die Fensterskalierung vergrößert Text und Bedienelemente gemeinsam, kann aber bei Bedarf begrenzt werden, damit das gesamte Fenster auf dem Bildschirm bleibt.
- Das Gruppen-Questlog und das Willkommensfenster speichern jetzt ihre Größe und bildschirmrelative Position pro Profil, und QuestTogether-Fenster werden nach Änderungen der Anzeigegröße oder UI-Skalierung neu angepasst.
- Verwende Fensterlayout zurücksetzen in Zugänglichkeit oder /qt resetlayout, um gespeicherte QuestTogether-Fensterlayouts zu löschen und sie wieder zu zentrieren.

### Spielerstandort-Steuerung

- Die Anzeige auf Weltkarte und Minimap kann jetzt getrennt von der Standortfreigabe umgeschaltet werden, sodass du lokale Markierungen ausblenden kannst, ohne zu ändern, was du teilst.
- Der Spielerstandortfilter bietet jetzt alle QuestTogether-Spieler, Questpartner oder nur die Gruppe an.
- Meine Gruppe immer anzeigen ist standardmäßig aktiviert, sodass Gruppenmitglieder weiterhin angezeigt werden, wenn der Questpartner-Filter verwendet wird, sofern ihre Standortberechtigungen dies zulassen.

### Korrekturen und Feinschliff

- Die experimentelle Layer-Erkennung behält dieselben Einstellungen und dieselbe UI bei, mit flüssigerer Anfrageverarbeitung, wenn sich lokale Hinweise ändern oder nahe Kandidaten eine Abklingzeit haben.
- QuestTogether-Dialoge behandeln Escape jetzt über ihre normalen Schließen-Aktionen, und dem Gruppen-Questlog kann im nativen Menü für Tastaturbelegungen eine Taste zugewiesen werden, wobei standardmäßig keine Taste festgelegt ist.
- Bewege den Mauszeiger über Quest- und Zielzeilen, um den vollständigen Text zu lesen. Die Schieberegler für Fensterskalierung und Umkreis haben jetzt hellere Leisten mit dunklen Umrandungen für bessere Sichtbarkeit.

## 6.4.1

Experimentelle Layer-Erkennung für QT-Spieler in der Nähe.

### Experimentelle Layer-Erkennung

- Standardmäßig unter Einstellungen > QuestTogether > Experimentell aktiviert. Deaktiviere Andere Layer erkennen, um Vergleiche zu stoppen und vermutete Phasenanzeigen auszublenden.
- In Forevers offener Welt vergleichen kompatible QT-Clients in der Nähe beobachtete NPCs und sichtbare Spieler. Ein Phasensymbol weist auf einen vermutlich anderen Layer hin. Details erscheinen beim Darüberfahren. Standortfreigabe ist erforderlich.
- Schätzungen können falsch sein. Fehlende Spieler allein sind nicht aussagekräftig. Gegenseitige Sichtbarkeit oder ein gemeinsam sichtbarer Spieler haben Vorrang vor der NPC-Schätzung. Veraltete Hinweise werden automatisch verworfen. Ältere QT-Clients können nicht teilnehmen.

### Bilder in Versionshinweisen

- Bilder aus Versionshinweisen werden jetzt direkt auf Discord hochgeladen, damit sie in den Änderungsprotokollen sichtbar bleiben.

## 6.4.0

Überarbeitete QT-Fenster und schnellerer Zugriff auf Gruppenquests.

### Gruppenquestlog

- Das mit 6.3 eingeführte Gruppenquestlog im Überblick: Vergleiche bis zu fünf Spieler in klassenfarbenen Spalten und erkenne, wer welche Quest hat, wem sie fehlt und wann die Gruppe abgabebereit ist. Kombiniere Suche und Filter für Besitz, Fortschritt und Aktionen. Teilen und Teilanfragen stehen zur Verfügung, wenn unterstützt.
- Unter jedem Spielernamen steht die aktuell fokussierte Quest. Klicke auf den Namen eines Mitspielers, um seinem Questfokus freiwillig zu folgen. Fehlt dir dessen Quest, bleibt deine Navigation unverändert. Aktualisieren lädt einen neuen Fortschrittsstand der anderen Spieler. Die Bilder zeigen fiktive Vorschaudaten.
- Quests in deinem Questlog haben jetzt eine kleine Buchschaltfläche, die ihre Details in Blizzards Questlog öffnet. Ein Klick auf die Zeile klappt weiterhin die Ziele auf.
- Eine Krone kennzeichnet den Gruppenanführer und wechselt bei einem Führungswechsel mit. Deine eigene Spalte bleibt an erster Stelle.

**Retail**

![Gruppenquestlog — Retail](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogRetail.png)

**Forever**

![Gruppenquestlog — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogForever.png)

### Ziele aller Gruppenmitglieder aufklappen

- Klicke auf eine Quest, um Zielzähler, Fortschrittsbalken und erledigte Schritte jedes Mitglieds anzuzeigen. Mehrere Quests können gleichzeitig geöffnet bleiben. Diese Version macht die Abschnitte kompakter und gleicht die Klassenfarben von Überschriften und Inhalt an. Eine typische Fünfergruppenquest mit je zwei Zielen passt in die Standardfenstergröße; längere Quests können weiterhin Scrollen erfordern.

**Forever**

![Ziele aller Gruppenmitglieder aufklappen — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestObjectivesForever.png)

### Fenster und Minikarte

- Ein Linksklick auf das Minikartensymbol öffnet oder schließt das Gruppenquestlog; ein Rechtsklick öffnet das Menü. Einstellungen ist wieder im Menü, und der Tooltip erklärt die Kurzbefehle.
- Erinnerungen an Gruppenchat-Meldungen, Teil- und Beitrittsanfragen, Sprechblaseneinstellungen und der Discord-Linkdialog verwenden jetzt QTs Schriftrollenrahmen und helle/dunkle Designs, mit mehr Innenabstand und Platz für Schiebereglerwerte.
- Beim Verschieben von Fenstern bleibt der Abstand zum Mauszeiger erhalten, auch in der Vergleichsvorschau. Menüs und Tooltips bezeichnen Blizzards Fenster jetzt durchgehend als Questlog.

### Vorschaubefehle

- /qt preview listet die Fenster- und Ankündigungsvorschauen auf. Die bisherigen Vorschaubefehle funktionieren weiterhin; simulierte Aktionen laden keine Spieler ein, teilen keine Quests und senden keine Nachrichten.
- Die Vergleichsvorschau zeigt jetzt eine vollständige Fünfergruppe mit Jäger und Schurke, unterschiedlichen Zielen, aktiven Quests und einer Anführerkrone.

## 6.3.1

Angenehmere Abstände im Gruppenquestlog.

### Abstände in den Zielfeldern

- Ausgeklappte Zielfelder haben jetzt unten mehr Innenabstand, damit Fortschrittsbalken den Rand nicht berühren. Scrollen und Ausklappanimationen berücksichtigen den zusätzlichen Platz.
- Meldungen wie „Keine Zieldetails verfügbar“ werden neben dem Spielernamen vertikal zentriert, statt zu dicht am oberen Rand zu stehen.

## 6.3.0

Ein neues Gruppenquestlog, geteilte Ziele und optionales Folgen aktiver Quests erleichtern das gemeinsame Questen.

### Gruppenquestlog

- Der Gruppenquestvergleich heißt jetzt Gruppenquestlog. Klappt mehrere Quests gleichzeitig auf, um Ziele und Fortschritt jedes Mitglieds sowie eine Übersicht der Abgabebereitschaft der Gruppe zu sehen.
- Sucht Quests und kombiniert Filter für Questbesitz, Fortschritt und Teilen. Aktualisieren lädt neue Daten anderer Spieler; ältere Clients können weiterhin Questlisten vergleichen, aber keine Zieldetails liefern.
- Passt die Größe des Pergamentfensters an und scrollt flüssig. Klassenfarbene Spalten, anklickbare Spielerüberschriften mit Innenabstand und abgerundete Zielbereiche machen den Fortschritt leichter lesbar.

### Questfokus und geteilte Wegpunkte

- Unter jedem Namen steht die aktive Quest. Wählt im Spielerkopf oder QT-Menü „Questfokus folgen“, um eigenen Quests zu folgen. Fehlende oder aufgehobene Quests lassen eure Navigation unverändert; manuelle Navigation, Verlassen der Gruppe oder Neuladen beendet das Folgen.
- Blizzard-Wegpunkte anderer Mitglieder erscheinen als klassenfarbene Markierungen auf Weltkarte und naher Minikarte. Überlappende Markierungen nennen alle Besitzer; „Hierhin navigieren“ nutzt TomTom oder die integrierte Navigation. Empfangene Markierungen ändern nie euer Ziel und bedeuten keine gemeinsame Phase.
- „Meine aktive Quest teilen“, „Meinen Wegpunkt teilen“ und „Gruppenwegpunkte anzeigen“ sind unter „Gruppen & Teilen“ standardmäßig an, unabhängig von öffentlicher Standortfreigabe und Partnersuche. Folgen wird ausdrücklich aktiviert. Die Funktionen benötigen aktualisierte Mitspieler in Gruppen bis fünf, auch in Dungeons; Schlachtzüge sind ausgeschlossen.

### Fenster und Menüs

- Patchnotes verwenden jetzt ebenfalls das dunkle Pergamentdesign mit optionalem hellem Modus. Verschiebt oder skaliert das Fenster, durchsucht übersichtlichere Verlaufseinträge und wechselt mit Pfeilen zwischen Versionen oder zum Anfang und Ende. Discord und Einstellungen stehen im Fußbereich.
- Spieler-Tooltips passen sich ihrem Inhalt besser an. Das Minikartenmenü trennt Questwerkzeuge von Patchnotes, Logfenster-Auswahl und Symbolanzeige. Einstellungen und „QT-Chatnachricht senden“ wurden daraus entfernt; Einstellungen bleiben über /qt options erreichbar.

## 6.2.3

Weniger wiederholte Meldungen über abgabebereite Quests.

### Korrekturen bei abgabebereiten Quests

- Quests, die beim Start der Verfolgung bereits abgabebereit oder abgeschlossen sind, werden still erfasst. Fehlende Bereitschaftsdaten und spätere Aktualisierungen lösen bereits erfasste Meldungen zur Abgabebereitschaft nicht erneut aus.
- Neue Abschlüsse werden weiterhin gemeldet. Wird eine Quest erneut angenommen, wird ihr Benachrichtigungsverlauf zurückgesetzt. Der sendende Spieler benötigt dieses Update; ältere Versionen können weiterhin Meldungen in Schüben senden.

## 6.2.2

Lesbarer Questfortschritt in jeder Sprache.

### Details zu den Zielen beibehalten

- Fortschrittsmeldungen für Quests, Weltquests und Bonusziele behalten im Chat und in Sprechblasen jetzt den ursprünglichen Text und die Zähler des Absenders bei, statt sie durch allgemeine Angaben wie „Ziel 1: 5/5“ zu ersetzen.
- Meldungen über angenommene und abgeschlossene Quests verwenden weiterhin übersetzte Bezeichnungen und lokal verfügbare Questtitel.

## 6.2.1

Mehr Klarheit bei Ankündigungen im Gruppenchat.

### Wissen, wann QT im Gruppenchat schreibt

- Die Einstellung unter Wo ankündigen erklärt jetzt deutlich, dass QT auch im Gruppenchat schreibt, wenn ein Mitglied nicht als QT-Nutzer erkannt wird. Sie bleibt standardmäßig aktiviert.
- Nach einer kurzen Erkennungsphase erscheint ein neuer Dialog mit dem QT-Logo. Wähle Aktiviert lassen oder Ankündigungen ausschalten, bevor die Weiterleitung beginnt. Nicht erneut erinnern speichert deine Bestätigung für das aktuelle Profil.
- Die übersetzte Erinnerung nennt die betroffenen Mitglieder und kann erneut erscheinen, wenn neue, noch nicht erkannte Mitglieder beitreten. Werden sie als QT-Nutzer erkannt, verschwindet sie. Während der Wartezeit zurückgehaltene Ereignisse werden nicht nachträglich gesendet.

## 6.2.0

Flüssigere Punkte in der Nähe, schnellere Spielerdetails und zuverlässigere Kommunikation.

### Flüssigere Bewegung auf der Minikarte

- Spieler in der Nähe können Positionen über begrenzte Addon-Flüsternachrichten austauschen. Flüssige Bewegungen bevorzugen bis zu vier der nächsten geeigneten Spieler und beachten Freigaben, Filter, ignorierte Spieler und Übertragungslimits.
- Beide Spieler benötigen dieses Update für Positionsstreams und direkte Antworten beim Darüberfahren. Ältere Versionen senden weiterhin reguläre Meldungen; Serververzögerungen und Einschränkungen können die Zustellung weiterhin beeinflussen.

### Schnellere Erkennung und Gruppendetails

- Beim Darüberfahren über einen Spielernamen oder Punkt können aktuelle Details direkt angefordert werden. Anfragen sind begrenzt, und unveränderte Gruppenlisten laufen nicht mehr nach zwei Minuten ab.
- Aktuelle Positionen, Partnersuchstatus und bekannte Gruppendetails bleiben nach /reload bis zu drei Minuten ab ihrer ursprünglichen Erfassung erhalten. Beim Betreten eines Gebiets wird außerdem eine zeitlich verteilte Erkennungsaktualisierung angefordert.
- Tooltips zeigen einen bekannten Solo- oder Gruppenstatus an, während die genaue Gruppengröße noch fehlt. Ein kleines Logo kennzeichnet QT-Nutzer in der Mitgliederliste; die Namen bleiben bündig.

### Klarere Übersetzungen und Darstellung

- Volksnamen, Ping-Details, Questdaten und weitere Oberflächentexte nutzen verfügbare lokale Übersetzungen. Fehlt eine Questübersetzung, bleibt der lesbare Text des Absenders erhalten; Fortschrittstexte übernehmen keine unpassenden lokalen Zielbeschreibungen.
- Allgemeine Ankündigungen verwenden jetzt das QT-Logo. Die Suche nach Questpartnern steht im Minikartenmenü an erster Stelle.

### Kommunikation und Zuverlässigkeit

- Vergleiche, Gruppenlisten, Beitritts- und Teilanfragen sowie Ping-Antworten bevorzugen direkte Flüsternachrichten mit kompatiblen Spielern. Zusammengefasste Statusmeldungen und weniger unveränderte Positionsupdates reduzieren unnötigen öffentlichen Datenverkehr.
- Wiederholte Questprüfungen, übermäßige Namensplakettenprüfungen, während Einschränkungen nicht schließbare Fenster und nicht umschaltbare Einstellungen bei /qt set wurden korrigiert. Das Abschalten der Positionsfreigabe verwirft keine anderen wartenden Anfragen mehr.

## 6.1.2

Reaktionsschnellere Punkte für Spieler in der Nähe und klarere übersetzte Meldungen.

### Minikarten-Spielerpunkte

- Fehlende QT-Spielerpunkte behoben, wenn die Minikarte keine Karten-ID bereitstellt. QT verwendet bei Bedarf jetzt deine aktuelle Karte.

### Schnellere lokale Standortaktualisierungen

- Standortaktualisierungen erfolgen jetzt etwa einmal pro Sekunde bei weniger als 10 bekannten QT-Nutzern in deiner Zone, alle 5–10 Sekunden bei 10–19 und alle 15–20 Sekunden bei 100. Die Intervalle werden zwischen diesen Stufen schrittweise länger; Timings bei 500 oder mehr bleiben unverändert.
- Schnelle Aktualisierungen senden kompakte, frisch erfasste Standorte, während andere Spielerdetails ihren langsameren Heartbeat beibehalten. Bestehende Traffic-Limits gelten weiterhin, daher kann Überlastung die Zustellung verzögern. Andere Spieler benötigen dieses Update, um schnellere Positionen zu senden.

### Klarere übersetzte Meldungen

- Questsereignis-Bezeichnungen wie Quest angenommen verwenden jetzt deine Sprache, selbst wenn ein lokaler Questtitel oder optionale Übersetzungsmetadaten nicht verfügbar sind.
- Wenn WoW keinen lokalen Questtitel bereitstellen kann, behält QT den lesbaren Titel des Absenders bei. Fortschrittsmeldungen behalten weiterhin ihren ursprünglichen Text bei, wenn sie nicht sicher rekonstruiert werden können.

## 6.1.1

Übersichtlichere Kontextmenüs für Spieler und Quests.

### Bereinigung der Kontextmenüs

- Menüs für Spielernamen und Questnamen enthalten nicht mehr die Verknüpfung zum Logfenster. Verschiebe QuestTogether-Logs über das Minikartenmenü oder die Einstellungen zwischen dem Haupt-Chatfenster und einem separaten Fenster.

## 6.1.0

Findet Gruppen auf der Karte, seht, wer gemeinsam questet, und bittet über ein beliebiges Gruppenmitglied um Beitritt. Spieler-Tooltips stellen Gruppendetails jetzt in den Mittelpunkt.

### Seht, wer gemeinsam questet

- Gruppierte Spieler haben jetzt ein kleines Abzeichen mit zwei Personen auf ihren Karten- und Minikartenpunkten. Fahrt mit der Maus über ein Gruppenmitglied, um seine Begleiter weiß zu umranden, nicht zugehörige Punkte abzudunkeln und auf dem Anführer eine Krone anzuzeigen. Goldene Leuchteffekte für „Suche nach Questpartnern“ bleiben sichtbar.
- Spieler-Tooltips listen Gruppenmitglieder mit klassenfarbenen Punkten und Namen auf, wobei der gekrönte Anführer zuerst angezeigt wird. Bei Gruppen mit bis zu fünf Spielern werden alle Mitglieder aufgelistet; größere Gruppen zeigen nur den Anführer. Diese Details erscheinen auch, wenn ihr im QuestTogether-Protokoll mit der Maus über Spielernamen fahrt.
- Eure eigene Gruppe nutzt die Gruppenübersicht des Spiels. Details zu entfernten Gruppen werden bei Bedarf von aktualisierten QuestTogether-Peers geladen, mit zwischengespeicherten Ergebnissen und dosierten Anfragen, um den Kanalverkehr gering zu halten. Ältere Clients behalten ihre normalen Punkte und grundlegenden Informationen zur Gruppengröße; vollständige Details zu entfernten Gruppen erfordern einen aktualisierten Peer.

### Beitrittsanfragen können den Gruppenanführer erreichen

- Ihr könnt über ein Gruppenmitglied um Beitritt bitten, das euch nicht einladen kann. Wenn dessen Anführer QuestTogether nutzt und zum Einladen verfügbar ist, wird die Anfrage mit den üblichen Bestätigungs- und Auto-Annahme-Einstellungen an den Anführer weitergeleitet.
- Wenn nicht bekannt ist, dass der Anführer QuestTogether nutzt, kann das Mitglied „[QT] PlayerName möchte der Gruppe beitreten.“ im Gruppenchat ankündigen, wenn Gruppenchat-Ankündigungen aktiviert sind. Jemand mit Einladungsberechtigung muss euch dann manuell einladen.
- Der Anfragende und das weiterleitende Mitglied benötigen dieses Update für weitergeleitete Anfragen. Bestehende Prüfungen auf volle Gruppe, Einschränkungen, Ignorieren, Ablauf und Anfragenrate gelten weiterhin.

### Übersichtlichere Spieler-Tooltips

- Gruppeninformationen stehen jetzt direkt unter der Zeile mit Stufe, Volk und Klasse, mit kompakten Mitgliederzeilen und Abstand zwischen den Abschnitten. Allianz- und Horde-Abzeichen sind doppelt so groß.
- Die Addon-Version erscheint zuletzt im kürzeren Format vX.Y.Z. Wenn das Alter eines Standorts angezeigt wird, steht „Letzte Aktualisierung“ direkt über der Version.
- Anzahlen verfolgter Quests wurden aus Spieler- und Minikartenbutton-Tooltips entfernt. Der aktive Questtitel für Spieler, die nach Questpartnern suchen, wird weiterhin angezeigt.

## 6.0.2

Durchsuche frühere Updates von QuestTogether in deiner Sprache, mit besserer Wiederherstellung von Questnamen für Abschlussmeldungen.

### Frühere Patchnotes anzeigen

- Das Willkommensfenster hat jetzt Schaltflächen für Älter und Neuer, eine Verknüpfung zu Neueste sowie eine Verlaufsauswahl, die Release-Versionen und Daten anzeigt. Beim Öffnen der Patchnotes wird mit dem neuesten Release begonnen.
- Der Verlauf enthält jedes zuvor veröffentlichte Release, einschließlich der frühen Betas. Alle historischen Hinweise sind in jede unterstützte WoW-Sprachversion übersetzt und in den entsprechenden Repository-Changelogs enthalten.
- Navigationsschaltflächen werden deaktiviert, wenn es nirgendwohin weitergeht. Das Durchsuchen älterer Hinweise ändert nicht, welches Upgrade du bestätigt hast; automatische Popups erscheinen weiterhin nur bei größeren und kleineren Upgrades. Öffne das Fenster jederzeit mit /qt notes.

### Questabschluss-Titel

- Wenn eine Quest aus deinem Questlog verschwindet, bevor QuestTogether einen verwendbaren Titel hat, versuchen Abschlussmeldungen jetzt zuerst die verfügbare Questtitel-Abfrage des Spiels, bevor auf eine Quest-ID zurückgegriffen wird. Ein wiederhergestellter Titel bleibt unabhängig von der Reihenfolge der Abgabe- und Entfernungsereignisse erhalten.
- Ankündigungen verwenden weiterhin den Text des Absenders, wenn dein Client keinen lokalen Titel auflösen kann. Wenn keiner der beiden Clients einen Namen verfügbar hat, bleibt die Quest-ID die Ausweichlösung. Die verbesserte Wiederherstellung auf Absenderseite greift, wenn der Absender aktualisiert.

## 6.0.1

Feiern bleiben jetzt bei Spielern, die du in der Nähe tatsächlich sehen kannst.

### Korrekturen für Feiern in der Nähe

- Reaktionen darauf, dass ein anderer Spieler eine Quest abschließt oder eine Stufe aufsteigt, erfordern jetzt eine passende, sichtbare Spielereinheit. Kartenkoordinaten oder ein Name allein lösen kein Emote mehr aus, auch nicht, wenn devlogall aktiviert ist.
- Eingehende Emotes müssen mit QuestTogethers eigener Feierliste übereinstimmen. Nicht aufgeführte Emotes, einschließlich mountspecial und Fraktionsjubel, werden ignoriert, ohne einen Ersatz auszuwählen.
- Deine eigenen Feiern für Questabschluss und Stufenaufstieg behalten ihr bestehendes Verhalten und ihre Einstellungen bei.

## 6.0.0

QuestTogether 6.0 bereitet sich mit einem Kommunikationssystem auf den Forever-Launch vor, das den Hintergrunddatenverkehr reduzieren soll, während die Community wächst.

### Lokale Aktivität, weltweite Entdeckung

- Questankündigungen und häufige Spieleraktualisierungen verwenden jetzt Zonenkanäle. Gruppenankündigungen erreichen eure Gruppe weiterhin über Zonengrenzen hinweg.
- Spielerpunkte bleiben weltweit verfügbar, mit langsameren Hintergrundaktualisierungen. Wenn du eine andere Zone auf der Weltkarte öffnest, abonnierst du vorübergehend ihre Aktualisierungen.
- Der QT-Textchat bleibt im globalen QuestTogether-Kanal. Deine Chateinstellung Global oder Nur Zone steuert weiterhin, welche Nachrichten du siehst.

### Weniger Hintergrunddatenverkehr

- Präsenz, Version, Questanzahl, Partnerstatus und Standort werden in kompakten Aktualisierungen gebündelt. Überfüllte Zonen werden seltener aktualisiert, um den Datenverkehr zu reduzieren.
- Ankündigungen werden zeitlich gestaffelt und haben Vorrang vor Hintergrundaktualisierungen. Ping-Antworten werden verteilt, um einen Antwortschwall zu vermeiden. WoW kann die Kanalauslieferung weiterhin verzögern; dieses Update garantiert keine sofortigen Nachrichten.
- Spieler-Tooltips zeigen das Alter älterer Standorte an. Die Diagnose meldet jetzt Nachrichtenanzahlen, Drosselung und vom Absender gemeldete Ankündigungsverzögerungen.

### Ein großes Update während der Beta

- Wir nehmen diese größere Kommunikationsänderung jetzt in Erwartung des Forever-Launches vor. Die Beta ist der beste Zeitpunkt, um diese grundlegenden Entscheidungen zu treffen, bevor mehr Spieler vom alten Verhalten abhängig sind.
- Version 6.0 verlässt QuestTogetherAnnounce1 und sendet oder empfängt nicht mehr auf diesem Legacy-Kanal. Sie verwendet QuestTogether für globalen Chat und Entdeckung sowie Zonenkanäle für lokale Aktivität.
- QuestTogether behält seine Kanäle nach deinen anderen Chatkanälen bei, wobei der Hauptchatkanal vor seinen Zonenkanälen steht. Deine Einstellungen für Standortfreigabe, Ignorierliste und Ankündigungen bleiben erhalten.

### Kompatibilität mit älteren Versionen

- Bitte aktualisiert gemeinsam. Ältere Versionen können die neuen gebündelten Spieleraktualisierungen nicht lesen und nicht auf die neuen Zonenkanäle hören, sodass Spielern mit gemischten Versionen Kartenpunkte, Partnerstatus und Questankündigungen in der Nähe entgehen können.
- Spieler, die nur den Legacy-Kanal verwenden, sind in 6.0 über diesen Kanal nicht mehr auffindbar. Einige Austausche mit neueren 5.x-Versionen können weiterhin über den gemeinsamen globalen Kanal oder eine Gruppe funktionieren, aber das ist nur teilweise Kompatibilität, nicht das volle Erlebnis.
- Manuelles /qt ping verwendet weiterhin den globalen Kanal. Es kann dort kompatible ältere Clients hören, ist aber ein Entdeckungswerkzeug nach bestem Bemühen und keine vollständige Zählung aller, die QuestTogether verwenden.

## 5.17.2

QT-Chat lässt sich leichter von Questankündigungen unterscheiden.

### Weißer QT-Chattext

- Nachrichten von Spielern im QT-Chat verwenden jetzt weißen Text im Chatfenster und in Sprechblasen über dem Kopf.
- Spielernamen behalten ihre Klassenfarben, und Questankündigungen behalten ihren gelben Text.

## 5.17.1

Erfahre mehr über deine Questgefährten und prüfe den Queststatus direkt über Chat-Tooltips.

### Nützlichere Spieler-Tooltips

- Tooltips für Spielernamen und Kartenpunkte zeigen jetzt an, wie viele Quests QuestTogether überwacht, plus Solo oder Gruppe mit N. Dein eigener Tooltip verwendet deinen aktuellen lokalen Status.
- Der Minikarten-Tooltip zählt jetzt die von QuestTogether überwachten Quests und entspricht damit der Startankündigung, statt nur die Quests zu zählen, die im WoW-Tracker verfolgt werden.
- Entfernte Questzahlen und Gruppengrößen erfordern einen aktualisierten Peer. Sie werden etwa alle 80 Sekunden über bestehende Heartbeat-Nachrichten aktualisiert, ohne zusätzliche Nachrichten; fehlende oder veraltete Meldungen werden als unbekannt angezeigt. Ältere Versionen erhalten weiterhin kompatible Versionsankündigungen.

### Queststatus beim Darüberfahren

- Fahre in QT-Protokollen mit der Maus über einen Questnamen, um deinen Queststatus, die Teilbarkeit, die Quest-ID und den lokal verfolgten Zielfortschritt in einem Tooltip neben dem Mauszeiger zu sehen.
- Der Menüpunkt Status wurde entfernt. Ein Klick auf einen Questnamen öffnet weiterhin Teilen, Im Questlog öffnen, Gruppenquests vergleichen und die Zielaktion des Protokollfensters.
- Die neuen Tooltip-Beschriftungen sind in alle unterstützten Sprachen übersetzt. Questdetails spiegeln deinen eigenen Fortschritt wider, nicht den Questfortschritt des Absenders.

## 5.17.0

Sag im QT-Chat Hallo, finde Questpartner in deiner ganzen Zone und entdecke übersichtlichere Spielerdetails und Einstellungen.

### Mit anderen QuestTogether-Spielern chatten

- Gib /qt <text> ein oder wähle im Minikartenmenü „QT-Chatnachricht senden“. Unterhaltungen erscheinen in den QT-Logs und in Sprechblasen über Spielern in der Nähe mit einem Sprechblasen-Symbol; bestehende Chatbefehle funktionieren weiterhin.
- Wähle Globaler Chat (Standard), Nur Zone oder blende den QT-Chat vollständig aus. Nur Zone erfordert einen kürzlich geteilten Standort des Absenders; Global nicht.
- Der neue QuestTogether-Kanal funktioniert während der Übergangsphase parallel zu QuestTogetherAnnounce1. QT platziert beide nach deinen anderen Kanälen, wenn unterstützt, mit QuestTogether zuerst; eingegebener Chat verwendet nur den neuen Kanal.

### Questpartner finden

- Wenn du „Suche nach Questpartnern“ aktivierst, wird deine Suche in deiner ganzen Zone mit einem goldglänzenden QT-Symbol und einem Smiley angekündigt. Zonenweite Zustellung erfordert Standortfreigabe und berücksichtigt Ankündigungseinstellungen; beim Deaktivieren bleibt es still.
- Steuere diese Nachrichten unter „Was angekündigt werden soll“. Eine Abklingzeit von 30 Sekunden begrenzt wiederholte Ankündigungen, während dein Status und Leuchten weiterhin sofort aktualisiert werden. Du kannst außerdem festlegen, dass die Suche beim Beitritt zu einer Gruppe automatisch beendet wird; dies ist zunächst deaktiviert.
- Umschalt-Klick auf die Minikartenschaltfläche, um deine Partnersuche ein- oder auszuschalten. Ein hellerer, pulsierender Goldring hebt deine aktive Suche hervor, ohne das Logo abzuschneiden.

### Wähle deine Reichweite und sieh mehr Spielerdetails

- Die Reichweite für Spieler in der Nähe reicht jetzt von 5 % bis Ganze Zone, mit 25 % als Standard. Sie skaliert die Entfernung über deine aktuelle Zone; Gruppenmitglieder und direkt sichtbare Spieler behalten ihr bestehendes Verhalten.
- Fahre in den QT-Logs mit der Maus über Namen, um denselben verbesserten Tooltip wie bei Kartenpunkten zu sehen: einen klassenfarbenen Namen, Stufe, Volk, Klasse, Fraktionsemblem, Partnerstatus, verfolgte Quest, wenn verfügbar, und QT-Version. Namenstooltips erscheinen jetzt neben deinem Cursor.
- Dein eigener Namenstooltip zeigt jetzt deine aktuell hervorgehobene Quest an, während du nach Partnern suchst. Aktualisierte Clients melden ihre Versionen etwa alle 40 Sekunden über bestehende Heartbeat-Nachrichten; ältere Clients behalten ihren bisherigen Zeitplan bei.

### Übersichtlichere Steuerung und Ankündigungen

- Der Minikarten-Tooltip zeigt jetzt deine QT-Version, den Partnerstatus, Chatbereich, die Anzahl beobachteter Quests, die Reichweite für Spieler in der Nähe und den Status der Standortfreigabe an.
- Einstellungselemente haben jetzt übersetzte Erklärungen beim Darüberfahren, einschließlich Dropdowns, Schiebereglern, Profilaktionen und Farbauswahl.
- Wenn dein Client einen lokalisierten Questtitel nicht auflösen kann, behalten Ankündigungen den ursprünglichen Text des Absenders sowohl in Logs als auch in Sprechblasen bei, statt eine generische Questnummer anzuzeigen. Die lokalisierte Darstellung wird bei späteren Ankündigungen fortgesetzt, sobald der Titel verfügbar ist.

## 5.16.7

Lies dieselben QuestTogether-Versionshinweise im Spiel, auf Discord und in deiner bevorzugten Sprache in den Changelog-Dateien.

### Einheitliche, mehrsprachige Changelogs

- Der englische Changelog enthält jetzt dieselben Zusammenfassungen und Stichpunkte zu Veröffentlichungen wie das Willkommensfenster und die Discord-Ankündigungen.
- Changelog-Dateien sind für alle unterstützten Gebietsschemata verfügbar, mit bereits übersetztem Versionsverlauf und einer erhaltenen Kopie der älteren handgeschriebenen englischen Notizen.
- Release-Prüfungen halten die Changelog-Dateien mit den kanonischen Hinweisen und Übersetzungen synchron.

## 5.16.6

Sieh auf einen Blick, wann du nach Questpartnern suchst.

### Eine leuchtende Minikarten-Erinnerung

- Dein QuestTogether-Minimap-Button pulsiert jetzt mit demselben goldenen Logo-Leuchten wie Spielernamensplaketten, während „Suche nach Questpartnern“ aktiviert ist.
- Das Leuchten folgt deinem Partnerstatus und endet, wenn QT deaktiviert ist oder der Minimap-Button ausgeblendet wird. Dein Button und dein Logo behalten ihre bestehende Größe.

## 5.16.5

Ein kürzeres Präfix hält Gruppenankündigungen kompakt.

### Kompakte Gruppenankündigungen

- Questfortschritt, der an Gruppenmitglieder ohne QuestTogether gesendet wird, beginnt jetzt mit [QT] statt mit [QuestTogether].
- Ankündigungen beachten weiterhin das Limit für Chatnachrichten und erhalten vollständige Zeichen in jeder Sprache.

## 5.16.4

Behalte deine Sprechblasen-Einstellungen beim Verlassen des Bearbeitungsmodus und finde Questbegleiter in der Nähe auf überfüllten Karten.

### Sprechblasen-Einstellungen bleiben gespeichert

- Beim Schließen des HUD-Bearbeitungsmodus bleiben jetzt Schriftgröße, Anzeigedauer und Position deiner QT-Sprechblase erhalten, statt zurückgesetzt zu werden.
- Das QT-Sprechblasenfenster hat jetzt eine eigene Schaltfläche Änderungen speichern und eine Meldung zum gespeicherten Zustand. Einstellungen werden automatisch übernommen; Änderungen speichern legt den Punkt fest, zu dem Änderungen zurücksetzen zurückkehrt.
- Nach dem Speichern und weiteren Anpassungen stellt Änderungen zurücksetzen deine zuletzt gespeicherten QT-Einstellungen wieder her.

### Spieler in der Nähe haben Vorrang

- Wenn mehr als 128 geeignete Punkte auf der Karte oder Minikarte um Platz konkurrieren, haben die nächsten Spieler basierend auf der Entfernung zu deinem Charakter Vorrang.
- Wenn der Cache mit 512 Positionen voll ist, werden nähere Spieler vor weiter entfernten neu ankommenden Spielern behalten. Verschieben und Zoomen der Karte ändern die Nähe-Priorität nicht.
- Diese Änderungen behalten die bestehenden Punkt- und Cache-Begrenzungen bei, ohne zusätzliche Kommunikationsnachrichten zu senden.

## 5.16.3

Finde die benötigten Einstellungen leichter und sieh deine QuestTogether-Einstellungen auf einen Blick.

### Einstellungen danach organisiert, wie du spielst

- Gruppen & Teilen ersetzt Verschiedenes und führt Partnerverfügbarkeit, Beitrittsanfragen und Genehmigungen zum Teilen von Quests zusammen.
- Feier-Emotes befinden sich jetzt unter „Wo ankündigen“. Die Sichtbarkeit der Minikarte ist unter „Allgemein“ auf der Hauptseite zu finden, Debug-Werkzeuge und das erneute Einlesen des Questlogs zusammen unter „Fehlerbehebung“.
- Quests der Gruppe vergleichen und Questpartner finden sind jetzt die ersten Schnellaktionen. Deine bestehenden Einstellungen bleiben erhalten.

### Ein nützlicherer Schnellstatus

- Sieh deinen Partnerstatus, die Standortfreigabe und Anzeigeeinstellungen, Anfragegenehmigungen, Ankündigungsausgabe sowie Quest- und Spieler-Namensplaketten-Einstellungen in verknüpften Abschnitten.
- Prüfe dein aktives Profil, die installierte Version und jede erkannte neuere Version. Wenn QT deaktiviert ist, kennzeichnet die Zusammenfassung die Einstellungen klar als gespeicherte Präferenzen.
- Klicke auf eine Abschnittsüberschrift, um die zugehörigen Einstellungen zu öffnen. Die Zusammenfassung passt sich an ihren Text an und bleibt aktuell, solange die Seite geöffnet ist.

## 5.16.2

Erkenne QuestTogether-Spieler anhand ihrer Tooltips und finde Quest-Partner leichter.

### QuestTogether-Spielertooltips

- Fahre mit der Maus über den Charakter, die Namensplakette oder den Einheitenrahmen eines QT-Spielers, um „Dieser Spieler verwendet QuestTogether.“ zu sehen. Spieler, die nach Quest-Partnern suchen, zeigen ebenfalls diesen Status und ein leuchtendes QT-Logo an.
- Der QT-Abschnitt passt sich Breite und Skalierung des Tooltips an, hält Abstand zu seiner Gesundheitsleiste und wird über den Tooltip verschoben, wenn darunter wenig Platz ist.

### Ein auffälligeres Partnerleuchten

- Das goldene Namensplaketten-Leuchten reicht jetzt doppelt so weit um das Logo, während das Logo selbst gleich groß bleibt.
- Symbole und Leuchteffekte zeigen echte QT-Nutzer und ihren aktuellen Status bei der Partnersuche an.

## 5.16.1

Finde leichter Questpartner und sieh, auf welche Quest sie sich konzentrieren.

### Helleres Leuchten für Partner

- Spieler, die nach Questpartnern suchen, haben nun ein helleres goldenes Leuchten um ihr QT-Namensplakettenlogo, mit einem sanften pulsierenden Effekt. Das Logo selbst bleibt ruhig.

### Ihre aktuelle Quest sehen

- Fahre mit der Maus über den Karten- oder Minikartenpunkt eines Spielers, der nach Questpartnern sucht, um seine superverfolgte Quest zu sehen – die einzelne Quest, die für die Navigation ausgewählt ist. Beide Spieler benötigen dieses Update.
- Questinformationen werden etwa alle 20 Sekunden aktualisiert. Sie werden nur geteilt, wenn „Nach Questpartnern suchen“ und die Standortfreigabe aktiviert sind.
- Questnamen verwenden deine Client-Sprache, wenn verfügbar, andernfalls den Titel oder die Quest-ID des Absenders als Fallback. Ältere QT-Versionen behalten ihre bestehenden Punkte und Partneranzeigen.

## 5.16.0

QuestTogether unterstützt jetzt alle WoW-Sprachen und kann Questupdates anderer Spieler in der Sprache deines Clients anzeigen.

### In mehr Sprachen spielen

- Menüs, Einstellungen und Patchnotes unterstützen jetzt alle WoW-Sprachversionen: Englisch, Deutsch, Französisch, europäisches Spanisch, lateinamerikanisches Spanisch, brasilianisches Portugiesisch, Russisch, Italienisch, Koreanisch, vereinfachtes Chinesisch und traditionelles Chinesisch.
- Lateinamerikanisches Spanisch hat jetzt eigene Texte, statt europäisches Spanisch mitzubenutzen.

### Lokalisierter Questfortschritt

- Unterstützte Questereignisse von aktualisierten QT-Spielern können in QT-Chatprotokollen und -Sprechblasen in deiner Clientsprache erscheinen, mit lokalen Questtiteln, sofern verfügbar, und den tatsächlichen Fortschrittszahlen des Absenders.
- Wenn eine übersetzte Zielbeschreibung nicht sicher ausgewählt werden kann, verwendet QT stattdessen eine lokalisierte Zielnummer mit Zählwerten, Prozentangaben, Abschluss- oder Fortschrittsstatus.
- Ältere QT-Versionen und der öffentliche Gruppenchat behalten die Formulierung des Absenders bei. Wenn WoW keinen lokalen Questtitel liefern kann, behält QT den Quelltitel bei oder zeigt die Quest-ID an. Ereignisse in derselben Sprache behalten ihre detaillierte Originalformulierung.

### Feinschliff für Questtitel

- Der Questvergleich bevorzugt jetzt deinen lokalen Questtitel, sofern verfügbar.
- Lokalisierte Questtitel mit Nicht-ASCII-Satzzeichen bleiben zuverlässiger anklickbar.

## 5.15.0

Frage direkt über das Spielermenü von QuestTogether an, ob du einer Questgruppe beitreten kannst.

### Einer Questgruppe beitreten

- Bei QT-Spielern in einer Gruppe erscheint jetzt Beitritt anfragen statt Einladen, wenn aktuelle Gruppeninformationen vorliegen. Beide Spieler benötigen dieses Update; der Anfragende darf keiner Gruppe angehören.
- Der Empfänger kann eine normale WoW-Einladung senden oder ablehnen. Er muss einladen dürfen und Platz in einer normalen Gruppe haben. Zum Beitritt nimmst du weiterhin die normale Einladung an.

### Optionale automatische Einladungen

- Zwei neue Optionen genehmigen Anfragen von Freunden deines Charakters automatisch oder von anderen Spielern, während du nach Questpartnern suchst. Beide sind anfangs aus und stehen im Dialog sowie unter Verschiedenes. Battle.net-Accountfreunde sind nicht eingeschlossen.
- Anfragen laufen ab und berücksichtigen ignorierte Spieler, Gruppenänderungen und Spieleinschränkungen. QT verlässt niemals deine aktuelle Gruppe und nimmt keine Einladungen für dich an.

## 5.14.1

Gruppenankündigungen zeigen jetzt den vollständigen Namen QuestTogether.

### Gruppenchat

- Das Präfix für Ankündigungen im Gruppenchat wurde von [QT] zu [QuestTogether] erweitert, damit andere Spieler das Addon leichter finden.

## 5.14.0

QuestTogether spricht jetzt fünf weitere Sprachen und hilft dir, Gruppenmitglieder ohne QT auf dem Laufenden zu halten.

### Spiele in deiner Sprache

- Die Benutzeroberfläche ist jetzt auf Deutsch, Französisch, Spanisch, brasilianischem Portugiesisch und Russisch verfügbar. QuestTogether verwendet deine Spielsprache und greift bei Bedarf auf Englisch zurück.
- Einstellungen, Menüs, Tooltips, Questvergleiche und Patchnotes sind übersetzt. Questnamen und Fortschrittstexte anderer Spieler bleiben in ihrer ursprünglichen Sprache.
- Übersetzte Versionshinweise findest du in den fünf sprachspezifischen Änderungsprotokoll-Kanälen auf unserem Discord.

### Halte deine ganze Gruppe auf dem Laufenden

- Eine neue Option unter „Ankündigungskanäle“ sendet deine aktivierten Ereignismeldungen in den Gruppenchat, wenn mindestens ein Gruppenmitglied noch nicht als QT-Nutzer erkannt wurde. Sie ist standardmäßig aktiviert und lässt sich in den Einstellungen ausschalten.
- Das funktioniert auch in automatisch zusammengestellten Instanzgruppen. Alleinspiel und Schlachtzüge sind ausgeschlossen; Meldungen anderer Spieler werden niemals weitergeleitet.

## 5.13.1

Dieses Wartungsupdate verbessert die Wiederherstellung von Quest-Plaketten, entfernt veraltete Sprechblasen und Spielerlogos und sorgt dafür, dass Einstellungen und das Debug-Fenster konsistent funktionieren.

### Quest-Plaketten und Spieleranzeigen

- Questsymbole und Lebensleisten-Einfärbungen werden korrekt wiederhergestellt, nachdem eingeschränkte Ansichten geschlossen wurden. Verzögerte Questscans behalten ihre Einschwingzeit bei, und vorübergehend fehlende Tooltip-Daten behalten ihr Wiederholungsbudget.
- Ankündigungsblasen werden bereinigt, wenn eine Spielerplakette verschwindet oder im Kampf wiederverwendet wird. Geschützte oder verbotene Frames warten auf eine sichere Bereinigung.
- Kartenpositionen und Spielerpräsenz werden wiederhergestellt, nachdem QuestTogether deaktiviert, die Zone gewechselt und es wieder aktiviert wurde. Fortgegangene Spieler erhalten kein QT-Logo mehr durch verspätete Zurückziehungen von Standort- oder Partnerstatusdaten.

### Korrekturen an Einstellungen und Fenstern

- Das Kontrollkästchen Suche nach Questpartnern bleibt synchronisiert, wenn sich der Status über Befehle, Menüs oder Profileinstellungen ändert.
- Das Debug-Fenster beendet unterbrochene Zieh- und Größenänderungsvorgänge sicher, wenn Einschränkungen aufgehoben werden, selbst nachdem es ausgeblendet wurde.

### Verbesserungen der Zuverlässigkeit

- Verstärkte Tests erkennen den Zugriff auf verbotene Frames auch dann, wenn ein Fehler intern abgefangen wird.
- Veröffentlichungsprüfungen verweigern nun die Veröffentlichung, solange Implementierungsänderungen nicht committet sind, damit Korrekturen tatsächlich im Download ankommen.

## 5.13.0

Finde Questpartner auf einen Blick mit hervorgehobenen Kartenpunkten und Spielerlogos, einfacheren Standorteinstellungen und Erinnerungen, wenn ein anderer Spieler eine neuere stabile QuestTogether-Version hat.

### Questpartner erkennen

- Spieler, die Questpartner suchen, haben einen sanften goldenen Schein um ihre klassenfarbenen Punkte auf Karte und Minikarte.
- Ihr QuestTogether-Logo an der Namensplakette erhält einen sanften goldenen Schein. Hervorhebungen verschwinden, wenn der Status ausgeschaltet wird oder abläuft.
- Die Einstellungen für Spielerstandorte enthalten Nur Spieler anzeigen, die Questpartner suchen. Die Option ist anfangs ausgeschaltet und filtert bei Aktivierung beide Karten.
- Das Was ist neu-Fenster im Spiel zeigt normale und leuchtende Logos und Kartenpunkte nebeneinander. Goldener Schein bedeutet, dass Questpartner gesucht werden.

### Einfachere Standorteinstellungen

- Meinen Standort teilen und Andere Spieler anzeigen gelten jeweils sowohl für die Weltkarte als auch für die Minikarte.
- Beide Optionen sind bei neuen Profilen anfangs aktiviert. Vorhandene Ablehnungen der Standortfreigabe bleiben beim Upgrade erhalten.

### Erinnerungen an neue Versionen

- QuestTogether erkennt, wenn ein anderer Spieler eine neuere stabile Addon-Version meldet, und gibt eine Update-Erinnerung in deinem gewählten QuestTogether-Chatfenster aus.
- Die Erinnerung wird charakterübergreifend gespeichert und erscheint nach jedem Neuladen einmal, bis du die erkannte Version oder eine neuere installierst. Alpha- und Betaversionen lösen keine Erinnerungen aus.
- Versionsankündigungen sind klein und selten. QuestTogether erkennt Versionsinformationen auch in vorhandenen Ping-Antworten.

## 5.12.0

Finde Leute zum Questen mit dem neuen Status Suche nach Questpartnern. Dieses Update verbessert außerdem die Sichtbarkeit von Minikarten-Tooltips und trennt das Verhalten von Kriegsmodus und Realm in Retail von Forever.

### Suche nach Questpartnern

- Lass andere QuestTogether-Benutzer wissen, dass du Gesellschaft möchtest. Dein Status erscheint in deinem Spielermenü und in Tooltips von Kartenpunkten; er aktiviert weder die Standortfreigabe noch sendet er Einladungen.
- Schalte den Status über das Minikartenmenü, Einstellungen > Verschiedenes oder /qt lfg um. Verwende /qt lfg on, off oder status, um ihn festzulegen oder zu prüfen. Er ist anfangs ausgeschaltet und wird pro Profil gespeichert.
- Der Partnerstatus läuft ab, wenn keine Updates mehr kommen. Ignorierte Spieler werden ausgeschlossen, und das Deaktivieren von QuestTogether pausiert deine Anzeige.

### Retail und Forever

- Forever zeigt den Kriegsmodus nicht mehr in Tooltips von Spielerpunkten, Quest-Standortdetails oder Ping-Ausgaben an. Forever-Pings lassen außerdem Realm-Bezeichnungen aus, während vollständige Spielernamen erhalten bleiben.
- Quest-Updates in der Nähe benötigen auf Forever keine Kriegsmodus-Informationen aus Retail mehr. Kartenpunkte bleiben phasenübergreifend sichtbar, damit du Leute zum Gruppieren findest.
- Retail verwendet den aktiven Kriegsmodus-Status, wenn verfügbar. Unbekannter oder nicht unterstützter Kriegsmodus wird nicht mehr als Aus gemeldet.

### Stabilere Spielerpunkte

- Kurzzeitig fehlende Koordinaten entfernen deinen Punkt nicht mehr sofort. Zuletzt gemeldete Positionen bleiben bis zu zwei Minuten erhalten, und ältere Meldungen zeigen ihr Alter im Tooltip an. Opt-outs für die Freigabe ziehen den Standort weiterhin sofort zurück, wenn Kommunikation verfügbar ist.
- Bewegungsübertragungen sind auf einmal alle zehn Sekunden begrenzt, wodurch der Standortdatenverkehr reduziert wird. Herzschläge im Stand bleiben alle zwanzig Sekunden, damit ältere Clients kompatibel bleiben.
- Der Standortcache behält nun bis zu 512 Spieler. Jede Karte zeichnet weiterhin höchstens 128 sichtbare Punkte, und Spieler außerhalb der angezeigten Karte verbrauchen dieses Zeichenlimit nicht mehr.

### Zuverlässige Spielerlogos

- Fehlende Logos auf Namensplaketten befreundeter Spieler in aktuellen Forever- und Retail-Clients werden behoben, indem die aktuelle Sichtbarkeitseinstellung für befreundete Spieler ausgelesen wird.
- Links positionierte Logos rücken nach außen, um Platz für sichtbare Stärkungszauber zu schaffen, und kehren dann an ihre übliche Position zurück, wenn die Stärkungszauber verschwinden.
- Alle unterstützten QuestTogether-Nachrichten identifizieren nun ihren Absender. Ein begrenzter Cache merkt sich Spieler für die aktuelle UI-Sitzung, sodass verpasste Herzschläge ihre Logos nicht mehr entfernen. Ausdrückliche Abmeldungen und ignorierte Spieler werden weiterhin entfernt; es werden keine zusätzlichen Nachrichten gesendet.

### Feinschliff an der Minikarte

- Der QuestTogether-Minikarten-Tooltip verwendet nun eine unabhängige Tooltip-Ebene, damit er über der Aktionsleisten-UI erscheinen kann. Er wird ausgeblendet, wenn die Schaltfläche nicht verfügbar ist oder Einschränkungen beginnen.

## 5.11.0

QuestTogether fügt nun Spielerstandorte, Spielerplaketten-Logos, fokussierte Questvergleiche sowie einfacheres Discord-Feedback und Unterstützung hinzu. Über die Einstellungen wählst du, was du teilst und was du siehst, während der Questfortschritt mit anderen QuestTogether-Benutzern koordiniert bleibt.

### QuestTogether-Spieler in der Nähe finden

- Zeige das Schriftrollenlogo neben befreundeten QuestTogether-Spielern, wenn WoWs Namensplaketten für befreundete Spieler aktiviert sind. Spielerplaketten sind standardmäßig aktiviert, mit einer gepolsterten Position Links; wähle Links, Rechts, Oben oder Präfix, ohne die Farben der Lebensleisten zu ändern.
- Klassenfarbene Spielerpunkte können auf Weltkarte und Minikarte für Spieler erscheinen, die ihren Standort teilen. Fahre mit der Maus über einen Punkt, um Name, Fraktion, Volk, Klasse und Stufe zu sehen; klicke darauf, um das QuestTogether-Spielermenü zu öffnen.
- Spielerstandorte hat separate Schalter zum Teilen und Anzeigen für Weltkarte und Minikarte, und alle vier sind anfangs aktiviert. Die Präsenz für Spielerplaketten-Logos kann weiterlaufen, selbst wenn beide Schalter zum Teilen des Standorts ausgeschaltet sind.
- Standorte werden regelmäßig aktualisiert und verschwinden, wenn sie ablaufen. Beide Spieler benötigen das aktualisierte Addon; ein Punkt garantiert nicht, dass ihr euch in derselben Phase oder demselben Layer befindet.

### Einen Spieler oder die ganze Gruppe vergleichen

- Die Aktion Quests vergleichen im Spielermenü vergleicht nun nur dich und den ausgewählten Spieler, einschließlich erreichbarer QuestTogether-Kontakte außerhalb der Gruppe. Der Vergleich der ganzen Gruppe bleibt über das Minikartenmenü, Questnamen-Menüs und /qt compare verfügbar.
- Questteilen und Teilen-Anfragen bleiben auf die Gruppe beschränkt. Gezielte Vergleiche erklären, wann eine Gruppe zum Teilen benötigt wird und wann der ausgewählte Spieler QuestTogether benötigt, um zu antworten.
- Wenn eine Anfrage zum Teilen bereits auf einen anderen Spieler wartet, zeigt der Vergleich nun an, auf wen gewartet wird, nachdem du das Ziel gewechselt hast.

### Feedback und Unterstützung

- Das Willkommensfenster und die Haupteinstellungsseite enthalten nun Discord — Feedback & Support. Es öffnet eine kopierbare Einladung, wenn verfügbar, oder gibt die Einladung im Chat aus, falls das Linkfenster nicht geöffnet werden kann.

### Korrekturen und Feinschliff

- Ignorierte Spieler werden nun vollständiger gefiltert. Neue Logs, Sprechblasen, Punkte, Vergleiche und Teilen-Vorgänge werden unterdrückt, während vorhandene Sprechblasen und Standorte gelöscht werden, wenn sich die Ignorierliste ändert.
- Falsche Quest-Plaketten wurden behoben, die dadurch entstanden, dass nicht verfügbare Tooltip-Grenzen mit dem Zieltext einer anderen Quest übereinstimmten.
- Beim Ausschalten der Karten- oder Minikartenfreigabe wird das Update nach vorübergehenden Kommunikationsfehlern nun erneut versucht. Das Ausschalten beider Freigabeoptionen entfernt außerdem Standortdetails aus anderen Addon-Updates.
- Spielerlogos werden korrekt entfernt, wenn die Präsenz eines Spielers kurz vor seinem Verlassen abläuft. Flüstern von Kartenpunkten öffnet dein Chatfenster, und das Ändern des Log-Ziels über die Einstellungen ist während Einschränkungen nicht verfügbar.

## 5.10.0

QuestTogether teilt Questfortschritt mit deiner Gruppe und Spielern in der Nähe. Verwende die Minikarten-Schaltfläche für Einstellungen, Gruppenquestvergleiche, dein Questlog und diese neuesten Hinweise.

### Gruppenquests vergleichen und teilen

- Öffne Gruppenquests vergleichen über die Minikarte oder Quest- und Spielermenüs, oder gib /qt compare ein. Sieh, wer welche Quest hat und wie weit alle fortgeschritten sind.
- Standardmäßig erscheinen alle Gruppenquests. Aktiviere Quests ausblenden, die ich nicht habe, um dich auf Quests in deinem eigenen Questlog zu konzentrieren.
- Fordere teilbare Quests von Gruppenmitgliedern an, die das aktualisierte Addon verwenden. Anfragen bitten standardmäßig um Erlaubnis; automatisches Teilen ist eine optionale Einstellung.
- Vergleiche werden nach Karten- oder Kampfeinschränkungen wiederhergestellt. Aktualisierungen ersetzen ältere Antworten, und Abklingzeiten und Fehlschläge von Anfragen erklären, wann du es erneut versuchen kannst.

### Tastenkürzel und Questmenüs

- Ziehe die schriftrollenförmige Minikarten-Schaltfläche, um sie neu zu positionieren. Ihr Menü öffnet Einstellungen, Vergleiche, das Questlog, Patchnotes und die Steuerung für das Ziel des Logfensters. Blende sie über das Menü aus und stelle sie in den Einstellungen unter Verschiedenes wieder her.
- Questnamen-Menüs bieten Status, Teilen, Im Questlog öffnen und Gruppenquests vergleichen. Teilen- und Questlog-Aktionen prüfen die aktuelle Quest und Einschränkungen erneut, wenn sie angeklickt werden.
- Queststatus-Links behalten ihre Titel, nachdem eine Quest dein Questlog verlassen hat. Das Kontrollkästchen für automatisches Teilen folgt nun gespeicherten Einstellungen und Profiländerungen.

### Hilfe und neueste Hinweise

- Lies die Willkommens- und neuesten Patchnotes in einem eigenen Fenster statt in wiederholten Chatnachrichten. Wähle Patchnotes im Minikartenmenü oder auf der Haupteinstellungsseite, oder verwende /qt notes, /qt changelog oder /qt patchnotes.
- Das Hinweise-Fenster öffnet sich automatisch bei Haupt- und Nebenversions-Upgrades. Patch-Updates enthalten weiterhin neue Hinweise, ohne das Fenster automatisch zu öffnen.
- Verwende /qt help für normale Befehle und /qt help debug für Vorschauen, Diagnosen und Entwicklerbefehle.

## 5.9.2

Klicke mit der linken oder rechten Maustaste auf einen Questnamen im QuestTogether-Log, um sein Menü zu öffnen, mit Status an erster und Teilen an zweiter Stelle. Teilen verwendet den aktuellen Questlog-Eintrag, ohne Blizzards ausgewählte Quest zu ändern, und ist nicht verfügbar, wenn du solo bist, eingeschränkt bist oder die Quest nicht geteilt werden kann. Nach einem Trennstrich verschiebt die letzte Option QuestTogether-Logs zwischen dem Hauptfenster und separaten Fenstern, passend zum Spielernamen-Menü von QT.

### Änderungen in dieser Version

- Questnamen in Statusmeldungen anklickbar machen, einschließlich Ersatztiteln aus den Logs anderer Spieler. Bestehende Questlinks beim Formatieren abgeschlossener Questvergleiche beibehalten, damit Statusdetails nicht Teil eines zweiten, defekten Links werden.
- Validierung: 521 Tests bestehen in normaler und umgekehrter Reihenfolge unter Lua 5.1 und 5.2. Alle sechs Client-API-Profile, Lua- und Shell-Syntaxprüfungen, exakte libchev-Verifizierung und Diff-Prüfungen bestehen. Menüverhalten im Live-Client, Questteilen-Zustellung und Taint-Validierung auf Engine-Ebene bleiben separat.

## 5.9.1

Behebt Questverfolgung, Sichtbarkeit von Quest-Namensplaketten, Ankündigungen in Aufgabenbereichen, Kommunikationszuverlässigkeit und Benutzeraktionen, die im umfassenden Audit identifiziert wurden.

### Änderungen in dieser Version

- Verhindern, dass nicht zugehörige Tooltip-Questblöcke gemeinsamen Zieltext übernehmen. Gültigen Gruppenfortschritt beibehalten und Namensplaketten nach Karten-, Instanz-, Gruppen- und Queständerungen wiederherstellen.
- Neu angenommene Quests und erste Scans ausstehend halten, bis lesbare Daten eintreffen. Zielmeilensteine, Aufgabenklassifizierung und unbekannten Ortsstatus ohne falsche Ausstiege oder doppelte Einträge beibehalten.
- Lokalisierte Ankündigungen und Questvergleiche verbessern, einschließlich Nutzdatenlimits, Taktung, Wiederholungen, Abbruch und Meldung der Teilbarkeit.
- Native Wegpunktfehler respektieren, ohne einen alten Pin weiterzuverfolgen. Eingeschränkte Klicks bei deaktiviertem Zustand ablehnen, statt eingereihte Arbeit zu verlieren.
- Sprechblasentests zu lokalen Vorschauen machen und vollständige Forever-Namen oder Namen in Anführungszeichen akzeptieren, während die exakte Spieleridentität erhalten bleibt.
- Aktivieren/Deaktivieren und Profilbehandlung, Öffnen des HUD-Bearbeitungsmodus, genehmigte Feier-Emotes und Diagnosen korrigieren.
- Live-sichere Testisolation und Regressionsabdeckung stärken, fehlerhafte Testannahmen korrigieren und CI Lua-Syntaxfehler weitergeben lassen.
- Validierung: 516 Tests bestehen in normaler und umgekehrter Reihenfolge unter Lua 5.1 und 5.2. Alle sechs Client-API-Profile, Syntaxprüfungen, exakte libchev-Verifizierung und Diff-Prüfungen bestehen. Live-Client-Rendering, Zwei-Client-Zustellung und Taint-Validierung auf Engine-Ebene bleiben separat.

## 5.9.0

Feiere deine eigenen Stufenaufstiege und die von QuestTogether-Spielern in der Nähe mit synchronisierten Emotes. Separate, standardmäßig aktivierte Stufenaufstieg-Emote-Schalter neben den Questabschluss-Emote-Einstellungen unter Sonstiges hinzufügen. Reaktionen in der Nähe berücksichtigen den bestehenden Spielerbereich und die Näherungsregeln.

### Änderungen in dieser Version

- Bestätigte Questziel-Abschlüsse nach Kreaturentyp sowie nach einzelnem Spawn merken. Mobs, die während des Kampfs erscheinen, bleiben unmarkiert, wenn Tooltip-Daten nicht verfügbar sind, selbst wenn ein älterer Spawn als benötigt zwischengespeichert wurde. Neue, nicht abgeschlossene Ziele können die Hervorhebung wiederherstellen; Queststatusänderungen löschen den Abschlussspeicher. Unvollständige oder unzugängliche Tooltip-Daten werden nie als Beweis behandelt, dass alle fertig sind.
- Quest-Namensplaketten-Symbole und Lebensbalkenfärbung sofort löschen, wenn das Anrecht auf einen Mob verweigert wird, auch während des Kampfs. Auf Besitzwechsel achten und Anrechte bei Lebens- und Bedrohungsaktualisierungen erneut prüfen.
- Neu entdeckte Questmobs während gewöhnlicher Open-World-Kämpfe anhand lesbarer Einheiten-Tooltip-Daten erkennen. Namensplaketten aktualisieren, wenn sie hinter der Kamera hervorkommen, zu deinem Ziel werden oder Mouseover erhalten. Verzögerte Frames, GUIDs und Tooltip-Questzeilen mit einem begrenzten Budget pro Einheit erneut versuchen, veraltete Arbeit abbrechen, wenn Einheiten entfernt werden, und Färbung und Symbol gemeinsam wiederherstellen. Schutzprüfungen für Karte, Instanz, unzugängliche Daten und geschützte Frames beibehalten; Kampferkennung ruft weder Questie noch versteckte Tooltip-UI auf.
- Validierung: 374 Offline-Tests bestehen in normaler und umgekehrter Reihenfolge unter Lua 5.1 und 5.2. Sechs Client-API-Profile, Lua-Syntaxprüfungen, exakte Bibliotheksverifizierung und Diff-Prüfungen bestehen. Abschluss-Cache-Regressionen haben den Fehler vor der Behebung reproduziert. Live-Gameplay und Taint-Validierung auf Engine-Ebene bleiben separat.

## 5.8.6

Charakternamen, Klassennamen, Questtitel und benutzerdefinierte Klassenfarben gegen unzugängliche oder fehlerhafte API-Werte absichern. Optionale TomTom- und Questie-Integrationsdaten vor der Verwendung validieren und das Lesen von Questie-Tooltip-Zeilen bei unzugänglichen Daten stoppen. Sprechblasen-Sichtbarkeit und Bearbeitungsmodus-Status zu booleschen Werten normalisieren, bevor sie an UI-Steuerelemente übergeben werden.

### Änderungen in dieser Version

- Den Ereignishandler für Ladebildschirme konsolidieren, ungenutzte private Argumente und einen ungenutzten Einschränkungs-Enum-Zweig entfernen und Callback- sowie Rückgabewertbehandlung klarstellen. Moderne/Legacy-Client-Fallbacks und die exakte private Bibliotheksrevision unverändert lassen.
- Validierung: 336 Tests bestehen in normaler und umgekehrter Reihenfolge unter Lua 5.1 und 5.2, mit erweiterten Adapterprüfungen über sechs Client-Profile. Neue Regressionen schlagen gegen die vorherige Implementierung fehl. Lua-Parsing, exakte Bibliotheksverifizierung und Diff-Prüfungen bestehen. Die verbleibenden Ketho WoW API/LuaLS-Diagnosen wurden überprüft, einschließlich eines separaten Durchlaufs ohne Offline-Client-Mocks; beibehaltene Befunde haben spezifische Gründe bei Kompatibilität, Schutzprüfung, Callback, Bibliothek oder Fixture. Live-Validierung in Retail und Forever bleibt separat.

## 5.8.5

Kartenentdeckung für Aufgaben/Weltquests auf modernen Clients beheben, indem questID aus C_TaskQuest.GetQuestsOnMap gelesen wird, während die Legacy-API und das Feld questId für ältere Clients beibehalten werden. C_ChatInfo.PerformEmote bevorzugen, damit Abschluss-Emotes funktionieren, wenn veraltete Globals deaktiviert sind; fehlende oder fehlschlagende Emote-APIs sicher behandeln.

### Änderungen in dieser Version

- Eine ungenutzte Gruppenlisten-Fingerabdruckberechnung und ungenutzte lokale Variablen entfernen. Offline-Client-Prüfungen erweitern, um moderne und Legacy-Aufgaben-/Emote-APIs, API-Priorität, unzugängliche Questdaten und fehlende/fehlschlagende APIs abzudecken. Validierung: 334 Tests bestehen in normaler und umgekehrter Reihenfolge unter Lua 5.1 und 5.2, dazu die erweiterten API-Prüfungen auf sechs Client-Profilen, Lua-Parsing und exakte Bibliotheksverifizierung. Gameplay-Validierung in Retail und Forever bleibt von Offline-Prüfungen getrennt.

## 5.8.4

Repository-Aufräumen: lokale Entwicklungsnotizen außerhalb der nachverfolgten Quellen und Release-Pakete halten. Das Gameplay-Verhalten ist unverändert.

### Änderungen in dieser Version

- Repository-Aufräumen: lokale Entwicklungsnotizen außerhalb der nachverfolgten Quellen und Release-Pakete halten. Das Gameplay-Verhalten ist unverändert.

## 5.8.3

Die installierte Version, unterstützte Clients und den Einstellungsbefehl einmal pro Login oder UI-Neuladen ankündigen. Addon-spezifische CurseForge- und GitHub-Feedbacklinks einschließen; ein Klick auf einen Link öffnet ein Kopierfenster im nativen Stil. Nachrichtenverhalten beim Teilen und sichere Kopier-UI über private libchev 1.2.0 gemeinsam nutzen. Wenn Linkregistrierung oder Kopierfenster nicht verfügbar sind, die vollständige URL im Chat anzeigen. Ein nicht verfügbarer Willkommenshelfer kann den normalen Addon-Start nicht unterbrechen.

### Änderungen in dieser Version

- Validierung: 334 Tests bestehen in beiden Reihenfolgen unter Lua 5.1 und 5.2, mit Client-API-Prüfungen, Lua-Parsing und exakter Bibliotheksanbieter-Verifizierung. NoPoizen-Smoke-Simulationen üben beide Feedbacklinks auf allen sieben Client-/Regelwerk-Profilen aus. Live-Rendering bleibt eine separate Prüfung.

## 5.8.2

GUID-Abfragen der Test-Fixture von Spielern in der Nähe isolieren. Zwei falsche Fehler in /qt test beheben, wenn eine echte Einheit das Namensplaketten-Token belegt, das von den Tooltip- und Zwischensymbol-Prüfungen verwendet wird. Das Gameplay-Verhalten von Namensplaketten ist unverändert.

### Änderungen in dieser Version

- Die Offline-Umgebung enthält nun diese Token-Kollision und reproduziert beide Fehler ohne die Fixture-Behebung. Alle 333 Tests bestehen nach der Behebung in beiden Reihenfolgen unter Lua 5.1 und 5.2; sechs Client-API-Profile bestehen ebenfalls. Bestätigung im Spiel bleibt separat.

## 5.8.1

Blizzards Questmarkierung neben QuestTogether in der AddOns-Liste statt des standardmäßigen Fragezeichens anzeigen.

### Änderungen in dieser Version

- Blizzards Questmarkierung neben QuestTogether in der AddOns-Liste statt des standardmäßigen Fragezeichens anzeigen.

## 5.8.0

Aktuelle Classic-Clients mit korrekten Nutzdaten zur Questannahme, abgesicherten Ziel-API-Fallbacks, ehrlicher Meldung unbekannter Teilbarkeit, Flavor-Metadaten und API-Regressionsprüfungen für sechs Clients unterstützen. Retail-/Forever-Verhalten und gemeinsame Debug-Hilfsfunktionen beibehalten.

### Änderungen in dieser Version

- Validierung: 333 Tests bestehen in beiden Reihenfolgen unter Lua 5.1 und 5.2, mit sechs Client-Profilen, Lua-Parsing und exakten Vendor-Prüfungen privater Bibliotheken. NoPoizen-Client-Smoke-Prüfungen und Paketverifizierung bestehen ebenfalls. Live-Validierung der neuen Adapter steht noch aus.
- Siehe CLIENT_COMPATIBILITY.md für Quellennachweise, Umfang und Validierungsgrenzen.

## 5.7.7

Überlappende Debug-Konsolen und ihre Steuerelemente über private libchev 1.1.3 in einer nativen Stapelgruppe halten. Kategoriemenüs bleiben bei ihrer zugehörigen Konsole.

### Änderungen in dieser Version

- Questziel-Symbole standardmäßig links von der Namensplakette platzieren. Bestehende gespeicherte Symbolpositionen bleiben unverändert.
- Forevers Einstellung „My Last Name“ beim Anzeigen des Namens deines Charakters berücksichtigen. Die Nachnamen anderer Spieler sichtbar lassen, passend zum Geltungsbereich der nativen Einstellung. Vollständige Namen konsequent für Kommunikation, Gruppenmitgliedschaft, Namensplaketten-Abgleich und soziale Aktionen verwenden, während bestehende Profil- und persönliche Sprechblasenpositions-Schlüssel erhalten bleiben.
- Doppelte lokale Questankündigungen beheben, die entstehen, wenn deine eigene Kanalnachricht unter einem anderen Vollnamenformat empfangen wird. Die Regressionsabdeckung prüft die lokale Ankündigung gefolgt von ihren Kanal- und Gruppenechos, einschließlich eines anderen Charakters mit demselben Vornamen.
- Validierung: 331 Tests bestehen in beiden Reihenfolgen unter Lua 5.1/5.2. Live-Bestätigung des neuen Symbolstandards und der Mehrfenster-Interaktion bleibt separat.

## 5.7.6

Verwendet dieselbe private Debug-Konsole libchev 1.1.2 über alle drei Addons hinweg, einschließlich Kategorie-/Suchfiltern, Kopiersteuerungen, Testergebnissen, Diagnoseberichten, Zeitstempeln, sofern verfügbar, und einer einzigen abschließenden Testzusammenfassung. Behebt gestreckte native Frame-Grafiken mit expliziten Texturgrenzen.

### Änderungen in dieser Version

- QuestTogether stellt eigene Questdiagnosen und isolierte Tests bereit, während die gemeinsame Bibliothek die Konsole und das allgemeine Debug-Verhalten verwaltet. Führe /qt test, /qt debug oder /qt diagnostics aus.
- Validierung: 324 Tests bestehen in beiden Reihenfolgen unter Lua 5.1/5.2. Der Benutzer hat das korrigierte Frame-Aussehen im Spiel bestätigt. Weitere Validierung von Live-Einschränkungen und Gameplay bleibt separat.

## 5.7.6-beta.3

QuestTogether 5.7.6-beta.3 aktualisiert die eingebettete gemeinsame Debug-Konsole auf libchev 1.1.1.

### Änderungen in dieser Version

- Stellt das native WoW-ähnliche Fensterdesign in der gemeinsamen Konsole der Addons wieder her.
- Entfernt die doppelte Testzusammenfassungszeile, während die abschließende Zusammenfassung im begrenzten Verlauf erhalten bleibt.
- Behält die gemeinsamen Such-, Kategorie-, Kopier-, Scroll-, Test- und Diagnosefunktionen sowie die bestehenden Einschränkungsprüfungen bei.
- Der Benutzer hat gemeldet, dass alle 324 QT-Tests in Forever 1.60.1 Build 70009 auf beta.2 bestanden wurden. Die sieben live geladenen Testdateien von QT wurden außerdem auf ungültige Arithmetik geprüft; es wurden keine Fixtures zur NaN-Erzeugung oder Division durch null gefunden. Dieses frühere Live-Testergebnis validiert diese neue Änderung am Aussehen nicht.
- Öffne nach /reload /qtd, führe /qt test aus und prüfe das Fensteraussehen sowie die einzelne Zusammenfassung. Live-Rendering und Einschränkungs-/Taint-Verhalten für diese Revision müssen noch im Client verifiziert werden.
- Validierung: Alle 324 Fälle bestehen vorwärts/rückwärts unter echtem Lua 5.1.5 und 5.2.4, jeder CLI-Lauf gibt eine Zusammenfassung aus, und die extrahierte installierbare ZIP mit 26 Dateien besteht auf beiden Versionen. Alle 23 Lua-Dateien werden geparst; alle 22 TOC-Einträge und das Vendor-Manifest werden verifiziert. Formatierungs- und Diff-Prüfungen bestehen. Bibliotheks-Pin: 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. Es ist keine QT-GitHub-CI konfiguriert; die CI der Upstream-Bibliothek wurde bestanden.

## 5.7.6-beta.2

QuestTogether 5.7.6-beta.2 ersetzt sein separates Debug-Fenster durch die gemeinsame libchev v1.1-Konsole, die über die Addons hinweg verwendet wird. Die eingebettete Bibliothek ist enthalten; keine separate Installation ist erforderlich.

### Änderungen in dieser Version

- Gemeinsame Kategoriefilterung, unscharfe/angeführte Suche, Kopieren/Auswählen, Löschen, Neuladen, Tests, Diagnosen und Scroll-Follow-Verhalten.
- /qt test öffnet die aktuellen Ergebnisse; wiederholte Läufe ersetzen den alten TEST-Verlauf und löschen veraltete Suchfilter.
- /qt diagnostics [questID] und /qt diag [questID] erstellen den aktuellen zwischengespeicherten Bericht in derselben Konsole neu und behalten aktuelle Ereignisse innerhalb des gemeinsamen Exportbudgets bei.
- Gemeinsame Einschränkungs- und Own-Frame-Schutzmechanismen ersetzen die alten Konsolen-Callbacks und die Dropdown-Implementierung von QT.
- Queststatus, Ankündigungen, Namensplaketten, Kommunikation und QT-spezifische Testisolation bleiben im Besitz von QuestTogether.
- Dies ist eine Betaversion. Live-Rendering und Taint-Verhalten in Retail/Forever müssen noch verifiziert werden. Führe nach /reload /qt test und /qt diagnostics aus und teste anschließend Kategorie/Suche, Kopieren, Löschen, Größenänderung, Scrollen, wiederholte Testläufe sowie das Wechseln zwischen Berichten und Logs. Schließe Kampf-/Einschränkungsübergänge und dein übliches Addon-Set ein.
- Validierung: 324/324 Tests bestehen in beiden Reihenfolgen unter Lua 5.1.5 und 5.2.4. Alle 23 Lua-Dateien werden geparst, alle 22 TOC-Einträge validiert, und das angepinnte Bibliotheksmanifest wird verifiziert. Die installierbare ZIP wurde extrahiert und bestand alle 324 Fälle mit dem separaten Offline-Harness. Bibliotheks-Pin: 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

QuestTogether 5.7.6-beta.1 bettet libchev v1.0.0 ein, um Logging, Diagnosen, Callback-Schutzmechanismen, Mechaniken für aufgeschobene Arbeit und Testausführung mit den anderen Together-Addons zu teilen. Die Bibliothek ist enthalten; keine separate Addon-Installation ist nötig.

### Änderungen in dieser Version

- Diagnoseberichte enthalten gemeinsame Client-/Addon-/Bibliotheksinformationen und behalten die neuesten Ereignisse bei, wenn das Kopierfenster voll wird.
- Quest-, Gruppen-, Namensplaketten- und Einschränkungsverhalten bleibt im Besitz von QuestTogether, mit isolierten Laufzeitspeichern pro Addon.
- Koordinatenlinks bleiben nutzbar, während QT deaktiviert ist, sofern Einschränkungen sie erlauben; eingereihte Hintergrundarbeit bleibt pausiert, und veraltete Timer werden verworfen.
- /qt test enthält jetzt 315 Fälle: die bestehenden 300, zehn Prüfungen der gemeinsamen Bibliothek und fünf Integrationsregressionen.
- Validierung: Alle 315 Tests bestehen in beiden Reihenfolgen unter Lua 5.1.5 und 5.2.4; Lua-Syntax, TOC-Ladereihenfolge und das eingebettete Revisions-/Hash-Manifest bestehen. Eingebettete libchev-Quelle: 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- Dies ist eine Betaversion. Live-Rendering der Benutzeroberfläche und Taint-Verhalten in Retail/Forever nach dieser Auslagerung müssen noch verifiziert werden. Führe nach dem Neuladen /qt test und /qt diagnostics aus und teste anschließend Quests, Fortschrittsblasen, Namensplaketten und Koordinatenlinks über Kampf, Gebietswechsel, Deaktivieren/Reaktivieren und Neuladen hinweg mit deinen üblichen Addons. Die frühere Retail-Bestätigung mit 300 Tests galt für v5.7.5.
