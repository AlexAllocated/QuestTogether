# QuestTogether — Registro delle modifiche

<!-- Generated from canonical release notes; do not edit by hand. -->

## 6.4.0

Finestre QT più curate e accesso più rapido alle missioni del gruppo.

### Registro missioni del gruppo

- Scopri il Registro missioni del gruppo introdotto nella versione 6.3: confronta fino a cinque giocatori in colonne con i colori delle classi, verifica chi possiede ogni missione, a chi manca e quando il gruppo è pronto a consegnarla. Combina ricerca e filtri per possesso, avanzamento e azione. Condivisione e richieste di condivisione sono disponibili quando supportate.
- L’intestazione di ogni giocatore mostra la sua missione attiva. Clicca sul nome di un compagno per seguirne volontariamente la missione; se non la possiedi, la tua navigazione resta invariata. Aggiorna recupera una nuova istantanea dei progressi remoti. Le immagini mostrano dati fittizi dell’anteprima.
- Le missioni che possiedi hanno ora un piccolo pulsante con un libro che apre i dettagli nel Registro missioni di Blizzard. Un clic sulla riga continua a espandere gli obiettivi.
- Una corona identifica il capogruppo e si aggiorna quando cambia il comando. La tua colonna rimane sempre la prima.

**Retail**

![Registro missioni del gruppo — Retail](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogRetail.png)

**Forever**

![Registro missioni del gruppo — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogForever.png)

### Espandi gli obiettivi di tutti

- Clicca su una missione per vedere contatori, barre di avanzamento e passaggi completati di ciascun membro. Puoi lasciare aperte più missioni. Questa versione rende le sezioni più compatte e uniforma lo sfondo con i colori di classe di nomi e obiettivi. Una missione tipica per cinque giocatori con due obiettivi ciascuno entra nella finestra predefinita; quelle più lunghe possono richiedere lo scorrimento.

**Forever**

![Espandi gli obiettivi di tutti — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestObjectivesForever.png)

### Finestre e minimappa

- Il clic sinistro sull’icona della minimappa apre o chiude il Registro missioni del gruppo; il clic destro apre il menu. Le impostazioni sono tornate nel menu e il tooltip spiega le scorciatoie.
- I promemoria della chat di gruppo, le richieste di condivisione e di ingresso, le impostazioni dei fumetti e la finestra del collegamento Discord usano ora la cornice a pergamena e i temi chiaro/scuro di QT, con più margini e spazio per i valori dei cursori.
- Trascinando le finestre si mantiene la distanza dal puntatore, anche nell’anteprima del confronto. Menu e tooltip ora chiamano sempre Registro missioni la finestra di Blizzard.

### Comandi di anteprima

- Usa /qt preview per elencare le anteprime di finestre e annunci. I vecchi comandi funzionano ancora; le azioni simulate non invitano giocatori, condividono missioni o inviano messaggi.
- L’anteprima del confronto ora mostra un gruppo completo di cinque giocatori, tra cui un Cacciatore e un Ladro, con obiettivi diversi, missioni attive e una corona per il capogruppo.

## 6.3.1

Spaziatura più confortevole nel registro missioni del gruppo.

### Spaziatura dei pannelli degli obiettivi

- I pannelli degli obiettivi espansi hanno ora più spazio interno in basso, così le barre di avanzamento non toccano il bordo. Lo scorrimento e le animazioni di espansione tengono conto dello spazio aggiunto.
- I messaggi come «Nessun dettaglio sugli obiettivi disponibile» sono centrati verticalmente accanto al nome del giocatore anziché essere troppo vicini al bordo superiore.

## 6.3.0

Un nuovo Registro missioni del gruppo, destinazioni condivise e il seguito facoltativo delle missioni rendono più facile giocare insieme.

### Registro missioni del gruppo

- Il confronto diventa Registro missioni del gruppo. Espandi più missioni contemporaneamente per vedere obiettivi e progressi di ogni membro, con un riepilogo delle missioni pronte per la consegna.
- Cerca missioni e combina filtri di possesso, progresso e condivisione. Aggiorna richiede nuovi dati agli altri giocatori; i client meno recenti confrontano ancora gli elenchi, ma non forniscono dettagli sugli obiettivi.
- Ridimensiona la finestra di pergamena e scorri in modo fluido. Colonne nei colori delle classi, intestazioni cliccabili con spaziatura interna e pannelli degli obiettivi arrotondati migliorano la leggibilità.

### Missione attiva e punti di passaggio condivisi

- La missione attiva compare sotto il nome di ogni membro. Scegli di seguirla dall'intestazione o dal menu QT per attivare missioni che possiedi. Una missione assente o deselezionata lascia invariata la navigazione; navigare manualmente, lasciare il gruppo o ricaricare l'interfaccia interrompe il seguito.
- I punti di passaggio Blizzard degli altri membri appaiono nei colori delle classi sulla mappa del mondo e, se vicini, sulla minimappa. I segnalini sovrapposti elencano tutti i proprietari; Naviga qui usa TomTom o la navigazione nativa. Ricevere un punto non cambia la destinazione e non implica una fase condivisa.
- Condividi la mia missione attiva, Condividi il mio punto di passaggio e Mostra i punti del gruppo sono attivi per impostazione predefinita in Gruppi e condivisione, indipendentemente dalla posizione pubblica e dalla ricerca di compagni. Seguire richiede una scelta esplicita. Servono compagni aggiornati in gruppi fino a cinque, spedizioni comprese; le incursioni sono escluse.

### Finestre e menu

- Anche le note di aggiornamento usano la pergamena scura, con modalità chiara facoltativa. Sposta o ridimensiona la finestra, sfoglia una cronologia più ordinata e usa le frecce per cambiare versione o saltare alle estremità. Discord e Impostazioni sono nel piè di pagina.
- I suggerimenti dei giocatori si adattano meglio al contenuto. Il menu della minimappa separa gli strumenti delle missioni da note, posizione del registro e visibilità dell'icona. Impostazioni e Invia messaggio nella chat QT sono rimossi da questo menu; le impostazioni restano disponibili con /qt options.

## 6.2.3

Meno annunci ripetuti di missioni pronte da consegnare.

### Correzioni al rilevamento delle missioni pronte

