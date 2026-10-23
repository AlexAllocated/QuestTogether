# QuestTogether — Registro delle modifiche

<!-- Generated from canonical release notes; do not edit by hand. -->

## 8.0.4

Gli indicatori seguono più fluidamente i movimenti della mappa del mondo.

### Indicatori sulla mappa del mondo

- I punti dei giocatori e i punti di passaggio condivisi del gruppo seguono la mappa con fluidità quando la trascini o usi la rotellina del mouse per cambiare lo zoom.
- Gli indicatori si aggiornano subito quando cambi livello della mappa, anche tornando indietro con il clic destro. I punti della zona precedente non restano più visibili.

## 8.0.3

Le note di aggiornamento sono più chiare e scorrevoli, e la cronologia delle versioni torna a includere una voce mancante.

### Note di aggiornamento e cronologia

- Abbiamo rivisto le note di aggiornamento attuali e passate in tutte le dieci lingue supportate oltre all'inglese, per renderle più naturali e facili da leggere.
- La voce mancante della versione 7.4.4 è di nuovo consultabile nella cronologia delle versioni e nei registri delle modifiche.

## 8.0.2

Indicatori sulla mappa e riconoscimento VIP più affidabili.

### Correzioni di affidabilità

- Le stelle VIP restano visibili anche dopo le schermate di caricamento. Gli aggiornamenti VIP simultanei non si bloccano più a vicenda.
- Risolto un caso in cui gli indicatori potevano sparire dalla mappa se un aggiornamento di posizione era temporaneamente privo di coordinate.
- La condivisione degli aggiornamenti è più affidabile quando il canale limita la velocità di invio.

## 8.0.1

Navigazione da tastiera senza un pulsante in più.

### Registro delle missioni del gruppo

- Aprendo il registro delle missioni del gruppo o facendo clic su una missione, puoi subito usare la tastiera nella lista. Il pulsante Tastiera è stato rimosso. Usa le frecce per spostarti e Invio per espandere o richiudere gli obiettivi.
- Tab alterna tra la lista e il campo di ricerca. Dalla lista, Esc chiude la finestra; un clic all’esterno libera la tastiera. Gli aggiornamenti delle missioni non spostano nuovamente il focus sulla lista.

## 8.0.0

Arriva QuestTogether VIP.

### Aspetto VIP

- I giocatori VIP hanno una stella sulla mappa del colore della propria classe, una stella dorata nel prefisso QT della chat e sul pulsante della minimappa, e la dicitura QuestTogether VIP nel tooltip individuale. Sono ricompense esclusivamente estetiche: non consentono di accedere alle funzioni dello sviluppatore.

**Forever**

![Aspetto VIP — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v8.0.0/Media/ReleaseNotes/VIPCosmetics.png)

### Come diventare VIP

- Condividi il link per scaricare QuestTogether con amici, gilda, un server Discord pertinente o sui social. Fai uno screenshot del messaggio inviato o del post pubblicato, in cui siano visibili il link di QT e il luogo in cui l’hai condiviso. Invia lo screenshot in un messaggio privato su Discord a @chevcast per la verifica. Prima entra nel server Discord di QT oppure manda una richiesta di amicizia a @chevcast, così potrai scrivergli in privato. Nella finestra VIP trovi il link da copiare e le istruzioni per l’attivazione dopo l’approvazione.

### Attiva la ricompensa

- Apri la finestra VIP dal menu della minimappa, dalle impostazioni o con /qt vip. Aspetta che @chevcast confermi l’assegnazione di VIP al tuo account Discord: il comando /qt claim su Discord funziona solo dopo questa conferma.

A quel punto copia il codice di richiesta con Ctrl+C e invialo a @chevcast, oppure usa /qt claim nel server Discord di QT. Incolla il codice di attivazione privato che ricevi nella finestra VIP e scegli Attiva VIP. Ripeti la procedura su Retail o Forever per usare la stessa ricompensa anche lì.

### Permanente, ma facoltativa da mostrare

- La ricompensa è legata al tuo account Discord e vale per tutti i personaggi di ciascuna installazione. Va riscattata separatamente su Retail e Forever. Disattiva Mostra il mio aspetto VIP per conservare la ricompensa senza esibirla. I pulsanti della minimappa normale, VIP e sviluppatore ora hanno bordi dorati che seguono la sagoma dell’icona. L’aspetto sviluppatore ha la precedenza su quello VIP.

## 7.4.4

Ogni aggiornamento e le sue patch si leggono insieme.

### Cronologia raggruppata

- La finestra delle note riunisce ogni versione minore e le sue patch in un’unica pagina. Si parte dalla versione minore, seguita dalle patch in ordine, ciascuna con versione e data nel titolo. I comandi della cronologia passano da una pagina raggruppata all’altra.
- Le vecchie note delle patch descrivono ora solo le proprie modifiche, senza ripetere guide, suggerimenti o immagini dell’aggiornamento precedente. Installare soltanto una patch continua a non aprire automaticamente la finestra; puoi consultarla quando vuoi con /qt notes.

## 7.4.3

Nomi e comandi più chiari per le missioni in gruppo.

### Missioni in gruppo

- Tracciamento missioni si chiama ora Tracciamento obiettivi del gruppo (Party Objective Tracker, POT). Le impostazioni di visualizzazione e la posizione della finestra restano invariate.
- Usa /qt pql per aprire il registro delle missioni del gruppo. /qt compare continua a funzionare come alias, mentre guida e suggerimenti indicano ora /qt pql.
- Nascondi quando non sei in gruppo è disponibile sia nella modalità Modifica HUD sia in Impostazioni > Gruppi e condivisione > Tracciamento obiettivi del gruppo. Le due caselle modificano la stessa preferenza. L’opzione è attiva nei nuovi profili e dopo un ripristino dei valori predefiniti; le scelte già salvate vengono mantenute.

## 7.4.2

Corretto il testo delle note di aggiornamento.

### Testo delle note di aggiornamento

- I caratteri separatori non supportati sono stati sostituiti con testo semplice, così nelle note non compaiono più quadratini vuoti.

## 7.4.1

Correzioni e nuove opzioni di disposizione per il tracciamento obiettivi del gruppo.

### Tracciamento obiettivi del gruppo

- Su Forever, alcuni obiettivi a passaggio singolo, tra cui Use Walk on Air, mostravano erroneamente 1/1 prima del completamento. La correzione riguarda sia il tracciamento obiettivi del gruppo sia il registro delle missioni del gruppo.

### Scegli quando mostrarlo

- Nella modalità Modifica HUD puoi attivare Nascondi quando non sei in gruppo per non vedere il tracciamento mentre giochi da solo. L’opzione è disattivata per impostazione predefinita; l’anteprima per il posizionamento resta comunque disponibile nella modalità Modifica HUD.

### Adatta la finestra alla tua interfaccia

- L’opzione Aggancia al tracciatore obiettivi di Blizzard è attiva per impostazione predefinita e colloca QT a filo del bordo esterno. Trascinando la finestra altrove, l’aggancio si disattiva e puoi ridimensionarla dagli angoli. Riattivarlo reimposta la posizione. I cursori di larghezza e altezza massima funzionano in entrambi i casi.
- La finestra si accorcia in base al contenuto, fino all’altezza massima impostata; oltre quella soglia il contenuto scorre. L’altezza massima predefinita passa a 600, senza modificare le dimensioni già salvate.
- Lo sfondo delle sezioni dei giocatori, colorato per classe, mantiene un’opacità fissa del 25%, indipendente dal cursore dello sfondo della finestra.

## 7.4.0

Tieni d’occhio i progressi del gruppo con il nuovo tracciamento obiettivi del gruppo.

### Tracciamento obiettivi del gruppo

- Una finestra compatta mostra conteggi e barre di avanzamento degli obiettivi, con sezioni colorate in base alla classe di ogni giocatore. Gli altri membri devono usare QuestTogether per condividere i propri progressi.
- I dati si aggiornano all’arrivo delle comunicazioni del gruppo, indipendentemente dalle impostazioni di visualizzazione in chat e nei fumetti. Se una missione non ha obiettivi numerici, viene mostrato il suo stato, per esempio pronta da consegnare.

**Forever**

![Tracciamento obiettivi del gruppo — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTracker.png)

### Scegli cosa seguire

- Puoi scegliere tra Nascosto, Missione selezionata, Missione sotto il cursore e Selezione e cursore. L’ultima opzione è quella predefinita: mostra la missione su cui passi il mouse nel tracciatore obiettivi di Blizzard, poi torna alla missione selezionata.
- La finestra rimane nascosta quando non c’è una missione da mostrare. La modalità si può cambiare nella modalità Modifica HUD oppure nelle impostazioni, sotto Gruppi e condivisione > Tracciamento obiettivi del gruppo.

**Forever**

![Scegli cosa seguire — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTrackerDisplay.png)

### Adatta la finestra alla tua interfaccia

- Apri la modalità Modifica HUD e seleziona il tracciamento obiettivi del gruppo per spostarlo, ridimensionarlo e regolare l’opacità dello sfondo. I pulsanti Salva modifiche, Annulla modifiche e Ripristina predefinito comprendono sia la disposizione sia la modalità di visualizzazione.
- Le sezioni dei giocatori si adattano alla larghezza disponibile e il contenuto scorre quando serve. Sono supportati i temi chiaro e scuro, con testo leggibile e un leggero sfondo per ciascun giocatore anche a opacità zero.

**Forever**

![Adatta la finestra alla tua interfaccia — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.4.0/Media/ReleaseNotes/QuestTrackerEditMode.png)

## 7.3.5

Indicatori più leggibili, navigazione più comoda e informazioni sul gruppo più aggiornate.

### Mappa e informazioni sui giocatori

- Passa il mouse sul pulsante QT della mappa per vedere una legenda illustrata di icone e stati.
- Sulla mappa del mondo, il clic sinistro su un giocatore lo evidenzia e apre la mappa più dettagliata disponibile per la sua posizione. Quando non ci sono mappe più dettagliate, apre invece il menu del giocatore. Il clic destro apre sempre il menu.
- Anche Trova sulla mappa porta alla mappa più dettagliata disponibile. L’evidenziazione verde rimane mentre cambi mappa e si cancella dopo un minuto, quando chiudi la mappa o quando selezioni un altro giocatore.
- Passando il mouse su un giocatore, un gruppo di indicatori o un punto condiviso, la mappa e gli indicatori non pertinenti si attenuano; quelli interessati restano ben visibili. Il pulsante QT non oscura più la mappa al passaggio del mouse.
- I bagliori dei giocatori usano ora un effetto uniforme. Tooltip e gruppi di indicatori condividono informazioni più aggiornate sui membri del gruppo e gestiscono meglio le risposte in ritardo.
- Migliorata la diagnostica dello sviluppatore, nel rispetto delle preferenze di condivisione diagnostica e della riservatezza della posizione pubblica.

## 7.3.4

Tooltip più chiari e indicatori QuestTogether più coerenti.

### Tooltip dei giocatori e chat

- Gli elenchi dei membri del gruppo mostrano l’icona QT appena sono disponibili dati validi sulla posizione del giocatore, anche dopo aver ricaricato l’interfaccia.
- Negli elenchi del gruppo e nei gruppi di indicatori sulla mappa, gli stati occupano meno spazio. Le spiegazioni dello stato di sviluppatore e della posizione nascosta compaiono soltanto passando il mouse direttamente sul giocatore interessato. Gli indicatori di posizione nascosta restano visibili solo allo sviluppatore.
- Le comunicazioni dello sviluppatore verificato usano un’icona con pergamena e ingranaggio, circondata da un bagliore dorato quando cerca compagni di missione.

## 7.3.3

Informazioni più compatte nei gruppi di indicatori.

### Giocatori sulla mappa

- Il tooltip di un gruppo di indicatori identifica lo sviluppatore di QuestTogether con l’ingranaggio del colore della sua classe, senza aggiungere un’etichetta. La dicitura esplicativa resta nel tooltip del singolo giocatore.

