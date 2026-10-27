# vod-web 接口契约（独立核查）

核查日期：2026-10-27。对象：`D:\各软件安装位置\vod-web`，只读请求 `127.0.0.1:8765`，未改生产、未转存、未播放。

## 0.2.0+2 当前适配补充

- `workId` 是客户端归并作品和片单/进度的首选身份；缺失时退回原 key，不按同名猜合并。API key 仍用于请求对应季详情。
- 海报与横图分别映射；支持 `backdrop/backdropUrl/background`、`genres`、`runtimeMinutes`、简介、评分、演员、导演。缺失时如实显示，不自动绑定示意资料。
- 首页在类型不全或可用作品不足时补相应 typed list，即使首页已有 20 部剧集也补电影；先呈现已获得数据，再异步补充。
- 列表 `sources[].lines[].preview` 在当前生产源码中是完整条目映射。资源描述仅驻内存，可直接进入授权播放；首页缓存明确剔除线路、分享和播放入口。
- 冷缓存时先请求当前季详情；其他季用搜索分页结果按**完全一致的 workId**合并，不串行请求每季详情。补季失败保留当前季并允许重试。实际资源保留所属 API key，便于从历史回到正确季。
- 默认续播/片单按作品计一条；界面显示已加载的不同作品数，不把服务端季行总数当作品总量。只有下一集编号连续或已知季终才自动跳转，不越过缺集。
- 本轮真实 API 7.6–10.4 秒；以下更早数字只作历史抽样，最新日志见 `VERIFICATION-20261027-CODEX.md`。

以下为早期原始响应与规则记录。

## 1. 已核实入口

| 方法与路径 | 参数 | 返回用途 | 客户端是否已接 |
| --- | --- | --- | --- |
| `GET /api/home` | 无 | `fourK`、`latest`、`stats` | 是 |
| `GET /api/list` | `type=movie\|tv`，`pg` | 分页作品、线路、资源描述 | 是 |
| `GET /api/search` | `wd` 必填，`pg` | 按片名搜索 | 是 |
| `GET /api/detail` | `id=<verified__base64>` | 作品详情、线路、每集资源描述 | 是 |
| `GET /api/resource` | `id=<resource id>` | 单条资源描述 | 服务层已实现，界面优先使用详情内嵌描述 |
| `GET /api.php/provide/verified/` | MacCMS 参数 | 兼容列表/详情 | 未接；客户端使用 JSON 专用接口 |

源码定位：

- `server.mjs`：HTTP 路由、`/api/home`、`/api/list`、`/api/search`、`/api/detail`、`/api/resource`、MacCMS 入口。
- `lib/verified-feed.mjs`：资格 SQL、线路去重、资源描述。
- `lib/cloud/quark.mjs`：观看者需要完成的夸克内部操作参考。
- `lib/db.mjs`：`work_catalog` 等表结构。

## 2. 实际响应结构（已用客户端模型解析）

### `/api/home`

顶层键：`ok`、`playback`、`fourK`、`latest`、`stats`。

`fourK` 与 `latest` 为作品数组，单项主要字段：

```json
{
  "key": "verified__...",
  "name": "作品名",
  "year": "2008.0",
  "workId": "tmdb:movie:...",
  "mediaType": "movie",
  "coverage": {
    "expected": 1,
    "covered": 1,
    "standardCovered": 0,
    "largeCovered": 1,
    "complete": true
  },
  "pics": [],
  "remarks": ["分辨率实测达标 · 普通 0/1 · 大文件 1/1"],
  "score": "",
  "sources": []
}
```

`score`、`pics` 可以为空；`year` 也可能缺失或带 `.0`。客户端按整数解析，并对空字段显示“待补齐”。

进一步抽样发现：`/api/home` 可能返回 `mediaType=null` 的未解析条目（片名也可能尚未归并）。客户端不会把这类条目猜成电影，而是标记为“类型待补齐”，并在首页精选/分类中排除，避免误导。若可用行不足 8 条，客户端会并发读取 `/api/list?type=movie` 与 `/api/list?type=tv` 的第一页来补足首页；这不修改后台，也不在手机端按文件名刮削全库。

### `/api/detail`

顶层为 `ok`、`playback`、`item`、`lines`。

