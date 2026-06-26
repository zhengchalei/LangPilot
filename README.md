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
- `Qwen/Qwen3.5-0.8B`
- `Qwen/Qwen3.5-2B`

Current packaging support is explicit in the app:

- Desktop: downloads selected models with ModelScope CLI, for example `modelscope download --model Qwen/Qwen3.5-0.8B`.
- Web: cannot execute ModelScope CLI or local inference in the browser. Use online mode.
- App/mobile: can expose the same model choices and resource guidance, but cannot run `modelscope` inside the app. Offline mobile inference needs a native runtime and usually a quantized model.

Model size guidance:

| Model | Storage | Suggested device |
| --- | --- | --- |
| `Qwen/Qwen3.5-0.5B` | about 1-2 GB | 4 GB+ RAM; lightest option, lower quality |
| `Qwen/Qwen3.5-0.8B` | about 2-4 GB | 6 GB+ RAM; balanced default |
| `Qwen/Qwen3.5-2B` | about 5-8 GB | 8-12 GB+ RAM; better quality, slower |

ModelScope downloads the original model files. The current embedded desktop inference path still needs a GGUF file or a native runtime adapter before offline correction can use those files directly.

The model configuration and auto-recommend delay are stored locally on the current browser or desktop profile.

## Checks

```bash
flutter analyze
flutter test
```
