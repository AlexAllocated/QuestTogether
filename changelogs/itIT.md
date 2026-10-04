# QuestTogether — Registro delle modifiche

<!-- Generated from canonical release notes; do not edit by hand. -->

## 6.0.1

Le celebrazioni ora restano con i giocatori che puoi effettivamente vedere nelle vicinanze.

### Correzioni alle celebrazioni nelle vicinanze

- Le reazioni al completamento di una missione o all'aumento di livello di un altro giocatore ora richiedono un'unità giocatore corrispondente e visibile. Le coordinate della mappa o il solo nome non attivano più un'emote, anche quando devlogall è abilitato.
- Le emote in arrivo devono corrispondere alla lista di celebrazioni di QuestTogether. Le emote non presenti nella lista, incluse mountspecial e le acclamazioni di fazione, vengono ignorate senza scegliere un sostituto.
- Le tue celebrazioni per il completamento delle missioni e per l'aumento di livello mantengono il comportamento e le impostazioni esistenti.

## 6.0.0

QuestTogether 6.0 si prepara al lancio di Forever con un sistema di comunicazione progettato per ridurre il traffico in background man mano che la community cresce.

### Attività locale, scoperta mondiale

- Gli annunci delle missioni e gli aggiornamenti frequenti dei giocatori ora usano i canali di zona. Gli annunci del gruppo raggiungono comunque il tuo gruppo oltre i confini di zona.
- I puntini dei giocatori restano disponibili in tutto il mondo, con aggiornamenti in background più lenti. Aprire un'altra zona sulla mappa del mondo ti iscrive temporaneamente ai suoi aggiornamenti.
- La chat testuale di QT resta sul canale globale QuestTogether. La tua impostazione chat Globale o Solo zona continua a controllare quali messaggi vedi.

### Meno traffico in background

- Presenza, versione, conteggi delle missioni, stato del compagno e posizione sono raggruppati in aggiornamenti compatti. Le zone affollate si aggiornano meno spesso per ridurre il traffico.
- Gli annunci sono regolati e hanno priorità sugli aggiornamenti in background. Le risposte ai ping vengono distribuite per evitare un picco di risposte. WoW può comunque ritardare la consegna dei canali; questo aggiornamento non garantisce messaggi istantanei.
- I tooltip dei giocatori mostrano l'età delle posizioni meno recenti. La diagnostica ora riporta conteggi dei messaggi, limitazioni e ritardi degli annunci segnalati dal mittente.

### Un aggiornamento importante durante la beta

- Stiamo apportando ora questa modifica più ampia alla comunicazione in previsione del lancio di Forever. La beta è il momento migliore per prendere queste decisioni fondamentali, prima che più giocatori dipendano dal vecchio comportamento.
- La versione 6.0 abbandona QuestTogetherAnnounce1 e non invia né riceve più su quel canale legacy. Usa QuestTogether per chat globale e scoperta, più canali di zona per l'attività locale.
- QuestTogether mantiene i propri canali dopo gli altri tuoi canali di chat, con il canale chat principale prima dei suoi canali di zona. Le tue preferenze di condivisione della posizione, lista ignorati e annunci vengono conservate.

### Compatibilità con le versioni precedenti

- Aggiornate insieme. Le versioni precedenti non possono leggere i nuovi aggiornamenti raggruppati dei giocatori né ascoltare i nuovi canali di zona, quindi i giocatori con versioni diverse potrebbero non vedere puntini sulla mappa, stato del compagno e annunci delle missioni vicine.
- I giocatori che usano solo il canale legacy non sono più rilevabili tramite quel canale nella 6.0. Alcuni scambi con le versioni 5.x più recenti possono ancora funzionare tramite il canale globale condiviso o un gruppo, ma si tratta di compatibilità parziale, non dell'esperienza completa.
- Il comando manuale /qt ping usa ancora il canale globale. Può rilevare lì i client precedenti compatibili, ma è uno strumento di scoperta best-effort, non un conteggio completo di tutti quelli che usano QuestTogether.

## 5.17.2

La chat QT è più facile da distinguere dagli annunci delle missioni.

### Testo bianco per la chat QT

- I messaggi dei giocatori nella chat QT ora usano testo bianco nel registro chat e nei fumetti sopra la testa.
- I nomi dei giocatori mantengono i colori della loro classe, e gli annunci delle missioni mantengono il testo giallo.

## 5.17.1

Scopri di più sui tuoi compagni d'avventura e controlla lo stato delle missioni direttamente dai tooltip della chat.

### Tooltip dei personaggi più utili

- I tooltip del nome del personaggio e dei punti sulla mappa ora mostrano quante missioni QuestTogether sta monitorando, più Solo o Gruppo di N. Il tuo tooltip usa il tuo stato locale attuale.
- Il tooltip della minimappa ora conta le missioni monitorate da QuestTogether, corrispondendo all'annuncio all'avvio invece di contare solo le missioni osservate nel tracker di WoW.
- I conteggi delle missioni remote e le dimensioni dei gruppi richiedono un peer aggiornato. Si aggiornano circa ogni 80 secondi tramite i messaggi heartbeat esistenti, senza messaggi aggiuntivi; i rapporti mancanti o obsoleti vengono mostrati come sconosciuti. Le versioni precedenti continuano a ricevere annunci di versione compatibili.

