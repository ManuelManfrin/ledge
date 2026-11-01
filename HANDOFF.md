# Handoff — Bordi

App personale da barra dei menu. I bordi del trackpad cambiano volume, luminosità e riproduzione. Gli angoli lanciano azioni. Non va sul Mac App Store: legge la posizione del dito da un framework privato.

Percorso: `/Users/manuel/Progetti/trackpad-bordi`. Bundle `it.manuel.bordi`, nome visibile Bordi, versione 0.1. Minimo macOS 13. `LSUIElement` è vero: niente icona nel Dock.

`COSA-SI-PUO-FARE.md` è la nota di prodotto da cui è partita la bozza. Questo file descrive il codice com'è ora.

## Avvio

```bash
cd /Users/manuel/Progetti/trackpad-bordi
./build-app.sh
open Bordi.app
```

`build-app.sh` fa `swift build -c release`, copia il binario `volume-bordo` in `Bordi.app/Contents/MacOS/Bordi`, ci mette `Support/Info.plist` e firma ad hoc (`codesign --sign -`). `swift run volume-bordo` apre la stessa interfaccia, ma è un altro processo: i permessi dati all'app non valgono per lui, e l'avvio al login funziona solo sul bundle.

Se l'app è già aperta, `open` non sostituisce il processo. Dopo una build va chiusa dal pannello (Esci) oppure con `pkill -x Bordi`, poi riaperta.

Permessi, in Impostazioni di Sistema → Privacy e sicurezza, dati a `Bordi.app`:

- **Monitoraggio input.** Senza, il callback del trackpad non riceve contatti. Il pannello dice che nessun trackpad è in ascolto.
- **Accessibilità.** Senza, l'event tap non nasce. Volume e luminosità cambiano lo stesso, ma il puntatore e lo scroll della finestra sotto possono muoversi durante il gesto.

Un aggiornamento di macOS o una nuova firma può far cadere i permessi. Vanno ridati al bundle, poi l'app va rilanciata.

## File

| File | Ruolo |
| --- | --- |
| `Package.swift` | Un solo target eseguibile, `volume-bordo`. Framework: AppKit, SwiftUI, CoreAudio, IOKit, ServiceManagement. |
| `Sources/volume-bordo/main.swift` | Trackpad, volume, luminosità, barra di sistema, aptica, gesto. |
| `Sources/volume-bordo/CornerActions.swift` | Azioni degli angoli e comandi Now Playing. |
| `Sources/volume-bordo/Settings.swift` | Impostazioni, UserDefaults, enum di angoli e azioni. |
| `Sources/volume-bordo/PopoverView.swift` | Pannello SwiftUI, due tab. |
| `Sources/volume-bordo/AppMain.swift` | `NSApplication`, icona in menu bar, popover. |
| `Support/Info.plist` | Identità del bundle. |
| `build-app.sh` | Produce `Bordi.app`. |
| `Bordi.app` | Build locale già firmata. Non è sorgente. |

`AppDelegate` è trattenuto da una variabile globale in `main.swift` perché `NSApplication.delegate` è weak. All'avvio riattacca il cursore (`CGAssociateMouseAndMouseCursorPosition(1)`), così un processo ucciso a metà gesto non lascia il puntatore fermo.

## Gesti

Coordinate normalizzate 0…1. `x` 0 è sinistra, `y` 0 è basso. Un dito è il puntatore, più i tap. Due dita sono le barre. Tre o più dita annullano il gesto.

La zona a due dita chiede che il dito più esterno sia nella fascia stretta e l'altro entro la fascia larga. Due dita affiancate non entrano in una striscia dell'8%.

| Zona | Dita | Gesto | Azione |
| --- | --- | --- | --- |
| Destra | 2 | slide verticale | volume. Su alza. |
| Sinistra | 2 | slide verticale | luminosità del pannello interno. Su alza. |
| Basso | 2 | swipe orizzontale | media. Verso destra, brano successivo. Verso sinistra, comando "precedente" della sessione in riproduzione (in genere il brano o il video ricomincia). |
| Basso | 1 | doppio tap | play / pausa, se l'angolo non ha un'azione sua. |
| Quattro angoli | 1 | doppio tap | azione scelta nel tab Angoli. |

Soglie, fisse in cima a `main.swift`:

