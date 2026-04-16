# WhisperServer – Code-Struktur (Notizen)

Dieses Dokument beschreibt die **Swift-App** im Ordner `WhisperServer/`: eine **macOS-Menüleisten-Anwendung**, die lokal einen **HTTP-Server** (Vapor) startet und eine **OpenAI-kompatible Transkriptions-API** bereitstellt (`/v1/audio/transcriptions`, `/v1/models`). Zwei Back-Ends sind möglich: **whisper.cpp** (lokale `.bin`-Modelle) und **FluidAudio** (CoreML ASR, optional mit Diarisierung).

---

## Gesamtfluss

1. **`WhisperServerApp`** / **`AppDelegate`**: Einstieg, `.accessory` (nur Menüleiste, kein Dock-Icon), verdrahtet die vier Hauptkomponenten.
2. **`ModelManager`**: Modelle laden/auswählen, Downloads, Pfade, Status; feuert `NotificationCenter`-Events.
3. **`ModelObserver`**: Reagiert auf Modell-Events → startet/stoppt Server, Menüleisten-Texte, Shader-Preload, Fortschritt.
4. **`ServerCoordinator`**: Lebenszyklus von **`VaporServer`** (Port standard **12017**), bei Modellwechsel **`WhisperTranscriptionService.reinitializeContext()`**.
5. **`MenuBarService`**: `NSStatusItem`, Menü (Server-Status, Modell, Download, Fortschritt), Icons/Tooltips.
6. **`VaporServer`**: Routen, Request-Warteschlange, Temp-Dateien, Streaming (SSE optional), Providerwahl Whisper vs. Fluid.

---

## Dateien in `WhisperServer/` (eine Rolle pro Datei)

| Datei | Rolle |
|--------|--------|
| **`WhisperServerApp.swift`** | `@main` SwiftUI-`App` mit minimalem `Settings`-Scene; eigentliche Logik im **`AppDelegate`**: Services erzeugen, gegenseitig verbinden, beim Launch Menüleiste + Modell-UI + Server starten, beim Beenden Server stoppen und Whisper aufräumen. |
| **`ServerCoordinator.swift`** | Hält optional eine **`VaporServer`**-Instanz; `startServer` / `stopServer` / `restartServer`; informiert **`MenuBarService`** über Lauf-Status und Port; bei Terminierung **`WhisperTranscriptionService.cleanup()`**. |
| **`VaporServer.swift`** | Vapor-`Application`: Bind an Host (Default **`0.0.0.0`**) und Port; **`TranscriptionRequestQueue`** (Actor): **nur eine Transkription gleichzeitig**; Routen **`GET /v1/models`**, **`POST /v1/audio/transcriptions`**; schreibt Upload in **Temp-Datei**, räumt auf; parst `response_format`, `stream`, `model`, `diarize`; wählt **Provider** `.whisper` oder `.fluid`; Streaming mit **`Response.Body(stream:)`**, SSE wenn `Accept: text/event-stream`; beendet SSE mit **`event: end`**; **`ProgressTracker`**: meldet Fortschritt über **`WhisperTranscriptionService.reportTranscriptionProgress`** (deinit setzt Verarbeitung auf fertig). |
| **`ModelManager.swift`** | Zentrale Modell-Verwaltung: **`Provider`** (whisper/fluid), **`@Published`** `availableModels`, `selectedModelID`, `selectedProvider`, `currentStatus`, `downloadProgress`, `isModelReady`; Verzeichnisse, Downloads (`URLSession`), Vorbereitung **`prepareModelForUse`**, UserDefaults-Persistenz; Fehler-Enums; im DEBUG optional **`resetAllData`**. |
| **`ModelObserver.swift`** | **`NotificationCenter`**: Modell bereit / fehlgeschlagen / Status / Download-Fortschritt / Transkriptions-Fortschritt / Metal aktiv / Tiny-Auto-Select; steuert **`MenuBarService`** und startet/stoppt **`ServerCoordinator`** je nach Download und Erfolg; **`preloadMetalShaders`** im Hintergrund für Whisper. |
| **`MenuBarService.swift`** | **`NSStatusBar`**: Status-Button, Menüeinträge (Server, Modellstatus, Download-%, Transkriptions-%, Aktionen wie Provider/Modell, DEBUG-Reset), Symbolwechsel bei Verarbeitung, Tooltips (inkl. „Caching shaders…“, GPU-Fallback). |
| **`WhisperTranscriptionService.swift`** | Öffentliche API für **whisper.cpp**: `transcribeAudio`, `transcribeAudioStream`, `transcribeAudioWithTimestamps`, `transcribeAudioStreamWithTimestamps`; delegiert Formatierung an **`WhisperSubtitleFormatter`**, Kontext an **`WhisperContextManager`**, Audio an **`WhisperAudioConverter`**; konfigurierbare **VAD-/Chunking**-Parameter; **`reportTranscriptionProgress`** → Notification für die Menüleiste. |
| **`WhisperContextManager.swift`** | **Ein** geteilter **`whisper` Kontext** (`OpaquePointer?`) mit Lock; **Inaktivitäts-Timer** gibt Ressourcen frei; Metal-Shader-Cache-Pfad unter Application Support; **`preloadModelForShaderCaching`**, **`reinitializeContext`**, **`cleanup`**. |
| **`WhisperAudioConverter.swift`** | **AVFoundation**: Eingabe → **16 kHz Mono Float32** für Whisper; enthält **VAD**-Hilfen (`SpeechSegment` etc.) für intelligentes Chunking. |
| **`WhisperSubtitleFormatter.swift`** | Gemeinsame Typen: **`TranscriptionSegment`**, **`ResponseFormat`** (`json`, `text`, `verbose_json`, `srt`, `vtt`); Zeitstempel- und SRT/VTT/verbose_json-Formatierung. |
| **`FluidTranscriptionService.swift`** | **FluidAudio** (`AsrModels`, `AsrManager`): **`transcribeAudio`** liefert **`TranscriptionResult`** (Text, Segmente aus Token-Timings, optional **`speaker_segments`** bei **`includeDiarization`**); festes **`ModelDescriptor`**-Katalog-Feld (z. B. Parakeet TDT v3); Cache-Pfade unter Application Support. |
| **`WhisperNotifications.swift`** | Zentrale **`Notification.Name`**-Extensions und Keys für Transkriptions-Fortschritt (vermeidet String-Literale überall). |
| **`ContentView.swift`** | SwiftUI-Platzhalter (App ist praktisch **nur Menüleiste**); für Xcode/Previews. |

