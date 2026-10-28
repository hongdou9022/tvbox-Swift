# 云影视 · CloudVideo (iOS)

媒体服务器的 iOS 客户端，严格按 `Box/docs/PHONE_UI_SPEC.md`（**v1.3**）实现。

- 语言 / UI：Swift 5.9 + SwiftUI
- 最低版本：iOS 17.0
- 播放内核：AVPlayer
- 工程管理：XcodeGen
- 后端接口：`omnibox/backend` 的 `/api/app/v1/*` 与 `/api/favorite`

---

## 一、和规范的对齐情况

| 规范章节 | 实现 | 说明 |
| --- | --- | --- |
| 0.1 配色 | ✅ | `Theme.swift` 逐条对应，含弹幕开关的 `#6BE38F` / `#8A8FA3` |
| 0.2 字号 | ✅ | `Theme.fontTitle/fontSection/fontCardTitle/fontCardMeta/fontBadge` |
| 0.3 圆角与间距 | ✅ | 卡片 10 / 剧集 8 / 输入框 18 / 弹层 20，页面 14、网格 9 |
| 1 登录 | ✅ | 地址自动补 `http://`、去尾斜杠；标题 26sp + 字距 0.08em 且取 `CFBundleDisplayName` 不硬编码；全 App 无旧名 |
| 2 主框架 | ✅ | 首页 / 电视 / 直播 / 我的，四栈独立 |
| 3.1 顶部结构 | ✅ | 胶囊搜索栏 + 五频道 + 18×3dp 绿色短横线 |
| 3.2 推荐页 | ✅ | 196dp 轮播、4 秒自动、6dp 圆点；分区标题 3×16dp 绿条；3 列横卡每区 6 个 |
| 3.3 分类页 | ✅ | 无轮播、首屏连续拉页铺满、滚动预加载、底部文案 |
| 3.4 推荐卡片 | ✅ | 图高 86、左上类型角标、右上金色评分、13sp 标题 + 10sp 元信息 |
| 3.4 点击行为 | ✅ | 无 `libraryId/videoId` 的豆瓣条目 → 按剧名跳搜索 |
| 4.1 搜索范围 | ✅ | 独占一行、30dp 胶囊、同行 11sp 速度提示；选择后写本地配置并立即重搜 |
| 4.2 最近热搜 | ✅ | 两列带序号，来源为本地搜索历史 + 推荐标题，最多 6 条 |
| 4.3 结果列表 | ✅ | 两列、海报 + 片名 + 绿色来源名 + 备注；状态行文案按规范 |
| 4.4 结果排序 | ✅ | rank 0–4 + 源优先级（`total-index` 降序）+ 来源名 + 片名；含粗过滤，已按 4.4.8 样例验证 |
| 5.1 详情结构 | ✅ | 16:9 播放区、20sp 标题 + 38dp 收藏、信息行、多源卡片、4 列剧集 |
| 5.2 竖屏控件 | ✅ | 播放 34 / 时间 11sp / 进度 2dp 橙 / 清晰度 12 / 弹 12 / 全屏 32 |
| 5.2 弹幕 | ✅ | 按「片名 年份 集名」匹配，解析 XML/JSON/纯文本，Canvas 逐帧渲染 |
| 5.3 多源卡片 | ✅ | 选中绿描边 + 深绿底；单源整块隐藏 |
| 5.4 收藏 | ✅ | 乐观更新（同步翻图标，≤150ms）+ 失败回滚 + 在途写请求保护后台刷新 |
| 5.5 详情弹层 | ✅ | 拖拽条、78×110 海报、概要（过滤 HTML）、来源 |
| 5.6 横屏全屏 | ✅ | 转屏、锁屏、底部两行、返回先退全屏并回竖屏 |
| 5.7 推送电视 | ✅ | 局域网发现 + 配对 + 推送，失败回落服务端单槽 |
| 6 电视 / 直播 | ✅ | 局域网设备列表；IPTV 源解析 m3u/txt，分组播放 |
| 7 我的 | ✅ | 账号、继续观看、收藏、设置入口 |
| 8 状态文案 | ✅ | 全部按规范原文，见 `Components.swift` 与各 ViewModel |
| 9 iOS 注意事项 | ✅ | pt 1:1、竖屏锁定、LazyVGrid 复用、海报圆角 10、`#1A1B22` 占位、安全区 |

### v1.1–v1.3 变更跟进

