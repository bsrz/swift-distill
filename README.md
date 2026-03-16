# distill

A macOS command-line tool that distills YouTube videos into structured, Obsidian-compatible markdown summaries using LLMs.

**distill** fetches video metadata, extracts transcripts (captions, local whisper, or cloud), optionally captures key frames, summarizes everything with an LLM, and writes the result as a richly-formatted markdown note — ready for your Obsidian vault.

## Features

- Summarize any YouTube video into structured markdown with key takeaways, section summaries, quotes, action items, and a timestamps table
- Direct Obsidian vault integration with YAML frontmatter, wikilinks, and configurable folder structure
- Three transcription methods: YouTube captions (default), local whisper (mlx-whisper / whisper.cpp), or OpenAI Whisper cloud API
- Key frame extraction from videos with scene detection
- Batch processing from a text file of URLs with configurable concurrency
- Full playlist support with automatic index note generation
- Multiple LLM providers: Claude (default), OpenAI, and Ollama (local)
- JSON and YAML output formats with extension-based inference
- Idempotent output with content hashing — won't rewrite unchanged summaries
- Dry-run mode for cost estimation before calling the LLM
- Custom prompt templates
- Intermediate result caching

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6.0+
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — video metadata and transcript extraction
- An LLM API key (Anthropic, OpenAI, or a running Ollama instance)

**Optional:**