- Il volume e la luminosità partono dopo uno spostamento verticale di `armDistance` (0,025). Prima il cursore è già fermo, il livello no.
- Lo swipe media parte dopo `mediaSwipeDistance` (0,08) e scatta una volta sola. Per ripeterlo bisogna sollevare le dita.
- Un tap vale se dura meno di `tapMaxDuration` (0,25 s) e il dito si sposta meno di `tapTravel` (0,02). Il secondo tap deve arrivare entro `doubleTapGap` (0,40 s) e nello stesso bersaglio.
- Il quadrato d'angolo è `cornerSize` (0,16) da ogni bordo. Il doppio tap di play/pausa usa invece l'altezza della fascia larga in basso (`bottomReach`).
- `⌥` moltiplica lo spostamento di volume e luminosità per `fineScale` (0,1). Si può premere a metà gesto: il livello non salta, perché il delta è incrementale.
- `⌘` è facoltativo. `requireCommand` è `false`. Il controllo è in `Engine.handle` e nel toggle del pannello.
- La sensibilità di default è 1,8: tutta l'altezza del trackpad copre la scala, con un po' di guadagno. Range nel pannello: 0,8…3,0.
- Un contatto con `size > 1,2` o rapporto degli assi sopra 2,4 è trattato come palmo e ignorato.

Priorità negli angoli in basso, dove la barra laterale e quella bassa si incrociano. Impostazione `cornerPriority`:

- `bottom` (default, etichetta "In basso"): se le due dita sono nella fascia bassa, è media anche nell'angolo.
- `sides` (etichetta "Laterali"): se le due dita sono anche nella fascia sinistra o destra, comandano luminosità o volume. Il media resta nel tratto centrale del bordo basso.

Il doppio tap è un'altra regola. Se l'angolo ha un'azione diversa da "Nessuna", quel doppio tap fa l'azione e non il play/pausa. Alto destra parte come mute / unmute. Gli altri tre partono vuoti.

Durante una barra a due dita il puntatore si stacca (`CGAssociateMouseAndMouseCursorPosition(0)`) e ogni frame viene riportato al punto salvato. Un event tap di sessione, inserito in testa, ingoia `scrollWheel`, `mouseMoved` e i drag del mouse finché `captureGesture` è vero. Al rilascio di una dita, o se le dita escono dalla fascia, il cursore si riattacca. Lo stesso succede se `requireCommand` è acceso e si molla il ⌘.

## Pannello

Popover transiente dall'icona del trackpad. Si apre sul mouse up, così il click fuori non lo riapre subito. Due tab.

**Bordi.** Disegno del trackpad (arancio luminosità, blu volume, verde media). Lo spessore disegnato segue gli slider. Se negli angoli prevalgono i lati, le fasce laterali vengono disegnate sopra quella bassa.

- Gesti attivi. Se spento, `handle` chiude ogni gesto.
- Richiedi ⌘.
- Feedback aptico. Default spento.
- Apri al login, via `SMAppService.mainApp`. Fallisce se il processo non è `Bordi.app`.
- Bordo laterale e seconda dita dei lati.
- Spessore in basso e seconda dita in basso. Indipendenti dai lati.
- Priorità degli angoli in basso.
- Sensibilità.

**Angoli.** Un menu per angolo. "Apri un'app" apre `NSOpenPanel` su `/Applications` e salva il path.

Slider: bordo esterno 4…16%, seconda dita 12…45%, con la seconda dita sempre almeno 4 punti sopra il bordo esterno. Stessi limiti per il basso.

## Azioni

| Azione | Come |
| --- | --- |
| Mute / unmute | `kAudioDevicePropertyMute` sull'uscita di default, più la barra di sistema. |
| Play / pausa, successivo, precedente | `MRMediaRemoteSendCommandWithReply` in `MediaRemote.framework`. Comandi `2`, `4`, `5`. È la sessione Now Playing, la stessa del Centro di Controllo: ci entra anche YouTube nel browser, se il Centro di Controllo mostra quel video. Se il simbolo manca si usa `MRMediaRemoteSendCommand`. Se manca anche quello, si simulano i tasti HID 16, 17 e 18, che il browser di solito ignora. |
| Blocca il Mac | `SACLockScreenImmediate` in `login.framework`. In mancanza, `CGSession -suspend`. |
| Siri | apre `/System/Applications/Siri.app`. |
| Mission Control | `CoreDockSendNotification("com.apple.expose.awake")`, altrimenti l'app Mission Control. |
| Mostra la scrivania | `com.apple.showdesktop.awake`, altrimenti il tasto F11 (key code 103), che dipende dalle scorciatoie del Mac. |
| Spegni lo schermo | `pmset displaysleepnow`. |
| Apri un'app | `NSWorkspace` sul path salvato. |

Volume e luminosità non passano da questi comandi.

- Volume: `kAudioDevicePropertyVolumeScalar` sull'uscita predefinita. Si prova l'elemento master, poi i canali 1 e 2. Scrivere il volume toglie il mute.
- Luminosità: `DisplayServicesGetBrightness` / `DisplayServicesSetBrightness` sul display interno (`CGDisplayIsBuiltin`). Un monitor esterno di solito non segue quel valore.
- Barra di sistema: `OSDManager showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:`. Grafica 1 luminosità, 3 volume, 4 mute. 16 segmenti, priorità `0x1F4`, fade 1000 ms. Se la classe sparisce, il livello cambia lo stesso.

