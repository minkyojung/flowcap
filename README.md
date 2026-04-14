# Flowcap

화면을 녹화하면 AI가 자동으로 워크플로우 문서를 만들어주는 macOS 앱.

반복 업무를 할 때 Ctrl+Option+R을 누르고 평소처럼 작업하면, Flowcap이 스크린샷을 자동 캡처하고 AI(Gemini 2.5 Flash)가 단계별 SOP 문서를 생성합니다.

<!-- 데모 영상을 추가하려면 아래 주석을 해제하세요 -->
<!-- ![Flowcap Demo](demo.gif) -->

## 지원 포맷

| 포맷 | 설명 |
|------|------|
| **Markdown** | 사람이 읽는 단계별 SOP 문서 |
| **Python** | pyautogui 기반 데스크탑 자동화 스크립트 |
| **JSON** | n8n, Make, Zapier 등 자동화 도구용 |
| **AppleScript** | macOS 네이티브 자동화 |
| **Playwright** | 브라우저 자동화 테스트 스크립트 (TypeScript) |
| **Shortcuts** | Apple Shortcuts 앱에서 재현 가능한 레시피 |

## 사용법

1. 메뉴바 아이콘을 클릭해서 패널을 엽니다
2. **Ctrl+Option+R** 을 누르면 녹화가 시작됩니다 (4초 간격으로 스크린샷 캡처)
3. 평소처럼 작업을 수행합니다
4. 다시 **Ctrl+Option+R** 을 누르면 녹화가 종료되고 AI가 워크플로우를 생성합니다
5. 패널에서 포맷을 선택하고, 결과를 복사하거나 다른 포맷으로 재생성할 수 있습니다

## 셋업

### 준비물

- macOS 14.2+ (ScreenCaptureKit 필요)
- Xcode 15+
- Node.js 18+ (Cloudflare Worker용)
- [Cloudflare](https://cloudflare.com) 계정 (무료)
- [Google AI Studio](https://aistudio.google.com) API 키 (Gemini)

> Clicky의 원래 기능(음성 대화, 커서 포인팅)도 사용하려면 [Anthropic](https://console.anthropic.com), [AssemblyAI](https://www.assemblyai.com), [ElevenLabs](https://elevenlabs.io) API 키도 필요합니다.

### 1. Cloudflare Worker 설정

Worker는 API 키를 안전하게 보관하는 프록시입니다. 앱은 Worker를 통해 API를 호출하므로, 앱 바이너리에 키가 포함되지 않습니다.

```bash
cd worker
npm install
```

API 키를 시크릿으로 등록합니다:

```bash
# Flowcap 워크플로우 생성에 필요 (필수)
npx wrangler secret put GEMINI_API_KEY

# Clicky 원래 기능용 (선택)
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
```

배포합니다:

```bash
npx wrangler deploy
```

배포 후 나오는 URL (예: `https://your-worker.your-subdomain.workers.dev`)을 복사합니다.

### 2. Worker URL 설정

앱에 Worker URL이 하드코딩되어 있습니다. 본인의 Worker URL로 교체합니다:

```bash
grep -r "clicky-proxy" leanring-buddy/
```

`CompanionManager.swift`와 `AssemblyAIStreamingTranscriptionProvider.swift`에서 URL을 교체합니다.

### 3. Xcode에서 빌드

```bash
open leanring-buddy.xcodeproj
```

Xcode에서:
1. `leanring-buddy` 스킴을 선택합니다 (이름의 오타는 의도적입니다)
2. Signing & Capabilities에서 팀을 설정합니다
3. **Cmd+R** 로 빌드 및 실행합니다

앱은 메뉴바에 나타납니다 (Dock에는 표시되지 않음).

> **주의**: 터미널에서 `xcodebuild`를 실행하지 마세요. TCC 권한이 초기화되어 화면 녹화, 접근성 등의 권한을 다시 요청해야 합니다.

### 필요한 권한

- **마이크** — 음성 입력용 (Flowcap 워크플로우 기능에는 불필요)
- **접근성** — 전역 단축키 감지 (Ctrl+Option+R)
- **화면 녹화** — 스크린샷 캡처
- **화면 콘텐츠** — ScreenCaptureKit 접근

## 기술 스택

- **SwiftUI + AppKit** — macOS 네이티브 메뉴바 앱
- **Gemini 2.5 Flash** — 1M+ 토큰 컨텍스트로 대량 스크린샷 분석
- **ScreenCaptureKit** — 멀티 모니터 스크린샷 캡처
- **Cloudflare Worker** — API 키 프록시
- **SSE Streaming** — 실시간 텍스트 생성

## 기여

PR 환영합니다. 프로젝트 구조와 코드 컨벤션은 `CLAUDE.md`를 참고하세요.

## 크레딧

[Clicky](https://github.com/farzaa/clicky) by [Farza](https://x.com/farzatv) 위에 만들어졌습니다. MIT 라이선스.
