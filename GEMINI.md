# lil agents

**lil agents** is a macOS application that brings tiny AI companions (Bruce and Jazz) to your desktop. They live just above your Dock, providing a playful, animated interface to popular AI command-line tools.

## Project Overview

- **Purpose:** A GUI wrapper for Claude Code, OpenAI Codex, and GitHub Copilot CLIs.
- **Main Technologies:** Swift, AppKit, SwiftUI, AVFoundation (transparent HEVC animations), Sparkle (auto-updates).
- **Core Concept:** Animated characters walk back and forth on the Dock; clicking them opens a themed "terminal" popover for chatting with the selected AI agent.

## Architecture

- **`LilAgentsApp.swift`**: The application entry point and `AppDelegate` implementation. Manages the system menu bar and app-level actions (switching providers, themes, etc.).
- **`LilAgentsController.swift`**: The core logic engine. Manages the animation loop using `CVDisplayLink` and calculates Dock geometry to position characters accurately on any screen.
- **`WalkerCharacter.swift`**: Handles individual character state, animation playback, and the lifecycle of the terminal popover and "thinking" bubbles.
- **`AgentSession.swift`**: Defines the protocol for interacting with AI providers.
  - `ClaudeSession.swift`: Wraps the Claude CLI using NDJSON (`--output-format stream-json`).
  - `CodexSession.swift`: Wraps the OpenAI Codex CLI.
  - `CopilotSession.swift`: Wraps the GitHub Copilot CLI.
- **`TerminalView.swift`**: A custom `AppKit` view that renders a themed terminal interface with basic Markdown support and auto-scrolling.
- **`PopoverTheme.swift`**: Centralizes styling (colors, fonts) for the terminal and popover UI.
- **`ShellEnvironment.swift`**: Utilities for locating CLI binaries and inheriting the user's shell environment (PATH, etc.).

## Key Commands

### Building and Running
- **Requirements:** macOS Sonoma (14.0+) and Xcode.
- **Build:** Open `lil-agents.xcodeproj` and build the `LilAgents` scheme.
- **Install CLI Dependencies:**
  - Claude: `curl -fsSL https://claude.ai/install.sh | sh`
  - Codex: `npm install -g @openai/codex`
  - Copilot: `brew install copilot-cli`

## Development Conventions

### Animation & UI
- **Dock Positioning:** The app dynamically calculates Dock size and position by reading `com.apple.dock` defaults.
- **Transparency:** Character animations use transparent HEVC video files (`.mov`) rendered via `AVPlayerLayer`.
- **System Level:** The app runs as an accessory (`NSApp.setActivationPolicy(.accessory)`) and uses high-level windows (`NSWindow.Level.statusBar`) to stay above other windows.

### CLI Interaction
- **Process Management:** Sessions are managed via `Foundation.Process` and `Pipe`.
- **Streaming:** The app parses standard output in real-time to provide a streaming text experience in the terminal.
- **Error Handling:** If a CLI is not found or fails to start, the app provides installation instructions directly in the chat UI.

### Theming
- Themes are defined in `PopoverTheme.swift` and can be switched dynamically.
- Characters have distinct colors and "personalities" (speed, pause duration) configured in `LilAgentsController.start()`.
