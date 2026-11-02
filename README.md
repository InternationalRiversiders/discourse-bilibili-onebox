# discourse-bilibili-onebox

## Introduction

Discourse plugin for embedding Bilibili videos and live rooms inline.

- Video links: `https://www.bilibili.com/video/...`, `https://m.bilibili.com/video/...`
- Short links: `https://b23.tv/...`
- Live links: `https://live.bilibili.com/...` and `https://live.bilibili.com/blanc/...`

Videos do **not** autoplay.

## Installation

Edit `app.yml` in `plugins` section:

```yml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - mkdir -p plugins
          - git clone https://github.com/discourse/docker_manager.git
          - git clone https://github.com/JackZ144/discourse-bilibili-onebox.git
```

Then rebuild:

```bash
./launcher rebuild app
```

## Behavior

### On create/edit (before save)

For standalone Bilibili video links (one link per line):

- Long links are normalized to canonical form:  
  `https://www.bilibili.com/video/<BVID>`
- Query params are cleaned to keep only `p` (if numeric)
- `b23.tv` links are resolved to long links first, then cleaned with the same rule
- If short-link resolving fails, original short link is kept (fallback path)

### On display

- Matched Bilibili links are rendered as iframe player
- Live room links are rendered as live iframe player

## Usage

Paste links on their own line in the composer.

Examples:

- `https://www.bilibili.com/video/BV1de6CBJED3/?spm_id_from=333.788.videopod.episodes&vd_source=xxx&p=108`
- `https://b23.tv/hiS7rgR`
- `https://live.bilibili.com/12345`

## Required site setting

In admin settings (`allowed_iframes`), include:

```text
https://player.bilibili.com/
https://www.bilibili.com/
```

## Plugin Settings

After installing the plugin, you can configure these options in Admin > Plugins > Bilibili Onebox:

| Setting | Default | Description |
|---------|---------|-------------|
| `bilibili_onebox_enabled` | true | Enable/disable the plugin |
| `bilibili_onebox_resolve_short_links` | true | Auto-resolve b23.tv short links |
| `bilibili_onebox_resolve_live_short_ids` | true | Auto-resolve live room short IDs |
| `bilibili_onebox_cache_duration` | 86400 | Cache duration in seconds (default: 1 day) |

## Troubleshooting

If you see iframe with `data-unsanitized-src` but no `src`:

1. Re-check `allowed_iframes`
2. Re-save or rebake the target posts
3. Check for plugin conflicts (for example, video-processing plugins)

## Demo

- https://meta.appinn.net/t/topic/55832

---

Thanks to [Discourse 中文本地化服务集合](https://github.com/erickguan/discourse-chinese-localization-pack).

## Player fixes (1.4.2)

AV links use the official numeric `aid` parameter; BV links use `bvid`. Valid
multi-part `p` values are preserved. Video embeds use the official player’s own navigation; no extra original-site
link is added below the player. This does not
bypass Bilibili login, regional, copyright, or browser playback restrictions.

Short-link resolution stops at a validated Bilibili `/video/` redirect. It does
not fetch the destination HTML, which can return HTTP 412 even when the video
URL is valid. Successful resolutions are cached. Failures retain the original
link. Creation and editing share this behavior.

Regression tests: run `bundle exec rails runner /path/to/test/player_test.rb`
inside a disposable Discourse instance/database. The tests create a topic and
must not be run against production. They cover AV/BV parameters, multi-part
videos, cached short links, destination-page rejection, create/edit processing,
plain text, multiple inline links, and repeat-processing stability.

For this forum, production releases follow `/opt/AGENTS.md`: prepare and verify
the inactive Web slot, then switch Nginx and drain the previous slot. Do not use
an in-place `launcher rebuild` on the live slot. Existing posts with incorrect
player parameters need their cooked display corrected; changing the plugin
alone does not repair already stored HTML.
