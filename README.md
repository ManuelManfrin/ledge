# Bordi

App per macOS. I bordi del trackpad cambiano volume, luminosità e riproduzione. Gli angoli lanciano azioni. Sta nella barra dei menu, senza icona nel Dock.

macOS 13 o successivo. Non è un'app del Mac App Store: legge la posizione del dito da framework privati di sistema.

## Licenza

[PolyForm Noncommercial 1.0.0](LICENSE).

Chi riceve il programma può usarlo, modificarlo e distribuirlo solo per scopi non commerciali: uso personale, hobby, studio, ricerca, e organizzazioni come scuole, enti di beneficenza e pubblica amministrazione. Non può venderlo, né usarlo in un prodotto o un servizio fatto per ricavarci denaro, nemmeno dopo averlo modificato.

L'autore resta titolare del copyright e questa licenza non gli toglie la possibilità di concedere, a parte, un uso commerciale.

## Build

Serve Xcode o i Command Line Tools di Swift.

```bash
./build-app.sh
open Bordi.app
```

Lo script compila in release, crea `Bordi.app` e lo firma in locale (`codesign --sign -`). `Bordi.app` è un artefatto di build e non sta nel repository.

Se l'app è già aperta, chiudila dal pannello (Esci) e riapri il bundle nuovo.

## Permessi

In Impostazioni di Sistema → Privacy e sicurezza, dati a `Bordi.app`:

- **Monitoraggio input.** Senza, il trackpad non manda i contatti.
- **Accessibilità.** Senza, durante il gesto il puntatore e lo scroll della finestra sotto possono muoversi.

Dopo una nuova firma i permessi possono cadere. Si ridanno al bundle e si rilancia l'app.

Un binario firmato ad hoc viene bloccato da Gatekeeper se lo apri su un altro Mac. Su un'altra macchina va compilato in locale.

## Gesti

Coordinate da 0 a 1. A sinistra e in basso è 0.

| Zona | Dita | Gesto | Azione |
| --- | --- | --- | --- |
| Destra | 2 | slide verticale | volume |
| Sinistra | 2 | slide verticale | luminosità del pannello interno |
| Basso | 2 | swipe orizzontale | brano successivo o precedente |
| Basso | 1 | doppio tap | play / pausa, se l'angolo non ha un'azione sua |
| Quattro angoli | 1 | doppio tap | azione scelta nel pannello |

Il dettaglio di soglie, priorità degli angoli e azioni è in [HANDOFF.md](HANDOFF.md). La nota di prodotto da cui è partita l'app è in [COSA-SI-PUO-FARE.md](COSA-SI-PUO-FARE.md).
