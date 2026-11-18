# BudsBar

Steuere deine **Samsung Galaxy Buds** direkt vom Mac aus – über ein kleines Symbol in der Menüleiste.

> BudsBar ist ein inoffizielles Open-Source-Projekt und steht in keiner Verbindung zu Samsung.
> „Samsung“ und „Galaxy Buds“ sind Marken der Samsung Electronics Co., Ltd.

## Funktionen

- 🔋 Akkustand von linkem und rechtem Ohrhörer und vom Case (inkl. Ladeanzeige)
- 🎧 Geräuschsteuerung: ANC · Umgebungsgeräusche · Aus
- 🎚️ Equalizer-Presets
- ✋ Touch-Steuerung sperren und „Berühren und halten“ belegen
- 🔊 Ohrhörer finden: Ton abspielen und Signalstärke („sehr nah“ … „weiter entfernt“)
- 🗺️ Karte „Zuletzt gesehen“: wo dein Mac war, als die Buds zuletzt verbunden waren (bleibt nur auf deinem Mac)
- Verbindet sich automatisch, sobald die Buds mit dem Mac verbunden sind
- Keine Datensammlung – Standort und Einstellungen bleiben auf deinem Mac

**Voraussetzung:** macOS 14 (Sonoma) oder neuer.

**Getestet mit:** Galaxy Buds3 Pro / Buds3. Andere Modelle ab Buds+ funktionieren vermutlich teilweise.

## Installation

1. Lade die neueste `BudsBar-x.y.z.dmg` unter [Releases](../../releases) herunter.
2. Öffne die DMG und ziehe **BudsBar** in den Ordner **Programme**.
3. Kopple deine Buds vorher normal unter *Systemeinstellungen → Bluetooth* mit dem Mac.
4. Starte BudsBar und erlaube den Bluetooth-Zugriff (und den Standortzugriff für die Karte).

### „Apple konnte nicht überprüfen …“

Ist die Release nicht von Apple notarisiert, zeigt macOS beim ersten Start diese Warnung. Einmalig freigeben:

1. BudsBar öffnen → Meldung mit **Fertig** schließen.
2. *Systemeinstellungen → Datenschutz & Sicherheit* öffnen, nach unten scrollen.
3. Bei „BudsBar wurde blockiert“ auf **Trotzdem öffnen** klicken und bestätigen.

Danach startet die App ganz normal.

## Selbst bauen

Voraussetzung: macOS 14 oder neuer und die Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/meherkaushal004-sudo/Galaxy-Wearable-for-MAC.git
cd Galaxy-Wearable-for-MAC
./scripts/build-dmg.sh
open build/BudsBar.app
```

Selbst gebaute Apps zeigen keine Gatekeeper-Warnung.

## Wie funktioniert das?

Die Buds sprechen über einen eigenen Bluetooth-Kanal (RFCOMM) ein Samsung-Protokoll. BudsBar nutzt
Apples `IOBluetooth`-Framework, um diesen Kanal zu öffnen. Die Protokolldetails stammen aus dem
großartigen Reverse-Engineering-Projekt [GalaxyBudsClient](https://github.com/timschneeb/GalaxyBudsClient)
von Tim Schneeberger – vielen Dank!

Protokoll-Selbsttest ohne Ohrhörer:

```bash
swift run BudsBar --selftest
```

## Mitmachen

Fehler gefunden oder ein anderes Modell getestet? Eröffne gern ein [Issue](../../issues) –
mit Modellname und, wenn möglich, was nicht funktioniert hat.

## Lizenz

[GPL-3.0](LICENSE)
