# Chess Recorder

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS-lightgrey.svg)]()

**Version 1.0** · [GitHub repository](https://github.com/pguntermann/ChessRecorder)

Chess Recorder is an iOS app for recording chess games by voice. Speak your moves in plain language — square names, piece names, captures, castling, and undo — and the app updates the board, builds the move list, and can export the game as PGN. Optional on-device engine analysis shows evaluation, a principal variation, and a best-move arrow while you record.

**Contents:** [Features](#features) · [Requirements](#requirements) · [Building](#building) · [Usage](#usage) · [Project layout](#project-layout) · [License](#license) · [Contributing](#contributing) · [Contact](#contact) · [Acknowledgments](#acknowledgments)

## Features

### Voice input

- Record moves with the device microphone using Apple’s on-device speech recognition
- Chess-specific language model with common English and German move phrases
- Teach custom phrases and corrections when recognition fails
- Configurable dictation pause before a move is committed
- Live transcript with pause countdown while recording

### Board and notation

- Interactive board with optional touch input for manual moves
- Move list and PGN export (share sheet)
- Flip board orientation
- Customizable board colors, coordinates, and piece size

### Engine analysis

- Integrated **Stockfish** analysis via [LucidEngine](https://github.com/CarlosDanielDev/lucid-engine)
- Evaluation bar, algebraic main line, and best-move arrow (each optional)

### Rules and game state

- Move validation and game logic via [ChessKit](https://github.com/chesskit-app/chesskit-swift)
- Undo, new game, and PGN archive support

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

- Speech language (English / Deutsch) and dictation pause
- Engine analysis visibility, depth, evaluation bar, algebraic line, and arrow
- Board appearance and touch input
- Learned phrases and corrections

## Project layout

| Path | Purpose |
|------|---------|
| `Chess Recorder/` | App source (SwiftUI views, speech, game logic, services) |
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

## Acknowledgments

Chess Recorder builds on several open-source projects:

- [ChessKit](https://github.com/chesskit-app/chesskit-swift) — chess rules and move generation (MIT)
- [LucidEngine](https://github.com/CarlosDanielDev/lucid-engine) — Swift wrapper around Stockfish (GPL-3.0 engine core)
- [Stockfish](https://stockfishchess.org/) — chess engine (GPL-3.0)
- **cburnett** SVG chess pieces — [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:SVG_chess_pieces) (CC BY-SA 3.0 / GFDL 1.2)

Full license texts and attribution details are in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

---

**Copyright (C) 2026 Philipp Guntermann**

Licensed under the GNU General Public License v3.0 (GPL-3.0)