### Stato missione al passaggio del mouse

- Passa il mouse sul nome di una missione nei registri QT per vedere lo stato della missione, la condivisibilità, l'ID missione e l'avanzamento degli obiettivi tracciati localmente in un tooltip accanto al cursore.
- La voce di menu Stato è stata rimossa. Fare clic sul nome di una missione apre ancora Condividi, Apri nel Registro missioni, Confronta missioni del gruppo e l'azione di destinazione della finestra di registro.
- Le nuove etichette dei tooltip sono tradotte in tutte le lingue supportate. I dettagli della missione riflettono il tuo avanzamento, non la fase della missione del mittente.

## 5.17.0

Saluta nella chat QT, trova compagni per le missioni nella tua zona e scopri dettagli dei giocatori e impostazioni più chiari.

### Chatta con altri giocatori di QuestTogether

- Digita /qt <text>, oppure scegli Invia messaggio chat QT dal menu della minimappa. Le conversazioni compaiono nei registri QT e nei fumetti sopra la testa nelle vicinanze con un'icona a fumetto; i comandi slash esistenti continuano a funzionare.
- Scegli chat globale (predefinita), Solo zona, oppure nascondi completamente la chat QT. Solo zona richiede una posizione condivisa recente dal mittente; Globale no.
- Il nuovo canale QuestTogether funziona insieme a QuestTogetherAnnounce1 durante la transizione. QT posiziona entrambi dopo gli altri tuoi canali quando supportato, con QuestTogether per primo; la chat digitata usa solo il nuovo canale.

### Trova compagni per le missioni

- Attivare Cerco compagni per le missioni annuncia la tua ricerca in tutta la zona con un'icona QT dal bagliore dorato e uno smiley. La consegna in tutta la zona richiede la condivisione della posizione e rispetta le preferenze degli annunci; disattivarla non invia nulla.
- Controlla questi messaggi in Cosa annunciare. Un tempo di recupero di 30 secondi limita gli annunci ripetuti, mentre il tuo stato e il bagliore si aggiornano comunque subito. Puoi anche scegliere di smettere automaticamente di cercare quando entri in un gruppo; questa opzione è inizialmente disattivata.
- Maiusc-clic sul pulsante della minimappa per attivare o disattivare la ricerca di compagni. Un anello dorato più luminoso e pulsante evidenzia la tua ricerca attiva senza tagliare il logo.

### Scegli il raggio e vedi più dettagli sui giocatori

- Raggio vicinanza ora va dal 5% a Intera zona, con valore predefinito 25%. Scala la distanza nella tua zona attuale; i membri del gruppo e i giocatori direttamente visibili mantengono il comportamento esistente.
- Passa il mouse sui nomi nei registri QT per lo stesso suggerimento migliorato dei punti sulla mappa: nome colorato per classe, livello, razza, classe, emblema della fazione, stato compagno, missione tracciata quando disponibile e versione QT. I suggerimenti dei nomi ora compaiono accanto al cursore.
- Il suggerimento del tuo nome ora mostra la missione attualmente super-tracciata mentre cerchi compagni. I client aggiornati pubblicizzano le versioni circa ogni 40 secondi usando i messaggi heartbeat esistenti; i client più vecchi mantengono la loro pianificazione precedente.

### Controlli e annunci più chiari

- Il suggerimento della minimappa ora mostra la tua versione QT, lo stato compagno, l'ambito della chat, il numero di missioni osservate, il raggio di vicinanza e lo stato della condivisione della posizione.
- I controlli delle impostazioni ora hanno spiegazioni tradotte al passaggio del mouse, inclusi menu a discesa, cursori, azioni profilo e controlli colore.
- Quando il tuo client non riesce a risolvere un titolo di missione localizzato, gli annunci conservano il testo originale del mittente sia nei registri sia nei fumetti invece di mostrare un numero di missione generico. La resa localizzata riprende per gli annunci successivi una volta che il titolo è disponibile.

## 5.16.7

Leggi le stesse note di rilascio di QuestTogether in gioco, su Discord e nella tua lingua preferita nei file del changelog.

### Changelog coerenti e multilingue

- Il changelog inglese ora condivide gli stessi riepiloghi di rilascio e gli stessi punti elenco della finestra di benvenuto e degli annunci su Discord.
- I file del changelog sono disponibili per tutte le lingue supportate, con la cronologia delle versioni tradotta esistente e una copia conservata delle vecchie note in inglese scritte a mano.
- I controlli di rilascio mantengono i file del changelog sincronizzati con le note canoniche e le traduzioni.

## 5.16.6

Vedi a colpo d'occhio quando stai cercando compagni per le missioni.

### Un promemoria luminoso sulla minimappa

- Il tuo pulsante di QuestTogether sulla minimappa ora pulsa con lo stesso bagliore dorato del logo delle targhette dei nomi dei personaggi mentre Cerchi compagni per le missioni è attivo.
- Il bagliore segue il tuo stato di compagno e si interrompe quando QT è disabilitato o il pulsante della minimappa è nascosto. Il tuo pulsante e il logo mantengono le dimensioni esistenti.

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
