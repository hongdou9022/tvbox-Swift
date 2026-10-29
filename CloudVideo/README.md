# 云影视 · CloudVideo (iOS)

媒体服务器的 iOS 客户端。实现依据三份文档：

| 文档 | 版本 | 负责 |
| --- | --- | --- |
| `Box/docs/PHONE_UI_SPEC.md` | **v1.14**（2026-10-29） | 界面、尺寸、交互、文案 |
| `Box/docs/SEARCH_OPTIMIZATION.md` | v1.5 | 搜索链路、并发、缓存、排序、源评分 |
| `Box/docs/PHONE_FUNCTION_API_SPEC.md` | v1.0 | 功能清单与接口契约 |

- 语言 / UI：Swift 5.9 + SwiftUI
- 最低版本：iOS 17.0
- 播放内核：AVPlayer
- 工程管理：XcodeGen
- 状态：GitHub Actions macOS 真实编译 **0 error / 0 warning**（42 个 Swift 文件）

---

## 一、和 PHONE_UI_SPEC 的对齐情况

| 规范章节 | 实现 | 说明 |
| --- | --- | --- |
| 0.1 配色 | ✅ | `Theme.swift` 逐条对应，含弹幕开关 `#6BE38F` / `#8A8FA3` |
| 0.2 字号 | ✅ | `Theme.fontTitle/fontSection/fontCardTitle/fontCardMeta/fontBadge` |
| 0.3 圆角与间距 | ✅ | 卡片 10 / 剧集 8 / 输入框 18 / 弹层 20，页面 14、网格 9 |
| 0.4 交互约定 | ✅ | 遮罩关闭、滚动续页、异步操作均有进行中状态 |
| 0.5 弹窗规范 | ✅ | `PhoneDialogs`：自绘确认卡片 + 贴锚点下拉菜单，**不用系统 Alert / Menu** |
| 0.6 应用图标 | ✅ | 用 `Icon/mobile_icon_diffusion_v6_master.png` 导出 1024，方形不加圆角 |
| 1 登录 | ✅ | 地址补 `http://`、去尾斜杠；标题 26sp + 字距 0.08em 取 `CFBundleDisplayName`；全 App 无旧名 |
| 2 主框架 | ✅ | 首页 / 电视 / 直播 / 我的，四栈独立，各自保留滚动位置 |
| 3.1 顶部结构 | ✅ | 胶囊搜索栏 + 五频道 + 18×3dp 绿色短横线 |
| 3.2 推荐页 | ✅ | 196dp 轮播、4 秒自动、6dp 圆点；3×16dp 绿条标题；3 列横卡每区 6 个 |
| 3.3 分类页 | ✅ | 无轮播、首屏连续拉页铺满、滚动预加载、`加载中…` / `没有更多了` |
| 3.4 推荐卡片 | ✅ | 图高 86、角标统一（半透明 + 1dp 描边 + 4dp 圆角）、金色评分 `#FFD166` |
| 3.4 点击行为 | ✅ | 豆瓣条目只有豆瓣 id → 按剧名跳搜索，不调 `media` |
| 3.5 数据来源 | ✅ | 豆瓣直连（UA + Referer），后端 `recommend` / `category` 兜底 |
| 4.1 搜索范围 | ✅ | 按钮在**搜索框内最左侧**（28dp / 最大 88dp / 竖分隔线 / 箭头旋转 90°），点击弹贴锚点浮层 |
| 4.1 纵向节奏 | ✅ | 框上 8、框下 4、统计行 6、结果区 6 |
| 4.1 统计行常驻 | ✅ | 固定 18dp 单行省略，`基准统计｜附加提示`，空时兜底 `共 N 条结果` |
| 4.2 空态 | ✅ | 最近热搜（两列 1–6，不可删）+ 历史记录（胶囊流式，长按删除，清空确认） |
| 4.3 结果列表 | ✅ | 左源栏 104dp（全部 + 实际返回过结果的源，仅 1 源时隐藏）+ 单列四行等高卡片 |
| 4.4 结果排序 | ✅ | 匹配度 → 词序命中 → 源优先级 → 来源名 → 片名，含粗过滤 |
| 5.1 详情结构 | ✅ | 16:9 播放区、20sp 标题 + 38dp 收藏、信息行、多源卡片、4 列剧集 |
| 5.2 竖屏控件 | ✅ | 播放 34 / 时间 11sp / 进度 2dp 橙 / 清晰度 12 / 弹 12 / 全屏 32 |
| 5.2 弹幕 | ✅ | 按「片名 年份 集名」匹配，解析 XML/JSON/纯文本，Canvas 逐帧渲染 |
| 5.3 多源卡片 | ✅ | 选中绿描边 + 深绿底；单源整块隐藏 |
| 5.4 收藏 | ✅ | 乐观更新（≤150ms）+ 失败回滚 + 在途写请求保护后台刷新；`extraInfo=ios` |
| 5.5 详情弹层 | ✅ | 拖拽条、78×110 海报、概要（过滤 HTML）、来源 |
| 5.6 横屏全屏 | ✅ | 转屏、锁屏、底部两行、返回先退全屏并回竖屏 |
| 5.7 推送电视 | ✅ | 局域网发现 + 配对 + 推送，失败回落服务端单槽 |
| 6 电视 / 直播 | ✅ | 设备列表 + 遥控（`/v2/state` + `/v2/command`）+ 配对管理；IPTV 分组 + 直播间 |
| 7 我的 | ✅ | 账号、继续观看、观看历史、收藏、追剧、设置入口 |
| 8 状态文案 | ✅ | 搜索中 / 完成 / 超时 / 空结果 / 分类三态 / 推送两态 |
| 9 iOS 注意事项 | ✅ | pt 1:1、竖屏锁定、LazyVGrid 复用、海报圆角 10、`#1A1B22` 占位、安全区 |

