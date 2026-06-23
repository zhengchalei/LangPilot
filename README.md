# LangPilot

LangPilot is a Flutter writing assistant for English correction and Chinese-English mixed drafting. It calls an OpenAI-compatible model endpoint configured by the user, returns 1-3 corrected expressions, explains the edits in Chinese, and lets the user copy or replace the input quickly.

It also supports automatic recommendations after the user stops editing for 2 seconds, plus a local diff view that highlights added and modified parts for each recommendation. After the first full check, later automatic or manual checks only send changed paragraphs to the model when possible, then compose the returned correction back into the full document preview.

## Run

```bash
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

Open the model settings from the top-right control and fill in:

- `Endpoint`, for example `https://api.deepseek.com/v1`
- `Model`, for example `deepseek-chat`
- `API Key`

The model configuration is stored locally on the current browser or desktop profile.

## Checks

```bash
flutter analyze
flutter test
```
