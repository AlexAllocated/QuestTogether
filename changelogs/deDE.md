# QuestTogether — Änderungsprotokoll

<!-- Generated from canonical release notes; do not edit by hand. -->

## 5.17.1

QT-Chat lässt sich leichter von Questankündigungen unterscheiden.

### Weißer QT-Chattext

- Nachrichten von Spielern im QT-Chat verwenden jetzt weißen Text im Chatfenster und in Sprechblasen über dem Kopf.
- Spielernamen behalten ihre Klassenfarben, und Questankündigungen behalten ihren gelben Text.

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