- Le missioni già pronte da consegnare o completate all’inizio del monitoraggio vengono registrate senza annunci. I dati di consegna mancanti e gli aggiornamenti successivi non ripetono più gli annunci di missioni pronte da consegnare già rilevati.
- I nuovi completamenti vengono ancora annunciati e accettare nuovamente una missione ne azzera la cronologia delle notifiche. Il giocatore che invia gli annunci deve installare questo aggiornamento; le versioni precedenti possono ancora inviarne molti tutti insieme.

## 6.2.2

Progressi delle missioni leggibili in ogni lingua.

### Mantieni i dettagli degli obiettivi

- I progressi di missioni, missioni mondiali e obiettivi bonus ora mantengono il testo e i contatori originali del mittente nella chat e nei fumetti, invece di sostituirli con testo generico come "Obiettivo 1: 5/5".
- Gli annunci delle missioni accettate e completate continuano a usare etichette tradotte e i titoli delle missioni disponibili localmente.

## 6.2.1

Più chiarezza e controllo sugli annunci nella chat di gruppo.

### Scopri quando QT scrive nella chat di gruppo

- L’opzione in Dove annunciare ora spiega chiaramente che QT scrive anche nella chat di gruppo quando un membro non viene riconosciuto come utente QT. Rimane attiva per impostazione predefinita.
- Una nuova finestra con il logo QT appare dopo una breve attesa per il rilevamento. Scegli Lascia attivo o Disattiva annunci prima che inizi l’invio. Non ricordarmelo più salva la conferma per il profilo attuale.
- Il promemoria tradotto elenca i membri interessati e può riapparire quando si uniscono nuovi membri non identificati. Scompare se vengono riconosciuti come utenti QT. Gli eventi trattenuti durante l’attesa non vengono inviati in seguito.

## 6.2.0

Punti vicini più fluidi, dettagli dei giocatori più rapidi e comunicazioni più affidabili.

### Movimento più fluido sulla minimappa

- I giocatori vicini possono scambiarsi le posizioni tramite sussurri dell’addon a frequenza limitata. Il movimento fluido privilegia fino a quattro dei giocatori idonei più vicini e rispetta condivisione, filtri, giocatori ignorati e limiti di traffico.
- Entrambi i giocatori devono installare questo aggiornamento per i flussi di posizione e le risposte dirette al passaggio del puntatore. Le versioni precedenti mantengono le normali trasmissioni; ritardi e restrizioni del server possono ancora influire sulla consegna.

### Rilevamento e dettagli del gruppo più rapidi

- Passare il puntatore su un nome o un punto può richiedere direttamente dettagli aggiornati. Le richieste hanno una frequenza limitata e gli elenchi dei membri invariati non scadono più dopo due minuti.
- Posizioni recenti, stato di ricerca di compagni e dettagli noti del gruppo sopravvivono a /reload per un massimo di tre minuti dal rilevamento originale. Entrare in una zona richiede anche un aggiornamento scaglionato del rilevamento.
- I tooltip usano lo stato noto di giocatore solo o in gruppo mentre attendono la dimensione esatta del gruppo. Un piccolo logo identifica gli utenti QT nell’elenco dei membri, mantenendo i nomi allineati.

### Traduzioni e presentazione più chiare

- Nomi delle razze, dettagli del ping, dati delle missioni e altri testi dell’interfaccia usano le traduzioni locali disponibili. Se manca una traduzione della missione, resta il testo leggibile del mittente; i progressi non usano descrizioni di obiettivi locali non pertinenti.
- Gli annunci generici ora usano il logo QT. La ricerca di compagni di missioni è la prima opzione nel menu della minimappa.

### Comunicazione e affidabilità

- Confronti, elenchi del gruppo, richieste di ingresso e condivisione e risposte ping preferiscono sussurri diretti con giocatori compatibili. Messaggi periodici consolidati e meno aggiornamenti di posizioni invariate riducono il traffico pubblico ridondante.
- Corretti controlli ripetuti delle missioni, tentativi eccessivi sulle barre dei nomi, finestre impossibili da chiudere durante le restrizioni e /qt set che accettava impostazioni diverse da attiva/disattiva. Disattivare la condivisione della posizione non elimina più altre richieste in coda.

## 6.1.2

Punti dei giocatori vicini più reattivi e annunci tradotti più chiari.

### Punti dei giocatori sulla minimappa

- Risolto il problema dei punti dei giocatori QT mancanti quando la minimappa non fornisce un ID mappa. QT ora usa la tua mappa attuale quando necessario.

### Aggiornamenti più rapidi della posizione locale

- Gli aggiornamenti della posizione ora vengono inviati circa una volta al secondo con meno di 10 utenti QT noti nella tua zona, ogni 5–10 secondi con 10–19 e ogni 15–20 secondi a 100. Gli intervalli si allungano gradualmente tra questi livelli; le tempistiche a 500 o più restano invariate.
- Gli aggiornamenti rapidi inviano posizioni compatte e appena rilevate, mentre gli altri dettagli dei giocatori mantengono il loro heartbeat più lento. I limiti di traffico esistenti sono ancora validi, quindi la congestione può ritardare la consegna. Gli altri giocatori devono avere questo aggiornamento per inviare posizioni più rapide.

### Annunci tradotti più chiari

- Le etichette degli eventi delle missioni, come Missione accettata, ora usano la tua lingua anche quando non è disponibile un titolo locale della missione o metadati di traduzione opzionali.
- Quando WoW non può fornire un titolo locale della missione, QT conserva il titolo leggibile del mittente. I messaggi di progresso mantengono comunque il loro testo originale quando non possono essere ricostruiti in modo sicuro.

## 6.1.1

Menu contestuali più puliti per giocatori e missioni.

### Pulizia del menu contestuale

- I menu dei nomi dei giocatori e delle missioni non includono più la scorciatoia per la finestra del registro. Sposta i registri di QuestTogether tra la finestra principale della chat e una finestra separata usando il menu della minimappa o le impostazioni.

## 6.1.0

Trova gruppi sulla mappa, vedi chi sta svolgendo missioni insieme e richiedi di unirti tramite qualsiasi membro del gruppo. I tooltip dei giocatori ora mettono i dettagli del gruppo in primo piano.