## 7.3.2

Informazioni di gruppo più coerenti e navigazione delle mappe più precisa.

### Mappe dei giocatori

- Tooltip individuali, raggruppamenti ed evidenziazione dei compagni condividono gli stessi dati noti del gruppo, riducendo caricamenti ripetuti e composizioni discordanti.
- I tooltip dei raggruppamenti mostrano il numero totale dei membri accanto all’icona bianca del gruppo.
- Dalla vista del mondo intero, un clic apre la mappa più dettagliata che contiene tutti i giocatori del raggruppamento, poi lo espande se necessario.

## 7.3.1

Informazioni sui gruppi più chiare e controlli della mappa più riconoscibili.

### Mappe dei giocatori

- Nel tooltip di un raggruppamento, chi appartiene allo stesso gruppo noto viene racchiuso in un bordo bianco arrotondato con un’icona di gruppo. Anche chi ha compagni fuori dal raggruppamento conserva l’indicatore.
- Quando i marker QT sono nascosti, il pulsante sulla mappa resta ben visibile e mostra una X rossa.
- Passare sul pulsante non attenua più la mappa quando i marker sono nascosti.

## 7.3.0

Trova giocatori sulle mappe affollate, ritrova vecchi compagni e segui i progressi con meno annunci ripetuti.

### Mappe dei giocatori

- I punti sovrapposti sulla mappa del mondo si raggruppano. La funzione è attiva per impostazione predefinita e può essere disabilitata nelle impostazioni delle posizioni.
- Un clic apre la mappa più dettagliata che contiene tutti i giocatori del raggruppamento. Se resta raggruppato, si espande in punti individuali con tooltip e menu; la rotellina permette di scorrere gli insiemi più grandi.
- Il pulsante QT in alto a destra mostra o nasconde giocatori e punti di passaggio condivisi. Passandoci sopra, la mappa dietro viene attenuata. Minimappa e condivisione della posizione non cambiano.
- L’azione per trovare un giocatore sulla mappa apre la sua posizione condivisa recente ed evidenzia il punto.

### Compagni recenti

- Apri /qt companions o il menu della minimappa per una cronologia privata delle persone con cui sei stato in gruppo. I loro menu permettono sussurri, inviti e note private.
- La cronologia è condivisa fra i tuoi personaggi sullo stesso client e reame. Conserva fino a 100 compagni per 90 giorni; puoi togliere singole voci o cancellarla tutta.

### Progressi e dettagli dei giocatori

- Aggiornamenti ravvicinati dello stesso obiettivo si uniscono in un annuncio con il progresso più recente. Gli obiettivi completati vengono comunque annunciati rapidamente.
- Gli sviluppatori QuestTogether verificati tramite firma hanno marker a ingranaggio del colore della classe e un’etichetta nei tooltip. I raggruppamenti mostrano gli stessi colori, loghi QT e stati di ricerca compagni degli elenchi del gruppo.

## 7.2.1

Correzioni alle note private e alle colonne compresse del registro di gruppo.

### Correzioni e rifiniture

- Ripristinato il cursore di testo nelle note private; il bordo che indica il campo attivo è più discreto.
- Migliorato lo scorrimento durante la modifica di note lunghe.
- Le colonne compresse usano icone affidabili per missioni pronte e completate, al posto di caratteri che potevano apparire come quadrati vuoti.

## 7.2.0

Prendi note private sui giocatori e usa un registro del gruppo più comodo.

### Note private sui giocatori

- Dal menu QT di un giocatore puoi aggiungere, modificare o cancellare una nota. La ritrovi passando il mouse su quel giocatore.
- Le note sono condivise fra i tuoi personaggi e restano sul computer. Non vengono mai inviate ad altri giocatori né incluse nei dati diagnostici.

### Miglioramenti al registro del gruppo

- Comprimi le colonne dei singoli giocatori per fare spazio e riaprile quando ti servono i dettagli.
- Il pulsante Tastiera attiva la navigazione con le frecce. Invio espande gli obiettivi, Spazio apre le azioni della missione ed Esc torna ai controlli normali.
- Le missioni completate si distinguono da quelle mancanti quando l’addon aggiornato dell’altro giocatore ne conferma la cronologia. Se la cronologia è sconosciuta, restano indicate come assenti dal registro.
- Le spiegazioni della condivisione chiariscono perché una richiesta non può procedere. I tooltip dei giocatori mostrano anche gli esiti recenti della condivisione segnalati da WoW.

### Suggerimenti e tooltip

- Molti suggerimenti in chat includono scorciatoie cliccabili alla finestra o all’impostazione pertinente.
- Passare su un giocatore lontano richiede metadati aggiornati e l’elenco completo del suo piccolo gruppo, con nuovi tentativi finché mantieni il mouse sopra.

> <img src="https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v7.2.0/Media/QuestTogetherTipIcon.png" width="20" height="20" alt=""> Consiglio: Scrivi /qt tip o /qt hint, poi usa le scorciatoie cliccabili del suggerimento per esplorare QuestTogether.

## 7.1.3

I testi delle missioni disponibili nella tua lingua vengono recuperati più affidabilmente.

### Testi delle missioni

- Annunci, registro di gruppo e avvisi di seguito trovano meglio i titoli locali disponibili.
- Gli aggiornamenti restano in ordine mentre si caricano i titoli. Anche la finestra dei dettagli recupera correttamente il testo del tooltip arrivato in ritardo.
- Migliorata la gestione dei nomi delle missioni ricevuti da altri giocatori.

## 7.1.2

Scegli se vedere suggerimenti all’avvio e usa impostazioni più semplici.

### Suggerimenti QuestTogether

- Puoi disattivare i suggerimenti automatici nelle opzioni generali della pagina principale. /qt tip e /qt hint restano disponibili.
- La pagina iniziale delle impostazioni è più semplice; il tema chiaro o scuro si sceglie da un menu a discesa.

## 7.1.1

Icona e colori più leggibili per i suggerimenti.

### Suggerimenti QuestTogether

- Un’icona QT con lampadina sostituisce l’emoji non supportata, con etichetta dorata e testo color crema.

## 7.1.0

Scopri le funzioni di QuestTogether con suggerimenti utili.

### Suggerimenti QuestTogether

- QT mostra un suggerimento all’accesso o al reload. La lista viene mescolata e non ripete un consiglio finché non li ha mostrati tutti.

> 💡 Consiglio: Scrivi /qt tip o /qt hint per vedere un altro suggerimento QuestTogether quando vuoi.

## 7.0.2

Miglioramenti alle informazioni delle missioni e alla diagnostica facoltativa.

### Miglioramenti

- Una finestra dei dettagli permette di leggere i testi disponibili delle missioni.
- Migliorate la diagnostica facoltativa dello sviluppatore e l’affidabilità delle comunicazioni. La tua scelta sulla condivisione diagnostica viene rispettata.

## 7.0.1

I controlli QuestTogether si avvicinano all’interfaccia attuale di Blizzard.

### Controlli in stile Blizzard

- I cursori delle impostazioni hanno frecce per le regolazioni fini e mostrano il valore accanto alla pista.
- Caselle di spunta, campioni di colore, barre di scorrimento e pulsanti standard adottano l’aspetto attuale di Blizzard.
- Le ricerche nel registro di gruppo e nel debug includono una lente e un pulsante per cancellare.

### Scorrimento

- Migliorato lo scorrimento in impostazioni, registro di gruppo, note e debug, anche durante il ridimensionamento e nell’allineamento delle righe delle missioni.
- Frecce e trascinamento delle barre native si fermano correttamente quando la finestra si chiude.

## 7.0.0

Il sistema di comunicazione di QuestTogether è stato ricostruito in vista dell’uscita di WoW Forever. Il nuovo protocollo richiede che tutti aggiornino l’addon insieme.

### Importante: le vecchie versioni non comunicano

- QuestTogether 7.x usa un nuovo protocollo e non può scambiare posizioni, progressi, dati del registro di gruppo o altri messaggi dell’addon con le versioni 6.x e precedenti. Chiedi anche ai tuoi compagni di aggiornare.

### Prepararsi a WoW Forever

- Stiamo facendo questi cambiamenti importanti, incompatibili con il passato, prima dell’uscita di WoW Forever per dare basi più solide alle comunicazioni di QT.
- Dopo il lancio di Forever presteremo maggiore attenzione alla compatibilità fra versioni, evitando aggiornamenti obbligatori che interrompano il gioco. Se diventasse necessario cambiare ancora protocollo, lo comunicheremo chiaramente.

### Trovare giocatori dove stai guardando

- Gli aggiornamenti privilegiano la tua zona e quella che tieni aperta sulla mappa. Le posizioni più lontane vengono aggiornate in background.
- I movimenti vicini usano messaggi brevi e mirati. Le richieste di ricerca vengono raggruppate e distribuite nel tempo per ridurre il traffico nelle zone affollate.

### Scambi più affidabili

- Progressi, registro di gruppo, dettagli dei giocatori e diagnostica condividono un invio a ritmo controllato, così le risposte grandi lasciano spazio al resto.
- Le risposte grandi possono recuperare le parti mancanti senza ricominciare da capo. Le posizioni in ritardo conservano l’età originale e non sovrascrivono posizioni più recenti o ritiri della condivisione.
- Cambiare la condivisione della posizione annulla le coordinate pubbliche già in coda. Alla disconnessione o durante un caricamento, QT tenta un ultimo avviso di uscita; la scadenza resta la soluzione se non arriva.

## 6.5.11

Nuove scorciatoie aprono gli strumenti QT e gestiscono la ricerca compagni.

### Scorciatoie da tastiera

- QuestTogether compare correttamente nell’elenco dei comandi del gioco al posto della voce errata HEADER_QUESTTOGETHER.
- Puoi assegnare tasti al menu QT, al registro del gruppo, alla ricerca compagni, all’interruzione del seguito, alla chat QT e alle impostazioni.
- Il tasto già assegnato al registro del gruppo è conservato. Le nuove azioni iniziano senza tasto; il menu si apre anche se l’icona della minimappa è nascosta.

## 6.5.10

Aggiornamenti più fluidi del registro di gruppo, richieste e mappe più affidabili e correzioni per profili e bolle.

### Registro delle missioni del gruppo

- Con l’aggiornamento automatico, gli elenchi invariati consumano meno traffico. Il pulsante Aggiorna continua a richiedere dati completi.
- Gli elenchi si riprendono dopo cambi degli obiettivi o dopo aver ignorato e poi ripristinato un giocatore, senza mantenere vecchi progressi o restare in caricamento.

### Finestre e profili

- Cambiare, copiare o azzerare un profilo ripristina le sue disposizioni salvate o quelle predefinite. Cambiare schermo mantiene le finestre visibili senza dimenticare dimensioni e posizione preferite.
- Chiudere una conferma di ingresso o condivisione mostra correttamente la richiesta successiva in attesa.
- Aprire le impostazioni durante la modalità Modifica Blizzard non impedisce più di ripristinare la disposizione originale della bolla personale.
- Le finestre di supporto aperte continuano ad adattarsi a tema e schermo anche con QuestTogether disabilitato.

### Monitoraggio e comunicazioni

- Le richieste di ingresso o condivisione scadute o non più necessarie vengono annullate prima di partire.
- Completamenti di obiettivi bonus e missioni mondiali conservano il giusto tipo di annuncio anche se la missione sparisce dal registro prima dell’evento.
- Gli aggiornamenti manuali delle posizioni usano le risposte pubbliche di vecchie versioni QT per i punti normali, preservando posizioni più recenti e scelte di condivisione.

## 6.5.9

Aggiornamenti del gruppo più affidabili, mappe più ordinate e correzioni al nascondimento dell’interfaccia con Alt+Z.

### Registro del gruppo e finestre