### v1.4–v1.14 变更跟进

| 版本 | 变更 | 落地 |
| --- | --- | --- |
| v1.4 | 范围按钮移入搜索框、改下拉菜单、只列首页搜索源 | `SearchScreen.scopeButton` + `PhoneDropdown`；`LocalSourceStore.menuTargets()` 同时收 sites 与 spiders |
| v1.5 | 最近搜索 10 条、可单删、可清空、重复只调顺序；打开搜索页强制刷新源配置 | `SearchViewModel.remember/removeHistory/clearHistory`；`prepareIfNeeded(force: true)` |
| v1.6 | 弹窗规范：系统弹窗改应用风格 | `PhoneDialogs.swift`，清空确认 / 断线确认 / 删除记录 / 清除评分全部改自绘 |
| v1.7→v1.8 | 角标撤销灰蓝实底，统一「半透明 + 描边 + 圆角」 | `BadgeText`，推荐卡与结果卡共用 |
| v1.9 | 清空同步重置源栏；空态拆两块；角标 4dp；源栏 104dp 超长缩字；剧名超长缩字 | `clear()` 调 `coordinator.reset()`；`minimumScaleFactor(0.72 / 0.73)` |
| v1.10 | 应用图标分发规则 | 移动版 master → 1024，方形不透明（系统自己裁圆角） |
| v1.11 | 结果改单列横排 | `SearchResultCard`：封面 70×96 + 右侧三行 |
| v1.12 | 卡片固定四行等高；修复清空后历史残留 | 文字区固定 96 高；清空走 `reset()` 回到空态 |
| v1.13 | 搜索栏与结果区上移收紧 | 首屏多显示约一条结果 |
| v1.14 | 统计行常驻，切源不重建整行 | `statusRow` 固定 18dp；`selectSource` 只更新 `extraStatus` |

---

## 二、搜索体系（SEARCH_OPTIMIZATION）

### 2.1 双通道与逐源并发

```
输入关键词
   │
   ├─► 站点源：GET /api/site-media/{id}/search?wd=&page=   （客户端逐源并发）
   └─► 爬虫源：GET /api/app/v1/search?sourceId=            （服务端执行）
          │
          ▼
     结果池 pool ──► 整池重排 ──► 整体刷新
```

- **滑动窗口调度**：先提交 `concurrency` 个源（服务端下发，上限 8），完成一个立即补一个
- **预算**：单源 3.5s（`APIClient.searchSession` 的 `timeoutIntervalForRequest`）、总 20s；超预算不再提交新源，已返回照常展示
- **整池重排**：每批到达后 `SearchRanker.rank` 全量重算，不做局部插入
- **去重**：`libraryId + "|" + videoId`
- **范围语义**：全站查**全部**已启用源（不受 `isHomeSearch` 限制）；菜单只列勾选首页搜索的源

### 2.2 缓存 / 冷却 / 评分