| 版本 | 变更 | 落地 |
| --- | --- | --- |
| v1.1 | 收藏改乐观更新 | 点击同步翻转 `isFavorited`，再后台提交；`favoriteMutationInFlight` 阻止后台刷新覆盖 |
| v1.1 | 恢复搜索范围按钮 | 独占一行、30dp、右侧「全站搜索会同时查询所有来源，较慢」/「仅搜索该来源，更快」 |
| v1.1 | 搜索排序改匹配度优先 | `SearchRanker` 重写，见 4.4 |
| v1.2 | 4.4 补伪代码 / 归一化 / 同分 / 增量合并 | `normalize` 只剔除规范列出的分隔符（括号内内容保留）；分词用**原始关键词**且单字词不参与；同分按来源名 → 片名稳定排序 |
| v1.2 | 登录页应用名统一 | 标题改 `AppInfo.displayName` |
| v1.3 | 全 App 清除旧名 | 登录页标题、设置页名称与版本、服务器名兜底全部走 `AppInfo.displayName` |

排序逻辑我用 JS 镜像跑过规范 4.4.8 的验收样例，结果一致：

```
搜「凡人修仙传」
  1. [rank 0] 凡人修仙传          (星云源)
  2. [rank 1] 凡人修仙传：外海风云  (星云源)
  3. [rank 1] 凡人修仙传：魔道争锋  (天空源)
  4. [rank 2] 新凡人修仙传        (月亮源)
  5. [rank 4] 修仙传             (星云源，保留但排最后)
```

### 尚未跟进（依赖后端）

规范 4.5「待优化」四项需要后端提供**流式分批返回**才能落地，当前 `/api/app/v1/search`
是一次性聚合返回，客户端拿不到「哪个源先回来」：

- 首屏优先返回高优先级源与低延迟源
- 命中缓存的源立即展示并标记「缓存」
- 长时间无响应源设置更激进超时
- 源级并发上限按实测延迟动态调整

客户端侧的排序与粗过滤已按 4.4 完成，后端改为流式后可直接接上。

### 三项补充实现说明

**1. 推送电视（5.7）**

协议来自电视端 `Box/.../remote/PairingServer.java` 与 `omni/phone/PhoneCastSheet.java`：

| 环节 | 实现 |
| --- | --- |
| 发现 | 本机各 IPv4 网段 /24 全量探测 + 回环，`GET http://<ip>:10081/v2/info`，校验 `magic == "OMNIBOX_TV"`，并发 24、单请求 1.5s |
| 归属过滤 | `omniHost` 必须与当前后端 host 一致，避免列出别人的电视 |
| 配对 | `POST /v2/pair` body `{deviceId, deviceName}` → `{token}`，token 存本地 |
| 推送 | `POST /v2/push`，header `X-Box-Token`，body 为载荷 |
| 回落 | 局域网失败 → 后端 `POST /devices/:id/pair` + `/push`，文案「已发送到服务器，电视下次前台时收取」 |
| 记忆 | 上次连过的设备置顶（`lastDevice`） |

载荷：`{sourceType, libraryId, videoId, line, episode, episodeId, positionMs, title}`。

> 首次连接局域网地址会触发 iOS 的「本地网络」权限弹窗，需要允许，否则扫不到电视。

**2. 电视 / 直播（第 6 章）**

- 电视：复用同一套发现层，列出局域网设备 + 配对状态，支持重新扫描。
- 直播：`GET /api/iptv/enabled` → 每个源优先用内嵌 `content`，否则拉 `url`；
  解析 M3U（`#EXTINF` + `group-title` / `tvg-logo`）与 TXT（`分组,#genre#`）；
  同名频道合并；播放复用同一套播放器（横屏 + 锁屏）。

**3. 弹幕**

- `POST /api/app/v1/danmaku` body `{fileName}`，`fileName = "片名 年份 集名"`（空项跳过，
  与电视端 `OmniDanmaku.buildFileName` 一致）。返回的是**弹幕文件列表**，内容需自行下载。
- 解析兼容三种格式：B 站 XML（`<d p="...">`）、JSON 数组、纯文本行；GBK 兜底。
- 渲染：`TimelineView(.animation)` + `Canvas`，用「最后进度回调 + 墙钟增量」插值，
  6 条泳道，二分查找可视窗口，单帧最多 80 条。开关状态与设置页联动。

---

## 二、数据层

全部接口按 `backend/internal/handlers/app/app.go` 的结构体定义对接：