### Vedi chi sta svolgendo missioni insieme

- I giocatori in gruppo ora hanno un piccolo distintivo con due persone sui loro punti di mappa e minimappa. Passa il mouse su un membro del gruppo per evidenziare i suoi compagni con un contorno bianco, attenuare i punti non correlati e mostrare una corona sul capogruppo. I bagliori dorati per la ricerca di compagni per le missioni restano visibili.
- I tooltip dei giocatori elencano i membri del gruppo con punti e nomi colorati in base alla classe, con il capogruppo incoronato per primo. I gruppi fino a cinque membri li elencano tutti; i gruppi più grandi mostrano solo il capogruppo. Questi dettagli appaiono anche passando il mouse sui nomi dei giocatori nel registro di QuestTogether.
- Il tuo gruppo usa l'elenco del gioco. I dettagli dei gruppi remoti vengono caricati dai peer QuestTogether aggiornati quando necessario, con risultati in cache e richieste scaglionate per mantenere basso il traffico del canale. I client più vecchi mantengono i loro normali punti e le informazioni di base sulla dimensione del gruppo; i dettagli completi dei gruppi remoti richiedono un peer aggiornato.

### Le richieste di invito possono raggiungere il capogruppo

- Puoi richiedere di unirti tramite un membro del gruppo che non può invitarti. Se il suo capogruppo usa QuestTogether ed è disponibile a invitare, la richiesta viene reindirizzata al capogruppo usando le solite impostazioni di conferma e approvazione automatica.
- Se non è noto che il capogruppo usi QuestTogether, il membro può annunciare “[QT] PlayerName richiede di unirsi al gruppo.” nella chat di gruppo quando gli annunci in chat di gruppo sono abilitati. Qualcuno con il permesso di invitare dovrà poi invitarti manualmente.
- Chi richiede e il membro che inoltra hanno bisogno di questo aggiornamento per le richieste reindirizzate. I controlli esistenti per gruppo pieno, restrizioni, ignorati, scadenza e frequenza delle richieste continuano ad applicarsi.

### Tooltip dei giocatori più chiari

- Le informazioni del gruppo ora si trovano subito sotto la riga con livello, razza e classe, con righe compatte per i membri e spazio tra le sezioni. Gli stemmi di Alleanza e Orda sono grandi il doppio.
- La versione dell'addon appare per ultima nel formato più breve vX.Y.Z. Quando viene mostrata l'età di una posizione, Ultimo aggiornamento si trova direttamente sopra la versione.
- I conteggi delle missioni tracciate sono stati rimossi dai tooltip dei giocatori e del pulsante sulla minimappa. Il titolo della missione attiva per i giocatori che cercano compagni per le missioni viene ancora mostrato.

## 6.0.2

Sfoglia gli aggiornamenti passati di QuestTogether nella tua lingua, con un recupero migliore dei nomi delle missioni per gli annunci di completamento.

### Sfoglia le note delle patch precedenti

- La finestra di benvenuto ora ha i pulsanti Meno recenti e Più recenti, una scorciatoia Ultima e un selettore Cronologia che mostra versioni e date di rilascio. All'apertura, le note della patch partono dall'ultima versione.
- La cronologia include ogni versione pubblicata in precedenza, incluse le prime beta. Tutte le note storiche sono tradotte in ogni localizzazione di WoW supportata e incluse nei changelog dei repository corrispondenti.
- I pulsanti di navigazione si disattivano quando non c'è nessun'altra nota da vedere. Consultare note più vecchie non cambia quale aggiornamento hai confermato; i popup automatici continuano a comparire solo per aggiornamenti maggiori e minori. Apri la finestra in qualsiasi momento con /qt notes.

### Titoli di completamento delle missioni

- Quando una missione lascia il tuo registro prima che QuestTogether abbia un titolo utilizzabile, gli annunci di completamento ora provano a usare la ricerca dei titoli missione disponibile del gioco prima di ripiegare su un ID missione. Un titolo recuperato viene preservato indipendentemente dall'ordine degli eventi di consegna e rimozione.
- Gli annunci usano comunque il testo del mittente quando il tuo client non riesce a risolvere un titolo locale. Se nessuno dei due client ha un nome disponibile, l'ID missione resta l'alternativa. Il recupero migliorato lato mittente si applica quando il mittente si aggiorna.

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

## 5.15.0

Chiedi di unirti a un gruppo per missioni direttamente dal menu giocatore di QuestTogether.

### Unisciti a un gruppo per missioni

- I giocatori QT già in gruppo ora mostrano Richiedi di unirti invece di Invita quando sono disponibili informazioni recenti sul gruppo. Entrambi i giocatori devono avere questo aggiornamento; chi fa la richiesta deve essere da solo.
- Il destinatario può inviare un normale invito di WoW o rifiutare. Deve avere il permesso di invitare e spazio in un gruppo normale. Dovrai comunque accettare il normale invito per unirti.

### Inviti automatici opzionali

- Due nuove opzioni approvano automaticamente le richieste dagli amici del personaggio, oppure da altri giocatori mentre sei In cerca di compagni per le missioni. Entrambe iniziano disattivate e compaiono nella richiesta e nelle impostazioni Varie. Gli amici dell'account Battle.net non sono inclusi.
- Le richieste scadono e rispettano ignore, cambi di gruppo e restrizioni di gioco. QT non abbandona mai il tuo gruppo attuale né accetta inviti per te.

## 5.14.1

Gli annunci di gruppo ora mostrano il nome QuestTogether completo.

### Chat di gruppo

- Il prefisso degli annunci nella chat di gruppo è stato esteso da [QT] a [QuestTogether], così gli altri giocatori possono trovare più facilmente l'addon.

## 5.14.0

QuestTogether ora parla cinque lingue in più e ti aiuta a tenere informati i membri del gruppo senza QT.

### Gioca nella tua lingua

- L'interfaccia è ora disponibile in tedesco, francese, spagnolo, portoghese brasiliano e russo. QuestTogether segue la lingua del gioco, con l'inglese come ripiego.
- Impostazioni, menu, tooltip, confronti delle missioni e note di aggiornamento sono tradotti. I nomi delle missioni e il testo dei progressi ricevuti da altri giocatori restano nella loro lingua originale.
- Trova gli annunci di rilascio tradotti nei cinque canali changelog specifici per lingua sul nostro Discord.

