# distill — Product Requirements Document

**Distill the essence of any YouTube video into your Obsidian vault.**

## Problem

There are too many valuable YouTube videos and not enough time to watch them all. Developers, researchers, and lifelong learners need a way to quickly extract the key insights from YouTube videos and store them in a searchable, browsable knowledge base — without sitting through every minute of content.

## Solution

`distill` is a macOS CLI tool written in Swift 6.0 that takes a YouTube URL and produces a well-formatted Obsidian-compatible markdown summary. It orchestrates a pipeline of best-in-class tools — yt-dlp, ffmpeg, Whisper, and an LLM — to go from URL to knowledge-base entry in a single command. Frame extraction is available opt-in for videos where screenshots add value.

---

## User Personas

| Persona | Description |
|---------|-------------|
| **Busy Developer** | Follows dozens of conference talks and tutorial channels. Wants to triage videos quickly and only deep-dive on the most relevant ones. |
| **Knowledge Collector** | Maintains an Obsidian vault as a second brain. Wants every piece of consumed content captured with proper metadata and tags. |
| **Researcher** | Needs to review large volumes of video content and extract structured notes for later synthesis. |

---

## User Flows

### Flow 1 — Single Video Summary

```
$ distill https://www.youtube.com/watch?v=abc123
```

**What happens:**

1. The tool resolves the video metadata (title, channel, duration, publish date).
2. It attempts to fetch existing YouTube captions/subtitles.
3. If no captions exist, it downloads the audio and transcribes it locally.
4. It sends the transcript to an LLM with a summarization prompt.
5. It writes a markdown file to the configured Obsidian vault (or `--output` path).

**Output** (spinners/progress go to stderr, final file path to stdout):

```
⠋ Resolving metadata...
✓ Fetched metadata: "Building a SwiftUI App from Scratch" by Sean Allen (32:14)
⠋ Extracting transcript...
✓ Extracted transcript (YouTube captions)
⠋ Generating summary...
✓ Generated summary (Claude) — estimated cost: $0.03
✓ Saved to ~/Obsidian/Vault/YouTube/2026-03-13-building-a-swiftui-app-from-scratch.md
```

### Flow 1b — Single Video Summary with Frames

```
$ distill https://www.youtube.com/watch?v=abc123 --frames
```

**What happens:**

Same as Flow 1, but additionally:

4. It downloads the video and extracts key frames (scene changes, slide transitions) **concurrently** with transcript acquisition.
5. Frame timestamps and filenames are included in the LLM summarization prompt.
6. Screenshots are embedded inline in the markdown output.

**Output:**

```
⠋ Resolving metadata...
✓ Fetched metadata: "Building a SwiftUI App from Scratch" by Sean Allen (32:14)
⠋ Extracting transcript...
⠋ Extracting frames...
✓ Extracted transcript (YouTube captions)
✓ Captured 8 key frames
⠋ Generating summary...
✓ Generated summary (Claude) — estimated cost: $0.03
✓ Saved to ~/Obsidian/Vault/YouTube/2026-03-13-building-a-swiftui-app-from-scratch.md
```

### Flow 2 — Batch Processing

```
$ distill --batch urls.txt
$ distill --batch urls.txt --concurrency 3
```

Process a list of YouTube URLs from a file, one per line. Each video is processed sequentially by default (configurable with `--concurrency`). Processing continues on failure by default (use `--fail-fast` to stop on first error). A detailed status table is printed at the end:

```
┌─────────────────────────────────────────────────────────────────────┐
│ Batch Results                                                       │
├──────┬──────────────────────────────────────────────┬───────────────┤
│  #   │ Video                                        │ Status        │
├──────┼──────────────────────────────────────────────┼───────────────┤
│  1   │ Building a SwiftUI App from Scratch (32:14)  │ ✓ Saved       │
│  2   │ Advanced Concurrency in Swift (45:02)        │ ✓ Saved       │
│  3   │ https://youtube.com/watch?v=xyz789           │ ✗ Private     │
│  4   │ Intro to Metal Shaders (28:30)               │ ✓ Saved       │
├──────┼──────────────────────────────────────────────┼───────────────┤
│      │ Total: 3/4 succeeded, 1 failed               │ Cost: $0.08  │
└──────┴──────────────────────────────────────────────┴───────────────┘
```

When `--output <dir>` is used with batch/playlist, it specifies the output directory. Individual files are named per the `filename_format` setting.

### Flow 3 — Playlist Processing

```
$ distill --playlist https://www.youtube.com/playlist?list=PLxyz
$ distill --playlist https://www.youtube.com/playlist?list=PLxyz --concurrency 3
```

Process every video in a YouTube playlist. Creates an index note linking to all individual summaries. Supports `--concurrency` for parallel processing. Same status table and `--fail-fast` behavior as batch. `--output <dir>` works the same as batch.

### Flow 4 — Custom Output (No Obsidian)

```
$ distill https://www.youtube.com/watch?v=abc123 --output ./summary.md
$ distill https://www.youtube.com/watch?v=abc123 --output ./summary.json
```

Write the summary to a specific file path instead of the Obsidian vault. Output format is inferred from file extension (`.md` → markdown, `.json` → json, `.yaml`/`.yml` → yaml). Use `--format` to override the inferred format.