---

## HTTP-API (Kurz)

- **`GET /v1/models`**: Liste installierbarer/konfigurierter Whisper-Modelle plus FluidAudio-Modelle; Felder u. a. `provider`, `supports_streaming`, `default`.
- **`POST /v1/audio/transcriptions`**: Multipart mit **`file`**, optional `language`, `prompt`, `response_format`, `stream`, `model`, `diarize`.
  - **Whisper**: alle genannten Formate; **Streaming** für `json`/`text` (Text-Chunks) und für `srt`/`vtt`/`verbose_json` (Segment-weise; nur Whisper).
  - **Fluid**: nicht-streamende SRT/VTT/verbose_json; Streaming nur **json/text** (ein Chunk am Ende). **`diarize`** ergänzt **`speaker_segments`** im JSON.

---

## Abhängigkeiten / Repo-Rand

- **`WhisperServer.xcodeproj`**: Xcode-Build, SPM-Abhängigkeiten (u. a. **Vapor**, **whisper**, **FluidAudio**).
- **`test_api.sh`**, **`jfk.wav`**: Smoke-Tests per `curl` (laufende App auf Port 12017).
- **`AGENTS.md`**: Projektrichtlinien für Agenten/Mitwirkende (Stil, Sicherheit, Tests).

---

## Wichtige Design-Entscheidungen

- **Eine Transkription zur Zeit** (`TranscriptionRequestQueue`), um GPU/RAM und whisper-Kontext stabil zu halten.
- **Temp-Dateien** werden bei Fehlern und nach nicht-streamenden Requests gelöscht; Streaming räumt in **`finishStream`** / Completion auf.
- **Modellwechsel** (Whisper): `activeWhisperModelID` in `VaporServer` + **`reinitializeContext`** wenn die Auswahl nicht mehr passt.
- **UI** ist bewusst **AppKit-Menüleiste**; SwiftUI nur für App-Shell und Preview.

---

*Erstellt als Lesehilfe zur Codebasis; bei Abweichungen zum Code gilt immer der Quelltext.*
