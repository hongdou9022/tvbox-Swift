# 云影视 · CloudVideo (iOS)

OmniBox 媒体服务器的 iOS 客户端，严格按 `Box/docs/PHONE_UI_SPEC.md`（v1.0）实现。

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
| 1 登录 | ✅ | 地址自动补 `http://`、去尾斜杠；失败在按钮下方显示原因 |
| 2 主框架 | ✅ | 首页 / 电视 / 直播 / 我的，四栈独立 |
| 3.1 顶部结构 | ✅ | 胶囊搜索栏 + 五频道 + 18×3dp 绿色短横线 |
| 3.2 推荐页 | ✅ | 196dp 轮播、4 秒自动、6dp 圆点；分区标题 3×16dp 绿条；3 列横卡每区 6 个 |
| 3.3 分类页 | ✅ | 无轮播、首屏连续拉页铺满、滚动预加载、底部文案 |
| 3.4 推荐卡片 | ✅ | 图高 86、左上类型角标、右上金色评分、13sp 标题 + 10sp 元信息 |
| 3.4 点击行为 | ✅ | 无 `libraryId/videoId` 的豆瓣条目 → 按剧名跳搜索 |
| 4.1 搜索范围 | ✅ | 全站 / 各源，站类标 `· 站`、爬虫标 `· 源` |
| 4.2 最近热搜 | ✅ | 两列带序号，来源为本地搜索历史 + 推荐标题，最多 6 条 |
| 4.3 结果列表 | ✅ | 两列、海报 + 片名 + 绿色来源名 + 备注；状态行文案按规范 |
| 4.4 结果排序 | ✅ | `SearchRanker`：完全 → 前缀 → 包含 → 分词，再按源优先级 |
| 5.1 详情结构 | ✅ | 16:9 播放区、20sp 标题 + 38dp 收藏、信息行、多源卡片、4 列剧集 |
| 5.2 竖屏控件 | ✅ | 播放 34 / 时间 11sp / 进度 2dp 橙 / 清晰度 12 / 弹 12 / 全屏 32 |
| 5.3 多源卡片 | ✅ | 选中绿描边 + 深绿底；单源整块隐藏 |
| 5.4 收藏 | ✅ | 空心白 / 实心橙，点击立即切换，失败回滚 |
| 5.5 详情弹层 | ✅ | 拖拽条、78×110 海报、概要（过滤 HTML）、来源 |
| 5.6 横屏全屏 | ✅ | 转屏、锁屏、底部两行、返回先退全屏并回竖屏 |
| 5.7 推送电视 | ⚠️ | 面板 UI 与文案完整，设备发现未接（见下） |
| 6 电视 / 直播 | ⚠️ | 页面骨架与空态就位，规范标注「本次不涉及改动」 |
| 7 我的 | ✅ | 账号、继续观看、收藏、设置入口 |
| 8 状态文案 | ✅ | 全部按规范原文，见 `Components.swift` 与各 ViewModel |
| 9 iOS 注意事项 | ✅ | pt 1:1、竖屏锁定、LazyVGrid 复用、海报圆角 10、`#1A1B22` 占位、安全区 |

### 未完成项

1. **推送电视（5.7）**：面板交互与文案已实现，但设备发现依赖后端
   `/api/app/v1/devices` 的注册 / 配对流程（需要先 `POST /devices/register`
   拿到设备 ID 才能查 `pairs`），当前只做到「扫描中 → 没找到电视」的闭环。
2. **电视 / 直播（第 6 章）**：规范明确「本次不涉及改动」，只落了页面结构与空态。
3. **弹幕**：开关状态与视觉已按规范实现，未接 `/api/app/v1/danmaku` 的渲染。

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
│   │   └── SearchRanker.swift      # 4.4 匹配度排序
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