### Tieni informato tutto il tuo gruppo

- Una nuova opzione Dove annunciare invia gli annunci evento abilitati alla chat di gruppo quando qualcuno nel tuo gruppo non è stato riconosciuto come utente QT. Inizia abilitata e può essere disattivata nelle impostazioni.
- Funziona anche nei gruppi di istanza abbinati. Il gioco in solitaria e le incursioni sono esclusi, e gli annunci degli altri giocatori non vengono mai inoltrati.

## 5.13.1

Questo aggiornamento di manutenzione migliora il ripristino degli indicatori delle missioni, rimuove fumetti e loghi giocatore obsoleti e mantiene coerenti le impostazioni e la finestra di debug.

### Indicatori missione e giocatori

- Le icone delle missioni e le tinte della salute si ripristinano correttamente dopo la chiusura delle visualizzazioni limitate. Le scansioni missioni ritardate mantengono il loro tempo di assestamento, e i dati tooltip temporaneamente mancanti conservano il loro limite di tentativi.
- I fumetti degli annunci vengono ripuliti quando la barra di un giocatore scompare o viene riutilizzata durante il combattimento. I riquadri protetti o vietati attendono una pulizia sicura.
- Le posizioni sulla mappa e la presenza dei giocatori si ripristinano dopo aver disattivato QuestTogether, cambiato zona e riattivato l'addon. I giocatori andati via non riottengono più un logo QT da ritiri tardivi della posizione o dello stato di partner.

### Correzioni a impostazioni e finestre

- La casella In cerca di compagni per le missioni resta sincronizzata quando lo stato cambia tramite comandi, menu o impostazioni del profilo.
- La finestra di debug conclude in sicurezza i gesti di trascinamento e ridimensionamento interrotti quando le restrizioni vengono rimosse, anche dopo essere stata nascosta.

### Miglioramenti dell'affidabilità

- Test rafforzati rilevano l'accesso a riquadri vietati anche quando un errore viene intercettato internamente.
- I controlli di rilascio ora rifiutano la pubblicazione finché restano modifiche dell'implementazione non registrate, aiutando a garantire che le correzioni arrivino davvero al download.

## 5.13.0

Trova a colpo d'occhio compagni per le missioni con punti sulla mappa e loghi giocatore evidenziati, impostazioni posizione più semplici e promemoria quando un altro giocatore ha una versione stabile di QuestTogether più recente.

### Trova compagni per le missioni

- I giocatori in cerca di compagni per le missioni hanno un leggero bagliore dorato attorno ai punti sulla mappa e sulla minimappa colorati in base alla classe.
- Il loro logo QuestTogether sulla barra del nome ottiene un leggero bagliore dorato. Le evidenziazioni scompaiono quando lo stato viene disattivato o scade.
- Le impostazioni Posizioni dei giocatori includono Mostra solo giocatori in cerca di compagni per le missioni. Inizia disattivata e filtra entrambe le mappe quando abilitata.
- La finestra Novità in gioco mostra fianco a fianco loghi e punti sulla mappa normali e luminosi. Il bagliore dorato significa in cerca di compagni per le missioni.

### Impostazioni posizione più semplici

- Condividi la mia posizione e Mostra altri giocatori si applicano ciascuna sia alla mappa del mondo sia alla minimappa.
- Entrambe le opzioni iniziano abilitate per i nuovi profili. Le disattivazioni esistenti della condivisione posizione vengono mantenute durante l'aggiornamento.

### Promemoria nuova versione

- QuestTogether nota quando un altro giocatore segnala una versione stabile più recente dell'addon e stampa un promemoria di aggiornamento nella finestra chat di QuestTogether scelta.
- Il promemoria viene salvato tra i personaggi e compare una volta a ogni ricaricamento finché non installi la versione rilevata o una più recente. Le versioni alpha e beta non attivano promemoria.
- Gli annunci di versione sono piccoli e poco frequenti. QuestTogether riconosce anche le informazioni di versione nelle risposte ping esistenti.

## 5.12.0

Trova persone con cui fare missioni usando il nuovo stato In cerca di compagni per le missioni. Questo aggiornamento migliora anche la visibilità dei tooltip della minimappa e separa il comportamento della Modalità Guerra e del reame di Retail da Forever.

### In cerca di compagni per le missioni

- Fai sapere agli altri utenti QuestTogether che vuoi compagnia. Il tuo stato compare nel menu del tuo giocatore e nei tooltip dei punti sulla mappa; non abilita la condivisione della posizione né invia inviti.
- Attiva o disattiva lo stato dal menu della minimappa, da Impostazioni > Varie o con /qt lfg. Usa /qt lfg on, off o status per impostarlo o controllarlo. Inizia disattivato e viene salvato per profilo.
- Lo stato di partner scade quando gli aggiornamenti si interrompono. I giocatori ignorati sono esclusi, e disattivare QuestTogether mette in pausa il tuo annuncio.

### Retail e Forever

- Forever non mostra più la Modalità Guerra nei tooltip dei punti giocatore, nei dettagli della posizione delle missioni o nell'output del ping. I ping di Forever omettono anche le etichette del reame pur conservando i nomi completi dei giocatori.
- Gli aggiornamenti delle missioni vicine su Forever non richiedono più informazioni della Modalità Guerra di Retail. I punti sulla mappa restano visibili attraverso le fasi, così puoi trovare persone con cui formare un gruppo.
- Retail usa lo stato attivo della Modalità Guerra quando disponibile. Una Modalità Guerra sconosciuta o non supportata non viene più segnalata come Disattivata.

### Punti giocatore più stabili

- Coordinate mancanti per poco tempo non rimuovono più subito il tuo punto. Le ultime posizioni segnalate restano fino a due minuti, e i report più vecchi mostrano la loro età nel tooltip. Le rinunce alla condivisione si ritirano comunque subito quando la comunicazione è disponibile.
- Le trasmissioni di movimento sono limitate a una volta ogni dieci secondi, riducendo il traffico delle posizioni. I segnali di presenza da fermi restano ogni venti secondi, così i client più vecchi restano compatibili.
- La cache delle posizioni ora conserva fino a 512 giocatori. Ogni mappa disegna comunque al massimo 128 punti visibili, e i giocatori fuori dalla mappa visualizzata non consumano più quel limite di disegno.

