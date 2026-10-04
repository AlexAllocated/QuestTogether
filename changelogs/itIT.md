# QuestTogether — Registro delle modifiche

<!-- Generated from canonical release notes; do not edit by hand. -->

## 5.16.6

Leggi le stesse note di rilascio di QuestTogether in gioco, su Discord e nella tua lingua preferita nei file del changelog.

### Changelog coerenti e multilingue

- Il changelog inglese ora condivide gli stessi riepiloghi di rilascio e gli stessi punti elenco della finestra di benvenuto e degli annunci su Discord.
- I file del changelog sono disponibili per tutte le lingue supportate, con la cronologia delle versioni tradotta esistente e una copia conservata delle vecchie note in inglese scritte a mano.
- I controlli di rilascio mantengono i file del changelog sincronizzati con le note canoniche e le traduzioni.

## 5.16.5

Un prefisso più breve mantiene compatti gli annunci del gruppo.

### Annunci di gruppo compatti

- I progressi delle missioni inviati ai membri del gruppo senza QuestTogether ora iniziano con [QT] invece di [QuestTogether].
- Gli annunci continuano a rispettare il limite dei messaggi della chat e preservano caratteri completi in ogni lingua.

## 5.16.4

Mantieni le impostazioni dei fumetti quando esci dalla modalità Modifica e trova compagni di missione nelle vicinanze sulle mappe affollate.

### Le impostazioni dei fumetti restano salvate

- Chiudendo la modalità Modifica dell'HUD ora vengono preservate le dimensioni del carattere, la durata di visualizzazione e la posizione del fumetto QT invece di ripristinarle.
- Il pannello dei fumetti QT ora ha un proprio pulsante Salva modifiche e un messaggio di stato salvato. Le impostazioni si applicano automaticamente; Salva modifiche imposta il punto a cui torna Annulla modifiche.
- Dopo aver salvato e apportato ulteriori modifiche, Annulla modifiche ripristina le ultime impostazioni QT salvate.

### Priorità ai giocatori vicini

- Quando più di 128 punti idonei competono per lo spazio sulla mappa o sulla minimappa, i giocatori più vicini hanno la priorità in base alla distanza dal tuo personaggio.
- Quando la cache da 512 posizioni si riempie, i giocatori più vicini vengono mantenuti prima degli arrivi più lontani. Spostare e ingrandire/ridurre la mappa non cambia la priorità di prossimità.
- Queste modifiche mantengono i limiti esistenti dei punti e della cache senza inviare messaggi di comunicazione aggiuntivi.

## 5.16.3

Trova più facilmente le impostazioni di cui hai bisogno e visualizza a colpo d'occhio le tue preferenze di QuestTogether.

### Impostazioni organizzate in base a come giochi

- Gruppi e condivisione sostituisce Varie, riunendo disponibilità dei compagni, richieste di ingresso e approvazioni per la condivisione delle missioni.
- Le emote di celebrazione ora si trovano sotto Dove annunciare. La visibilità della minimappa è sotto Generale nella pagina principale, con gli strumenti di debug e la nuova scansione del registro missioni insieme sotto Risoluzione dei problemi.
- Confronta le missioni del gruppo e Trova compagni per le missioni ora sono le prime Azioni rapide. Le tue preferenze esistenti vengono mantenute.

### Uno stato rapido più utile

- Visualizza lo stato dei tuoi compagni, le preferenze di condivisione della posizione e di visualizzazione, le approvazioni delle richieste, l'output degli annunci e le impostazioni di missioni e targhette dei nomi dei personaggi in sezioni collegate.
- Controlla il tuo profilo attivo, la versione installata e qualsiasi versione più recente rilevata. Quando QT è disattivato, il riepilogo identifica chiaramente le impostazioni come preferenze salvate.
- Fai clic sull'intestazione di una sezione per aprirne le impostazioni. Il riepilogo si espande per adattarsi al testo e rimane aggiornato mentre la pagina è aperta.

## 5.16.2

Riconosci i giocatori di QuestTogether dai loro tooltip e individua più facilmente compagni per le missioni.

### Tooltip dei giocatori di QuestTogether

- Passa il cursore sul personaggio, sulla barra del nome o sul riquadro unità di un giocatore QT per vedere “Questo giocatore usa QuestTogether.” I giocatori in cerca di compagni per le missioni mostrano anche quello stato e un logo QT luminoso.
- La sezione QT si adatta alla larghezza e alla scala del tooltip, resta separata dalla sua barra della salute e si sposta sopra il tooltip quando lo spazio sotto è limitato.

### Un bagliore dei compagni più visibile

- Il bagliore dorato della barra del nome ora si estende il doppio intorno al logo, mantenendo il logo stesso della stessa dimensione.
- Le icone e i bagliori rispecchiano i veri utenti QT e il loro attuale stato di ricerca compagni.

## 5.16.1

Trova più facilmente compagni per le missioni e vedi su quale missione si stanno concentrando.

### Un bagliore più luminoso per i compagni

- I giocatori in cerca di compagni per le missioni ora hanno un bagliore dorato più luminoso attorno al logo QT della loro targhetta, con una leggera pulsazione. Il logo stesso rimane stabile.

### Vedi la loro missione attuale

- Passa il mouse sul punto nella mappa o nella minimappa di un giocatore in cerca di compagni per le missioni per vedere la sua missione super-tracciata, cioè la singola missione selezionata per la navigazione. Entrambi i giocatori devono avere questo aggiornamento.
- Le informazioni sulla missione si aggiornano circa ogni 20 secondi. Vengono condivise solo mentre la ricerca di compagni per le missioni e la condivisione della posizione sono abilitate.
- I nomi delle missioni usano la lingua del tuo client quando disponibile, con il titolo inviato dal mittente o l'ID missione come ripiego. Le versioni precedenti di QT mantengono i loro punti e indicatori di compagno esistenti.

## 5.16.0

QuestTogether ora supporta tutte le lingue di WoW e può mostrare gli aggiornamenti delle missioni degli altri giocatori nella lingua del tuo client.

### Gioca in più lingue

- Menu, impostazioni e note della patch ora supportano tutte le lingue locali di WoW: inglese, tedesco, francese, spagnolo europeo, spagnolo latinoamericano, portoghese brasiliano, russo, italiano, coreano, cinese semplificato e cinese tradizionale.
- Lo spagnolo latinoamericano ora ha un proprio testo invece di condividere quello dello spagnolo europeo.

### Progressi delle missioni localizzati

- Gli eventi missione supportati dai giocatori QT aggiornati possono apparire nella lingua del tuo client nei registri e nei fumetti della chat QT, usando i titoli locali delle missioni quando disponibili e i numeri di progresso effettivi del mittente.
- Quando non è possibile scegliere in modo sicuro una descrizione tradotta dell'obiettivo, QT usa un numero di obiettivo localizzato con conteggi, percentuali, completamento o stato di avanzamento.
- Le versioni precedenti di QT e la chat di gruppo pubblica mantengono la formulazione del mittente. Quando WoW non può fornire un titolo di missione locale, QT mantiene il titolo originale o mostra l'ID della missione. Gli eventi nella stessa lingua mantengono la loro formulazione nativa dettagliata.

### Rifinitura dei titoli delle missioni

- Il confronto delle missioni ora preferisce il titolo locale della missione quando disponibile.
- I titoli localizzati delle missioni con punteggiatura non ASCII restano cliccabili in modo più affidabile.