## Aptica

`Haptics` apre l'attuatore Force Touch con `MTActuatorCreateFromDeviceID` / `Open` / `Actuate` / `Close`. L'handle vale un colpo: si ricrea a ogni tick. L'id del device è il `UInt64` a offset 64 nell'oggetto multitouch, con riserva sugli `mt-device-id` di `AppleMultitouchDevice` nell'IORegistry.

La scala di waveform è ancora in `ladder`: 4, 1, 15, 5, 6, 2, 16, dal tocco leggero al colpo pieno. `tick` usa solo il primo, il 4. Con `hapticsEnabled` false non parte nulla, ma simboli e device si preparano all'avvio così il toggle ha effetto subito.

## Come si leggono le dita

`MultitouchSupport.framework`, caricato con `dlopen`. Su disco il binario è uno stub nella dyld shared cache: `nm` non lo vede, a runtime `dlopen` sì.

`MTDeviceCreateDefault()` su Apple Silicon spesso non è il trackpad. Si usa `MTDeviceCreateList` e si scartano le griglie con meno di 10 righe (sensori ausiliari). Il Magic Trackpad passa dallo stesso framework. Un mouse no.

`MTData` è il layout ricostruito, 96 byte, con il padding davanti al `Double` del timestamp. `MemoryLayout` all'avvio deve restare 96. Se le coordinate escono da 0…1, è cambiato il layout, non la matematica del gesto. Stati usati: 1 e 3 appoggio, 4 e 6 contatto, 5 e 7 rilascio. Il 2 è hover e si ignora. Questo mapping è quello con cui il volume ha funzionato su questo Mac; non va "allineato" a mappe diverse senza una prova sul trackpad.

## Impostazioni salvate

`UserDefaults.standard`. Dentro `Bordi.app` il dominio è `it.manuel.bordi`.

| Chiave | Default |
| --- | --- |
| `enabled` | true |
| `requireCommand` | false |
| `hapticsEnabled` | false |
| `edgeWidth` | 0,08 |
| `twoFingerEdge` | 0,30 |
| `bottomEdge` | 0,08 |
| `bottomReach` | 0,30 |
| `cornerPriority` | `bottom` |
| `sensitivity` | 1,8 |
| `cornerActions` | alto destra = `mute`, gli altri assenti (contano come `none`) |
| `cornerApps` | dizionario angolo → path |

`cornerActions` e `cornerApps` sono dizionari con chiave `topLeft`, `topRight`, `bottomLeft`, `bottomRight`. I raw delle azioni sono i case di `CornerAction`. Play, pausa e cambio brano sono stati tolti da quell'enum: un valore vecchio in UserDefaults non decodifica e l'angolo diventa "Nessuna".

## Cosa non toccare alla leggera

- Il layout di `MTData` e la soglia delle 10 righe.
- `MTActuatorOpen(actuator, 0)`: il secondo argomento c'è. I tre argomenti dopo il waveform sono `UInt32`, non `Float`, altrimenti su arm64 finiscono nei registri sbagliati.
- Non chiamare insieme `MRMediaRemoteSendCommandWithReply` e `MRMediaRemoteSendCommand` per lo stesso gesto. Il primo, se c'è, è l'unico che parte. Due invii togglerebbero due volte e il play/pausa sembrerebbe morto.
- Non ingoiare click e mouse down nell'event tap. Si ingoiano solo movimento e scroll, e solo mentre un gesto a due dita è attivo.
- La firma ad hoc cambia a ogni build. Il TCC può richiedere di nuovo i permessi.

## Limiti noti

- La luminosità non pilota un monitor esterno.
- "Mostra la scrivania" di riserva è F11, non la scorciatoia che l'utente ha cambiato.
- Lo swipe a sinistra manda il comando previous della sessione. L'app decide se ricominciare il brano o passare al precedente. È lo stesso comportamento del tasto nel Centro di Controllo.
- Se il Centro di Controllo non mostra il video, non lo vede neanche Bordi.
- Non c'è bordo superiore, né seek continuo, né menu extra oltre al popover.
- Nessun test automatico. La verifica è sul trackpad: due dita sul bordo, doppio tap, e il puntatore che torna al rilascio.

## Da qui

Ordine già sensato, se si continua: bordo alto per il seek, icone e avvio al login già abbozzati da rifinire, e una prova esplicita che `MRMediaRemoteSendCommandWithReply` su questo macOS restituisce diverso da zero. Se nel log compare "MediaRemote non ha accodato il comando", il play/pausa sta no-op e va usata solo l'altra funzione, non entrambe.
