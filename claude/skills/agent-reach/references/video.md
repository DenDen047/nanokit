# YouTube

`yt-dlp` is a pixi global tool; `~/.config/yt-dlp/config` already sets
`--js-runtimes node`, which YouTube needs for subtitles and some formats.

## Metadata

```bash
yt-dlp --dump-json "URL"
```

## Subtitles

```bash
yt-dlp --write-sub --write-auto-sub --sub-lang "en,ja" --skip-download \
  -o "/tmp/%(id)s" "URL"
cat /tmp/VIDEO_ID.*.vtt
```

Manually uploaded subtitles are reliable; auto-generated ones repeat lines across
cue boundaries and need de-duplication before quoting.

## Comments

```bash
yt-dlp --write-comments --skip-download --write-info-json \
  --extractor-args "youtube:max_comments=20" -o "/tmp/%(id)s" "URL"
# comments land in the .info.json "comments" field
```

Scraped, not the Data API — treat the set as a sample, not as complete.

## Search

```bash
yt-dlp --dump-json "ytsearch5:query"
```

## When there are no subtitles

`agent-reach transcribe URL` downloads the audio and transcribes it, but it needs a
Groq or OpenAI key (`agent-reach configure groq-key`) that is not configured on this
host. Either ask the user before setting one up, or say the video has no usable
transcript. Do not send audio to a provider on your own initiative.

Note: `yt-dlp` is for YouTube only here. Bilibili blocks it and has no backend
installed on this host.