- Nascondere e ripristinare l’interfaccia con Alt+Z conserva conferme di cambio missione in attesa e sfondi del colore della classe dietro ai nomi.
- Le richieste del registro recuperano meglio dopo reload, caricamenti o pagine di messaggi mancanti, anziché lasciare i giocatori bloccati in caricamento.
- Finestre e bolle personali si adattano meglio agli schermi piccoli. Ripristinare le disposizioni conserva le scelte in attesa nei dialoghi.

### Mappe e aggiornamenti del gruppo

- Posizioni, gruppi e missioni attive rifiutano messaggi superati, evitando che risposte tardive facciano tornare giocatori usciti o sovrascrivano dati nuovi.
- QT invia un avviso quando lascia il mondo: se arriva, gli altri possono togliere prima il punto. Se si perde, resta la normale scadenza. La disponibilità alle richieste di ingresso si riprende dopo i caricamenti.
- I membri del gruppo usano i marker Blizzard senza duplicati QT. Il filtro offre tutti gli utenti QuestTogether, chi cerca compagni o nessuno; la condivisione della tua posizione resta separata.

### Monitoraggio e comunicazioni

- Il monitoraggio recupera quando il registro è incompleto all’accesso. Raffiche di eventi delle missioni non continuano più a rimandare gli aggiornamenti in attesa.
- I messaggi in uscita condividono una coda a ritmo controllato. La verifica delle richieste dello sviluppatore procede a piccoli passi per ridurre i blocchi dei fotogrammi. Disattivare la diagnostica annulla il lavoro diagnostico in coda.
- I report grandi hanno più tempo per completarsi. I richiedenti meno recenti ricevono una risposta esplicita sui limiti di dimensione quando il report non entra, invece di un’attesa senza spiegazione.

## 6.5.8

Menu a discesa nativi, controlli delle mappe più chiari e diagnostica per lo sviluppatore.

### Impostazioni e mappe dei giocatori

- Tutti i nove menu a discesa usano i controlli WoW con selezione dorata, menu neri e pulsanti precedente/successivo.
- La scelta dei giocatori mostrati sostituisce le caselle di visibilità e l’eccezione del gruppo. Puoi mostrare tutti gli utenti QT, chi cerca compagni con o senza il tuo gruppo, solo il gruppo o nessuno. Le preferenze sono mantenute; condividere la tua posizione resta separato.
- La nuova categoria Sviluppatore raccoglie finestra di debug, nuova scansione del registro e opzione di condivisione diagnostica.

### Risposte diagnostiche

- La condivisione diagnostica con lo sviluppatore è attiva per impostazione predefinita. Consente richieste autenticate per diagnostica QT, impostazioni dell’addon e dati di gioco su personaggio, gruppo e posizione, anche con la condivisione pubblica disattivata. Disabilitala in Sviluppatore per interrompere questi invii.
- Le risposte usano sussurri privati dell’addon, divisi in pagine e scaglionati per mantenere tutti i campi dei rapporti più voluminosi. Entrambi devono usare 6.5.8 o successiva; i client pubblicati come 6.5.7 non rispondono a queste richieste.

## 6.5.7

Seleziona un giocatore dalla minimappa e riconosci meglio le icone del gruppo.

### Punti e icone del gruppo

- Fuori combattimento, il clic sinistro su un punto della minimappa seleziona il giocatore se il gioco lo consente. Il clic destro apre ancora il menu, con la selezione del bersaglio per prima. I menu della mappa del mondo non cambiano.
- Le icone di ricerca compagni hanno un bordo dorato molto più marcato. Nei tooltip, gli elenchi del gruppo mostrano anche il logo luminoso dei membri che stanno cercando compagni.
- I simboli delle missioni attive nel registro del gruppo usano un proprio livello in primo piano, così lo sfondo dei pulsanti non può coprirli.

## 6.5.6

Riconosci nel registro chi cerca compagni per le missioni.

### Ricerca compagni

- L’icona della ricerca ha un bordo dorato più luminoso e un alone più intenso, leggibili anche alle piccole dimensioni del registro.
- Il prefisso con il logo QT ora si illumina quando il giocatore cerca compagni. Le icone specifiche delle missioni e quelle dei messaggi di chat restano invariate.

## 6.5.5

Corretti i simboli delle missioni mancanti nel registro di gruppo.

### Icone delle missioni

- Dopo uno scorrimento o un aggiornamento, alcuni pulsanti potevano apparire come cerchi vuoti. I pulsanti riutilizzati ora ripristinano la grafica e usano un’icona alternativa se quella richiesta non può essere applicata.

## 6.5.3

Il registro di gruppo ha tre nuove sezioni illustrate nella guida. Il gioco non cambia; le schermate mostrano compagni simulati su Forever.

### Il gruppo a colpo d’occhio

- La guida include una schermata d’insieme del registro del gruppo.

**Forever**

![Il gruppo a colpo d’occhio — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestOverviewForever.png)

### Scegliere una missione o seguire un compagno

- Aggiunta una schermata dei controlli per seguire le missioni.

**Forever**

![Scegliere una missione o seguire un compagno — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestFollowingForever.png)

### Confermare il cambio di missione

- Aggiunta una schermata della conferma di cambio della missione attiva.

**Forever**

![Confermare il cambio di missione — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.5.3/Media/ReleaseNotes/PartyQuestFocusWarningForever.png)

## 6.5.2

Corretto il seguito dopo l’anteprima.

### Prove con le tue missioni

- Chiudere l’anteprima del registro del gruppo ora riprende il seguito già attivo nel tuo gruppo reale.

## 6.5.1

Pulsanti delle missioni più chiari, conferma prima di cambiare il seguito e icone coerenti con il tracker nativo.

### Controlli più chiari

- Quando segui qualcuno, resta colorato soltanto il pulsante della sua missione attiva. Altrimenti sono colorati i tuoi pulsanti e le missioni attive dei compagni. Gli altri sono grigi, senza dissolvenze. Le missioni attive altrui restano cliccabili per iniziare o cambiare seguito.

### Confermare prima di cambiare

- Scegliere una tua missione o un altro compagno chiede conferma prima di interrompere il seguito attuale. Anche cambiare o cancellare la missione dal tracker Blizzard apre la richiesta: QT ripristina quella seguita mentre decidi. Annulla mantiene il seguito; cambia applica la scelta. Prova il dialogo con /qt preview unfollow.

### Icone coerenti con il gioco

- Lo stato di consegna usa la stessa verifica del tracker Blizzard, correggendo missioni di consegna che mostravano progresso anziché un punto interrogativo. Lo stato pronto corretto viene incluso anche nei dati condivisi del registro di gruppo.

### Prove con le tue missioni

- L’anteprima usa il tuo vero registro con quattro compagni simulati e missioni aggiuntive che non possiedi. I controlli modificano la navigazione Blizzard reale, mentre la condivisione resta simulata. Dal menu di un compagno puoi far avanzare la sua missione attiva. Per le missioni non condivisibili compare una dicitura centrata di impossibilità o stato sconosciuto, anziché una colonna azioni vuota.

## 6.5.0

Scegli la missione attiva dal registro del gruppo e continua a seguire un compagno anche dopo il reload.

### Pulsanti delle missioni attive

- Pulsanti in stile Blizzard compaiono nelle colonne dei giocatori al posto dei titoli nell’intestazione. Nella tua colonna cambiano la missione seguita per navigare. I pulsanti selezionati mostrano le scelte dei compagni: fai clic sui loro per seguirli.

### Un seguito che si conserva

- La scelta del compagno viene salvata per personaggio e resiste ai reload e alle assenze temporanee di dati. Gli aggiornamenti del gruppo allineano la tua missione se la possiedi. Scegliere una navigazione propria, l’uscita del compagno, lo scioglimento del gruppo o il passaggio a incursione interrompono il seguito.

### Quando ti manca la missione

- Se il compagno sceglie una missione che non possiedi, il seguito si ferma senza cambiare navigazione. Una finestra a tema QT spiega il motivo e apre il registro del gruppo per chiedere la missione e riprendere a seguirlo. /qt preview focus mostra il dialogo; /qt preview compare permette di provare pulsanti e cambi simulati.

## 6.4.3

Correzioni alla missione attiva e ai tooltip del gruppo, con un controllo delle mappe più semplice.

### La tua missione attiva

- L’intestazione del registro di gruppo legge direttamente la tua missione attiva, anche da solo o con la condivisione disattivata. Cambiare la missione seguita per navigare aggiorna l’intestazione senza usare Aggiorna.

### Membri nei tooltip

- Nei piccoli gruppi, il giocatore su cui passi compare subito insieme al capo mentre arriva l’elenco completo. L’attesa viene indicata soltanto se mancano altri membri. I gruppi oltre cinque continuano a mostrare solo il capo.

### Impostazioni delle mappe più semplici

- Un’unica casella controlla la visualizzazione degli altri giocatori su mappa e minimappa. La condivisione della tua posizione resta indipendente. Le preferenze esistenti mantengono il display attivo se almeno una mappa era attiva, oppure spento se lo erano entrambe.

## 6.4.2

Più controllo sui dati delle missioni, sui giocatori mostrati sulle mappe e sull’accessibilità delle finestre. Discord resta il punto di riferimento per aiuto e feedback.

### Registro delle missioni del gruppo

- Le intestazioni indicano quanto sono recenti i dati di ogni giocatore. Dal relativo menu puoi aggiornare soltanto quella persona.
- Nei filtri trovi l’aggiornamento automatico facoltativo: se attivo, richiede nuovi dati circa ogni 30 secondi mentre la finestra reale è aperta.
- L’arrivo di nuovi dati conserva quando possibile ricerca, missioni espanse, scorrimento orizzontale e posizione della missione visibile.
- Le indicazioni della missione attiva spiegano attesa, scadenza e dati non supportati. Quando QT non distingue mancata condivisione da indisponibilità, lo dice. Il menu avverte anche se seguire qualcuno creerebbe un ciclo.

### Accessibilità e disposizione

- Le opzioni di accessibilità permettono una scala delle finestre dall’80 % al 150 % e movimento ridotto, con scorrimento ed espansione degli obiettivi immediati.
- La scala ingrandisce insieme testi e controlli, ma può essere limitata per mantenere l’intera finestra sullo schermo.
- Registro del gruppo e benvenuto salvano dimensioni e posizione relativa allo schermo per profilo. Le finestre QT si riadattano quando cambia la dimensione dello schermo o la scala dell’interfaccia.
- Il ripristino della disposizione in Accessibilità, o /qt resetlayout, cancella le posizioni salvate e ricentra le finestre.

### Visualizzazione delle posizioni

- Mappa e minimappa possono essere mostrate o nascoste separatamente dalla condivisione: nascondere i punti locali non cambia ciò che invii.
- Il filtro offre tutti i giocatori QT, chi cerca compagni oppure soltanto il gruppo.
- Mostrare sempre il proprio gruppo è attivo per impostazione predefinita. I membri restano visibili anche con il filtro dei compagni, purché le loro autorizzazioni di posizione lo consentano.

### Altri miglioramenti

- Il rilevamento sperimentale degli strati mantiene opzioni e interfaccia, ma gestisce meglio le richieste quando cambiano gli indizi locali o i giocatori vicini devono attendere.
- Esc chiude i dialoghi QT tramite le normali azioni di chiusura. Puoi assegnare una scorciatoia al registro del gruppo nei comandi del gioco; inizialmente non ne è assegnata nessuna.
- Passa sulle righe di missioni e obiettivi per leggere tutto il testo. I cursori di scala e distanza hanno piste più luminose con bordi scuri.

## 6.4.1

Un rilevamento sperimentale può segnalare quando un giocatore QT vicino sembra trovarsi in uno strato diverso del mondo.

### Rilevamento sperimentale degli strati

