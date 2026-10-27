# 跨设备同步设计（未实现）

此文档给出后续实现的最小数据契约，避免把“夸克登录”误当作应用身份。当前版本**没有任何远程同步代码或服务**，观看记录只在本机 SharedPreferences。

## 身份分层

1. **应用账号**：独立于夸克，负责设备、收藏、历史和偏好。建议邮箱/手机号或一次性设备码 + 服务端签发的短期访问令牌。
2. **网盘授权**：每个观看者在本机连接夸克；Cookie 只存设备 Keychain/Keystore，不上传同步服务。
3. **设备**：应用账号下的 device_id、名称、平台、最后活跃时间。

## 最小数据模型

```text
users(id, created_at, status)
devices(id, user_id, name, platform, last_seen_at, revoked_at)
favorites(user_id, work_id, created_at, deleted_at, version)
progress(
  user_id, work_id,
  season, episode,
  position_ms, duration_ms,
  line_group, resource_fingerprint,
  completed, updated_at, device_id, version
)
preferences(user_id, key, value_json, updated_at, version)
libraries(user_id, kind, config_json, updated_at, version)
```

约束：

- `work_id` 使用后台作品 ID（如 `tmdb:tv:...`），不使用某一分享资源 ID；换线路不丢进度。
- `resource_fingerprint` 只用于辅助判断同一文件/版本，不作为主键。
- 不上传夸克 Cookie、分享 URL、直链、文件 ID 路径或账号。
- 删除采用 tombstone（`deleted_at`），避免离线设备把已删除收藏重新推回。

## API（提案，未实现）

```text
POST /v1/auth/device/start
POST /v1/auth/device/finish
POST /v1/auth/refresh

GET  /v1/sync/pull?cursor=<opaque>
POST /v1/sync/push
DELETE /v1/devices/{id}
```

`/v1/sync/pull` 返回服务端游标、增量记录和服务器时间。

`/v1/sync/push` 接受客户端产生的 `mutation_id`，服务端按幂等键去重。每条记录带 `version`，使用乐观并发；冲突策略：

- 观看进度：同一 work/season/episode 取 `updated_at` 较新的非未来时间；若几乎相同，按完成状态 > 位置较大。
- 收藏：删除 tombstone 优先于旧的新增。
- 偏好：字段级最后写入，避免整个 JSON 覆盖。
- 片库配置：设备本地配置不强制同步，除非明确标记为账户级。

离线队列存储在本机，联网后重试；访问令牌存 Keychain/Keystore。

## 接续流程

1. iPhone 和服务端记录 `progress(work, season, episode, position)`。
2. Android TV 登录同一应用账号，拉取增量，展示“继续观看”。
3. TV 选中后仍使用 TV 自己的夸克授权和本机转存；同步只传递观看位置，不传递媒体或网盘凭据。
4. 两端同时播放同一作品时，由 `updated_at` 决定当前主进度；不宣称实时同播。

## 实施前置

- 选择/搭建服务端、数据库和身份验证；
- TLS、限流、审计、账户注销与数据删除；
- 端到端测试跨设备冲突、断网、时钟偏差、重放和撤销设备；
- 隐私说明和用户同意。

本版本不包含上述服务器、客户端 API 或 UI，只保留本机 LocalStore。不得以“夸克已登录”暗示观看记录已同步。