- `item` 包含 `id`、`name`、`year`、`mediaType`、`pic`、`actor`、`director`、`content`、`remarks`、`coverage` 等。
- `lines[]` 是版本线路，字段 `group`、`has4k`、`qualities`、`count`、`entries`。
- `entries[]` 有 `label`、`url`、`quality`、`isM3u8`、`resource`。
- `resource` 才是客户端需要交给设备内夸克桥接的信息，包含分享、文件 ID、文件路径、大小、季集、实测视频参数。

典型资源描述：

```json
{
  "id": "resource id",
  "platform": "quark",
  "playback": "client",
  "share": {"url": "https://pan.quark.cn/s/...", "id": "...", "password": null},
  "file": {"id": "...", "name": "...mkv", "path": "...", "sizeBytes": 78129395856},
  "tier": "large",
  "season": null,
  "episode": null,
  "video": {
    "width": 3840,
    "height": 2160,
    "codec": "hevc",
    "bitrate": 102023238,
    "durationSeconds": 6126.4,
    "bitDepth": 10
  },
  "accountRequirement": "viewer_quark_account"
}
```

**关键结论：`url` 指向资源描述接口，不是可直接播放的媒体地址。** 真正播放地址仍需观看者账号完成夸克转存与取链。

## 3. 资格与线路规则（来自源码，非界面推测）

`lib/verified-feed.mjs` 的资格条件包括：

- `route='cloud_share'`、`source='quark'`、分享 URL 形式受限；
- `last_seen` 在一天内；
- `verified_by='file_probe_v2'` 且存在文件 ID；
- `is_uhd=1`、级别 `L2_probed` 或 `L3_decoded`；
- 分辨率条件；
- 每个作品/季集/档位最多两条线路；
- 标准档与大文件档分界为 `10,000,000,000` 字节。

因此当前发布源不是全库、不是普通清晰度全集，也不代表所有历史上验证过的条目仍在发布。

## 4. 数据完整性抽样（只读）

2026-10-27 16:12 左右，第一页样本：

| 类别 | 返回 | 总数字段 | 海报缺失 | 年份缺失 |
| --- | ---: | ---: | ---: | ---: |
| 电影 `/api/list?type=movie` | 20 | 468 | 20/20 | 0/20 |
| 电视剧 `/api/list?type=tv` | 20 | 325 | 20/20 | 10/20 |

同次详情抽样中，第一部电影没有海报、简介、演员和导演字段值。样本只能说明这些问题实际存在，不能推导全库比例。客户端没有在手机端按文件名重新刮削片库，也没有用演示图片冒充海报。

后续真实接口测试（16:53）成功解析：

```text
home=20 moviePage=20 tvPage=20 search=1 detailLines=1 detailEntries=17
```

## 5. 性能抽样

同机只读请求，单次耗时（会因后台采集和 SQLite 负载变化）：

| 路径 | 状态 | 字节 | 耗时 |
| --- | ---: | ---: | ---: |
| `/api/home` | 200 | 256,835 | 8,892 ms |
| `/api/list?type=movie&pg=1` | 200 | 34,286 | 3,567 ms |
| `/api/list?type=tv&pg=1` | 200 | 455,349 | 4,448 ms |
| `/api/search?wd=钢铁侠` | 200 | 3,466 | 3,930 ms |

客户端因此设置了 30 秒请求超时、首页本地缓存和明确的超时/重试状态。这里的耗时是本机采样，不代表 iPhone 网络表现。

17:14 的客户端实测进一步显示：`/api/home` 408,897 字节 / 7.9 秒，电影列表 34,475 字节 / 4.3 秒，电视剧列表 357,419 字节 / 3.7 秒，详情 14,298 字节 / 4.0 秒，搜索 15,080 字节 / 5.4 秒。后台采集进行中，数字会变。

## 6. 接口缺口与适配

| 缺口 | 客户端当前处理 | 后台后续建议 |
| --- | --- | --- |
| 海报大量为空 | 用真实空态海报，不伪造图片 | 继续补元数据 |
| 简介/演员/导演为空 | 隐藏演职员，简介显示“暂未提供” | 补 TMDB/片库字段 |
| 季集只有编号 | 显示“第 N 集”和无虚构标题 | 提供季集标题、简介、时长 |
| 只有已核验 4K 线路 | 明确为已核验片库 | 需要普通档时增加独立索引 |
| 分享/文件描述不具备播放地址 | 设备内夸克桥接 | 不要改成服务端代播 |
| 接口无 CORS/客户端身份概念 | 原生 HTTP 直接读取 | 正式公网建议 HTTPS、限流和只读缓存 |

没有为此在本次交付中修改生产接口。`/api/home` 已存在，无需补该路由。