- È attivo per impostazione predefinita nelle opzioni sperimentali di QuestTogether. Disattivare il rilevamento degli strati diversi interrompe i confronti e nasconde gli indicatori di fase stimati.
- Nel mondo aperto di Forever, client QT compatibili e vicini confrontano osservazioni di PNG e giocatori visibili. Un’icona di fase indica uno strato probabilmente diverso; passaci sopra per i dettagli. È necessaria la condivisione della posizione.
- Le stime possono essere sbagliate. Non vedere un giocatore non basta: vedersi a vicenda o vedere lo stesso giocatore prevale sulla stima basata sui PNG. Gli indizi vecchi scadono automaticamente; i vecchi client QT non partecipano.

### Schermate nelle note

- Le schermate delle note vengono caricate direttamente su Discord, così restano visibili nei messaggi delle modifiche.

## 6.4.0

Finestre QT più curate e accesso più rapido al registro delle missioni del gruppo.

### Registro delle missioni del gruppo

- Scopri il registro introdotto in 6.3: fino a cinque giocatori in colonne del colore della classe, missioni possedute o mancanti e prontezza del gruppo per la consegna. Combina ricerca e filtri di possesso, progresso e azione; condividi o richiedi missioni quando consentito.
- L’intestazione di ciascun giocatore mostra la missione attiva. Fai clic sul nome di un compagno per scegliere di seguirla; se non la possiedi, la tua navigazione resta invariata. Aggiorna richiede nuovi dati dei progressi remoti. Le schermate usano dati fittizi.
- Un piccolo pulsante a libro apre nel registro Blizzard i dettagli delle missioni che possiedi. Fare clic sulla riga continua a espandere gli obiettivi.
- Una corona indica il capogruppo e si aggiorna quando cambia. La tua colonna resta per prima.

**Retail**

![Registro delle missioni del gruppo — Retail](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogRetail.png)

**Forever**

![Registro delle missioni del gruppo — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestLogForever.png)

### Espandere gli obiettivi di tutti

- Fai clic su una missione per vedere conteggi, barre dei progressi e passi completati di ciascun membro; puoi tenerne aperte diverse. I pannelli sono più compatti, con intestazioni e corpi coordinati per classe. Una missione tipica di cinque giocatori con due obiettivi ciascuno entra nella finestra predefinita; quelle lunghe possono ancora richiedere scorrimento.

**Forever**