### Loghi giocatore affidabili

- Corregge i loghi mancanti sulle barre dei nomi dei giocatori amichevoli nei client Forever e Retail attuali leggendo l'impostazione corrente di visibilità dei giocatori amichevoli.
- I loghi posizionati a sinistra si spostano verso l'esterno per fare spazio ai benefici visibili, poi tornano alla posizione abituale quando i benefici scompaiono.
- Tutti i messaggi QuestTogether supportati ora identificano il mittente. Una cache limitata ricorda i giocatori per la sessione UI corrente, così i segnali di presenza mancati non rimuovono più i loro loghi. Le uscite esplicite e i giocatori ignorati vengono comunque eliminati; non vengono inviati messaggi extra.

### Rifiniture della minimappa

- Il tooltip della minimappa di QuestTogether ora usa un livello tooltip indipendente, così può apparire sopra l'UI della barra delle azioni. Si nasconde quando il pulsante diventa non disponibile o iniziano le restrizioni.

## 5.11.0

QuestTogether ora aggiunge posizioni dei giocatori, loghi sulle barre dei giocatori, confronti mirati delle missioni e feedback e supporto Discord più semplici. Le impostazioni ti permettono di scegliere cosa condividere e cosa vedere mentre i progressi delle missioni restano coordinati con altri utenti QuestTogether.

### Trova giocatori QuestTogether nelle vicinanze

- Mostra il logo della pergamena accanto ai giocatori amichevoli di QuestTogether quando le barre dei nomi amichevoli di WoW sono attive. Le Targhette giocatore sono abilitate per impostazione predefinita, con una posizione a Sinistra distanziata; scegli Sinistra, Destra, Alto o Prefisso senza cambiare i colori della barra della salute.
- I punti giocatore colorati in base alla classe possono comparire sulla mappa del mondo e sulla minimappa per i giocatori che condividono la loro posizione. Passa il mouse su un punto per nome, fazione, razza, classe e livello; cliccalo per il menu giocatore di QuestTogether.
- Posizioni dei giocatori ha interruttori separati per condividere e visualizzare sulla mappa del mondo e sulla minimappa, e tutti e quattro iniziano abilitati. La presenza per i loghi sulle barre dei giocatori può continuare anche quando entrambi gli interruttori di condivisione posizione sono disattivati.
- Le posizioni si aggiornano periodicamente e scompaiono quando scadono. Entrambi i giocatori devono avere l'addon aggiornato; un punto non garantisce che condividiate la stessa fase o layer.

### Confronta un giocatore o tutto il gruppo

- L'azione Confronta missioni del menu giocatore ora confronta solo te e il giocatore selezionato, inclusi i pari QuestTogether raggiungibili fuori dal gruppo. Il confronto dell'intero gruppo resta disponibile dal menu della minimappa, dai menu dei nomi missione e da /qt compare.
- La condivisione delle missioni e le richieste di condivisione restano solo per il gruppo. I confronti mirati spiegano quando serve un gruppo per condividere e quando il giocatore selezionato ha bisogno di QuestTogether per rispondere.
- Se una richiesta di condivisione è già in attesa su un altro giocatore, il confronto ora mostra chi sta aspettando dopo che cambi bersaglio.

### Feedback e supporto

- La finestra di benvenuto e la pagina principale delle impostazioni ora includono Discord — Feedback e supporto. Apre un invito copiabile quando disponibile, oppure stampa l'invito in chat se la finestra del link non può aprirsi.

### Correzioni e rifiniture

- I giocatori ignorati ora vengono filtrati in modo più completo. Nuovi registri, fumetti, punti, confronti e lavori di condivisione vengono soppressi, mentre fumetti e posizioni esistenti vengono eliminati quando cambia la lista ignore.
- Corrette false targhette missione causate da limiti tooltip non disponibili che corrispondevano al testo obiettivo di un'altra missione.
- Disattivare la condivisione della mappa o della minimappa ora ritenta l'aggiornamento dopo errori temporanei di comunicazione. Disattivare entrambe le opzioni di condivisione rimuove anche i dettagli della posizione dagli altri aggiornamenti dell'addon.
- I loghi giocatore si eliminano correttamente quando la presenza di un giocatore scade appena prima che se ne vada. Sussurra dai punti sulla mappa apre la finestra chat, e cambiare la destinazione del registro dalle Impostazioni non è disponibile durante le restrizioni.

## 5.10.0

QuestTogether condivide i progressi delle missioni con il tuo gruppo e i giocatori vicini. Usa il pulsante sulla minimappa per le impostazioni, i confronti delle missioni del gruppo, il tuo registro missioni e queste ultime note.

### Confronta e condividi le missioni del gruppo

- Apri Confronta missioni del gruppo dalla minimappa o dai menu delle missioni e dei giocatori, oppure digita /qt compare. Scopri chi ha ogni missione e quanto è progredito ciascuno.
- Tutte le missioni del gruppo compaiono per impostazione predefinita. Seleziona Nascondi missioni che non ho per concentrarti sulle missioni nel tuo registro.
- Richiedi le missioni condivisibili ai membri del gruppo che usano l'addon aggiornato. Le richieste chiedono il permesso per impostazione predefinita; la condivisione automatica è un'impostazione opzionale.
- I confronti vengono recuperati dopo restrizioni di mappa o combattimento. Gli aggiornamenti sostituiscono le risposte precedenti, e i tempi di recupero e gli errori delle richieste spiegano quando puoi riprovare.

### Scorciatoie e menu delle missioni

- Trascina il pulsante a forma di pergamena sulla minimappa per riposizionarlo. Il suo menu apre impostazioni, confronti, il registro missioni, note della patch e il controllo di destinazione della finestra del registro. Nascondilo dal menu e ripristinalo nelle impostazioni Varie.
- I menu dei nomi delle missioni offrono Stato, Condividi, Apri nel registro missioni e Confronta missioni del gruppo. Le azioni di condivisione e registro ricontrollano la missione attuale e le restrizioni quando vengono cliccate.
- I link allo stato delle missioni mantengono intatti i titoli dopo che una missione lascia il tuo registro. La casella della condivisione automatica ora segue le impostazioni salvate e le modifiche del profilo.

