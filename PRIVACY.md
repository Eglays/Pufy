# Privacy

Pufy has **no accounts and no servers**. The developer never receives your data.

## Stored only on your device
- Chats, notes, reminders, timers and scheduled tasks
- Personal Network (things Pufy learns about you)
- Mini apps you create and their data
- Settings, profile name and photo
- Your AI provider API key: iOS Keychain or Android encrypted storage

You can delete items one by one, or everything at once in **Settings → Delete all my data**. Uninstalling the app also removes everything.

## What leaves your device, and where it goes

| What | Where | When |
|---|---|---|
| Your messages, attached photos, text extracted from attached files | The AI provider **you** chose (or your own computer with Ollama / LM Studio) | When you send a message |
| Dictation audio | The AI provider you chose, for transcription | When you use the microphone |
| City name | Open-Meteo (open-meteo.com) | When you ask about the weather. Device location is not used. |
| Image and site-icon requests | Wikipedia / Wikimedia, Google favicon service | When an answer shows pictures or sources |
| Library downloads | unpkg.com | When a mini app uses an open-source library |
| Live score page | flashscore.mobi (iOS) | When you ask about a match. No user data is sent. |
| Search queries and page addresses | Your own SearXNG server and Jina Reader (r.jina.ai) | Only if you configure them in advanced settings |

Each AI provider handles your data under its own privacy policy.

## What Pufy does not include
No analytics, crash reporting, advertising or tracking SDKs, and no cookies. Pufy does not sell or share data.

## Permissions
- **Microphone:** Only when you start dictation.
- **Camera / Photos:** Only when you attach or save a picture.
- **Notifications:** For reminders, timers and scheduled tasks.
- **Local network (iOS):** Only to reach a local model on your own computer.
