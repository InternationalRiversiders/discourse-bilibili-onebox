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
          - git clone https://github.com/scavin/discourse-bilibili-onebox.git
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

## Troubleshooting

If you see iframe with `data-unsanitized-src` but no `src`:

1. Re-check `allowed_iframes`
2. Re-save or rebake the target posts
3. Check for plugin conflicts (for example, video-processing plugins)

## Demo

- https://meta.appinn.net/t/topic/55832

---

Thanks to [Discourse 中文本地化服务集合](https://github.com/erickguan/discourse-chinese-localization-pack).
