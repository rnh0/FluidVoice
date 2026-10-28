# Privacy audit of this fork

Scope: the macOS app under `Sources/Fluid` at upstream commit `6150956`, plus SwiftPM dependencies from
`Fluid.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Audited by reading the source
(`grep -rnE "URLSession|URLRequest\(|NWConnection|NWListener|WKWebView|https?://" Sources`), not by observing
traffic. The runtime check (step 9 below) is still to do.

## What this fork changes

| Change | Where | Effect |
|---|---|---|
| `FLUID_NO_ANALYTICS` (Debug and Release) | `Analytics/AnalyticsService.swift`, `Analytics/AnalyticsConfig.swift` | Every analytics entry point returns before touching the database; upload code is compiled out. The PostHog key and host were also removed from `Info.plist`, and the release script fails if a `phc_…` key is found in the binary. |
| `FLUID_NO_UPDATER` (Release only) | `Services/SimpleUpdater.swift`, `Persistence/SettingsStore.swift` (`shouldCheckForUpdates`) | No GitHub release checks, downloads or self-replacement. The release-notes view shows "Unable to load release notes". |
| `FLUID_LOCAL_ONLY` (Release only) | `Services/ForkBuildPolicy.swift`; enforced in `LLMClient.buildRequest`, `AIProvider`, `FunctionCallingProvider` (2×), `ModelRepository.fetchModels`, `AIEnhancementSettingsViewModel` (connection test), `FeedbackClient`, `TranscriptionFeedbackReporter` | Text may only be sent to `localhost`, `127.0.0.0/8` or `::1` over http(s), or to exact host names baked into `Info.plist` → `FluidEgressAllowlist` (empty by default). Anything else fails with an error naming this policy. |
| Local API hardening | `Services/LocalAPI/LocalAPIServer.swift`, `LocalAPIAccessPolicy.swift` | Listener bound to the loopback interface; every request needs a loopback `Host`, no `Origin`, and `Authorization: Bearer <token>`. |
| Redirect guard | `EgressRedirectGuard` in `Services/ForkBuildPolicy.swift`, passed as task delegate on every text-carrying request | A redirect to a host outside the policy is refused, so an allowed loopback server cannot forward the request elsewhere. |
| History retention | `Persistence/SettingsStore+HistoryPrivacy.swift`, `Services/TranscriptionHistoryRetentionService.swift`, Settings → Dictation → "Keep History For" | 1 / 7 / 30 / 90 / 365 days or forever; **default 30 days**. Unstarred dictations and their saved audio are deleted after loading, after each change (new dictation, backup restore), when the setting changes, and hourly. Starred entries are kept. |
| Window titles off | Same files; Settings → "Save Window Titles" | New history entries store an empty window title unless you turn this on. Existing entries keep theirs until they expire or you clear history. |
| No prompt traces in logs | `Services/RewriteModeService.swift` (`logPromptTrace`) | With `FLUID_LOCAL_ONLY`, Edit-mode prompt tracing (selected text, prompts, answers) is never written, whatever `RewriteModeDiagnosticsEnabled` / `FLUID_PROMPT_TRACE` say. |
| CI | `.github/workflows/`, `scripts/fork-sign-and-package.sh` | See `docs/fork-release.md`. The build fails if any privacy flag is missing from the compiler invocations or if `PRIVATE_AI_PROVIDER` is set. |

`FLUID_NO_UPDATER` and `FLUID_LOCAL_ONLY` are not set in Debug, which is the configuration the test suite runs in:
upstream's tests exercise the updater against a local fixture (`UpdatePromptIntegrationTests`) and build requests to
remote URLs (`LLMClientRequestBodyTests`, `FeedbackClientTests`). Use Release builds (what `release.yml` produces)
for daily use. `Tests/run_fork_build_policy_tests.sh` tests the egress policy itself.

Using the Privatemode proxy: run it on `127.0.0.1` and point a custom provider at it. Loopback allows any local
process, and the policy cannot see what that process forwards. The proxy is trusted to send text only to attested
confidential compute.

## Network egress (Release build of this fork)

| # | Destination | What is sent | When | Controlled by | Status in fork |
|---|---|---|---|---|---|
| 1 | `eu.i.posthog.com/batch` | Install UUID, app version, RAM, CPU brand, OS; daily counts of dictations/commands/edits/meetings, model ids, latencies, onboarding steps, model-download outcomes. No transcript text. `active_user`/`core_action` events were sent **even with "detailed analytics" off**. | Every 30 s flush | Upstream: `ShareDetailedAnalytics` (default on) only gates the detailed part | **Removed** (`FLUID_NO_ANALYTICS`, key deleted) |
| 2 | `api.github.com/repos/altic-dev/Fluid-oss/releases`, release asset downloads | IP, User-Agent | Launch + hourly, if auto-check on (default on) | `AutoUpdateCheckEnabled` | **Removed** (`FLUID_NO_UPDATER`). Important: the updater's signature check trusts upstream's team IDs (`V4J43B279J`, `537RRRT57V`), so an upstream build would have passed validation and replaced the fork. |
| 3 | `altic.dev/api/fluid/examples` | Raw and processed transcript, model name, your comment | Only when you press "report" on a history item | User action | **Blocked** (`FLUID_LOCAL_ONLY`) |
| 4 | `altic.dev/api/fluid/feedback` | Email, message, app/macOS version | Only when you submit the feedback form | User action | **Blocked** |
| 5 | Configured LLM provider base URL (`/chat/completions`, `/responses`, `/messages`, `/models`) | Dictation cleanup: transcript + system prompt. Edit mode: **selected text** (AX). Command mode: spoken command, chat history, tool output. Meeting summaries: transcript. `/v1/postprocess`: request text. | When AI processing is enabled and a provider is selected | Provider settings | **Loopback only** |
| 6 | `models.fluidvoice.app/feed/v1/speech-models.json` | IP, `User-Agent: FluidVoice/<version>` | At launch and before Fluid compact model use | None | Kept. Signed manifest (`SpeechModelFeed.verified`), metadata only, no user data. |
| 7 | `models.fluidvoice.app/parakeet/fluid-{mini,pico,pro}/…tar` | IP | When installing a Fluid compact model | User action | Kept. SHA-256 verified against the signed manifest. |
| 8 | `huggingface.co/<repo>/resolve/main/…` via FluidAudio `DownloadUtils` (Parakeet v2/v3, VAD, EOU, diarizer, Qwen3, …) | IP | When a model is first selected/downloaded | User action | Kept, **not pinned** (always `main`). Needs a FluidAudio change to pin. `REGISTRY_URL`/`MODEL_REGISTRY_URL` env vars can redirect it to a mirror. |
| 9 | `huggingface.co/api/models/<repo>/tree/main`, `…/resolve/main` via `Networking/ModelDownloader.swift` (Nemotron, Cohere CoreML, meeting models) | IP | Model download | User action | Kept, revision `main` |
| 10 | `huggingface.co/handy-computer/<model>-gguf/resolve/main/<model>-Q8_0.gguf` (`WhisperProvider.swift:89`) | IP | Whisper model download | User action | Kept, revision `main` |
| 11 | Browser links (GitHub, docs, provider key pages) | Opened in your browser | On click | User action | Kept |
| 12 | Local API on `127.0.0.1:47733` (inbound) | — | Only if `defaults write com.FluidApp.app LocalAPIEnabled -bool true` | Off by default; no UI toggle | Hardened (see below) |

Not found: `WKWebView`, crash reporters, third-party analytics SDKs, raw sockets. Fluid-1 / Private AI is only compiled
with `PRIVATE_AI_PROVIDER` (`Services/PrivateAIProvider.swift:386`), which is set nowhere in this repo; the release
workflow fails if it appears. `mxcl/AppUpdater` and PromiseKit are linked but `AppUpdater` is never imported.

### Hugging Face revisions at audit time (2026-10-28)

Recorded so a later download can be compared. Not enforced.

| Repo | Commit |
|---|---|
| `FluidInference/parakeet-tdt-0.6b-v2-coreml` | `ee09c569f73759e6d44c9bd16766f477b2b36d39` |
| `FluidInference/parakeet-tdt-0.6b-v3-coreml` | `7dd20fe6b1797d35f5e3307e8b1732d9a178edfe` |
| `FluidInference/silero-vad-coreml` | `b419383c55c110e2c9271fa6ee0ea83d03c70d96` |
| `FluidInference/parakeet-realtime-eou-120m-coreml` | `40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355` |
| `FluidInference/speaker-diarization-coreml` | `7eab74f3463c736418d0eb10296261ae581146c9` |
| `handy-computer/whisper-large-v3-turbo-gguf` | `18ada752005f5fddef499256f9a458d0b37a203a` |

Note: Whisper now uses GGUF files from `handy-computer/*-gguf` via `transcribe-cpp-swift`, not `ggml-*.bin`.

## Data on disk

The app is not sandboxed. `<AS>` = `~/Library/Application Support/FluidVoice`.

| Data | Location | Retention | Delete in UI |
|---|---|---|---|
| Dictation history: raw + processed text, app name, window title (off by default in this fork), model, timings | `<AS>/TranscriptionHistory.sqlite3` (`secure_delete=ON`) | **30 days by default** (configurable; starred kept); on by default (`saveTranscriptionHistory`) | Yes (entry / all) |
| Dictation audio (WAV, 16 kHz) | `<AS>/DictationAudioHistory/` | Off by default; deleted with its history entry; 4 GB budget, oldest pruned | Yes |
| File-transcription history | UserDefaults `FileTranscriptionHistoryEntries` | 50 entries | Yes |
| Command-mode chats incl. shell commands | UserDefaults `CommandModeChatSessions` | 30 + 30 archived | Yes |
| Meeting audio (CAF, 0600) | `<AS>/Meetings/<id>/tracks/` | Default 7 days (`meetingAudioRetentionPolicy`) | Yes |
| Meeting transcripts and summaries | `<AS>/Meetings/<id>/*.json` | Until deleted | Yes |
| Pronunciation profiles (encoder embeddings) | `<AS>/pronunciation-dictionary-v1.json` | ≤10 enrollments per word | Via dictionary entry |
| **Pronunciation audio** (raw PCM, ≤15 s, + heard/intended text) | `<AS>/pronunciation-audio/*.json` | Tied to enrollment | Via dictionary entry |
| Pronunciation inspection (PCM ≤120 s + **encoder frames**) | `<AS>/pronunciation-inspection/*.plist` | Orphans removed | Indirect |
| Pronunciation debug capture | `<AS>/DictionaryDebug/` | Opt-in; 50 files / 200 MB | Toggle |
| Correction pairs (heard → corrected) | UserDefaults `AutomaticDictionarySuggestionPolicyStateV1` | 30 days, ≤200 | No |
| Boost words / replacements | `<AS>/parakeet_custom_vocabulary.json`, UserDefaults `CustomDictionaryEntries` | — | Yes |
| Search index (history text, app, window title; file transcripts; chats) | `<AS>/zeppelin/` | Reconciled with sources; physical erasure not verified | Indirect |
| Analytics DB | `~/Library/Application Support/com.FluidApp.app/Analytics/` | Not created in this fork | — |
| API keys | Keychain, service `com.fluidvoice.provider-api-keys` | — | Via provider settings |
| Local API token | `~/Library/Application Support/com.FluidApp.app/local-api-token` (0600) | — | Delete the file to rotate |
| Logs | `~/Library/Logs/Fluid/Fluid.log` (+ `.1`) | Rotates at 1 MB or 72 h | No |
| Models | `~/Library/Application Support/FluidAudio/Models`, `~/Library/Caches/WhisperModels`, `~/Library/Caches/<model>` | — | Per model |
| Settings backup (manual export) | Path you choose | — | — |

Settings backups contain the **full transcription history** and pronunciation embeddings, but no audio or API keys.

**Logs.** Release builds drop `.debug` lines (`DebugLogger.swift:8-14`), which is where request JSON is logged
(e.g. `FunctionCallingProvider`). Info/warn/error lines log sizes and counts, not text, based on a pattern search,
not an exhaustive review. Exception: LLM provider HTTP error bodies are logged (`LLMClient.swift`). Upstream's Edit-mode prompt
tracing (selected text, prompts, answers at info level, behind hidden settings) is disabled in Release builds of this fork.

## Accessibility (AX) and screen reading

| Reads | When | Goes to |
|---|---|---|
| Text before the caret (`kAXValueAttribute` + selection range) | Recording start/stop, if context-aware capitalization or continuous spacing is on | Local formatting only |
| Window title (`CGWindowListCopyWindowInfo`, not AX) | Recording stop | History and search index only if "Save Window Titles" is on (default off). Not in prompts for OpenAI-compatible providers (only the bundle ID picks a prompt profile). |
| Selected text (`kAXSelectedTextAttribute`) | Edit-mode hotkey | **Edit-mode LLM** (loopback only in this fork) |
| Focused field value + AXObserver for 30 s after a paste | Automatic dictionary learning (default on) | Local diff; detected correction pair saved; matching audio saved as pronunciation evidence if accepted |
| Focused field value after a paste (0.15/0.35/1 s) | Every paste | Local "did it land" check |
| Window AX tree + OCR of the target window (ScreenCaptureKit + Vision) | Only with `dictationScreenContextEnabled` (default off) **and** the Private AI provider | Private AI only, which is not compiled in this fork |
| Meeting-app window titles, browser tab URL, call-page button labels | Meeting auto-detect (default on) | Local detection |

## Local API

Off by default (`LocalAPIEnabled`), port 47733 (`LocalAPIPort`). Routes: `GET /v1/health`, `GET /v1/history`
(full text and window titles), `GET /v1/meetings`, `GET /v1/meetings/transcript`, `GET|POST
/v1/dictionary/{replacements,custom-words}`, `POST /v1/transcribe` (accepts a path to any file the app can read),
`POST /v1/postprocess`.

Upstream had no authentication. It listened on all interfaces and dropped non-loopback peers after accepting
the connection. It did not check `Host` or `Origin`, so DNS rebinding could read history, and cross-site
`text/plain` POSTs could probably write the dictionary (inferred, not tested). The fork binds to loopback and
requires a token:

```bash
curl -s -H "Authorization: Bearer $(cat ~/Library/Application\ Support/com.FluidApp.app/local-api-token)" \
  http://127.0.0.1:47733/v1/dictionary/custom-words
```

Any process running as your user can read the token file. The token keeps out browsers and other users,
not your own processes. Dictionary changes apply live (`parakeetVocabularyDidChange` → `ASRService`).

## Recommended: block the app in Little Snitch

Deny all connections for FluidVoice. Little Snitch does not filter loopback, so a local LLM server or the Privatemode
proxy on `127.0.0.1` keeps working; the proxy is a separate process with its own rules. Effects of a full block:

- Model downloads fail. Allow `huggingface.co` (and `models.fluidvoice.app` for Fluid compact models) once while
  downloading, then block again. Models stay in the caches listed above.
- The launch-time feed fetch (`models.fluidvoice.app`) fails silently; built-in model metadata is used.
- Nothing else in this build needs the network.

## Still to do

1. Confirm with Little Snitch's network monitor that nothing but the expected hosts is attempted.
2. Pin model downloads: FluidAudio and `ModelDownloader` always fetch `main`. FluidAudio is a remote SwiftPM
   dependency, so this needs a patched fork of it or a hash check in FluidVoice.
3. Optional: stop the launch-time feed fetch (#6) when no Fluid compact model is installed.
4. Other unbounded stores: meeting transcripts and summaries, command-mode chats (30 + 30), file transcriptions (50).
   Automatic dictionary learning (AX watch after each paste) is still on by default.
