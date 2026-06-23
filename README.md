# LangPilot

LangPilot is a Flutter writing assistant for English correction and Chinese-English mixed drafting. It can call an OpenAI-compatible model endpoint configured by the user, returns 1-3 corrected expressions, explains the edits in Chinese, and lets the user copy or replace the input quickly.

It also supports automatic recommendations after the user stops editing for a configurable delay, plus a local diff view that highlights added and modified parts for each recommendation. After the first full check, later automatic or manual checks only send changed paragraphs to the model when possible, then compose the returned correction back into the full document preview.

## Run

```bash
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

Open the model settings from the top-right control.

For online models, fill in:

- `Endpoint`, for example `https://api.deepseek.com/v1`
- `Model`, for example `deepseek-chat`
- `API Key`

For local Qwen mode, the UI exposes:

- `Qwen/Qwen3.5-0.5B`
- `Qwen/Qwen3.5-2B`

Current packaging support is explicit in the app:

- Web: local Qwen download and inference are not supported. Use online mode.
- Desktop: `Qwen/Qwen3.5-2B` downloads a public Q4_K_M GGUF runtime file derived from the model and can run offline correction locally. `Qwen/Qwen3.5-0.5B` downloads a GGUF runtime file from a token-gated Hugging Face repository, so fill in a Hugging Face token before downloading it.
- App/mobile: local Qwen download and inference are not supported in the current build. Use online mode.

The model configuration and auto-recommend delay are stored locally on the current browser or desktop profile.

## Checks

```bash
flutter analyze
flutter test
```