### Flow 5 — Transcript Only

```
$ distill https://www.youtube.com/watch?v=abc123 --transcript-only
$ distill https://www.youtube.com/watch?v=abc123 --transcript-only | head -50
$ distill https://www.youtube.com/watch?v=abc123 --transcript-only --output transcript.md
```

Skip summarization. Output the raw transcript as markdown with timestamps to **stdout** (pipe-friendly). Use `--output` to redirect to a file instead. `--format` is ignored with `--transcript-only` — transcript is always plain text with timestamps.

### Flow 6 — Dry Run

```
$ distill https://www.youtube.com/watch?v=abc123 --dry-run
```

Show what would happen without executing anything. Fetches metadata only (one lightweight `yt-dlp --dump-json` call), then estimates token count and cost from video duration (~150 words/minute → ~200 tokens/minute). Cost is shown as an approximate range:

```
Dry run: "Building a SwiftUI App from Scratch" by Sean Allen
  Duration:    32:14
  Est. tokens: ~6,400 (approx. from duration)
  Est. cost:   $0.02–0.05 (Claude Sonnet)
  Output:      ~/Obsidian/Vault/YouTube/2026-03-13-building-a-swiftui-app-from-scratch.md
  Status:      New (no existing output)
```

### Flow 7 — Setup

```
$ distill setup
```

Interactive guided setup that walks through:

1. LLM provider selection and API key configuration
2. Obsidian vault path
3. Default preferences (language, tags, etc.)
4. Creates `~/.distill/config.yaml` and default `~/.distill/prompt.md`

### Flow 8 — Init Config

```
$ distill init
```

Creates a starter `~/.distill/config.yaml` with documented defaults. Non-interactive alternative to `distill setup` for users who prefer to edit config files directly.

---

## Pipeline Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌────────────┐     ┌─────────────┐
│  YouTube URL │────▶│   Metadata   │────▶│  Transcript  │────▶│   Summary  │────▶│   Output    │
│              │     │  Resolution  │     │  Acquisition │     │ Generation │     │  (md/json)  │
└─────────────┘     └──────────────┘     └──────┬───────┘     └────────────┘     └─────────────┘
                                                 │                                       ▲
                                                 │ (concurrent       ┌────────────┐      │
                                                 │  when --frames)   │   Frame    │──────┘
                                                 └─────────────────▶ │ Extraction │
                                                                     └────────────┘
```

Pipeline stages use Swift structured concurrency (`async/await`, `TaskGroup`). When `--frames` is enabled, transcript acquisition and frame extraction run concurrently after metadata resolution. Both must complete before summarization begins. If transcript acquisition fails (after all retries), frame extraction is cancelled via structured concurrency since summarization cannot proceed.

All progress/spinner output goes to **stderr**. Content output (transcript, file paths) goes to **stdout**. This enables clean piping (e.g., `distill <url> --transcript-only | wc -w`).

### Stage 1 — Metadata Resolution

- **Tool**: `yt-dlp --dump-json`
- **Extracts**: Title, channel name, upload date, duration, description, tags, thumbnail URL, available subtitle languages.
- **Used for**: Frontmatter generation, filename, and deciding the transcript strategy.

### Stage 2 — Transcript Acquisition (Fallback Chain)

| Priority | Method | Tool | When |
|----------|--------|------|------|
| 1 | YouTube captions | `yt-dlp --write-auto-subs --sub-lang en --skip-download` | Default — most videos have auto-captions |
| 2 | Local transcription | `mlx-whisper` or `whisper.cpp` | When captions are unavailable or user forces with `--transcription local` |
| 3 | Cloud transcription | OpenAI Whisper API | When user specifies `--transcription cloud` |

The caption-first approach avoids unnecessary audio downloads and transcription compute for ~95% of videos.

**Audio optimization**: When both `--frames` and `--transcription local` are used, the audio track is extracted from the already-downloaded video file instead of downloading audio separately. This avoids a redundant download.

**Subtitle format**: yt-dlp auto-captions are fetched as VTT. The `SubtitleParser` handles VTT format only (yt-dlp can be instructed to convert any format to VTT).

### Stage 3 — Frame Extraction (Opt-in: `--frames`)

- **Tool**: `ffmpeg`
- **Requires**: Full video download (impacts performance — this is why frames are opt-in).
- **Strategy**:
  - Extract one frame per 60 seconds **plus** scene-change frames (`select='gt(scene,0.4)'`).
  - This captures slide transitions in talks/tutorials effectively.
  - Frames are saved as compressed PNGs in the Obsidian attachments folder.
  - A maximum of 20 frames per video to avoid bloat (configurable).
- **Smart placement**: The LLM receives frame data as a markdown table in the prompt (timestamps and filenames). During summarization, it generates the actual `![alt text](path/filename.png)` references inline, choosing which frames best illustrate each section.

### Stage 4 — LLM Summarization

- **Providers** (configurable):
  - **Claude API** (default) — Best structured output and markdown formatting.
  - **OpenAI API** — Alternative.
  - **Ollama** (local) — Free, offline, lower quality.
- **Prompt template**: Loaded from `~/.distill/prompt.md` (overridable with `--prompt <file>`). A default template is created by `distill setup` or `distill init`. Users can customize the prompt to change summary style, section structure, or add domain-specific instructions.
- **Prompt strategy**:
  - Send full transcript (most YouTube videos fit within 200K context window).
  - Request structured markdown with: key takeaways, section-by-section summary, notable quotes, and action items.
  - When `--frames` is used, include frame data as a markdown table so the LLM generates inline image references.
  - Summaries are always generated in English regardless of source language.
- **LLM always produces markdown**. For `--format json`/`yaml`, a second pass parses the structured markdown into the JSON/YAML schema. This keeps the LLM prompt simple and consistent regardless of output format.
- **Context window overflow**: If a transcript exceeds the LLM's context window, the tool fails with a clear error message suggesting the user try a different model with a larger context window or split the video. Chunked summarization (map-reduce) is deferred to a future release.
- **Cost estimation**: Based on video duration → approximate token count → provider pricing table. Shown in `--dry-run` output and post-summarization.
- **Cost**: Typically $0.01–0.10 per video depending on length and provider.

### Stage 5 — Tag Generation (M2+)

- **Separate LLM call** dedicated to tag extraction from the transcript/summary.
- Returns a list of lowercase, hyphenated tags (e.g., `swift-concurrency`, `error-handling`).
- Tags are merged with the default tags from config (deduped).
- When `auto_tag` is disabled in config, this stage is skipped and only default tags are used.
- **Not included in M1** — M1 uses only the default `youtube` tag.

### Stage 6 — Output

Generate a markdown file with:

1. **YAML frontmatter** (metadata, tags, and `distill_hash` for idempotency)
2. **Embedded screenshots** at relevant points (when `--frames` is used)
3. **Structured summary** with headers, bullets, and timestamps
4. **Link back to original video** with timestamp links

For `--format json`/`yaml`, the markdown is parsed into the structured schema (see [Structured Output Format](#structured-output-format---format-json)).

---

## Output Format

### Example Output File (Without Frames — Default)

```markdown
---
title: "Building a SwiftUI App from Scratch"
source: "https://www.youtube.com/watch?v=abc123"
channel: "Sean Allen"
published: 2026-02-15
summarized: 2026-03-13
duration: "32:14"
tags:
  - youtube
  - swiftui
  - ios
  - tutorial