| 项 | 实现 |
| --- | --- |
| 结果缓存 | 2 分钟、200 条，key = `配置版本 + 范围 + 页 + 关键词`；配置版本一变自动失效 |
| 源配置缓存 | 10 分钟 + ETag 条件请求，304 时沿用本地 |
| 失败冷却 | 5 分钟，冷却中的源本轮跳过 |
| 源动态评分 | `latencyScore`（300ms→100，8s→0，对数过渡）× 0.55 + `outcomeScore`（有结果 100 / 无结果 60）× 0.45；总分按 `×0.85 + 样本×0.15` 衰减；样本 < 3 时向默认 50 收敛；失败直接 `×0.85`；持久化在 `UserDefaults` |
| 查看入口 | 设置 → 播放与搜索 → **搜索源评分**（按分数降序，含样本数/成功率/最近延迟，可清除重置） |

### 2.3 排序口径

```
matchRank 升序（0 完全 / 1 前缀 / 2 包含 / 3 分词 / 4 其他）
  → tokenHit 升序（命中的分词下标，越小越好）
  → 源优先级降序（total - index）
  → 来源名升序
  → 片名升序
```

`tokenHit` 来自 `SEARCH_OPTIMIZATION` v1.4（「同 rank 内先比它」）。两份文档在这一点上不一致，
以更新的 SEARCH_OPTIMIZATION 为准，其余三级完全一致，代码注释里写明了取舍。

`SearchRanker` 的规则用 JS 逐行镜像跑过规范 4.4.8 的验收样例：

```
搜「凡人修仙传」
  1. [rank 0] 凡人修仙传          (星云源)
  2. [rank 1] 凡人修仙传：外海风云  (星云源)
  3. [rank 1] 凡人修仙传：魔道争锋  (天空源)
  4. [rank 2] 新凡人修仙传        (月亮源)
  5. [rank 4] 修仙传             (星云源，保留但排最后)
```

---

## 三、功能接口（PHONE_FUNCTION_API_SPEC）

| 功能 | 接口 | 状态 |
| --- | --- | --- |
| 探活 | `GET /health` | ✅ 登录前先探，失败提示「连不上服务器」而不是「密码错误」 |
| 登录 | `POST /app/v1/auth/login` | ✅ JWT 用 `.` 判有效（排除旧 Emby hex token） |
| 首页聚合 | `GET /app/v1/home` | ✅ 分类兜底用 |
| 推荐四分区 | `GET /app/v1/recommend` | ✅ 豆瓣直连失败时兜底 |
| 豆瓣直连 | `rexxar/recent_hot` + `new_search_subjects` | ✅ 四频道并发，每页 18 |
| 首页横幅 | `GET /api/proxy/tencent-banner-data` | ✅ 过滤 `isAd` 与空标题 |
| 分类分页 | `GET /douban-recommendation` | ✅ `start` 偏移量 |
| 详情 / 播放 | `/app/v1/media`、`/app/v1/play` | ✅ `header` 里的 UA/Referer 透传给 AVURLAsset |
| 搜索 | `/app/v1/search`、`/site-media/{id}/search` | ✅ 见第二节 |
| 本地源配置 | `GET /app/v1/local-sources` | ✅ ETag + 10 分钟缓存 |
| 弹幕 | `POST /app/v1/danmaku` | ✅ 丢弃空 url 条目 |
| 进度上报 | `POST /app/v1/progress` | ✅ 三 id 任一为空则静默跳过 |
| 继续观看 | `GET /app/v1/resume` | ✅ 首页横滑 |
| 收藏 | `/api/favorite` check / POST / DELETE / list | ✅ 乐观更新 + `(vodId, sourceId)` 判重 |
| 观看历史 | `GET /api/play-history` | ✅ 我的页，注意单位是**秒** |
| 追剧 | `GET /api/watch-follow` | ✅ 我的页，只有 tmdbId → 按剧名跳搜索 |
| IPTV | `/api/iptv/enabled` + `/api/iptv/{id}/channels` | ✅ 结构化分组优先，退回 m3u/txt 解析 |
| 直播间 | `/api/live-room` + `/api/live/stream/{platform}/{roomId}` | ✅ 未开播给提示不白屏 |
| 设备注册 / 配对 / 推送 | `/app/v1/devices/*` | ✅ 局域网失败时回落服务端 |
| 配对管理 | `/devices/{id}/pairs` GET/PUT/DELETE | ✅ 电视页遥控弹层内 |
| 电视遥控 | `/v2/state` + `/v2/command` | ✅ 方向键、播放控制、±5s、在电视上搜索 |
| 局域网发现 | `GET :10081/v2/info` | ⚠️ 用 `/24` HTTP 探测代替 UDP 广播（见第四节） |

---

## 四、偏差与未做（如实记录）