![Espandere gli obiettivi di tutti — Forever](https://raw.githubusercontent.com/AlexAllocated/QuestTogether/v6.4.0/Media/ReleaseNotes/PartyQuestObjectivesForever.png)

### Finestre e minimappa

- Clic sinistro sul pulsante della minimappa apre o chiude il registro del gruppo; clic destro apre il menu. Le impostazioni tornano nel menu e il tooltip spiega le scorciatoie.
- Promemoria della chat di gruppo, richieste di condivisione e ingresso, impostazioni delle bolle e collegamento Discord usano la cornice a pergamena e i temi chiaro e scuro di QT, con più margini e spazio per i valori dei cursori.
- Trascinare una finestra conserva la distanza iniziale dal cursore, anche nell’anteprima del confronto. Menu e tooltip chiamano coerentemente la finestra Blizzard registro missioni.

### Comandi di anteprima

- /qt preview elenca le anteprime di finestre e annunci. I vecchi comandi restano validi; le azioni simulate non invitano giocatori, condividono missioni o inviano messaggi.
- L’anteprima del confronto mostra cinque giocatori, inclusi un cacciatore e un ladro, con obiettivi diversi, missioni attive e corona del capogruppo.

## 6.3.1

Gli obiettivi nel registro delle missioni del gruppo hanno più respiro.

### Spaziatura dei pannelli

- I pannelli espansi hanno più margine in basso, così le barre di avanzamento non toccano il bordo. Scorrimento e animazioni di espansione includono lo spazio aggiunto.
- Messaggi come l’assenza di dettagli degli obiettivi sono centrati verticalmente accanto al nome del giocatore anziché vicino al bordo superiore.

## 6.3.0

Un registro delle missioni del gruppo, destinazioni condivise e la possibilità di seguire un compagno rendono più facile fare missioni insieme.

### Registro delle missioni del gruppo

- Il confronto diventa il registro delle missioni del gruppo. Espandi più missioni insieme per vedere obiettivi e progressi di ogni membro, con un riepilogo della prontezza del gruppo.
- Cerca missioni e combina filtri di possesso, progresso e condivisione. Aggiorna richiede nuove istantanee agli altri giocatori. I client precedenti possono ancora confrontare gli elenchi, ma non fornire i dettagli degli obiettivi.
- La finestra a pergamena è ridimensionabile e scorre fluidamente. Colonne colorate per classe, intestazioni cliccabili e spaziose e pannelli arrotondati rendono più leggibili i progressi.

### Missione attiva e punti condivisi

- La missione attiva compare sotto il nome di ciascun membro. Dall’intestazione o dal menu QT puoi scegliere di seguirne la missione, purché tu la possieda. Missioni mancanti o rimosse non cambiano la tua navigazione; navigare manualmente, lasciare il gruppo o ricaricare l’interfaccia interrompe il seguito.
- I punti di passaggio Blizzard degli altri membri compaiono sulla mappa e sulla minimappa vicina con il colore della classe. Quelli sovrapposti elencano tutti i proprietari. L’azione per navigare lì usa TomTom o la navigazione nativa. Ricevere un punto non cambia mai la destinazione e non garantisce di essere nella stessa fase.
- In Gruppi e condivisione, condividere missione attiva e punto di passaggio e mostrare i punti del gruppo sono opzioni inizialmente attive, indipendenti dalle posizioni pubbliche e dalla ricerca compagni. Seguire qualcuno è facoltativo. Servono utenti aggiornati in gruppi fino a cinque, anche nelle spedizioni; le incursioni sono escluse.

### Finestre e menu

- Le note usano il tema a pergamena scuro, con modalità chiara facoltativa. Puoi spostare e ridimensionare la finestra, leggere righe della cronologia più ordinate e usare le frecce fra versioni o fino alle estremità. Discord e impostazioni sono in fondo.
- I tooltip dei giocatori aderiscono meglio al contenuto. Il menu della minimappa separa gli strumenti delle missioni da note, posizione del registro e visibilità dell’icona. Impostazioni e invio di chat QT lasciano il menu; le impostazioni restano disponibili con /qt options.

## 6.2.3

Meno annunci ripetuti delle missioni pronte per la consegna.

### Missioni pronte da consegnare

- Una missione già pronta o completata all’inizio del monitoraggio viene registrata in silenzio. Dati mancanti e aggiornamenti successivi non ripetono più annunci già osservati.
- I nuovi completamenti vengono ancora annunciati; accettare di nuovo una missione azzera la sua cronologia di notifiche. Deve aggiornare il giocatore che invia: le versioni precedenti possono ancora produrre raffiche di annunci.

## 6.2.2

I progressi conservano i dettagli degli obiettivi in ogni lingua.

### Mantenere il testo degli obiettivi

- Chat e bolle mostrano testo e conteggi originali del mittente per missioni, missioni mondiali e obiettivi bonus, invece di diciture generiche come « Obiettivo 1: 5/5 ».
- Gli annunci di accettazione e completamento continuano a usare etichette tradotte e titoli locali quando disponibili.

## 6.2.1

È più chiaro quando QT scrive nella chat di gruppo.

### Controllare gli annunci al gruppo

- L’impostazione delle destinazioni spiega che QT scrive anche nella chat quando un membro non è riconosciuto come utente QT. Resta attiva per impostazione predefinita.
- Dopo una breve attesa per riconoscere i membri, una finestra con il logo QT permette di mantenere l’opzione o spegnere gli annunci prima che inizino. Scegliere di non ricordarlo più salva la conferma nel profilo attuale.
- Il promemoria localizzato nomina i membri interessati e può tornare quando ne arrivano altri non identificati. Sparisce se vengono riconosciuti come utenti QT. Gli eventi trattenuti durante l’attesa non vengono riprodotti.

## 6.2.0

Punti vicini più fluidi, dettagli dei giocatori più rapidi e comunicazioni più affidabili.

### Movimento più fluido sulla minimappa

- I giocatori vicini possono scambiarsi posizioni tramite sussurri dell’addon distribuiti nel tempo. Vengono favoriti fino a quattro utenti idonei più vicini, rispettando condivisione, filtri, ignorati e limiti di traffico.
- Entrambi devono essere aggiornati per questi flussi e le risposte dirette al passaggio del mouse. Le vecchie versioni mantengono gli invii ordinari; ritardi del server e restrizioni possono ancora incidere sulla consegna.

### Ricerca e dettagli dei gruppi

- Passare su un nome o un punto può richiedere direttamente dati aggiornati. Le richieste sono limitate in frequenza; un elenco di membri invariato non scade più dopo due minuti.
- Posizioni recenti, ricerca compagni e dettagli noti del gruppo sopravvivono a /reload fino a tre minuti dal rilevamento originale. Entrare in una zona richiede anche un aggiornamento della ricerca, con risposte scaglionate.
- In attesa del numero esatto, i tooltip usano lo stato noto di giocatore solo o in gruppo. Un piccolo logo identifica chi usa QT mantenendo allineati i nomi.

### Localizzazione e presentazione

- Razze, dettagli dei ping, dati delle missioni e altri testi usano la lingua locale quando disponibile. Le traduzioni mancanti lasciano il testo leggibile del mittente; i progressi non prendono descrizioni da obiettivi locali non pertinenti.
- Gli annunci generici usano il logo QT. La ricerca compagni è la prima voce del menu della minimappa.

### Comunicazioni e affidabilità

- Confronti, elenchi del gruppo, richieste di ingresso e condivisione e risposte ai ping preferiscono sussurri diretti fra utenti compatibili. Messaggi periodici consolidati e meno aggiornamenti di posizioni invariate riducono il traffico pubblico.
- Corretti scansioni ripetute delle missioni, tentativi eccessivi sulle barre dei nomi, finestre che non si chiudevano con restrizioni e /qt set che accettava impostazioni non booleane. Disattivare la posizione non elimina più richieste non correlate dalla coda.

## 6.1.2

I punti dei giocatori vicini rispondono più rapidamente e gli annunci localizzati sono più chiari.

### Punti della minimappa

- Quando la minimappa non fornisce l’ID della mappa, QT usa quella attuale del personaggio. Questo corregge punti dei giocatori mancanti.

### Aggiornamenti locali più rapidi

- Con meno di 10 utenti QT noti nella zona, l’obiettivo è un invio al secondo; fra 10 e 19, ogni 5–10 secondi; a 100, ogni 15–20 secondi. Gli intervalli crescono gradualmente fra queste soglie. Da 500 in su restano invariati.
- Gli invii rapidi contengono posizioni compatte appena rilevate, mentre gli altri dettagli restano sui messaggi periodici più lenti. I limiti di traffico continuano a valere e la congestione può ritardare la consegna. Gli altri giocatori devono aggiornare l’addon per inviare posizioni più frequenti.

### Annunci localizzati più chiari

- Le etichette degli eventi, come l’accettazione di una missione, usano la tua lingua anche senza titolo locale o metadati facoltativi di traduzione.
- Se WoW non fornisce il titolo locale, QT conserva quello leggibile del mittente. I progressi mantengono il testo originale quando non possono essere ricostruiti in sicurezza.

## 6.1.1

I menu di giocatori e missioni sono più essenziali.

### Menu contestuali

- La scelta della finestra del registro non compare più nei menu dei nomi. Per spostare i messaggi QT fra chat principale e finestra separata, usa il menu della minimappa o le impostazioni.

## 6.1.0

Trova i gruppi sulla mappa, scopri chi sta giocando insieme e chiedi di unirti attraverso qualsiasi membro.

### Vedere chi è nello stesso gruppo

- I punti dei giocatori in gruppo hanno un piccolo simbolo con due persone. Passando su un membro, i compagni ricevono un bordo bianco, gli altri punti si attenuano e il capogruppo mostra una corona. Gli aloni dorati della ricerca compagni restano visibili.
- I tooltip elencano membri con punti e nomi del colore della classe, mettendo prima il capogruppo con la corona. Fino a cinque membri vengono mostrati tutti; nei gruppi più grandi compare soltanto il capo. Gli stessi dettagli sono disponibili sui nomi del registro QT.
- Per il tuo gruppo viene usata la lista del gioco. I dettagli dei gruppi remoti sono richiesti quando servono a utenti QT aggiornati, con cache e richieste scaglionate. I vecchi client mantengono punti e dimensione di base del gruppo; i dettagli completi richiedono un utente aggiornato.

### Richieste inoltrate al capogruppo

- Puoi chiedere di entrare attraverso un membro che non può invitarti. Se il capo usa QT ed è disponibile a invitare, la richiesta viene inoltrata a lui con le normali regole di conferma e approvazione automatica.
- Se non è noto che il capo usi QT e gli annunci di gruppo sono attivi, il membro può avvisare in chat: « [QT] PlayerName chiede di unirsi al gruppo. ». Qualcuno con il permesso deve poi invitarti manualmente.
- Richiedente e membro che inoltra devono avere questo aggiornamento. Restano i controlli per gruppo pieno, restrizioni, giocatori ignorati, scadenza e frequenza delle richieste.

### Tooltip più ordinati

- I dettagli del gruppo sono subito sotto livello, razza e classe, con righe compatte e spazio fra sezioni. Gli emblemi di Alleanza e Orda hanno dimensioni raddoppiate.
- La versione dell’addon è in fondo nel formato breve vX.Y.Z. L’età della posizione, quando presente, si trova subito sopra.
- Il conteggio delle missioni seguite è stato tolto dai tooltip dei giocatori e del pulsante della minimappa. Resta la missione attiva di chi cerca compagni.

## 6.0.2

Sfoglia i vecchi aggiornamenti di QuestTogether nella tua lingua. Migliora anche il recupero dei titoli negli annunci di completamento.

### Sfogliare le note precedenti

- La finestra offre pulsanti per versioni precedenti e successive, un collegamento all’ultima e una cronologia con versioni e date. Aprendo le note si parte sempre dall’ultima pubblicazione.
- Sono incluse tutte le versioni pubblicate in precedenza, comprese le prime beta, in ogni lingua WoW supportata. Le stesse note compaiono nei changelog del repository.
- I pulsanti si disabilitano quando non c’è una versione verso cui andare. Sfogliare la cronologia non cambia l’aggiornamento che hai già riconosciuto; l’apertura automatica resta limitata a versioni maggiori e minori. Puoi aprire la finestra con /qt notes.

### Titoli delle missioni completate

- Se una missione esce dal registro prima che QT ne abbia un titolo utilizzabile, l’annuncio di completamento prova le funzioni del gioco per recuperarlo prima di usare l’ID. Un titolo recuperato viene conservato indipendentemente dall’ordine degli eventi di consegna e rimozione.
- Se il tuo client non trova un titolo locale, l’annuncio mantiene il testo del mittente. Se nessuno dei due client ha un nome disponibile, resta l’ID. Il mittente deve aggiornare l’addon per usare il nuovo recupero del titolo.

## 6.0.1

Le reazioni di festa agli altri giocatori riguardano ora chi puoi davvero vedere vicino a te.

### Festeggiamenti dei giocatori vicini

- Per reagire a una missione finita o a un livello guadagnato, QT richiede un’unità giocatore visibile che corrisponda al mittente. Nome o coordinate da soli non attivano più emote, anche con devlogall.
- Le emote ricevute devono appartenere all’elenco di festeggiamenti di QT. Quelle non previste, fra cui mountspecial e grida di fazione, vengono ignorate senza sceglierne un’altra.
- I festeggiamenti per le tue missioni e i tuoi livelli mantengono comportamento e impostazioni.

## 6.0.0

QuestTogether si prepara al lancio di Forever con un sistema di comunicazione pensato per ridurre il traffico in background mentre la comunità cresce.

### Attività locale e ricerca nel mondo

- Gli annunci delle missioni e gli aggiornamenti frequenti dei giocatori usano canali di zona. Gli annunci al gruppo continuano a raggiungerlo anche oltre i confini della zona.
- I punti restano disponibili in tutto il mondo con aggiornamenti di fondo più lenti. Aprire un’altra zona sulla mappa ti iscrive temporaneamente ai suoi aggiornamenti.
- La chat testuale QT resta nel canale globale QuestTogether. La scelta tra chat globale e solo zona continua a determinare quali messaggi vedi.

### Meno traffico in background

- Presenza, versione, conteggio missioni, ricerca compagni e posizione vengono raccolti in aggiornamenti compatti. Nelle zone affollate vengono inviati meno spesso.
- Gli annunci sono distribuiti nel tempo e precedono gli aggiornamenti di fondo. Anche le risposte ai ping sono scaglionate per evitare raffiche simultanee. WoW può comunque ritardare la consegna: i messaggi non sono garantiti istantanei.
- I tooltip indicano l’età delle posizioni meno recenti. La diagnostica riporta conteggi dei messaggi, limitazioni di invio e ritardi degli annunci segnalati dal mittente.

### Un cambiamento importante durante la beta

- Questa riorganizzazione anticipa il lancio di Forever. La beta è il momento per decidere queste basi, prima che più giocatori dipendano dal vecchio comportamento.
- QuestTogether lascia QuestTogetherAnnounce1 e non vi invia né riceve più messaggi. Usa QuestTogether per chat e ricerca globali, oltre ai canali di zona per l’attività locale.
- I canali QT restano dopo gli altri canali, con quello principale prima di quelli di zona. Sono conservate preferenze di condivisione della posizione, giocatori ignorati e annunci.

### Compatibilità con le vecchie versioni

- Aggiornate l’addon insieme. I vecchi client non leggono i nuovi aggiornamenti aggregati o i canali di zona: fra versioni diverse possono mancare punti, stato di ricerca e annunci vicini.
- Chi usa soltanto il vecchio canale non viene più trovato attraverso quel canale. Alcuni scambi con le versioni 5.x più recenti possono ancora funzionare tramite il canale globale comune o il gruppo, ma la compatibilità è parziale.
- /qt ping usa ancora il canale globale e può ricevere risposte da vecchi client compatibili. È uno strumento di ricerca senza garanzia di completezza, non un conteggio di tutti gli utenti QT.

## 5.17.2

Le conversazioni QT si distinguono meglio dagli annunci delle missioni.

### Testo bianco per la chat QT

- I messaggi dei giocatori nella chat QT sono bianchi sia nel registro sia nelle bolle sopra i personaggi.
- I nomi conservano il colore della classe e gli annunci delle missioni restano gialli.

## 5.17.1

I tooltip raccontano di più sui tuoi compagni e permettono di controllare lo stato di una missione direttamente dalla chat.

### Più dettagli sui giocatori

- I tooltip dei nomi e dei punti sulla mappa mostrano quante missioni QT sta monitorando e se il giocatore è da solo o in un gruppo di una certa dimensione. Il tuo tooltip usa lo stato locale attuale.
- Il tooltip della minimappa conta ora le missioni monitorate da QuestTogether, come l’annuncio di avvio, invece delle sole missioni seguite nel tracker di WoW.
- Per vedere conteggi e dimensione del gruppo altrui serve un utente aggiornato. I dati si aggiornano circa ogni 80 secondi nei messaggi periodici esistenti, senza invii aggiuntivi; quelli mancanti o vecchi risultano sconosciuti. Le versioni precedenti continuano a ricevere annunci di versione compatibili.

### Stato delle missioni al passaggio del mouse

- Passa sul nome di una missione nel registro QT per vedere accanto al cursore il tuo stato, la possibilità di condividerla, l’ID e i progressi degli obiettivi seguiti localmente.
- La voce Stato è stata tolta dal menu. Il clic offre ancora condivisione, apertura nel registro, confronto del gruppo e scelta della finestra del registro QT.
- Le nuove etichette sono disponibili in tutte le lingue supportate. I dettagli riguardano i tuoi progressi, non la fase della missione del mittente.

## 5.17.0

Parla nella chat QT, trova compagni nella tua zona e consulta informazioni più complete sui giocatori.

### Chattare con altri utenti QuestTogether

- Scrivi /qt <text> oppure scegli l’invio di un messaggio QT dal menu della minimappa. Le conversazioni compaiono nel registro QT e nelle bolle sopra i giocatori vicini, con un’icona di dialogo. I comandi esistenti continuano a funzionare.
- La chat globale è la scelta predefinita. Puoi limitarla alla tua zona o nascondere del tutto i messaggi QT. Il filtro di zona richiede una posizione recente condivisa dal mittente; quello globale no.
- Durante la transizione, il nuovo canale QuestTogether affianca QuestTogetherAnnounce1. Quando supportato, QT li colloca dopo gli altri canali, con QuestTogether per primo. La chat digitata usa soltanto il nuovo canale.

### Trovare compagni per le missioni

- Attivare la ricerca annuncia la tua disponibilità in tutta la zona con un’icona QT dorata e una faccina. L’invio alla zona richiede la condivisione della posizione e rispetta le preferenze degli annunci. Disattivare la ricerca non manda messaggi.
- Puoi controllare questi messaggi nelle impostazioni degli eventi da annunciare. Un intervallo di 30 secondi limita gli annunci ripetuti, mentre stato e bagliore cambiano subito. Puoi anche interrompere automaticamente la ricerca entrando in gruppo: questa opzione parte disattivata.
- Maiusc-clic sul pulsante della minimappa attiva o disattiva la ricerca. Un anello dorato più luminoso e pulsante la segnala senza tagliare il logo.

### Distanza e dettagli dei giocatori

- La distanza dei giocatori vicini va dal 5 % all’intera zona, con valore predefinito del 25 %. La misura si adatta alla zona attuale; membri del gruppo e giocatori direttamente visibili mantengono il comportamento precedente.
- Passare su un nome nel registro QT mostra lo stesso tooltip migliorato dei punti sulla mappa: nome colorato per classe, livello, razza, classe, emblema di fazione, ricerca compagni, missione seguita se disponibile e versione QT. I tooltip dei nomi sono accanto al cursore.
- Il tuo tooltip mostra la missione seguita per la navigazione mentre cerchi compagni. I client aggiornati annunciano la versione circa ogni 40 secondi nei messaggi periodici esistenti; quelli vecchi mantengono la cadenza precedente.

### Controlli e annunci più chiari

- Il tooltip della minimappa mostra versione QT, ricerca compagni, ambito della chat, numero di missioni seguite, distanza dei vicini e stato della condivisione della posizione.
- I controlli delle impostazioni hanno spiegazioni localizzate al passaggio del mouse, inclusi menu a discesa, cursori, azioni dei profili e colori.
- Se il client non trova il titolo locale di una missione, registro e bolle mantengono il testo originale del mittente invece di un numero generico. Le notizie successive tornano localizzate quando il titolo è disponibile.

## 5.16.7

Leggi le stesse novità di QuestTogether in gioco, su Discord e nei file delle modifiche nella tua lingua.

### Note multilingue coerenti

- Il changelog inglese usa gli stessi riepiloghi e punti della finestra di benvenuto e degli annunci Discord.
- I file delle modifiche sono disponibili per tutte le lingue supportate, con la cronologia già tradotta. È conservata anche una copia delle vecchie note inglesi scritte a mano.
- I controlli di pubblicazione mantengono questi file allineati con le note di riferimento e i testi localizzati.

## 5.16.6

Il pulsante sulla minimappa ti ricorda quando stai cercando compagni.

### Un promemoria luminoso

- Durante la ricerca, il pulsante QT pulsa con lo stesso bagliore dorato dei loghi sulle barre dei nomi.
- L’effetto segue il tuo stato e si ferma se QT viene disabilitato o il pulsante nascosto. Pulsante e logo mantengono le dimensioni precedenti.

## 5.16.5

Un prefisso più breve rende compatti gli annunci di gruppo.

### Annunci più brevi

- I progressi inviati ai membri del gruppo senza QuestTogether iniziano con [QT] anziché [QuestTogether].
- Gli annunci rispettano il limite dei messaggi di chat senza troncare i caratteri, in qualsiasi lingua.

## 5.16.4

Le impostazioni delle bolle restano salvate quando esci dalla modalità Modifica, mentre sulle mappe affollate vengono privilegiati i giocatori vicini.

### Impostazioni delle bolle conservate

- Chiudere la modalità Modifica dell’HUD non annulla più dimensione del testo, durata e posizione della bolla QT.
- Il pannello della bolla ha un proprio pulsante per salvare e un messaggio sullo stato del salvataggio. Le modifiche si applicano automaticamente; il salvataggio stabilisce il punto a cui torna il ripristino.
- Dopo aver salvato e fatto altre modifiche, il ripristino recupera gli ultimi valori QT salvati.

### Precedenza ai giocatori vicini

- Quando più di 128 punti idonei competono sulla mappa o minimappa, hanno precedenza i giocatori più vicini al tuo personaggio.
- Se la cache di 512 posizioni è piena, conserva chi è vicino prima dei nuovi arrivi più lontani. Spostare o ingrandire la mappa non cambia questa priorità.
- Restano gli stessi limiti per punti e cache, senza messaggi di comunicazione aggiuntivi.

## 5.16.3

Le impostazioni sono riorganizzate per trovare più facilmente le opzioni e controllare le tue preferenze a colpo d’occhio.

### Opzioni raggruppate per uso

- Gruppi e condivisione sostituisce la sezione varie e raccoglie disponibilità per le missioni, richieste di ingresso e autorizzazioni alla condivisione.
- Le emote di festeggiamento sono fra le destinazioni degli annunci. La visibilità del pulsante della minimappa è nelle opzioni generali della pagina iniziale; strumenti di debug e nuova scansione del registro sono nella risoluzione dei problemi.
- Confronto delle missioni del gruppo e ricerca compagni sono le prime azioni rapide. Le preferenze esistenti restano salvate.

### Un riepilogo più utile

- Le sezioni del riepilogo mostrano ricerca compagni, condivisione e visualizzazione delle posizioni, approvazione delle richieste, destinazioni degli annunci e impostazioni delle barre di missioni e giocatori.
- Sono visibili anche profilo attivo, versione installata ed eventuale versione più recente rilevata. Quando QT è disabilitato, il riepilogo chiarisce che si tratta delle preferenze salvate.
- Fai clic sul titolo di una sezione per aprirne le impostazioni. Il riepilogo cresce per contenere il testo e resta aggiornato finché la pagina è aperta.

## 5.16.2

I tooltip permettono di riconoscere gli utenti QuestTogether e chi sta cercando compagni.

### Informazioni QT nei tooltip

- Passa sul personaggio, sulla barra del nome o sul riquadro unità di un giocatore QT per vedere che usa QuestTogether. Se cerca compagni, compaiono anche lo stato e un logo QT luminoso.
- La sezione QT segue larghezza e scala del tooltip, lascia libera la barra della salute e si sposta sopra il tooltip quando manca spazio sotto.

### Un alone più visibile

- Il bagliore dorato sulla barra del nome si estende al doppio della distanza intorno al logo, che mantiene le stesse dimensioni.
- Icone e bagliori rappresentano utenti QT reali e il loro stato attuale di ricerca compagni.

## 5.16.1

Trova più facilmente chi cerca compagni e scopri quale missione sta seguendo.

### Un bagliore più evidente

- Il logo QT sulle barre dei nomi di chi cerca compagni ha un alone dorato più luminoso, con una pulsazione delicata. Il logo resta fermo.

### La missione attualmente seguita

- Passa sul punto di un giocatore in cerca di compagni, sulla mappa o sulla minimappa, per vedere la missione selezionata come destinazione di navigazione. Entrambi devono avere questo aggiornamento.
- Le informazioni si aggiornano circa ogni 20 secondi e vengono condivise solo con ricerca compagni e condivisione della posizione attive.
- Il titolo usa la lingua del tuo client quando disponibile, altrimenti quello del mittente o l’ID della missione. Le versioni precedenti di QT mantengono i loro punti e indicatori di ricerca compagni.

## 5.16.0

QuestTogether supporta tutte le lingue di WoW e può mostrare gli aggiornamenti delle missioni altrui nella lingua del tuo client.

### Tutte le lingue di WoW

- Menu, impostazioni e note supportano inglese, tedesco, francese, spagnolo europeo e latinoamericano, portoghese brasiliano, russo, italiano, coreano, cinese semplificato e cinese tradizionale.
- Lo spagnolo latinoamericano ha testi propri anziché usare quelli europei.

### Progressi nella tua lingua

- Gli eventi supportati inviati da utenti QT aggiornati possono comparire nella tua lingua nel registro e nelle bolle. Vengono usati il titolo locale, quando disponibile, e i valori reali dei progressi del mittente.
- Se non è possibile scegliere con sicurezza una descrizione tradotta dell’obiettivo, QT mostra un numero di obiettivo localizzato con quantità, percentuale o stato di avanzamento o completamento.
- Le vecchie versioni di QT e la chat pubblica di gruppo mantengono il testo originale del mittente. Se WoW non fornisce un titolo locale, resta quello ricevuto oppure l’ID della missione. Gli eventi nella stessa lingua conservano la formulazione dettagliata.

### Titoli delle missioni

- Il confronto preferisce ora il titolo nella tua lingua quando disponibile.
- I titoli localizzati con punteggiatura non ASCII mantengono più affidabilmente i collegamenti cliccabili.

## 5.15.0

Puoi chiedere di unirti a un gruppo di missioni direttamente dal menu di un giocatore QuestTogether.

### Chiedere di entrare nel gruppo

- Se un giocatore QT risulta già in gruppo da informazioni recenti, il menu propone una richiesta per unirsi anziché un invito. Entrambi devono avere questo aggiornamento e chi fa richiesta deve essere senza gruppo.
- Il destinatario può rifiutare o inviare un normale invito di WoW. Deve poter invitare e avere spazio in un gruppo ordinario. Per entrare devi comunque accettare l’invito nel modo consueto.

### Inviti automatici facoltativi

- Due opzioni approvano automaticamente le richieste degli amici del personaggio, oppure degli altri giocatori mentre cerchi compagni. Entrambe partono disattivate e sono disponibili nella richiesta e nelle impostazioni varie. Gli amici dell’account Battle.net non sono inclusi.
- Le richieste scadono e rispettano giocatori ignorati, cambi di gruppo e restrizioni del gioco. QT non abbandona mai il tuo gruppo e non accetta inviti per te.

## 5.14.1

Gli annunci di gruppo mostrano il nome completo di QuestTogether.

### Chat di gruppo

- Il prefisso [QT] diventa [QuestTogether], così gli altri giocatori possono trovare più facilmente l’addon.

## 5.14.0

QuestTogether aggiunge cinque lingue e aiuta a tenere informati anche i membri del gruppo che non usano QT.

### Giocare nella propria lingua

- L’interfaccia è disponibile in tedesco, francese, spagnolo, portoghese brasiliano e russo. QT segue la lingua del gioco, con l’inglese come alternativa.
- Sono localizzati impostazioni, menu, tooltip, confronti e note di aggiornamento. Nomi delle missioni e testi dei progressi ricevuti da altri giocatori restano nella lingua originale.
- Le novità delle versioni sono pubblicate anche nei cinque canali dedicati alle singole lingue sul nostro Discord.

### Informare tutto il gruppo

- Una nuova opzione per la destinazione degli annunci invia nella chat di gruppo gli eventi che hai abilitato quando almeno un membro non è stato riconosciuto come utente QT. È attiva per impostazione predefinita e si può disabilitare nelle impostazioni.
- Funziona anche nei gruppi d’istanza formati dal sistema di abbinamento. Gioco in solitaria e incursioni sono esclusi; gli annunci degli altri giocatori non vengono mai ritrasmessi.

## 5.13.1

Questo aggiornamento migliora il ripristino degli indicatori delle missioni, elimina bolle e loghi obsoleti e rende più coerenti impostazioni e finestra di debug.

### Indicatori di missioni e giocatori

- Icone e colori della salute si ripristinano correttamente quando si chiudono viste soggette a restrizioni. Le scansioni ritardate conservano il tempo di assestamento; dati del tooltip temporaneamente mancanti non consumano le possibilità di riprovare.
- Le bolle vengono rimosse quando una barra del nome sparisce o viene riutilizzata in combattimento. Frame protetti o vietati attendono un momento sicuro per la pulizia.
- Posizioni e presenza si riprendono dopo disattivazione di QT, cambio zona e riattivazione. Aggiornamenti tardivi che ritirano posizione o stato di ricerca non fanno più ricomparire il logo di chi è già uscito.

### Impostazioni e finestre

- La casella per cercare compagni resta allineata con modifiche effettuate da comandi, menu e profili.
- La finestra di debug conclude in sicurezza trascinamenti e ridimensionamenti interrotti quando terminano le restrizioni, anche se nel frattempo è stata nascosta.

### Affidabilità

- I test rilevano l’accesso a frame vietati anche quando l’errore viene intercettato internamente.
- I controlli di pubblicazione rifiutano modifiche di implementazione non ancora registrate in Git, per assicurare che le correzioni finiscano davvero nel pacchetto scaricabile.

## 5.13.0

Una luce dorata rende riconoscibili i giocatori in cerca di compagni. Questo aggiornamento semplifica anche le impostazioni delle posizioni e segnala le versioni stabili più recenti.

### Riconoscere chi cerca compagni

- I punti sulla mappa e sulla minimappa mantengono il colore della classe e ricevono un alone dorato quando il giocatore cerca compagni. Anche il logo QT sulla barra del nome si illumina.
- L’effetto sparisce quando lo stato viene disattivato o scade. Nelle impostazioni delle posizioni puoi scegliere di mostrare soltanto chi cerca compagni: il filtro è inizialmente disattivato e vale per entrambe le mappe.
- La finestra delle novità affianca loghi e punti normali a quelli luminosi. Il bagliore dorato indica la ricerca di compagni per le missioni.

### Posizioni: impostazioni più semplici

- Condividere la propria posizione e mostrare gli altri giocatori sono ora due opzioni valide sia per la mappa sia per la minimappa.
- Entrambe sono attive nei nuovi profili. L’aggiornamento conserva le precedenti scelte di non condividere la posizione.

### Avvisi di nuova versione

- Quando un altro giocatore segnala una versione stabile più recente, QT mostra un promemoria nella finestra di chat che hai scelto.
- Il promemoria viene ricordato fra personaggi e compare una volta per reload finché non installi quella versione o una successiva. Le versioni alfa e beta non attivano avvisi.
- Gli annunci di versione sono piccoli e poco frequenti. QT legge anche le informazioni di versione già incluse nelle risposte ai ping.

## 5.12.0

Il nuovo stato di ricerca compagni ti aiuta a trovare persone con cui fare missioni. Migliorano anche i tooltip della minimappa e la distinzione fra modalità Guerra e reami di Retail e Forever.

### Cercare compagni per le missioni

- Lo stato compare nel menu del giocatore e nei tooltip dei punti sulla mappa. Non abilita la condivisione della posizione e non invia inviti.
- Puoi cambiarlo dal menu della minimappa, dalle impostazioni varie o con /qt lfg. Usa /qt lfg on per attivarlo; gli argomenti off e status servono a disattivarlo o controllarlo. Parte disattivato e viene salvato per profilo.
- Se gli aggiornamenti cessano, lo stato scade. I giocatori ignorati sono esclusi; disabilitare QuestTogether sospende l’annuncio della tua disponibilità.

### Retail e Forever

- Su Forever non viene più mostrata la modalità Guerra nei tooltip dei giocatori, nei dettagli di posizione delle missioni o nei ping. I ping omettono anche il reame, mantenendo i nomi completi.
- Gli aggiornamenti delle missioni vicine su Forever non richiedono più dati sulla modalità Guerra di Retail. I punti restano visibili fra fasi diverse per aiutare a trovare un gruppo.
- Retail usa lo stato attivo della modalità Guerra quando disponibile. Uno stato sconosciuto o non supportato non viene più indicato come disattivato.

### Punti sulla mappa più stabili

- Una breve mancanza di coordinate non rimuove subito il tuo punto. L’ultima posizione resta fino a due minuti e i report meno recenti mostrano la loro età nel tooltip. Disattivare la condivisione ritira ancora subito la posizione quando la comunicazione è disponibile.
- Gli aggiornamenti del movimento vengono inviati al massimo ogni dieci secondi. Da fermi resta un segnale ogni venti secondi, compatibile con i client precedenti.
- La cache conserva fino a 512 giocatori. Ogni mappa disegna al massimo 128 punti visibili; chi si trova fuori dalla mappa mostrata non occupa più quel limite.

### Loghi dei giocatori più affidabili

- La lettura dell’impostazione attuale delle barre dei nomi amichevoli corregge loghi mancanti nei client recenti di Forever e Retail.
- I loghi a sinistra si allontanano per lasciare spazio ai benefici visibili e tornano al loro posto quando questi spariscono.
- Tutti i messaggi QT supportati identificano chi li invia. Una cache limitata ricorda i giocatori per la sessione dell’interfaccia: un segnale periodico perso non rimuove più il logo. Uscite esplicite e giocatori ignorati vengono comunque rimossi, senza nuovi messaggi di rete.

### Tooltip della minimappa

- Il tooltip del pulsante QT usa un livello indipendente, così può apparire sopra le barre delle azioni. Si nasconde quando il pulsante diventa indisponibile o iniziano restrizioni.

## 5.11.0

Trova i giocatori QuestTogether, confronta le missioni con una persona specifica e raggiungi più facilmente assistenza e feedback su Discord. Le impostazioni ti permettono di scegliere cosa condividere e cosa vedere.

### Trovare i giocatori QuestTogether

- Con le barre dei nomi amichevoli di WoW attive, i giocatori QT possono mostrare il logo a pergamena. La funzione è attiva per impostazione predefinita, a sinistra con spazio dal nome. Puoi scegliere sinistra, destra, alto o prefisso senza cambiare i colori delle barre della salute.
- Chi condivide la propria posizione può apparire sulla mappa e sulla minimappa con un punto del colore della classe. Passaci sopra per vedere nome, fazione, razza, classe e livello; fai clic per aprire il menu del giocatore.
- Le posizioni hanno quattro opzioni separate: condivisione e visualizzazione per mappa e minimappa, tutte inizialmente attive. La presenza necessaria ai loghi può continuare a essere annunciata anche con entrambe le condivisioni della posizione disattivate.
- Le posizioni si aggiornano periodicamente e spariscono quando scadono. Entrambi i giocatori devono avere l’addon aggiornato; vedere un punto non garantisce di essere nella stessa fase o nello stesso strato del mondo.

### Confrontare un giocatore o tutto il gruppo

- Il confronto dal menu di un giocatore ora riguarda soltanto te e quella persona, anche se è un utente QT raggiungibile fuori dal gruppo. Per il confronto dell’intero gruppo restano minimappa, menu delle missioni e /qt compare.
- Condivisione e richieste di missioni restano riservate al gruppo. Il confronto individuale spiega quando serve essere nello stesso gruppo e quando l’altro giocatore deve avere QT per rispondere.
- Se una richiesta di condivisione attende già un giocatore, viene indicato chi deve rispondere anche dopo aver cambiato destinatario del confronto.

### Assistenza e feedback

- La finestra di benvenuto e la pagina principale delle impostazioni offrono un collegamento a Discord per assistenza e feedback. Si apre un invito da copiare; se la finestra non è disponibile, l’invito compare in chat.

### Correzioni

- I giocatori ignorati vengono filtrati più completamente: niente nuovi messaggi, bolle, punti, confronti o attività di condivisione. Bolle e posizioni già presenti vengono rimosse quando cambia la lista degli ignorati.
- Corretti falsi indicatori di missione causati da limiti illeggibili del tooltip che facevano coincidere il testo con l’obiettivo di un’altra missione.
- La disattivazione della condivisione su mappa o minimappa viene ritentata dopo errori temporanei di comunicazione. Disattivandole entrambe, i dettagli della posizione vengono tolti anche dagli altri aggiornamenti dell’addon.
- I loghi vengono rimossi correttamente quando la presenza scade subito prima dell’uscita del giocatore. L’azione per sussurrare da un punto apre la chat; cambiare destinazione al registro dalle impostazioni non è possibile durante le restrizioni.

## 5.10.0

QuestTogether condivide i progressi delle missioni con il gruppo e i giocatori vicini. Dal pulsante sulla minimappa puoi aprire impostazioni, confronto del gruppo, registro delle missioni e note di aggiornamento.

### Confrontare e condividere le missioni

- Apri il confronto dalla minimappa, dai menu delle missioni o dei giocatori, oppure con /qt compare. Puoi vedere chi ha ogni missione e a che punto è ciascuno.
- Per impostazione predefinita compaiono tutte le missioni del gruppo. Attiva l’opzione che nasconde quelle che non possiedi per concentrarti sul tuo registro.
- Puoi chiedere missioni condivisibili ai membri del gruppo che hanno l’addon aggiornato. Normalmente viene chiesta la loro autorizzazione; la condivisione automatica è facoltativa.
- Il confronto riprende dopo le restrizioni della mappa o del combattimento. Gli aggiornamenti sostituiscono le vecchie risposte; attese fra richieste ed errori spiegano quando puoi riprovare.

### Scorciatoie e menu delle missioni

- Trascina il pulsante a forma di pergamena per riposizionarlo sulla minimappa. Il menu apre impostazioni, confronto, registro delle missioni, note e scelta della finestra del registro QT. Puoi nasconderlo dal menu e ripristinarlo nelle impostazioni varie.
- Dal nome di una missione puoi consultarne lo stato, condividerla, aprirla nel registro o confrontarla con il gruppo. Condivisione e apertura ricontrollano missione attuale e restrizioni al momento del clic.
- I collegamenti di stato mantengono il titolo anche dopo che la missione lascia il registro. La casella della condivisione automatica ora rispecchia le preferenze salvate e i cambi di profilo.

### Aiuto e note di aggiornamento

- Benvenuto e ultime novità hanno una finestra dedicata anziché ripetersi in chat. Aprila dal menu della minimappa, dalla pagina principale delle impostazioni oppure con /qt notes, /qt changelog o /qt patchnotes.
- La finestra si apre automaticamente per gli aggiornamenti maggiori e minori. Anche le patch hanno nuove note, ma non la aprono da sole.
- /qt help mostra i comandi comuni; /qt help debug raccoglie anteprime, diagnostica e comandi per lo sviluppatore.

## 5.9.2

Un clic sinistro o destro sul nome di una missione nel registro QT apre il suo menu, con lo stato della missione seguito dalla condivisione.

### Menu e collegamenti delle missioni

- La condivisione usa la voce attuale del registro senza cambiare la missione selezionata nell’interfaccia Blizzard. Non è disponibile da soli, in presenza di restrizioni o per missioni non condivisibili. Dopo un separatore, l’ultima voce sposta il registro QT fra finestra principale e separata, come nel menu dei giocatori.
- I nomi nei messaggi di stato diventano cliccabili, anche quando il titolo di ripiego proviene dal registro di un altro giocatore. Nei confronti delle missioni completate vengono conservati i collegamenti esistenti, evitando che i dettagli di stato entrino in un secondo collegamento non valido.
- Superati 521 test nei due ordini su Lua 5.1 e 5.2, insieme ai sei profili API, sintassi Lua e shell, revisione esatta di libchev e controlli delle differenze. Menu nel client, consegna delle condivisioni e taint del motore richiedono verifiche separate.

## 5.9.1

Una revisione completa ha portato correzioni al monitoraggio delle missioni, alle barre dei nomi, agli annunci delle aree degli incarichi, alle comunicazioni e alle azioni dell’interfaccia.

### Correzioni emerse dalla revisione

- I blocchi di missioni non collegate nei tooltip non prendono più in prestito il testo di un obiettivo comune. I progressi validi del gruppo vengono conservati e le barre si ripristinano dopo cambi di mappa, istanza, gruppo o missione.
- Missioni appena accettate e scansioni iniziali restano in attesa finché i dati non sono leggibili. Vengono mantenuti traguardi degli obiettivi, classificazione degli incarichi e posizione sconosciuta, senza false uscite o voci duplicate.
- Annunci localizzati e confronti delle missioni gestiscono meglio limiti dei messaggi, ritmo di invio, tentativi successivi, annullamenti e indicazioni sulla possibilità di condividere.
- Se un punto di passaggio nativo non viene impostato, QT non segue una vecchia puntina. I clic soggetti a restrizioni vengono rifiutati mentre QT è disabilitato, senza perdere il lavoro in coda.
- I test delle bolle sono anteprime locali. Accettano nomi completi di Forever o nomi tra virgolette senza perdere l’identità esatta del giocatore.
- Corretti attivazione e disattivazione, gestione dei profili, apertura della modalità Modifica dell’HUD, emote di festeggiamento consentite e diagnostica.
- Rafforzati isolamento dei test eseguiti in gioco e copertura delle regressioni; corrette ipotesi sbagliate nei test. La CI ora riporta correttamente gli errori di sintassi Lua.
- Superati 516 test nei due ordini su Lua 5.1 e 5.2. Passano tutti i sei profili API, i controlli di sintassi, la revisione esatta di libchev e le differenze nei file. Resa nel client, consegna fra due client e taint del motore richiedono prove separate.

## 5.9.0

Festeggia il tuo passaggio di livello e quello dei giocatori QuestTogether vicini con emote sincronizzate. Nelle impostazioni varie ci sono due opzioni separate, attive per impostazione predefinita, accanto alle emote di fine missione. Le reazioni ai giocatori vicini rispettano le regole già impostate per destinatari e distanza.

### Progressi e barre dei nomi

- Il completamento confermato di un obiettivo viene ricordato anche per tipo di creatura, non soltanto per singolo esemplare. In combattimento, una creatura appena comparsa resta senza indicazione se il tooltip non è leggibile, anche se un vecchio esemplare risultava necessario. Nuovi dati su obiettivi incompleti possono ripristinare l’evidenziazione; i cambiamenti delle missioni cancellano questa memoria. Dati parziali o inaccessibili non dimostrano mai che tutti abbiano finito.
- Quando un nemico risulta assegnato ad altri giocatori, icona di missione e colore della salute spariscono subito, anche in combattimento. QT segue i cambiamenti di assegnazione e ricontrolla durante gli aggiornamenti di salute e minaccia.
- Durante i normali combattimenti nel mondo aperto, QT riconosce nuovi nemici di missione dai dati leggibili dei tooltip. Aggiorna le barre quando tornano nell’inquadratura, diventano il bersaglio o vengono sorvolate dal mouse. Frame, GUID e righe di missione in ritardo vengono riprovati entro un limite per unità; il lavoro obsoleto è annullato quando l’unità scompare. Colore e icona tornano insieme.
- Restano i controlli per mappe, istanze, dati inaccessibili e frame protetti. La ricerca in combattimento non richiama Questie né tooltip nascosti.
- Superati 374 test offline nei due ordini su Lua 5.1 e 5.2, oltre ai sei profili API, sintassi Lua, revisione esatta della libreria e controlli delle differenze. I test sulla memoria degli obiettivi riproducevano il problema prima della correzione. Gioco reale e taint del motore richiedono verifiche separate.

## 5.8.6

Nomi dei personaggi e delle classi, titoli delle missioni e colori di classe personalizzati ora gestiscono meglio valori API inaccessibili o malformati.

### Controlli sui dati

- Le integrazioni facoltative con TomTom e Questie verificano i dati prima di usarli. La lettura delle righe dei tooltip di Questie si ferma davanti a dati inaccessibili. Visibilità delle bolle e stato della modalità Modifica vengono normalizzati a valori booleani prima di raggiungere i controlli dell’interfaccia.
- Unificato il gestore degli eventi della schermata di caricamento. Rimossi argomenti privati inutilizzati e un ramo superfluo dell’enumerazione delle restrizioni; chiarita la gestione di callback e valori restituiti. Restano intatte le alternative per client vecchi e nuovi e la revisione esatta della libreria interna.
- Superati 336 test in ordine normale e inverso su Lua 5.1 e 5.2, con controlli degli adattatori ampliati a sei profili client. I nuovi test rilevano gli errori nell’implementazione precedente. Verificati anche sintassi Lua, libreria e differenze nei file.
- Esaminati i messaggi diagnostici residui di Ketho WoW API/LuaLS, anche senza simulazioni offline dei client. Quelli mantenuti hanno motivi specifici legati a compatibilità, controlli, callback, libreria o dati di prova. La verifica del comportamento in Retail e Forever resta separata.

## 5.8.5

La ricerca di incarichi e missioni mondiali sulla mappa ora legge questID da C_TaskQuest.GetQuestsOnMap nei client recenti. Per quelli meno recenti restano disponibili la vecchia API e il campo questId.

### Compatibilità e correzioni

- Le emote di completamento preferiscono C_ChatInfo.PerformEmote, così possono funzionare anche quando le vecchie funzioni globali sono disabilitate. Le API delle emote assenti o che restituiscono errori vengono gestite in modo sicuro.
- Eliminati un calcolo inutilizzato dell’impronta del gruppo e alcune variabili locali superflue. I test offline coprono API vecchie e nuove per incarichi ed emote, le loro priorità, dati delle missioni inaccessibili e API mancanti o non funzionanti.
- Tutti i 334 test passano in ordine normale e inverso su Lua 5.1 e 5.2. Passano anche i controlli API ampliati su sei profili client, sintassi Lua e revisione esatta della libreria. Le prove di gioco su Retail e Forever restano separate.

## 5.8.4

Questo aggiornamento riguarda soltanto la pulizia del repository.

### Organizzazione dei file

- Gli appunti di sviluppo locali restano fuori dai sorgenti versionati e dai pacchetti distribuiti. Il funzionamento in gioco non cambia.

## 5.8.3

A ogni accesso o reload dell’interfaccia, un solo messaggio indica versione installata, client supportati e comando per aprire le impostazioni.

### Benvenuto e collegamenti

- I collegamenti dell’addon a CurseForge e GitHub aprono una finestra in stile WoW da cui copiare l’indirizzo. Se il collegamento o la finestra non sono disponibili, l’URL completo viene mostrato in chat.
- libchev 1.2.0 condivide fra gli addon il messaggio e la finestra di copia protetta. Un problema con la funzione di benvenuto non interrompe il normale avvio di QT.
- Superati 334 test in entrambi gli ordini su Lua 5.1 e 5.2, insieme ai controlli API dei client, sintassi Lua e revisione esatta della libreria. Le simulazioni NoPoizen provano entrambi i collegamenti sui sette profili di client e regole. La resa nel client richiede una verifica separata.

## 5.8.2

Corretti due falsi errori di /qt test: un giocatore vicino poteva occupare l’identificativo della barra del nome usato dai test di tooltip e icone in cache. Le ricerche dei GUID di prova sono ora isolate. Il comportamento delle barre dei nomi in gioco non cambia.

### Test più affidabili

- L’ambiente offline ora riproduce la collisione e i due errori senza la correzione. Con la modifica passano tutti i 333 test, nei due ordini, su Lua 5.1 e 5.2, oltre ai sei profili API dei client. La conferma nel gioco resta separata.

## 5.8.1

QuestTogether è più riconoscibile nell’elenco degli addon.

### Icona dell’addon

- Accanto a QuestTogether compare il simbolo delle missioni di Blizzard, al posto del punto interrogativo predefinito.

## 5.8.0

QuestTogether supporta i client Classic attuali con eventi di accettazione missione corretti, alternative controllate alle API degli obiettivi, metadati per ciascuna edizione e test per sei profili di client. Se non è possibile stabilire se una missione sia condivisibile, lo stato resta sconosciuto.

### Compatibilità dei client

- Restano invariati il comportamento su Retail e Forever e gli strumenti di debug condivisi.
- Superati 333 test in entrambi gli ordini su Lua 5.1 e 5.2. Verificati sei profili di client, sintassi Lua e revisioni esatte della libreria interna. Passano anche i controlli di base dei client NoPoizen e la verifica dei pacchetti. I nuovi adattatori devono ancora essere provati in gioco.
- CLIENT_COMPATIBILITY.md raccoglie le fonti esaminate, l’ambito coperto e i limiti delle verifiche.

## 5.7.7

libchev 1.1.3 mantiene le console di debug sovrapposte e i loro controlli nello stesso gruppo di finestre native. I menu delle categorie restano associati alla rispettiva console.

### Nomi e visualizzazione

- Le icone degli obiettivi vengono posizionate a sinistra delle barre dei nomi per impostazione predefinita. Le posizioni già salvate non cambiano.
- Su Forever, il tuo nome rispetta l’opzione « My Last Name ». I cognomi degli altri giocatori restano visibili, come previsto dall’impostazione nativa. Comunicazioni, appartenenza al gruppo, abbinamento alle barre dei nomi e azioni sociali usano sempre i nomi completi, senza cambiare le chiavi dei profili o delle posizioni della bolla personale.
- Corretto un annuncio locale duplicato quando il proprio messaggio tornava dal canale con un formato diverso del nome completo. I test coprono annuncio iniziale ed echi da canale e gruppo, anche con un altro personaggio dallo stesso nome di battesimo.
- Superati 331 test in entrambi gli ordini con Lua 5.1 e 5.2. Il nuovo posizionamento predefinito delle icone e l’interazione fra più finestre richiedono ancora conferma in gioco.

## 5.7.6

I tre addon ora usano la stessa console interna libchev 1.1.2. Sono stati definiti i limiti delle texture per correggere la grafica deformata della cornice nativa.

### La console condivisa

- La console offre filtri per categoria e ricerca, copia, risultati dei test e report diagnostici. Mostra gli orari quando disponibili e un solo riepilogo finale dei test.
- La libreria gestisce console e funzioni generali di debug; QuestTogether fornisce la diagnostica delle missioni e i propri test isolati. Puoi accedervi con /qt test, /qt debug o /qt diagnostics.
- Tutti i 324 test passano nei due ordini con Lua 5.1 e 5.2. L’utente ha confermato in gioco la correzione della cornice; le altre prove su restrizioni e funzionamento nel client restano separate.

## 5.7.6-beta.3

La console di debug integrata viene aggiornata a libchev 1.1.1 e torna ad avere l’aspetto delle finestre native di WoW.

### In questa beta

- Il nuovo stile riguarda la console condivisa degli addon. Eliminata anche la seconda riga di riepilogo dei test: il riepilogo finale resta nella cronologia a dimensione limitata.
- Ricerca, categorie, copia, scorrimento, test, diagnostica e controlli sulle restrizioni mantengono il comportamento precedente.
- Un utente ha confermato tutti i 324 test di QT su Forever 1.60.1, build 70009, con beta.2. Sono stati esaminati anche i sette file di test caricati in gioco: nessun caso genera NaN o divisioni per zero. Quel risultato precedente non conferma però la nuova grafica.
- Dopo /reload, apri /qtd ed esegui /qt test per controllare aspetto della finestra e singolo riepilogo. Resa grafica, restrizioni e taint di questa revisione richiedono ancora una prova nel client.
- Tutti i 324 test passano in ordine normale e inverso con gli interpreti Lua 5.1.5 e 5.2.4, con un solo riepilogo per esecuzione da riga di comando. Il ZIP installabile di 26 file, dopo l’estrazione, supera le prove su entrambi. Verificati anche i 23 file Lua, le 22 voci TOC, il manifest delle dipendenze, la formattazione e le differenze nei file.
- Revisione della libreria: 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. QT non dispone ancora di CI GitHub; i controlli CI della libreria sono riusciti.

## 5.7.6-beta.2

La console condivisa di libchev v1.1 prende il posto della finestra di debug separata di QuestTogether. È la stessa usata dagli altri addon ed è già inclusa: non occorre installarla a parte.

### In questa beta

- La console raccoglie filtri per categoria, ricerca approssimata o tra virgolette, selezione e copia, cancellazione, reload, test e diagnostica. Anche lo scorrimento che segue i nuovi eventi usa il comportamento condiviso.
- /qt test mostra i risultati attuali. Ogni nuova esecuzione sostituisce la vecchia cronologia TEST e azzera i filtri di ricerca rimasti impostati.
- /qt diagnostics [questID] e /qt diag [questID] ricostruiscono il report in cache nella stessa console, conservando gli eventi recenti entro il limite comune di esportazione.
- I controlli condivisi per restrizioni e finestre dell’addon sostituiscono i vecchi gestori della console e dei menu a discesa di QT. QuestTogether continua a occuparsi di missioni, annunci, barre dei nomi, comunicazioni e isolamento dei propri test.
- Resa grafica e taint devono ancora essere verificati in Retail e Forever. Dopo /reload esegui /qt test e /qt diagnostics, poi prova categorie, ricerca, copia, cancellazione, ridimensionamento, scorrimento, test ripetuti e passaggio fra report e registri. Usa i tuoi soliti addon e includi entrata e uscita dal combattimento e dalle altre restrizioni.
- Verifiche: 324/324 test superati in entrambi gli ordini con Lua 5.1.5 e 5.2.4; controllati i 23 file Lua, le 22 voci TOC e il manifest della libreria. Anche il pacchetto ZIP installabile, una volta estratto, supera tutti i 324 test nell’ambiente di prova offline separato. Revisione della libreria: 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

QuestTogether include libchev v1.0.0: gli addon Together possono così condividere registri, diagnostica, chiamate protette, attività differite ed esecuzione dei test. La libreria è già nel pacchetto; non serve installare altro.

### In questa beta

- I report diagnostici raccolgono le informazioni su client, addon e libreria. Quando la finestra per la copia si riempie, vengono conservati gli eventi più recenti.
- Missioni, gruppo, barre dei nomi e restrizioni restano gestiti da QuestTogether. Ogni addon mantiene separati i propri dati in memoria.
- Anche con QT disabilitato puoi usare i collegamenti alle coordinate, se le restrizioni di WoW lo consentono. Le attività in coda restano sospese e i timer ormai superati vengono scartati.
- /qt test esegue 315 casi: i 300 già presenti, dieci controlli della libreria condivisa e cinque test di regressione per l’integrazione.
- Tutti i 315 test passano in entrambi gli ordini con Lua 5.1.5 e 5.2.4. Sono verificati anche sintassi Lua, ordine di caricamento del TOC e manifest con revisioni e hash. Revisione libchev inclusa: 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- Questa è una beta: resa dell’interfaccia e possibili problemi di taint dopo la riorganizzazione devono ancora essere verificati in Retail e Forever. Dopo il reload esegui /qt test e /qt diagnostics; prova poi missioni, bolle di progresso, barre dei nomi e collegamenti alle coordinate con i tuoi soliti addon, durante combattimenti, cambi di zona, disattivazione/riattivazione e reload. La precedente conferma dei 300 test su Retail riguardava v5.7.5.
