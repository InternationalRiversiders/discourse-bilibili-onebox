# discourse-bilibili-onebox

## 简介

这是一个用于在 Discourse 内联播放 Bilibili 视频/直播的插件。

- 视频链接：`https://www.bilibili.com/video/...`、`https://m.bilibili.com/video/...`
- 短链接：`https://b23.tv/...`
- 直播链接：`https://live.bilibili.com/...`、`https://live.bilibili.com/blanc/...`

视频**不会**自动播放。

## 安装

在 `app.yml` 的插件部分添加：

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

然后重建：

```bash
./launcher rebuild app
```

## 行为说明

### 发帖/编辑（入库前）

针对“单独一行”的 B 站视频链接：

- 长链接会规范化为：  
  `https://www.bilibili.com/video/<BVID>`
- 查询参数只保留 `p`（且必须是数字）
- `b23.tv` 会先解析为长链接，再执行同样清洗规则
- 若短链接解析失败，则保留原短链接（走兜底路径）

### 帖子展示

- 命中的 B 站链接会渲染为 iframe 播放器
- 直播链接会渲染为直播 iframe 播放器

## 使用方式

在编辑器中将链接单独占一行粘贴。

示例：

- `https://www.bilibili.com/video/BV1de6CBJED3/?spm_id_from=333.788.videopod.episodes&vd_source=xxx&p=108`
- `https://b23.tv/hiS7rgR`
- `https://live.bilibili.com/12345`

## 必要配置

后台 `allowed_iframes` 需包含：

```text
https://player.bilibili.com/
https://www.bilibili.com/
```

## 排查建议

如果看到 iframe 只有 `data-unsanitized-src`、没有 `src`：

1. 检查 `allowed_iframes` 是否正确
2. 对目标帖子重新保存或 `rebake`
3. 检查是否存在插件冲突（例如其他视频处理插件）

## 使用效果

- https://meta.appinn.net/t/topic/55832

---

感谢 [Discourse 中文本地化服务集合](https://github.com/erickguan/discourse-chinese-localization-pack)。
