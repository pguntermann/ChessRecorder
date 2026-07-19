# Chess Recorder

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS-lightgrey.svg)]()

**Version 1.3**

Chess Recorder is an iOS app for recording chess games by voice. Speak your moves in plain language — square names, piece names, captures, castling, and undo — and the app updates the board, builds the move list, and can export games as PGN. Optional on-device engine analysis and background move assessment provide instant feedback while you record and review.

![Chess Recorder on iPad and iPhone — landscape and portrait views with board, live transcript, and engine analysis](Chess%20Recorder/Resources/Screenshots/multi_device_view1.PNG)

> **Related project:** Also check out [CARA](https://pguntermann.github.io/CARA/) — Chess Analysis and Review Application for Windows, macOS, and Linux.

**Contents:** [Features](#features) · [Requirements](#requirements) · [Building](#building) · [Usage](#usage) · [Screenshots](#screenshots) · [Project layout](#project-layout) · [License](#license) · [Contributing](#contributing) · [Contact](#contact) · [Acknowledgments](#acknowledgments)

## Features

### Voice input

- Record moves with the device microphone using Apple’s on-device speech recognition
- Chess-specific language model with common English and German move phrases
- Teach custom phrases and corrections when recognition fails
- Configurable dictation pause before a move is committed
- Live transcript with pause countdown while recording

### Board and notation

- Interactive board with optional touch input for entering moves manually
- Move navigation with scrubbing and jump controls
- ECO code and opening name in the toolbar
- Interactive opening book: browse expandable continuations from the current position
- Flip board orientation
- Customizable board colors, coordinates, piece size, and more…
- Multi-Game PGN export

### Engine analysis

- Integrated **Stockfish** analysis via [LucidEngine](https://github.com/CarlosDanielDev/lucid-engine)
- Evaluation, win probability, algebraic main line, and best-move arrow (each optional)

### Move assessment

- Background Stockfish review of played moves (separate from live analysis)
- Inaccuracy, mistake, blunder, and miss (slower forced mate) marks in the move list and PGN notation
- Optional assessment symbols in exported PGN

### Rules and game state

- Move validation and game logic via [ChessKit](https://github.com/chesskit-app/chesskit-swift)
- Undo, new game, multi-game archive, and session restore

## Requirements

- **Device:** iPhone or iPad running **iOS 26.5** or later (see `IPHONEOS_DEPLOYMENT_TARGET` in the Xcode project)
- **Development:** Xcode with Swift 5 and Swift Package Manager
- **Permissions:** Microphone and speech recognition (requested at runtime)

## Building

1. **Clone the repository**

   ```bash
   git clone https://github.com/pguntermann/ChessRecorder
   cd ChessRecorder
   ```

2. **Download Stockfish NNUE weights** (required for engine analysis)

   ```bash
   ./Scripts/fetch-stockfish-nnue.sh
   ```

   This places the network files in `StockfishNNUE/`. If you build from Xcode before the LucidEngine package is resolved, run `./Scripts/prepare-lucid-engine-nnue.sh` after a first resolve/build to copy them into the package checkout.

3. **Open and build in Xcode**

   - Open `Chess Recorder.xcodeproj`
   - Select the **Chess Recorder** scheme and a simulator or device
   - Build and run (`⌘R`)

Swift Package Manager fetches **ChessKit** and **LucidEngine** automatically.

### Command-line build (optional)

```bash
xcodebuild -scheme "Chess Recorder" -destination "platform=iOS Simulator,name=iPhone 16" build
```

Adjust the simulator name to match an installed runtime.

## Usage

1. Grant **microphone** and **speech recognition** access when prompted.
2. Tap **Record** and speak a move (e.g. `e4`, `Knight f3`, `Castle kingside`, or German equivalents such as `Springer f3`, `Kurz rochiert`).
3. Pause briefly when finished — the app waits for the configured dictation pause, then plays the move.
4. Use **Undo** by voice or tap pieces when **Touch input** is enabled in Settings.
5. Export the game from the notation panel via the share button.

In-app help (**?** in the toolbar) lists supported phrase patterns for English and German.

### Settings highlights

- Speech language (English / Deutsch) and dictation pause length
- Engine depth and which analysis overlays to show (including arrow color)
- Move assessment on/off, search depth, and quality colors (including miss)
- Whether assessment symbols are included in PGN export
- Board appearance, piece size, and touch-input highlight color
- Opening name visibility and explorer mini-board size
- Default PGN header fields and learned phrase management

## Screenshots

<p align="center">
  <img src="Chess%20Recorder/Resources/Screenshots/ipad_mini_ls1.PNG" alt="iPad landscape — live voice recording, engine analysis, and assessed PGN notation" width="80%">
</p>
<p align="center"><em>iPad — live recording with engine analysis and move assessment</em></p>

<p align="center">
  <img src="Chess%20Recorder/Resources/Screenshots/ipad_mini_pt1.PNG" alt="iPad — opening book explorer with mini-board continuations" width="80%">
</p>
<p align="center"><em>iPad — interactive opening book with mini-board previews</em></p>

<p align="center">
  <img src="Chess%20Recorder/Resources/Screenshots/ipad_pro_ls1.PNG" alt="iPad Pro — accuracy summary with move-quality pies and progress chart" width="80%">
</p>
<p align="center"><em>iPad Pro — game accuracy summary and move-quality breakdown</em></p>

<p align="center">
  <img src="Chess%20Recorder/Resources/Screenshots/iphone_promax_pt1.PNG" alt="iPhone — Manual/Touch move entering" width="36%">
</p>
<p align="center"><em>iPhone — Manual/Touch move entering</em></p>

## Project layout

| Path | Purpose |
|------|---------|
| `Chess Recorder/` | App source (SwiftUI views, speech, game logic, services) |
| `Chess RecorderTests/` | Unit tests for game logic, speech, archive, and session |
| `Chess Recorder.xcodeproj` | Xcode project and SPM package references |
| `Scripts/` | NNUE download and LucidEngine preparation scripts |
| `StockfishNNUE/` | Stockfish neural network files (not in git; fetched by script) |
| `LICENSE` | GPLv3 license for Chess Recorder |
| `THIRD_PARTY_LICENSES.md` | Third-party software and asset licenses |

## License

Chess Recorder is released under the **GNU General Public License v3.0 (GPL-3.0)**.

Stockfish is linked into the app for engine analysis, which requires GPL-compatible licensing for distributed binaries. See [LICENSE](LICENSE) for the full text and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for dependency and asset notices.

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/pguntermann/ChessRecorder). Please keep changes focused and include a short description of what you tested.

## Contact

Philipp Guntermann — [pguntermann@me.com](mailto:pguntermann@me.com)

Privacy Policy: [PRIVACY.md](PRIVACY.md)

## Acknowledgments

Chess Recorder builds on several open-source projects:

- [ChessKit](https://github.com/chesskit-app/chesskit-swift) — chess rules and move generation (MIT)
- [LucidEngine](https://github.com/CarlosDanielDev/lucid-engine) — Swift wrapper around Stockfish (GPL-3.0 engine core)
- [Stockfish](https://stockfishchess.org/) — chess engine (GPL-3.0)
- [eco.json](https://github.com/hayatbiralem/eco.json) — FEN-based ECO opening name lookup (`eco_base`, `eco_interpolated`; MIT)
- [lichess chess-openings](https://github.com/lichess-org/chess-openings) — ECO opening TSV files used as the authoritative opening data source (CC0)
- **cburnett** SVG chess pieces — [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:SVG_chess_pieces) (CC BY-SA 3.0 / GFDL 1.2)

Full license texts and attribution details are in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

---

**Copyright (C) 2026 Philipp Guntermann**

Licensed under the GNU General Public License v3.0 (GPL-3.0)