### Aiuto e ultime note

- Leggi il messaggio di benvenuto e le ultime note della patch nella loro finestra invece che in messaggi di chat ripetuti. Scegli Note della patch dal menu della minimappa o dalla pagina principale delle Impostazioni, oppure usa /qt notes, /qt changelog o /qt patchnotes.
- La finestra delle note si apre automaticamente per gli aggiornamenti principali e secondari. Gli aggiornamenti delle patch includono comunque note nuove senza aprire automaticamente la finestra.
- Usa /qt help per i comandi normali e /qt help debug per anteprime, diagnostica e comandi per sviluppatori.

## 5.9.2

Fai clic sinistro o destro sul nome di una missione nel registro di QuestTogether per aprirne il menu, con Stato per primo e Condividi per secondo. Condividi usa la voce corrente del registro missioni senza cambiare la missione selezionata da Blizzard, e non è disponibile quando sei da solo, ci sono restrizioni o la missione non può essere condivisa. Dopo un separatore, l'opzione finale sposta i registri di QuestTogether tra la finestra principale e quella separata, in accordo con il menu dei nomi dei giocatori di QT.

### Modifiche in questa versione

- Rendi cliccabili i nomi delle missioni nei messaggi di stato, inclusi i titoli di riserva dai registri di altri giocatori. Mantieni i link delle missioni esistenti durante la formattazione dei confronti delle missioni completate, così i dettagli di stato non diventano parte di un secondo link non funzionante.
- Validazione: 521 test superati in ordine normale e inverso su Lua 5.1 e 5.2. Tutti e sei i profili API del client, i controlli di sintassi Lua e shell, la verifica esatta di libchev e i controlli diff sono superati. Il comportamento dei menu del client live, la consegna delle condivisioni di missione e la validazione del taint a livello di motore restano separati.

## 5.9.1

Corregge il tracciamento delle missioni, la visibilità delle barre del nome delle missioni, gli annunci delle aree obiettivo, l'affidabilità della comunicazione e le azioni utente identificate nell'audit completo.

### Modifiche in questa versione

- Impedisci a blocchi di missione non correlati nei tooltip di prendere in prestito il testo degli obiettivi condivisi. Mantieni i progressi validi del gruppo e recupera le barre del nome dopo cambi di mappa, istanza, elenco del gruppo e missione.
- Mantieni in sospeso le missioni appena accettate e le scansioni iniziali finché non arrivano dati leggibili. Conserva le tappe degli obiettivi, la classificazione degli incarichi e lo stato di posizione sconosciuta senza uscite false o voci duplicate.
- Migliora annunci localizzati e confronti delle missioni, inclusi limiti del payload, ritmo, tentativi, annullamento e segnalazione della condivisibilità.
- Rispetta gli errori nativi dei waypoint senza tracciare un vecchio segnaposto. Rifiuta i clic soggetti a restrizioni mentre è disabilitato invece di perdere il lavoro in coda.
- Rendi i test delle bolle anteprime locali e accetta nomi Forever completi o nomi tra virgolette, preservando l'identità esatta del giocatore.
- Correggi gestione di abilitazione/disabilitazione e profili, apertura della Modalità modifica dell'HUD, emote di celebrazione approvate e diagnostica.
- Rafforza l'isolamento dei test sicuro per il client live e la copertura delle regressioni, correggi presupposti errati dei test e fai propagare a CI gli errori di sintassi Lua.
- Validazione: 516 test superati in ordine normale e inverso su Lua 5.1 e 5.2. Tutti e sei i profili API del client, i controlli di sintassi, la verifica esatta di libchev e i controlli diff sono superati. Rendering del client live, consegna tra due client e validazione del taint a livello di motore restano separati.

## 5.9.0

Festeggia gli aumenti di livello tuoi e dei giocatori QuestTogether vicini con emote sincronizzate. Aggiungi interruttori separati per le emote di aumento di livello, abilitati per impostazione predefinita, accanto alle impostazioni delle emote di completamento missione in Varie. Le reazioni vicine rispettano l'ambito giocatori e le regole di prossimità esistenti.

### Modifiche in questa versione

- Ricorda il completamento confermato degli obiettivi missione per tipo di creatura oltre che per singolo spawn. I mob che compaiono durante il combattimento restano non contrassegnati quando i dati del tooltip non sono disponibili, anche se uno spawn precedente era stato memorizzato come necessario. Obiettivi recenti non completati possono ripristinare l'evidenziazione; i cambi di stato della missione azzerano la memoria di completamento. Dati del tooltip parziali o inaccessibili non vengono mai trattati come prova che tutti abbiano finito.
- Rimuovi immediatamente le icone delle missioni sulle barre del nome e la tinta della salute quando il tag di un mob viene negato, anche durante il combattimento. Ascolta i cambi di proprietà e ricontrolla i tag sugli aggiornamenti di salute e minaccia.
- Rileva i nuovi mob di missione incontrati durante il normale combattimento nel mondo aperto usando dati leggibili del tooltip dell'unità. Aggiorna le barre del nome quando tornano da dietro la telecamera, diventano il tuo bersaglio o vengono sorvolate col mouse. Riprova frame ritardati, GUID e righe di missione del tooltip con un budget limitato per unità, annulla il lavoro obsoleto quando le unità vengono rimosse e ripristina insieme tinta e icona. Mantieni le protezioni per mappa, istanza, dati inaccessibili e frame protetti; la scoperta in combattimento non invoca Questie né UI dei tooltip nascoste.
- Validazione: 374 test offline superati in ordine normale e inverso su Lua 5.1 e 5.2. Sei profili API del client, controlli di sintassi Lua, verifica esatta delle librerie e controlli diff sono superati. Le regressioni della cache di completamento hanno riprodotto il bug prima della correzione. Gameplay live e validazione del taint a livello di motore restano separati.

## 5.8.6

