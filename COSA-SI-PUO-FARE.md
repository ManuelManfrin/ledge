# Trackpad a zone

Nota di prodotto precedente. Lo stato attuale del codice, come si builda e dove sta ogni gesto, è in `HANDOFF.md`.

App solo per questo Mac. Fuori dal Mac App Store, perché la posizione del dito sul trackpad non è un'API pubblica.

La bozza in `Sources/Ledge/main.swift` usa due dita sul bordo: destro per il volume, sinistro per la luminosità. Il doppio tap in alto a destra mette e toglie il mute. Il vincolo ⌘ è nel codice (`requireCommand`) ma è spento.

## Come si leggono le dita

`NSEvent` e le gesture di sistema arrivano già interpretate (scroll, swipe, pinch) e non dicono *dove* sta il dito.

La posizione arriva da `MultitouchSupport.framework`, privato, caricato a runtime con `dlopen`. Ogni contatto ha:

- `x` e `y` normalizzati da 0 a 1 (0 è sinistra e basso)
- un id che resta lo stesso finché il dito è giù
- lo stato (appoggiato, mosso, sollevato)
- dimensione ed ellisse del contatto, utili per scartare il palmo

Su Apple Silicon `MTDeviceCreateDefault()` spesso non è il trackpad vero. La bozza enumera i device e tiene quelli con una griglia di almeno 10 righe. Il Magic Trackpad esterno passa dallo stesso framework. Un mouse no.

Il layout della struct è quello ricostruito dalla community e usato da app come EdgePad. Se un giorno le coordinate escono fuori da 0…1, è cambiato il layout e va riallineato. Non è un'API stabile.

## Cosa si può mappare

Ogni zona è un rettangolo in coordinate 0…1, più un gesto (slide, tap, doppio tap) e un'azione.

| Zona | Gesto | Azione realistica |
| --- | --- | --- |
| Bordo destro | scroll verticale a due dita | volume |
| Bordo sinistro | scroll verticale a due dita | luminosità del display interno |
| Bordo inferiore | slide orizzontale | traccia avanti / indietro, oppure scroll orizzontale |
| Bordo superiore | slide orizzontale | seek nel player in primo piano |
| Angolo alto a destra | doppio tap con un dito | mute, e di nuovo per riattivare |
| Angolo | tap | play / pausa |
| Qualsiasi bordo | slide a due dita | lasciare la gesture di sistema, non rubarla |

Azioni comode da collegare, tutte già usate da tool di questo tipo:

- volume e mute, con la barra nativa (OSD)
- luminosità, stessa barra
- play, pausa, traccia dopo e prima
- scorciatoia da tastiera verso l'app davanti
- scroll verticale o orizzontale nella finestra attiva
- Mission Control, scrivanie, finestra a pieno schermo
- azione diversa a seconda dell'app davanti

Dettagli che rendono la cosa usabile, e che la bozza fa solo in parte:

- **Zona stretta.** 6–10% del bordo. Più larga ruba i click normali.
- **Soglia di movimento.** Un tap sul bordo destro resta un click. Il volume parte solo dopo qualche millimetro in verticale.
- **Solo un dito.** Due o più dita annullano il gesto e tornano a scroll e swipe di sistema.
- **Cursore fermo.** Quando il gesto parte, il puntatore si stacca dal dito (`CGAssociateMouseAndMouseCursorPosition`) e si riattacca al rilascio. Senza questo lo slide sposta il mouse.
- **Palmo.** Contatti molto larghi o molto ovali si ignorano, così il polso appoggiato in basso non cambia il volume.
- **Passo fine.** Con ⌥ tenuto, lo stesso movimento del dito sposta il livello di un decimo.
- **Haptic.** Se acceso, a ogni tacca c'è un solo tocco, il più lieve. La scala di intensità è ancora nel codice e non viene usata.
- **Solo il quarto inferiore.** Lo slide del volume vale solo se il dito parte nella parte bassa del bordo, così il resto del trackpad resta libero.

## Cosa è fragile

- **Aggiornamenti di macOS.** Il framework privato può cambiare struct o nomi. La bozza fallisce in modo visibile (niente device, coordinate assurde) invece di indovinare.
- **Permesso Monitoraggio input.** Senza, il callback non riceve contatti. Si dà a Terminale, oppure al binario `.build/debug/Ledge`, in Impostazioni di Sistema → Privacy e sicurezza → Monitoraggio input. Dopo averlo aggiunto va rilanciato.
- **Stacco del cursore.** Può chiedere Accessibilità. All'uscita con Ctrl-C la bozza riattacca il cursore. Se il processo viene ucciso a forza mentre un gesto è attivo, il puntatore resta fermo: si sistema muovendo un mouse esterno o rilanciando la bozza, che all'avvio riattacca il cursore.
- **Firma.** Per uso personale basta l'eseguibile locale. Un `.app` distribuito ad altri vuole Developer ID e notarizzazione, altrimenti Gatekeeper lo blocca.
- **Display esterno.** La luminosità via API di sistema vale per il pannello del Mac. Un monitor esterno spesso ignora quel valore.

## Cosa non vale la pena

- Pubblicarla sul Mac App Store. Con questo framework viene rifiutata.
- Disegnare una barra del volume nostra. Quella di sistema (`OSD.framework`, la stessa dei tasti F) è già giusta.
- Intercettare lo scroll a due dita per trasformarlo in volume. È il gesto che si usa di continuo. Il bordo a un dito sta fuori dai piedi.

## La bozza

`Ledge` resta in foreground nel terminale. Un dito solo muove il puntatore come sempre. Il controllo ⌘ è `requireCommand` in cima al sorgente: ora vale `false`.

1. Due dita sul bordo. Il dito più esterno sta nell'8% del bordo, l'altro può arrivare fino al 30% verso il centro. Destra è il volume, sinistra la luminosità.
2. Per tutta la durata il puntatore resta fermo e lo scroll della finestra sotto non parte. Servono i permessi Monitoraggio input e Accessibilità, altrimenti il sistema continua a muovere puntatore e pagina.
3. Dopo un movimento verticale di almeno il 2,5% dell'altezza, su alza e giù abbassa.
4. Con ⌥ tenuto, ogni millimetro vale un decimo.
5. Due dita sul bordo in basso: swipe verso destra, brano successivo; verso sinistra, il brano ricomincia. Doppio tap con un dito in basso, play / pausa.
6. Doppio tap con un dito in un angolo lancia l'azione scelta nel tab Angoli. Alto destra parte come mute / unmute. Play, pausa e cambio brano non sono tra le azioni degli angoli.
7. Sollevare una dita chiude il gesto e il cursore torna normale.

Il volume è quello dell'uscita audio predefinita, via CoreAudio. La luminosità è quella del pannello interno, via DisplayServices. La barra a 16 segmenti è `OSDManager`. Se una di queste API manca, il resto continua e nel terminale resta il log.

```bash
./build-app.sh
open Ledge.app
```

L'app sta solo nella barra dei menu, senza icona nel Dock. Il pannello ha pausa, richiesta di ⌘, aptica, avvio al login, larghezza dei bordi e sensibilità. `swift run Ledge` apre la stessa interfaccia da terminale.

I permessi (Monitoraggio input e Accessibilità) vanno dati a `Ledge.app`, non al vecchio binario.

## Dopo la bozza

Ordine sensato, un pezzo alla volta:

1. Menu bar, avvio al login, larghezza del bordo e sensibilità regolabili.
2. Bordo alto → seek nel player in primo piano.
