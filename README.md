# Flowcap

![macOS](https://img.shields.io/badge/macOS-14.2+-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

A macOS menu bar app that records your screen and uses AI to generate workflow documentation automatically.

Press Ctrl+Option+R, do your work as usual, and Flowcap captures screenshots every 4 seconds. When you stop, Gemini 2.5 Flash analyzes the sequence and generates a step-by-step workflow document.

https://github.com/user-attachments/assets/137b3ca2-aed9-4a2a-8a5a-bd9b637b6a47

## Output Formats

| Format | Description |
|--------|-------------|
| **Markdown** | Human-readable step-by-step SOP document |
| **Python** | Desktop automation script using pyautogui |
| **JSON** | Structured workflow for tools like n8n, Make, or Zapier |
| **AppleScript** | Native macOS automation |
| **Playwright** | Browser automation test script (TypeScript) |
| **Shortcuts** | Recipe for the Apple Shortcuts app |

## How It Works

1. Click the menu bar icon to open the panel
2. Press **Ctrl+Option+R** to start recording (captures a screenshot every 4 seconds)
3. Do your work as usual
4. Press **Ctrl+Option+R** again to stop — AI generates the workflow automatically
5. Pick an output format, copy the result, or regenerate in a different format

## Setup

### Prerequisites

- macOS 14.2+ (requires ScreenCaptureKit)
- Xcode 15+
- Node.js 18+ (for the Cloudflare Worker)
- A [Cloudflare](https://cloudflare.com) account (free tier works)
- A [Google AI Studio](https://aistudio.google.com) API key (for Gemini)

> The app also includes Clicky's original features (voice chat, cursor pointing). To use those, you'll need API keys from [Anthropic](https://console.anthropic.com), [AssemblyAI](https://www.assemblyai.com), and [ElevenLabs](https://elevenlabs.io).

### 1. Set Up the Cloudflare Worker

The Worker is a proxy that keeps your API keys safe. The app calls the Worker, the Worker calls the APIs — so no keys ever ship in the app binary.

```bash
cd worker
npm install
```

Add your API keys and auth token as secrets:

```bash
# Required for Flowcap workflow generation
npx wrangler secret put GEMINI_API_KEY

# Auth token — pick any random string. The app must send the same token.
npx wrangler secret put APP_AUTH_TOKEN

# Optional — for Clicky's original voice/chat features
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
```

Deploy:

```bash
npx wrangler deploy
```

Copy the URL it gives you (e.g. `https://your-worker.your-subdomain.workers.dev`).

### 2. Update the Proxy URL

The app has the Worker URL hardcoded in two files. Replace it with your own Worker URL:

- `leanring-buddy/CompanionManager.swift` — look for `workerBaseURL`
- `leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift` — look for `tokenProxyURL`

### 3. Set the Auth Token in Xcode

The app reads `WORKER_AUTH_TOKEN` from a build setting and sends it to the Worker in every request. This must match the `APP_AUTH_TOKEN` you set in step 1.

In Xcode:
1. Select the project (not the target) → **Build Settings** tab
2. Click **+** → **Add User-Defined Setting**
3. Name: `WORKER_AUTH_TOKEN`
4. Value: the same token you used for `APP_AUTH_TOKEN`

### 4. Build and Run

```bash
open leanring-buddy.xcodeproj
```

In Xcode:
1. Select the `leanring-buddy` scheme (the typo is intentional — legacy name)
2. Set your signing team under Signing & Capabilities
3. Hit **Cmd+R** to build and run

The app appears in the menu bar (not the Dock).

> **Do NOT run `xcodebuild` from the terminal** — it invalidates TCC permissions and the app will need to re-request screen recording, accessibility, etc.

### Permissions

- **Accessibility** — required for the global keyboard shortcut (Ctrl+Option+R)
- **Screen Recording** — required for capturing screenshots
- **Screen Content** — required for ScreenCaptureKit access
- **Microphone** — only needed for Clicky's voice features, not for workflow recording

## Tech Stack

- **SwiftUI + AppKit** — native macOS menu bar app
- **Gemini 2.5 Flash** — 1M+ token context window for analyzing large screenshot sequences
- **ScreenCaptureKit** — multi-monitor screenshot capture
- **Cloudflare Worker** — API key proxy
- **SSE Streaming** — real-time text generation

## Contributing

PRs welcome. See `CLAUDE.md` for project structure and code conventions.

## Credits

Built on top of [Clicky](https://github.com/farzaa/clicky) by [Farza](https://x.com/farzatv). MIT License.