Rendi più robusti nomi dei personaggi, nomi delle classi, titoli delle missioni e colori personalizzati delle classi contro valori API inaccessibili o malformati. Valida i dati di integrazione opzionale di TomTom e Questie prima di usarli, e smetti di leggere le righe del tooltip di Questie quando i dati sono inaccessibili. Normalizza visibilità delle bolle e stato della modalità modifica in booleani prima di passarli ai controlli UI.

### Modifiche in questa versione

- Consolida il gestore degli eventi della schermata di caricamento, rimuovi argomenti privati inutilizzati e un ramo inutilizzato dell'enum delle restrizioni, e chiarisci la gestione di callback e valori di ritorno. Mantieni intatti i fallback dei client moderni/legacy e la revisione esatta della libreria privata.
- Validazione: 336 test superati in ordine normale e inverso su Lua 5.1 e 5.2, con controlli dell'adapter ampliati su sei profili client. Le nuove regressioni falliscono contro l'implementazione precedente. Parsing Lua, verifica esatta delle librerie e controlli diff sono superati. Rivisti i restanti diagnostici Ketho WoW API/LuaLS, incluso un passaggio separato senza mock offline del client; i risultati mantenuti hanno motivi specifici di compatibilità, protezione, callback, libreria o fixture. La validazione del gameplay live Retail e Forever resta separata.

## 5.8.5

Correggi la scoperta di incarichi/missioni mondiali sulla mappa nei client moderni leggendo questID da C_TaskQuest.GetQuestsOnMap, mantenendo al tempo stesso l'API legacy e il campo questId per i client più vecchi. Preferisci C_ChatInfo.PerformEmote così le emote di completamento funzionano quando le globali deprecate sono disabilitate; gestisci in sicurezza API delle emote mancanti o non funzionanti.

### Modifiche in questa versione

- Rimuovi un calcolo inutilizzato dell'impronta dell'elenco del gruppo e variabili locali inutilizzate. Estendi i controlli offline del client per coprire API moderne e legacy di incarichi/emote, precedenza API, dati missione inaccessibili e API mancanti/non funzionanti. Validazione: 334 test superati in ordine normale e inverso su Lua 5.1 e 5.2, più i controlli API ampliati su sei profili client, parsing Lua e verifica esatta delle librerie. La validazione del gameplay in Retail e Forever resta separata dai controlli offline.

## 5.8.4

Manutenzione del repository: tieni le note di sviluppo locali fuori dal sorgente tracciato e dai pacchetti di rilascio. Il comportamento di gioco è invariato.

### Modifiche in questa versione

- Manutenzione del repository: tieni le note di sviluppo locali fuori dal sorgente tracciato e dai pacchetti di rilascio. Il comportamento di gioco è invariato.

## 5.8.3

Annuncia la versione installata, i client supportati e il comando delle impostazioni una volta per accesso o ricaricamento dell'UI. Includi link di feedback specifici dell'addon per CurseForge e GitHub; cliccando un link si apre una finestra di copia in stile nativo. Condividi il comportamento dei messaggi e l'UI di copia sicura tramite libchev 1.2.0 privata. Se la registrazione del link o la finestra di copia non è disponibile, mostra l'URL completo in chat. Un helper di benvenuto non disponibile non può interrompere il normale avvio dell'addon.

### Modifiche in questa versione

- Validazione: 334 test superati in entrambi gli ordini su Lua 5.1 e 5.2, con controlli API del client, parsing Lua e verifica esatta del vendor della libreria. Le simulazioni smoke NoPoizen esercitano entrambi i link di feedback su tutti e sette i profili client/ruleset. Il rendering live resta un controllo separato.

## 5.8.2

Isola le ricerche GUID delle fixture di test dai giocatori vicini. Correggi due falsi errori in /qt test quando una vera unità occupa il token della barra del nome usato dai controlli del tooltip e dell'icona in cache. Il comportamento delle barre del nome in gioco è invariato.

### Modifiche in questa versione

- L'ambiente offline ora include quella collisione di token e riproduce entrambi gli errori senza la correzione della fixture. Tutti i 333 test passano in entrambi gli ordini su Lua 5.1 e 5.2 dopo la correzione; anche sei profili API del client passano. La conferma in gioco resta separata.

## 5.8.1

Mostra l'indicatore di missione di Blizzard accanto a QuestTogether nell'elenco AddOns invece del punto interrogativo predefinito.

### Modifiche in questa versione

- Mostra l'indicatore di missione di Blizzard accanto a QuestTogether nell'elenco AddOns invece del punto interrogativo predefinito.

## 5.8.0

Supporta gli attuali client Classic con payload corretti per l'accettazione delle missioni, fallback protetti per l'API degli obiettivi, condivisibilità sconosciuta dichiarata onestamente, metadati di flavor e controlli di regressione API su sei client. Mantiene il comportamento Retail/Forever e le utilità di debug condivise.

### Modifiche in questa versione

- Validazione: 333 test superati in entrambi gli ordini su Lua 5.1 e 5.2, con sei profili client, parsing Lua e controlli esatti del vendor della libreria privata. Superati anche gli smoke check del client NoPoizen e la verifica del pacchetto. La validazione live dei nuovi adattatori resta in sospeso.
- Consulta CLIENT_COMPATIBILITY.md per le prove delle fonti, l'ambito e i limiti di validazione.

## 5.7.7

Mantiene le console di debug sovrapposte e i relativi controlli in un unico gruppo di impilamento nativo tramite libchev privata 1.1.3. I menu categoria restano con la console a cui appartengono.

### Modifiche in questa versione

- Imposta per impostazione predefinita le icone degli obiettivi missione a sinistra della targhetta del nome. Le posizioni delle icone salvate esistenti restano invariate.
- Rispetta l'impostazione “My Last Name” di Forever quando mostra il nome del tuo personaggio. Mantiene visibili i cognomi degli altri giocatori, in linea con l'ambito dell'impostazione nativa. Usa coerentemente i nomi completi per comunicazioni, appartenenza al gruppo, corrispondenza delle targhette dei nomi e azioni social, preservando le chiavi esistenti di profilo e posizione della bolla personale.
- Corregge gli annunci locali duplicati delle missioni causati dalla ricezione del proprio messaggio di canale con un formato diverso del nome completo. La copertura di regressione verifica l'annuncio locale seguito dai suoi echi di canale e gruppo, incluso un altro personaggio con lo stesso nome.
- Validazione: 331 test superati in entrambi gli ordini con Lua 5.1/5.2. La conferma live della nuova impostazione predefinita delle icone e dell'interazione a più finestre resta separata.