type: youtube-summary
distill_hash: "a1b2c3d4"
---

# Building a SwiftUI App from Scratch

> **Channel**: [Sean Allen](https://www.youtube.com/@seanallen)
> **Duration**: 32:14 | **Published**: 2026-02-15
> **Source**: [Watch on YouTube](https://www.youtube.com/watch?v=abc123)

## Key Takeaways

- SwiftUI's `@Observable` macro replaces `ObservableObject` for simpler state management
- Navigation stacks should use value-based navigation for deep linking support
- Always extract business logic into a dedicated model layer for testability

## Summary

### Project Setup (0:00–4:32)

Sean begins by creating a new Xcode project targeting iOS 18...

### Building the Main View (4:32–12:15)

The main content view uses a `NavigationStack` with a `List`...

### State Management with @Observable (12:15–22:00)

Rather than using the older `ObservableObject` protocol...

### Networking Layer (22:00–30:45)

A lightweight networking layer is built using async/await...

### Wrap-Up (30:45–32:14)

Sean summarizes the key architectural decisions...

## Notable Quotes

- "If you're still using ObservableObject in 2026, you're making your life harder than it needs to be." ([12:45](https://www.youtube.com/watch?v=abc123&t=765))

## Action Items

- [ ] Try migrating an existing project from `ObservableObject` to `@Observable`
- [ ] Explore `NavigationStack` value-based routing

## Timestamps

| Time | Topic |
|------|-------|
| [0:00](https://www.youtube.com/watch?v=abc123&t=0) | Project Setup |
| [4:32](https://www.youtube.com/watch?v=abc123&t=272) | Building the Main View |
| [12:15](https://www.youtube.com/watch?v=abc123&t=735) | State Management |
| [22:00](https://www.youtube.com/watch?v=abc123&t=1320) | Networking Layer |
| [30:45](https://www.youtube.com/watch?v=abc123&t=1845) | Wrap-Up |
```

### Example Output File (With `--frames`)

When `--frames` is used, the output includes inline screenshots placed by the LLM:

```markdown
---
title: "Building a SwiftUI App from Scratch"
source: "https://www.youtube.com/watch?v=abc123"
channel: "Sean Allen"
published: 2026-02-15
summarized: 2026-03-13
duration: "32:14"
tags:
  - youtube
  - swiftui
  - ios
  - tutorial
type: youtube-summary
distill_hash: "e5f6g7h8"
---

# Building a SwiftUI App from Scratch

> **Channel**: [Sean Allen](https://www.youtube.com/@seanallen)
> **Duration**: 32:14 | **Published**: 2026-02-15
> **Source**: [Watch on YouTube](https://www.youtube.com/watch?v=abc123)

## Key Takeaways

- SwiftUI's `@Observable` macro replaces `ObservableObject` for simpler state management
- Navigation stacks should use value-based navigation for deep linking support
- Always extract business logic into a dedicated model layer for testability

## Summary

### Project Setup (0:00–4:32)

Sean begins by creating a new Xcode project targeting iOS 18...

![Project setup in Xcode](attachments/building-a-swiftui-app-from-scratch/frame-001.png)

### Building the Main View (4:32–12:15)

The main content view uses a `NavigationStack` with a `List`...

![Main view layout](attachments/building-a-swiftui-app-from-scratch/frame-004.png)

### State Management with @Observable (12:15–22:00)

Rather than using the older `ObservableObject` protocol...

### Networking Layer (22:00–30:45)

A lightweight networking layer is built using async/await...

### Wrap-Up (30:45–32:14)

Sean summarizes the key architectural decisions...

## Notable Quotes

- "If you're still using ObservableObject in 2026, you're making your life harder than it needs to be." ([12:45](https://www.youtube.com/watch?v=abc123&t=765))

## Action Items

- [ ] Try migrating an existing project from `ObservableObject` to `@Observable`
- [ ] Explore `NavigationStack` value-based routing

## Timestamps

| Time | Topic |
|------|-------|
| [0:00](https://www.youtube.com/watch?v=abc123&t=0) | Project Setup |
| [4:32](https://www.youtube.com/watch?v=abc123&t=272) | Building the Main View |
| [12:15](https://www.youtube.com/watch?v=abc123&t=735) | State Management |
| [22:00](https://www.youtube.com/watch?v=abc123&t=1320) | Networking Layer |
| [30:45](https://www.youtube.com/watch?v=abc123&t=1845) | Wrap-Up |
```

### Structured Output Format (`--format json`)

When `--format json` or `--format yaml` is used, the LLM-generated markdown is parsed into structured data. Each video produces its own file (for batch/playlist, each video gets a separate `.json`/`.yaml` file in the output directory):

```json
{
  "metadata": {
    "title": "Building a SwiftUI App from Scratch",
    "source": "https://www.youtube.com/watch?v=abc123",
    "channel": "Sean Allen",
    "channel_url": "https://www.youtube.com/@seanallen",
    "published": "2026-02-15",
    "summarized": "2026-03-13",
    "duration": "32:14",
    "duration_seconds": 1934,
    "tags": ["youtube", "swiftui", "ios", "tutorial"]
  },
  "key_takeaways": [
    "SwiftUI's @Observable macro replaces ObservableObject for simpler state management",
    "Navigation stacks should use value-based navigation for deep linking support",
    "Always extract business logic into a dedicated model layer for testability"
  ],
  "sections": [
    {
      "title": "Project Setup",
      "start_time": "0:00",
      "end_time": "4:32",
      "start_seconds": 0,
      "end_seconds": 272,
      "summary": "Sean begins by creating a new Xcode project targeting iOS 18...",
      "frames": ["attachments/building-a-swiftui-app-from-scratch/frame-001.png"]
    }
  ],
  "quotes": [
    {
      "text": "If you're still using ObservableObject in 2026, you're making your life harder than it needs to be.",
      "timestamp": "12:45",
      "timestamp_seconds": 765,
      "url": "https://www.youtube.com/watch?v=abc123&t=765"
    }
  ],
  "action_items": [
    "Try migrating an existing project from ObservableObject to @Observable",
    "Explore NavigationStack value-based routing"
  ],
  "timestamps": [
    {"time": "0:00", "seconds": 0, "topic": "Project Setup"},
    {"time": "4:32", "seconds": 272, "topic": "Building the Main View"},
    {"time": "12:15", "seconds": 735, "topic": "State Management"},
    {"time": "22:00", "seconds": 1320, "topic": "Networking Layer"},
    {"time": "30:45", "seconds": 1845, "topic": "Wrap-Up"}
  ]
}
```

---

## Obsidian Integration

### Vault Structure

```
<Vault Root>/
├── YouTube/
│   ├── 2026-03-13-building-a-swiftui-app-from-scratch.md
│   ├── 2026-03-12-advanced-concurrency-in-swift.md
│   └── attachments/
│       ├── building-a-swiftui-app-from-scratch/
│       │   ├── frame-001.png
│       │   ├── frame-004.png
│       │   └── frame-012.png
│       └── advanced-concurrency-in-swift/
│           ├── frame-001.png
│           └── frame-007.png
```

### Configuration

The vault path and folder structure are configured in `~/.distill/config.yaml`:

```yaml
obsidian:
  vault: ~/Obsidian/Vault
  folder: YouTube
  attachments: YouTube/attachments
  filename_format: "{date}-{slug}"     # 2026-03-13-video-title
  image_syntax: markdown               # "markdown" or "wikilink"

tags:
  default:
    - youtube
  auto_tag: true                       # LLM generates tags via separate call (M2+)

transcription:
  prefer: captions                     # "captions" | "local" | "cloud"
  local_engine: mlx-whisper            # "mlx-whisper" | "whisper.cpp"
  model: base                          # whisper model size: tiny, base, small, medium, large-v3
  language: en

summarization:
  provider: claude                     # "claude" | "openai" | "ollama"
  model: claude-sonnet-4-6             # model identifier
  api_key_env: ANTHROPIC_API_KEY       # env var name (never stored in config)
  prompt: ~/.distill/prompt.md         # path to prompt template

frames:
  max_frames: 20
  interval_seconds: 60
  scene_detection: true
  scene_threshold: 0.4

cache:
  enabled: true
  directory: ~/.distill/cache
  ttl_hours: 168                       # 7 days — intermediate results expire after this

output:
  include_timestamps: true
  include_quotes: true
  include_action_items: true
  include_transcript: false            # append full transcript at end
```

When no config file exists, the tool uses sensible defaults (Claude provider, English language, standard Obsidian paths). Run `distill init` to generate a starter config or `distill setup` for guided configuration.

### Slug Generation

Filenames are generated from the video title:
- Unicode characters are preserved (no transliteration to ASCII).
- Filesystem-unsafe characters (`/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`) are removed.
- Spaces and underscores are replaced with hyphens.
- Consecutive hyphens are collapsed.
- Truncated at 80 characters (at a word boundary when possible).
- Prefixed with the date per `filename_format`.

Example: `"Über die Grundlagen: Swift 6.0 & Concurrency!"` → `über-die-grundlagen-swift-6.0-concurrency`

### Configuration Precedence

CLI flags > config file > built-in defaults. For example, `--provider openai` overrides `summarization.provider: claude` in config.

### Configuration Validation

- **Bad YAML syntax**: Error with line number and description.
- **Wrong types** (e.g., `max_frames: "twenty"`): Error with field name and expected type.
- **Unknown keys**: Warning printed to stderr (forward-compatible — allows config to work across versions).

### Obsidian CLI Integration (Optional)

If Obsidian v1.12.4+ is running, the tool can optionally use the [Obsidian CLI](https://help.obsidian.md/cli) to create notes through Obsidian's API. This ensures wikilinks auto-update and the vault index stays in sync. The tool falls back to direct file writing if the CLI is unavailable.

---

## External Dependencies

| Dependency | Purpose | Install | Min Version |
|------------|---------|---------|-------------|
| **yt-dlp** | Video/audio download, metadata, subtitles | `brew install yt-dlp` | 2024.01+ |
| **ffmpeg** | Audio conversion, frame extraction | `brew install ffmpeg` | 6.0+ |
| **mlx-whisper** | Local transcription on Apple Silicon | `pip install mlx-whisper` | 0.1+ |
| **whisper.cpp** | Alternative local transcription | `brew install whisper-cpp` | 1.5+ |

The tool validates that required dependencies are installed on first run and provides inline install instructions for any that are missing. Version checks are best-effort: presence is required, but a version below the minimum produces a **warning** (not an error) since version parsing varies across package managers.

```
$ distill --check-deps

Checking dependencies...
  ✓ yt-dlp 2025.12.23
  ✓ ffmpeg 7.1
  ✗ mlx-whisper — not found
    Install with: pip install mlx-whisper
  ⚠ whisper.cpp 1.4.0 — minimum recommended: 1.5+
```

---

## CLI Reference

```
USAGE: distill <url> [options]
       distill --batch <file> [options]
       distill --playlist <url> [options]
       distill setup
       distill init
       distill cache <subcommand>

COMMANDS:
  setup                         Interactive guided setup (API key, vault path, preferences)
  init                          Create a starter config file at ~/.distill/config.yaml
  cache clear                   Remove all cached intermediate results
  cache status                  Show cache size and entry count

ARGUMENTS:
  <url>                       YouTube video URL

OPTIONS:
  --batch <file>              Process URLs from a text file (one per line)
  --playlist <url>            Process all videos in a YouTube playlist
  --concurrency <n>           Number of videos to process in parallel (default: 1)
  --fail-fast                 Stop batch/playlist processing on first error

  --output <path>             Write to a specific file (single video) or directory (batch/playlist)
  --format <type>             Output format: markdown, json, yaml (default: inferred from --output extension, or markdown)
  --transcript-only           Output transcript to stdout, skip summarization (--format ignored)
  --frames                    Enable frame extraction (requires video download)
  --transcription <method>    Transcription method: captions, local, cloud (default: captions)
  --dry-run                   Show plan and cost estimate without executing
  --overwrite                 Re-process even if output file already exists

  --provider <name>           LLM provider: claude, openai, ollama (default: claude)
  --model <id>                LLM model identifier
  --language <code>           Transcript language (default: en)
  --prompt <file>             Path to custom prompt template (default: ~/.distill/prompt.md)

  --config <path>             Path to config file (default: ~/.distill/config.yaml)
  --check-deps                Verify external dependencies are installed
  --verbose                   Show detailed progress output
  --quiet                     Suppress all output except errors

  --version                   Print version
  --help                      Show help
```

`--quiet` and `--verbose` are mutually exclusive. Passing both is an error.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success — all videos processed |
| `1` | Failure — single video failed, or all videos in a batch failed |
| `2` | Partial failure — some videos in a batch/playlist succeeded, some failed |
| `3` | Configuration error — invalid config, missing API key, mutually exclusive flags |

---

## Error Handling

All errors are presented inline with a suggested fix when possible:

```
✗ yt-dlp not found
  Install with: brew install yt-dlp

✗ Video unavailable: "This video is private"
  This video cannot be accessed. Check the URL or try a different video.

✗ ANTHROPIC_API_KEY not set
  Set your API key: export ANTHROPIC_API_KEY=sk-...
  Or run: distill setup

✗ Transcript extraction failed (attempt 2/3, retrying in 4s...)
✗ Transcript extraction failed after 3 attempts
  YouTube may be throttling requests. Try again in a few minutes.

✗ Failed to write to ~/Obsidian/Vault/YouTube/
  Directory does not exist. Run: distill setup

✗ Transcript too long for claude-sonnet-4-6 context window (~250K tokens, max 200K)
  Try a model with a larger context window, or use a shorter video.

✗ --quiet and --verbose cannot be used together

✗ Invalid config at ~/.distill/config.yaml line 12: expected integer for frames.max_frames, got "twenty"
```

### Retry Strategy

Each pipeline stage retries up to 3 times with exponential backoff (1s, 2s, 4s) on transient failures (network errors, HTTP 429/5xx). Non-transient errors (invalid URL, missing API key, file permission errors) fail immediately.

### Rate Limiting (Batch/Playlist)

When processing multiple videos:

- A base delay of 2 seconds between videos avoids YouTube throttling.
- On HTTP 429 or throttle responses, exponential backoff kicks in (starting at 5s, max 60s).
- LLM API rate limits are handled the same way (backoff on 429 responses).

---

## Caching

Intermediate results are cached in `~/.distill/cache/` to avoid redundant work:

| Artifact | Cache Key | TTL |
|----------|-----------|-----|
| Video metadata (JSON) | Video ID | 7 days |
| Transcript (text) | Video ID + language | 7 days |
| Extracted frames (PNGs) | Video ID + frame config hash | 7 days |

Caching is especially valuable when:
- Summarization fails and the user re-runs (no need to re-download transcript).
- The user re-runs with `--frames` after an initial run without them.
- The user switches LLM providers/models and wants a new summary from the same transcript.

Cache management:
- `distill cache status` — shows total size and entry count.
- `distill cache clear` — removes all cached data.
- Cache TTL is configurable in `config.yaml`.

---

## Idempotency

Re-running `distill` on the same URL skips processing if the output file already exists **and** the `distill_hash` in its YAML frontmatter matches the current config hash.

The hash is computed from all config fields **except** `obsidian.*` paths and `cache.*` settings (since those don't affect output content). This means:

- Changing LLM provider, model, prompt template, or output options triggers re-processing automatically.
- Changing only vault path or cache settings does not trigger re-processing.
- `--overwrite` bypasses all idempotency checks.

The `distill_hash` is stored directly in the output file's YAML frontmatter — no separate meta files needed.

---

## Security

### Shell Command Execution

All external tool invocations (yt-dlp, ffmpeg, whisper) use Swift's `Process` API with explicit argument arrays — **never** string interpolation through a shell. This prevents command injection via malicious URLs or metadata.

Additionally, all user-provided URLs are validated against a strict pattern before being passed to external tools:
- Must match `https://(www\.)?youtube\.com/watch\?v=` or `https://youtu\.be/` patterns.
- Playlist URLs must match `https://(www\.)?youtube\.com/playlist\?list=` patterns.
- Any URL failing validation is rejected before reaching external tools.

---

## Prompt Template

The summarization prompt is loaded from `~/.distill/prompt.md` (overridable with `--prompt <file>`). A default is created by `distill setup` or `distill init`.

Users can customize the prompt to:
- Change the summary structure (e.g., remove action items, add a TL;DR section).
- Add domain-specific instructions (e.g., "focus on code examples", "extract API references").
- Adjust tone and detail level.

The prompt template supports the following placeholders:

| Placeholder | Replaced With |
|-------------|---------------|
| `{{title}}` | Video title |
| `{{channel}}` | Channel name |
| `{{duration}}` | Video duration |
| `{{transcript}}` | Full transcript text |
| `{{frames}}` | Markdown table of frame data (when `--frames` is used, empty otherwise) |
| `{{language}}` | Transcript language code |

When `--frames` is used, the `{{frames}}` placeholder renders as:

```markdown
| Timestamp | Filename |
|-----------|----------|
| 0:00 | attachments/building-a-swiftui-app/frame-001.png |
| 1:05 | attachments/building-a-swiftui-app/frame-002.png |
| 4:32 | attachments/building-a-swiftui-app/frame-003.png |
```

---

## Technical Design

### Swift Version

- **Swift 6.0** with Swift 6 language mode disabled (strict concurrency adopted incrementally).
- **macOS 14+ (Sonoma)** deployment target, Apple Silicon optimized.
- **Xcode 16+** required for development.

### Concurrency Model

The pipeline uses Swift structured concurrency throughout:

- `Pipeline.swift` orchestrates stages using `async/await`.
- When `--frames` is enabled, transcript acquisition and frame extraction run in a `TaskGroup` concurrently. If transcript acquisition fails after all retries, frame extraction is cancelled via the `TaskGroup`'s cooperative cancellation.
- When `--frames` + `--transcription local` are both used, audio is extracted from the downloaded video file rather than downloading audio separately.
- Batch/playlist processing uses `TaskGroup` with `--concurrency` controlling max concurrent tasks.
- All pipeline stage protocols are `async` — implementations can be swapped for testing.

### I/O Convention

- **stderr**: All progress output (spinners, checkmarks, warnings, errors, batch status table).
- **stdout**: Content output only — file paths after save, transcript text with `--transcript-only`.

This enables clean piping and scripting (e.g., `distill <url> --transcript-only | pbcopy`).

### Swift Package Structure

```
distill/
├── Package.swift
├── Sources/
│   ├── Distill/          # Library target
│   │   ├── Pipeline/
│   │   │   ├── Pipeline.swift            # Orchestrates the full pipeline
│   │   │   ├── MetadataResolver.swift    # yt-dlp metadata extraction
│   │   │   ├── TranscriptAcquirer.swift  # Caption/transcription fallback chain
│   │   │   ├── FrameExtractor.swift      # ffmpeg frame extraction
│   │   │   ├── Summarizer.swift          # LLM summarization
│   │   │   ├── MarkdownParser.swift      # Parses LLM markdown into structured Summary model
│   │   │   ├── TagGenerator.swift        # LLM tag generation (separate call, M2+)
│   │   │   └── OutputWriter.swift        # Markdown/JSON/YAML file output
│   │   ├── Models/
│   │   │   ├── VideoMetadata.swift
│   │   │   ├── Transcript.swift
│   │   │   ├── Summary.swift             # Structured summary (sections, quotes, etc.)
│   │   │   └── Configuration.swift
│   │   ├── Providers/
│   │   │   ├── ClaudeProvider.swift       # Anthropic API client
│   │   │   ├── OpenAIProvider.swift       # OpenAI API client
│   │   │   └── OllamaProvider.swift       # Local Ollama client
│   │   └── Utilities/
│   │       ├── Shell.swift               # Process execution helper (argument arrays, no shell)
│   │       ├── DependencyChecker.swift
│   │       ├── VTTParser.swift           # WebVTT subtitle parsing
│   │       ├── URLValidator.swift        # YouTube URL validation
│   │       ├── SlugGenerator.swift       # Unicode-safe filename slug generation
│   │       ├── CacheManager.swift        # Intermediate result caching
│   │       ├── CostEstimator.swift       # Token count / pricing estimation
│   │       └── PromptLoader.swift        # Loads and renders prompt template
│   └── distill/        # Executable target
│       └── CLI.swift                     # ArgumentParser entry point
├── Tests/
│   ├── DistillTests/
│   │   ├── PipelineTests.swift
│   │   ├── TranscriptAcquirerTests.swift
│   │   ├── VTTParserTests.swift
│   │   ├── OutputWriterTests.swift
│   │   ├── MarkdownParserTests.swift
│   │   ├── URLValidatorTests.swift
│   │   ├── SlugGeneratorTests.swift
│   │   ├── CostEstimatorTests.swift
│   │   ├── PromptLoaderTests.swift
│   │   └── TagGeneratorTests.swift
│   └── DistillIntegrationTests/
│       └── Fixtures/                     # Recorded yt-dlp/ffmpeg output for replay
│           ├── metadata-abc123.json
│           ├── captions-abc123.vtt
│           └── ...
└── Resources/
    └── default-prompt.md                 # Default prompt template bundled with the binary
```

### Testing Strategy

- **Unit tests**: Protocol-based abstractions for all external dependencies (`MetadataResolving`, `TranscriptAcquiring`, `FrameExtracting`, `Summarizing`, `TagGenerating`). Mock implementations injected in tests. Covers pure logic: VTT parsing, URL validation, slug generation, cost estimation, prompt rendering, config parsing, markdown-to-JSON parsing, idempotency hash comparison.
- **Integration tests**: Recorded fixtures from real yt-dlp/ffmpeg output. Tests replay these fixtures through the actual pipeline stages without hitting external services. Ensures the full pipeline works end-to-end with realistic data.
- **No live API tests in CI**: All network-dependent tests use recorded fixtures or mocks.

### Key Swift Dependencies

| Package | Purpose |
|---------|---------|
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | CLI argument parsing |
| [Yams](https://github.com/jpsim/Yams) | YAML configuration parsing |

### API Communication

All LLM API calls use Foundation's `URLSession` — no SDK dependencies needed. API keys are read from environment variables, never stored in configuration files.

### Temp File Management

All temporary files (downloaded audio, video, intermediate transcription output) are written to the system temp directory (`FileManager.default.temporaryDirectory`). The OS cleans these up automatically. No custom signal handling is needed — if the process is interrupted, temp files are reclaimed by the OS on its normal schedule.

---

## Non-Functional Requirements

| Requirement | Target |
|-------------|--------|
| **Platform** | macOS 14+ (Sonoma), Apple Silicon optimized |
| **Swift** | Swift 6.0, Xcode 16+ |
| **Performance** | < 2 minutes for a 30-minute video (transcript only, no frames) |
| **Offline support** | Full pipeline works offline when using local transcription + Ollama |
| **Error handling** | Inline errors with suggested fixes; retry with exponential backoff (3 attempts) |
| **Idempotency** | Re-running skips if output exists and `distill_hash` matches (override with `--overwrite`) |
| **Privacy** | No telemetry. Audio/video files are temp files deleted after processing. Only the summary and frames persist. |
| **Distribution** | `swift build` from source. Additional distribution channels to be determined later. |

---

## Milestones

### M1 — Core Pipeline (MVP)

- [ ] Project scaffolding (SPM, ArgumentParser, Swift 6.0)
- [ ] Metadata resolution via yt-dlp
- [ ] Transcript acquisition (YouTube captions via yt-dlp, VTT parsing)
- [ ] LLM summarization (Claude API) with default bundled prompt
- [ ] Markdown output to a specified file path (`--output`)
- [ ] Basic CLI interface (`distill <url>`)
- [ ] URL validation
- [ ] Slug generation (Unicode-safe, 80 char truncation)
- [ ] Spinner-based progress UX (stderr)
- [ ] Inline error messages with suggested fixes
- [ ] Retry with exponential backoff (3 attempts)
- [ ] Exit codes (0, 1, 3)
- [ ] Default `youtube` tag in frontmatter

### M2 — Obsidian Integration

- [ ] YAML configuration file support (with precedence: CLI > config > defaults)
- [ ] Config validation (error on bad syntax/wrong types, warn on unknown keys)
- [ ] `distill init` (starter config generation)
- [ ] `distill setup` (interactive guided setup)
- [ ] Obsidian vault output with frontmatter
- [ ] Filename formatting with date and slug
- [ ] Tag generation via separate LLM call (default + auto-generated)

### M3 — Frame Extraction

- [ ] `--frames` flag (opt-in)
- [ ] ffmpeg frame extraction at intervals
- [ ] Scene-change detection for key frames
- [ ] Concurrent execution with transcript acquisition via `TaskGroup`
- [ ] Cancellation of frame extraction if transcript fails
- [ ] Audio extraction from downloaded video when `--frames` + `--transcription local`
- [ ] Frame data as markdown table in prompt (`{{frames}}`)
- [ ] LLM generates inline `![](path)` references from frame filenames
- [ ] Max frame limit and cleanup

### M4 — Transcription Fallback

- [ ] `--transcription` flag (`captions`/`local`/`cloud`)
- [ ] Local transcription via mlx-whisper (default model: `base`, configurable)
- [ ] whisper.cpp as alternative backend
- [ ] OpenAI Whisper API as cloud option
- [ ] Automatic fallback chain

### M5 — Batch & Playlist

- [ ] Batch processing from URL file
- [ ] Playlist URL support
- [ ] `--output <dir>` for batch/playlist output directory
- [ ] `--concurrency <n>` for parallel processing
- [ ] `--fail-fast` flag
- [ ] Rate limiting (base delay + exponential backoff on throttle)
- [ ] Detailed status table at end of batch/playlist
- [ ] Exit code 2 for partial failures
- [ ] Index note generation for playlists

### M6 — Polish

- [ ] Dependency checker (`--check-deps`) with version warnings
- [ ] Dry run mode with duration-based cost estimation (approximate range)
- [ ] Idempotency via `distill_hash` in frontmatter (`--overwrite` to bypass)
- [ ] `--quiet` mode (mutually exclusive with `--verbose`)
- [ ] `--format json` and `--format yaml` structured output (markdown → parsed → schema)
- [ ] Format inference from `--output` file extension
- [ ] `--transcript-only` to stdout (`--format` ignored)
- [ ] Custom prompt template (`~/.distill/prompt.md`, `--prompt`)
- [ ] Intermediate result caching (`~/.distill/cache/`)
- [ ] `distill cache clear` and `distill cache status`
- [ ] Obsidian CLI integration (optional)
- [ ] OpenAI and Ollama provider support

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| yt-dlp breaks due to YouTube changes | Pipeline cannot fetch metadata/captions | yt-dlp is actively maintained and typically patches within days. Pin to known-good versions. |
| LLM costs add up with heavy use | Unexpected bills | Show cost estimate in `--dry-run` and post-summary. Default to Sonnet (cheaper) over Opus. Support local Ollama for zero-cost option. |
| Long videos exceed LLM context window | Failed summaries | Fail with clear error and model suggestion. Claude supports 200K tokens (~4 hours of transcript). Chunked summarization deferred to future release. |
| ffmpeg scene detection produces too many/few frames | Cluttered or sparse screenshots | Configurable threshold + max frame cap. Tuned defaults for common video types. Frames are opt-in so users choose when to pay the cost. |
| YouTube captions are low quality (auto-generated) | Poor summary quality | LLMs are robust to transcription errors. Offer `--transcription local` flag to force higher-quality local transcription. |
| Rate limiting during batch processing | Stalled pipeline, incomplete batches | Base delay between videos + exponential backoff on 429 responses. `--fail-fast` for early termination. Detailed status table shows what completed. |
| Markdown-to-JSON parsing fails on unexpected LLM output | Structured output is incomplete | Parse best-effort with fallback to raw markdown in unparseable sections. Log warnings with `--verbose`. |

---

## Prior Art

| Project | What We Learn |
|---------|---------------|
| [steipete/summarize](https://github.com/steipete/summarize) | Transcript-first approach, multi-backend fallbacks, slide extraction with OCR. Most complete existing tool — but it's TypeScript, not Swift, and not Obsidian-native. |
| [TubeSage](https://github.com/rmccorkl/TubeSage) | Obsidian plugin with LLM summarization. Limited to Obsidian context, no CLI, no frame extraction. |
| [YouTubeKit](https://swiftpackageindex.com/alexeichhorn/YouTubeKit) | Native Swift YouTube URL extraction. Useful if we ever want to reduce yt-dlp dependency. |

**What makes `distill` different**: A native macOS CLI tool that combines the best pipeline (transcript-first with smart fallbacks), Obsidian-native output with optional screenshots, and the ergonomics of a single-command workflow — all in Swift for Apple Silicon performance.