| 方法 | 接口 |
| --- | --- |
| 登录 | `POST /api/app/v1/auth/login` |
| 首页 | `GET /api/app/v1/home` |
| 推荐 | `GET /api/app/v1/recommend` |
| 分类 | `GET /api/app/v1/category?libraryId=&categoryId=&page=` |
| 详情 | `GET /api/app/v1/media?libraryId=&videoId=&sourceType=` |
| 播放 | `GET /api/app/v1/play?libraryId=&videoId=&line=&episode=&sourceType=` |
| 续播 | `GET /api/app/v1/resume?limit=` |
| 进度 | `POST /api/app/v1/progress` |
| 搜索 | `GET /api/app/v1/search?q=&page=&sourceId=` |
| 搜索源 | `GET /api/app/v1/search-sources` |
| 收藏状态 | `GET /api/favorite/check?vodId=&sourceId=` |
| 收藏增删 | `POST /api/favorite` / `DELETE /api/favorite/:id` |
| 直播源 | `GET /api/iptv/enabled` |
| 弹幕 | `POST /api/app/v1/danmaku` |
| 设备配对 | `POST /api/app/v1/devices/:id/pair` |
| 设备推送 | `POST /api/app/v1/devices/:id/push` |

统一响应封装 `{code, message, data, success}`，401 直接抛 `unauthorized`。
除登录外全部带 `Authorization: Bearer <token>`。

> 规范 3.5 建议推荐接口「客户端直连豆瓣优先，后端兜底」。这里统一走后端
> `/recommend`：它已经做了分区聚合与豆瓣兜底，客户端再直连反而要重复实现
> 分区逻辑，且豆瓣对无 UA/Referer 的请求会返回异常。

---

## 三、目录结构

```
CloudVideo/
├── project.yml
├── CloudVideo/
│   ├── Info.plist
│   ├── App/
│   │   ├── CloudVideoApp.swift     # 入口 + 全局外观 + 方向代理
│   │   └── RootView.swift          # 登录 / 四 Tab
│   ├── Design/
│   │   ├── Theme.swift             # 0.1–0.3 全套 + OrientationLock
│   │   └── Components.swift        # 分区标题、按钮、空态、拖拽条
│   ├── Models/
│   │   ├── APIModels.swift         # 与 Go 结构体一一对应
│   │   └── Navigation.swift        # Route / MediaTarget
│   ├── Services/
│   │   ├── APIClient.swift
│   │   ├── SessionStore.swift      # 登录态 + Keychain
│   │   ├── Keychain.swift
│   │   ├── ImagePipeline.swift     # 带 Referer 的海报加载
│   │   ├── SearchRanker.swift      # 4.4 匹配度排序
│   │   ├── CastService.swift       # 5.7 局域网发现 / 配对 / 推送
│   │   ├── LiveService.swift       # 6 IPTV 源解析
│   │   └── DanmakuService.swift    # 弹幕匹配与解析
│   └── Features/
│       ├── Login/ Home/ Search/ Detail/ Player/
│       ├── Cast/ TV/ Live/ Mine/ Settings/
└── prototype/
    └── cloudvideo-preview.html     # 浏览器直接打开的高保真预览
```

---

## 四、编译

需要 macOS + Xcode 15+。

```bash
brew install xcodegen
cd CloudVideo
xcodegen generate
open CloudVideo.xcodeproj
```

选中 `CloudVideo` scheme，设置开发者 Team，`Cmd + R`。

### 没有 Mac 怎么验证？

Windows / Linux 上**无法编译 SwiftUI**（没有 Apple SDK），也**没有 iOS 模拟器**。

`.github/workflows/cloudvideo-build.yml` 会在 GitHub Actions 的 macOS runner 上跑真实编译：

1. `brew install xcodegen` → `xcodegen generate`
2. `xcodebuild -scheme CloudVideo -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
3. 失败时单独摘出 `error:` 行并上传完整 `build.log`

不需要开发者账号或证书 —— 编译模拟器版本不涉及签名。

本地能做到的最强检查是**语法解析**（tree-sitter-swift），能抓括号、语法结构、非法
token，但抓不到类型错误。真正的类型检查只能跑 macOS。

> 注意：tree-sitter 的 Swift 语法不支持 `if let x = try? await f()`，
> 所以代码里统一拆成 `let x = try? await f()` + `if let x` 两步。

---

## 五、免责声明

本项目仅供技术交流。应用不提供、不内置任何影视资源，所有内容均来自使用者
自行连接的媒体服务器。