## 5.7.6

Usa la stessa console di debug privata libchev 1.1.2 in tutti e tre gli addon, inclusi filtri categoria/ricerca, controlli di copia, risultati dei test, rapporti diagnostici, timestamp quando disponibili e un unico riepilogo finale dei test. Corregge gli elementi grafici nativi del riquadro stirati con limiti espliciti delle texture.

### Modifiche in questa versione

- QuestTogether fornisce la propria diagnostica delle missioni e test isolati, mentre la libreria condivisa gestisce la console e il comportamento di debug generico. Esegui /qt test, /qt debug, o /qt diagnostics.
- Validazione: 324 test superati in entrambi gli ordini su Lua 5.1/5.2. L'utente ha confermato in gioco l'aspetto corretto del riquadro. Altre validazioni live di restrizioni e gameplay restano separate.

## 5.7.6-beta.3

QuestTogether 5.7.6-beta.3 aggiorna la console di debug condivisa incorporata a libchev 1.1.1.

### Modifiche in questa versione

- Ripristina l'aspetto nativo delle finestre in stile WoW nella console condivisa degli addon.
- Rimuove la riga duplicata del riepilogo dei test mantenendo il riepilogo finale nella cronologia limitata.
- Mantiene il comportamento comune di ricerca, categoria, copia, scorrimento, test e diagnostica e le protezioni esistenti contro le restrizioni.
- L'utente ha segnalato che tutti i 324 test QT sono stati superati in Forever 1.60.1 build 70009 su beta.2. I sette file di test caricati live di QT sono stati anche verificati per aritmetica non valida; non sono stati trovati casi di test con generazione di NaN o divisione per zero. Quel precedente risultato di test live non valida questa nuova modifica dell'aspetto.
- Dopo /reload, apri /qtd, esegui /qt test, e controlla l'aspetto della finestra e il riepilogo singolo. Il rendering live e il comportamento di restrizioni/taint per questa revisione necessitano ancora di verifica sul client.
- Validazione: tutti i 324 casi superati in ordine normale/inverso su Lua 5.1.5 e 5.2.4 reali, ogni esecuzione CLI emette un solo riepilogo e lo ZIP installabile estratto con 26 file passa su entrambe le versioni. Tutti i 23 file Lua vengono analizzati correttamente; tutte le 22 voci TOC e il manifest del vendor sono verificati. I controlli di formattazione e diff sono superati. Pin libreria: 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. Non è configurata alcuna CI GitHub per QT; la CI della libreria upstream è passata.

## 5.7.6-beta.2

QuestTogether 5.7.6-beta.2 sostituisce la sua finestra di debug separata con la console condivisa libchev v1.1 usata in tutti gli addon. La libreria incorporata è inclusa; non è richiesta alcuna installazione separata.

### Modifiche in questa versione

- Filtri categoria condivisi, ricerca approssimata/con virgolette, copia/selezione, cancellazione, ricarica, test, diagnostica e comportamento di seguito dello scorrimento.
- /qt test apre i risultati correnti; le esecuzioni ripetute sostituiscono la vecchia cronologia TEST e cancellano i filtri di ricerca obsoleti.
- /qt diagnostics [questID] e /qt diag [questID] ricostruiscono il report nella cache corrente nella stessa console, mantenendo gli eventi recenti entro il budget di esportazione condiviso.
- Le protezioni condivise per restrizioni e frame posseduti sostituiscono i vecchi callback della console e l'implementazione del menu a discesa di QT.
- Stato delle missioni, annunci, targhette dei nomi, comunicazioni e isolamento dei test specifici di QT restano gestiti da QuestTogether.
- Questa è una versione beta. Il rendering live Retail/Forever e il comportamento del taint richiedono ancora verifica. Dopo /reload, esegui /qt test e /qt diagnostics, poi prova categoria/ricerca, copia, cancellazione, ridimensionamento, scorrimento, esecuzioni ripetute dei test e passaggio tra report e registri. Includi transizioni di combattimento/restrizione e il tuo set abituale di addon.
- Validazione: 324/324 test superati in entrambi gli ordini con Lua 5.1.5 e 5.2.4. Tutti i 23 file Lua vengono analizzati correttamente, tutte le 22 voci TOC sono valide e il manifest della libreria fissata è verificato. Lo ZIP installabile è stato estratto e ha superato tutti i 324 casi usando l'harness offline separato. Pin libreria: 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

QuestTogether 5.7.6-beta.1 incorpora libchev v1.0.0 per condividere registrazione, diagnostica, protezioni dei callback, meccaniche di lavoro differito ed esecuzione dei test con gli altri addon Together. La libreria è inclusa; non è necessaria alcuna installazione separata di addon.

### Modifiche in questa versione

- I rapporti diagnostici includono informazioni comuni su client/addon/libreria e mantengono gli eventi più recenti quando la finestra di copia si riempie.
- Il comportamento di missioni, gruppo, targhette dei nomi e restrizioni resta gestito da QuestTogether, con archivi di runtime isolati per ogni addon.
- I link alle coordinate restano utilizzabili mentre QT è disabilitato quando le restrizioni lo consentono; il lavoro in background in coda resta in pausa e i timer obsoleti vengono scartati.
- /qt test ora include 315 casi: i 300 esistenti, dieci controlli della libreria condivisa e cinque regressioni di integrazione.
- Validazione: tutti i 315 test superati in entrambi gli ordini con Lua 5.1.5 e 5.2.4; sintassi Lua, ordine di caricamento TOC e manifest di revisione/hash incorporato superati. Sorgente libchev incorporata: 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- Questa è una versione beta. Il rendering UI live Retail/Forever e il comportamento del taint dopo questa estrazione richiedono ancora verifica. Dopo il ricaricamento, esegui /qt test e /qt diagnostics, poi prova missioni, bolle di progresso, targhette dei nomi e link alle coordinate durante combattimento, cambio di zona, disattivazione/riattivazione e ricaricamento con i tuoi addon abituali. La precedente conferma dei 300 test Retail si applicava a v5.7.5.