- [ffmpeg](https://ffmpeg.org/) — required for `--frames` and local whisper transcription
- [mlx-whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper) — local transcription on Apple Silicon
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — local transcription alternative

Check your setup with:

```bash
distill check-deps
```

## Installation

```bash
git clone https://github.com/your-username/swift-distill.git
cd swift-distill
swift build -c release
cp .build/release/distill-cli /usr/local/bin/distill
```

## Quick Start

```bash
# Set your API key
export ANTHROPIC_API_KEY="sk-ant-..."

# Summarize a video
distill "https://www.youtube.com/watch?v=dQw4w9WgXcQ" --output summary.md

# Interactive setup (creates config + vault folder)
distill setup

# Once configured, output goes to your vault automatically
distill "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

## Usage

### Summarize a single video

```bash
# Basic usage — output to a file
distill "https://www.youtube.com/watch?v=VIDEO_ID" --output notes.md

# With Obsidian vault configured, just pass the URL
distill "https://www.youtube.com/watch?v=VIDEO_ID"

# Extract key frames alongside the summary
distill "https://www.youtube.com/watch?v=VIDEO_ID" --frames

# Use local whisper for transcription (no captions needed)
distill "https://www.youtube.com/watch?v=VIDEO_ID" --transcription local

# Use OpenAI Whisper cloud API
distill "https://www.youtube.com/watch?v=VIDEO_ID" --transcription cloud
```

### Batch processing

Process multiple videos from a text file (one URL per line, `#` comments supported):

```bash
distill batch urls.txt --output ./summaries/
distill batch urls.txt --concurrency 3
distill batch urls.txt --fail-fast
```

### Playlist processing

```bash
distill playlist "https://www.youtube.com/playlist?list=PLxxxxxx" --output ./playlist/
distill playlist "https://www.youtube.com/playlist?list=PLxxxxxx" --concurrency 2
```

This resolves all video URLs in the playlist, processes each one, and generates an index note linking to all summaries.

### Transcript only

Print the raw transcript to stdout without summarization (no API key required):

```bash
distill "https://www.youtube.com/watch?v=VIDEO_ID" --transcript-only
distill "https://www.youtube.com/watch?v=VIDEO_ID" --transcript-only > transcript.txt
```

### Dry run

See estimated cost without calling the LLM:

```bash
distill "https://www.youtube.com/watch?v=VIDEO_ID" --dry-run
```

### Output formats

```bash
# Default: Obsidian-compatible markdown with YAML frontmatter
distill "URL" --output summary.md

# Structured JSON
distill "URL" --output summary.json
distill "URL" --format json --output summary.txt

# Structured YAML
distill "URL" --output summary.yaml
distill "URL" --format yaml
```

The format is inferred from the file extension (`.json`, `.yaml`, `.yml`), or you can set it explicitly with `--format`.

### LLM providers

```bash
# Claude API (default, requires ANTHROPIC_API_KEY)
distill "URL"

# Claude CLI — uses your existing Claude Pro/Max subscription, no API key needed
distill "URL" --provider claude-cli

# OpenAI API
export OPENAI_API_KEY="sk-..."
distill "URL" --provider openai

# OpenAI with a specific model
distill "URL" --provider openai --model gpt-4-turbo

# Ollama (local, no API key needed)
distill "URL" --provider ollama --model llama3.2
```

The `claude-cli` provider shells out to the `claude` CLI (Claude Code) in non-interactive mode. It uses your existing subscription login — no API key required. You must have `claude` installed and authenticated (`claude` will prompt you to log in on first use).

### Custom prompt

```bash
distill "URL" --prompt ~/.distill/my-prompt.md
```

The prompt template supports these placeholders:

| Placeholder | Description |
|---|---|
| `{{title}}` | Video title |
| `{{channel}}` | Channel name |
| `{{duration}}` | Video duration string |
| `{{transcript}}` | Full transcript text |
| `{{frames}}` | Frame extraction table (empty if `--frames` not used) |
| `{{language}}` | Transcript language code |

### Cache management

```bash
distill cache status    # Show cache size and entry count
distill cache clear     # Remove all cached data
```

### Other options

```bash
# Suppress all non-essential output
distill "URL" --quiet

# Show detailed progress and debug info
distill "URL" --verbose

# Overwrite existing output even if content unchanged
distill "URL" --overwrite

# Use browser cookies for age-restricted videos
distill "URL" --cookies-from-browser brave

# Use a specific config file
distill "URL" --config ~/my-config.yaml
```

## Configuration

Run `distill init` or `distill setup` to create `~/.distill/config.yaml`:

```yaml
# distill configuration

obsidian:
  vault: "~/Documents/Obsidian"
  folder: YouTube
  filename_format: "{date}-{slug}"
  attachments: YouTube/attachments
  image_syntax: markdown          # or: wikilink
  use_cli: false                  # use Obsidian CLI for writing notes (requires Obsidian 1.12+)

tags:
  default:
    - youtube
  auto_tag: true                  # generate tags via LLM

summarization:
  provider: claude                # claude, claude-cli, openai, ollama
  model: claude-sonnet-4-6
  api_key_env: ANTHROPIC_API_KEY
  max_tokens: 8192

transcription:
  prefer: captions                # captions, local, cloud
  local_engine: mlx-whisper       # mlx-whisper, whisper.cpp
  model: base
  language: en
  openai_api_key_env: OPENAI_API_KEY

frames:
  max_frames: 20
  interval_seconds: 60
  scene_detection: true
  scene_threshold: 0.4

# cookies_from_browser: brave
```

CLI flags always override config file values.

### Filename format

The `filename_format` option supports these tokens:

| Token | Example |
|---|---|
| `{date}` | `2025-03-14` |
| `{slug}` | `how-to-build-a-cli-in-swift` |

Default: `{date}-{slug}` produces files like `2025-03-14-how-to-build-a-cli-in-swift.md`.

### Obsidian CLI integration

When `use_cli: true` is set, distill uses the [Obsidian CLI](https://help.obsidian.md/cli) (available in Obsidian 1.12+) to create notes instead of writing files directly. This means:
- Notes appear instantly in Obsidian without waiting for re-indexing
- Obsidian's internal link resolution is used
- Falls back to direct file writes if the Obsidian CLI is unavailable or Obsidian isn't running

Requirements: Obsidian must be running, and the CLI must be registered via **Settings > General > Command line interface > Register CLI**.

### Obsidian vault structure

With the default configuration, distill writes to:

```
~/Documents/Obsidian/
  YouTube/
    2025-03-14-video-title.md
    2025-03-14-another-video.md
    attachments/
      video-title/
        frame_001_00m30s.png
        frame_002_01m45s.png
```

## Output

### Markdown (default)

```markdown
---
title: "How to Build a CLI in Swift"
source: https://www.youtube.com/watch?v=VIDEO_ID
channel: "Swift by Sundell"
published: 2025-01-15
summarized: 2025-03-14
duration: "12:34"
distill_hash: a1b2c3d4e5f6a7b8
tags:
  - youtube
  - swift
  - cli-development
type: youtube-summary
---

## Key Takeaways

- Swift's ArgumentParser library makes CLI development straightforward
- ...

## Section Summaries

### Introduction [00:00:00 - 00:01:30]
...

## Notable Quotes

> "The best CLI tools do one thing and do it well." — 00:05:22

## Action Items

- Try building a simple CLI with `swift package init --type executable`
- ...

## Timestamps

| Timestamp | Topic |
|-----------|-------|
| 00:00:00  | Introduction |
| 00:01:30  | Setting up the project |
| ...       | ... |
```

### Idempotency

Each output file includes a `distill_hash` in its frontmatter. If you re-run distill on the same video and the content hasn't changed, the file is skipped. Use `--overwrite` to force a rewrite.

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Failure (single video or all videos in batch failed) |
| `2` | Partial failure (some videos in batch/playlist failed) |
| `3` | Configuration error (missing API key, invalid config) |

## Architecture

distill is built as a Swift 6 library (`Distill`) with a thin CLI wrapper (`distill-cli`). The pipeline is protocol-based with dependency injection for full testability.

```
YouTube URL
    |
    v
[URLValidator] ── validate & extract video ID
    |
    v
[MetadataResolver] ── yt-dlp --dump-json
    |
    v
[TranscriptAcquirer] ── captions (yt-dlp) / local (whisper) / cloud (OpenAI)
    |                         |
    |   (concurrent if --frames)
    |                         v
    |                  [FrameExtractor] ── ffmpeg scene detection
    |
    v
[Summarizer] ── Claude / OpenAI / Ollama
    |
    v
[OutputWriter] ── markdown / JSON / YAML with frontmatter & hash
```

### Key design decisions

- **Swift 6 strict concurrency** — full `Sendable` conformance, no data races
- **Protocol-based stages** — every pipeline stage is a protocol, enabling mock-based testing
- **Concurrent transcript + frame extraction** via `TaskGroup`
- **Automatic retry** with exponential backoff for transient errors (HTTP 429, 5xx)

## Development

```bash
# Build
swift build

# Run tests (111 tests across 28 suites)
swift test

# Run directly
swift run distill-cli "https://www.youtube.com/watch?v=VIDEO_ID" --output /tmp/test.md
```