1. **爬虫源没有在客户端执行**。
   Android 用 QuickJS 跑脚本，iOS 需要 JavaScriptCore + `cheerio`/`axios` 的 CommonJS 打包。
   `PHONE_FUNCTION_API_SPEC` 7.2 明确「本地直连引擎：其他端可先全走服务端」，所以首版把
   爬虫搜索交给 `/app/v1/search?sourceId=`，站点搜索仍走客户端逐源并发（真正的双通道）。
   补齐需要额外引入 JS 运行时与 cheerio 打包，是一个独立工程量。

2. **局域网发现没用 UDP 广播**。
   电视每 2s 广播 `{magic:"OMNIBOX_TV", ...}` 到 10081，客户端要绑 UDP socket 监听。
   当前用各网段 `/24` 全量 `GET /v2/info` 探测（并发 24、单请求 1.5s、窗口 2.6s），
   结果等价但慢一点，且首次会触发 iOS「本地网络」权限弹窗。UDP 版可以后补。

3. **搜索只做首页**。
   规范 4.3 的结果列表没有「加载更多」，`pageCount` 只在缓存 key 里预留。
   `SEARCH_OPTIMIZATION` 第 5 节要求的「翻页先本地后服务端」因此未实现。

4. **豆瓣直连可能被风控**。
   直连带 `User-Agent` + `Referer: https://m.douban.com`，但豆瓣对机房 IP 不友好；
   失败会自动落到 `/app/v1/recommend` 与 `/douban-recommendation`，界面上看不出差别。

5. **卡片高度取 96 而非 82**。
   规范 4.3 的示意图写「封面 70×96」，实现说明又写「封面高度对齐文字区（约 82）」。
   这里按 96 做，文字区同样 96（剧名 44 + 源名 19 + 集数 19 + 留白），底边齐平。

6. **推送认领（ack/release）没有客户端入口**。
   `/devices/{id}/push` 的认领是**电视端**行为，手机端只负责推；接口已封装但无页面调用。

7. **`/v2/command` 的 `text` 指令未接**。
   遥控页做了方向键、播放控制、±5s、`search`，`text`（填入电视输入框）没有对应 UI。

---

## 五、目录结构

```
CloudVideo/
├── App/                    CloudVideoApp、RootView、AppInfo
├── Design/                 Theme、Components（BadgeText 等）、PhoneDialogs
├── Models/                 APIModels、SearchModels、ExtraModels、Navigation
├── Services/
│   ├── APIClient.swift         所有接口（含短超时搜索会话）
│   ├── LocalSourceStore.swift  本地源配置 + 菜单 + 优先级
│   ├── SearchCoordinator.swift 滑动窗口调度 / 缓存 / 冷却 / 状态
│   ├── SearchRanker.swift      归一化 + 匹配度 + 词序 + 稳定排序
│   ├── SourceScorer.swift      源动态评分
│   ├── SearchCache.swift       2 分钟 / 200 条
│   ├── DoubanService.swift     豆瓣直连
│   ├── CastService.swift       发现 / 配对 / 推送 / 遥控 / 配对管理
│   ├── LiveService.swift       IPTV 频道 + 直播间
│   ├── DanmakuService.swift    弹幕匹配与解析
│   ├── SessionStore.swift      会话（Keychain）
│   └── ImagePipeline.swift     带 Referer 的海报加载
└── Features/
    ├── Login/ Home/ Search/ Detail/ Player/ Cast/ TV/ Live/ Mine/ Settings/
```

---

## 六、构建

```bash
brew install xcodegen
cd CloudVideo && xcodegen generate
open CloudVideo.xcodeproj      # 设置 Team，Cmd+R
```

CI 在 `.github/workflows/cloudvideo-build.yml`（仓库根的 `CloudVideo/` 目录一改就触发）。

---

## 七、验证记录

- 语法级：`tree-sitter-swift` 解析 42 个文件全部通过（先用故意构造的坏样本验证过灵敏度）
- 类型级：GitHub Actions macOS runner，`xcodebuild -scheme CloudVideo -sdk iphonesimulator`
  → `** BUILD SUCCEEDED **`，`error: 0`，源码 `warning: 0`
- 排序：`SearchRanker` 的规则用 JS 逐行镜像跑过规范 4.4.8 验收样例，顺序一致
- 预览页：`prototype/cloudvideo-preview.html` 在 Chromium 里无 console / page error

> 编译通过 ≠ 跑起来没问题。播放器手势、防盗链、投屏发现、豆瓣直连仍需真机验证。
