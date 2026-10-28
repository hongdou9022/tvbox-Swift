# 云影视 · CloudVideo (iOS)

参考 [`hongdou9022/tvbox-Swift`](https://github.com/hongdou9022/tvbox-Swift) 的功能与信息架构，重写的 iOS 原生影视客户端。

- 语言 / UI：Swift 5.9 + SwiftUI
- 最低版本：iOS 17.0
- 播放内核：AVPlayer（无需 VLCKit，clone 下来就能跑）
- 工程管理：XcodeGen

---

## 一、和参考项目的关系

参考项目是一套 13000 行的跨平台（iOS + macOS）TVBox 客户端。这个工程**只做 iOS**，并且做了取舍：

| 维度 | tvbox-Swift | 云影视 |
| --- | --- | --- |
| 平台 | iOS + macOS 双端 | 只做 iOS，布局不再受 macOS 分栏拖累 |
| 播放器 | AVPlayer + VLCKit 双引擎 | 只用 AVPlayer，去掉 60MB+ 的 VLCKit 依赖 |
| 持久化 | SwiftData | JSON 文件（收藏/历史数据量小，升级不会因模型迁移丢数据） |
| 配置解析 | 支持多仓、gh-proxy、注释容错 | 保留核心能力：注释容错、GitHub blob→raw、多仓自动下钻 |
| 收藏入口 | 详情页入口待完善 | 详情页 + 我的页，双向同步 |
| 直播 | 分组 + 线路切换 | 分组 + 多线路合并 + 重试 |
| 手势 | 独立的 GestureLayer 组件 | 内聚在 PlayerView，双击/拖动/捏合齐备 |

复用的部分：CMS 接口协议（`ac=class` / `ac=videolist` / `ac=detail` / `wd=`）、`vod_play_from` + `vod_play_url` 的解析规则、XML 源（type=0）的容错解析、GBK 编码兜底。

**明确不支持**：`type=3`（JAR / Spider）源。这类源依赖 Java 运行时执行爬虫脚本，iOS 上没有可行实现，代码里会在入口直接拦截并提示。

---

## 二、界面结构

```
TabView
├── 首页 HomeView
│   ├── 顶栏：当前源切换（弹 sheet）+ 刷新
│   ├── 推荐位：横向分页大卡（模糊海报底 + 海报 + 立即观看）
│   ├── 分类条：横向滚动，吸顶（pinnedViews）
│   └── 海报网格：自适应 3 列，2:3 比例，滚动到底自动翻页
├── 直播 LiveView
│   ├── 分组 chips
│   └── 频道网格 → 全屏播放（同名频道自动合并多线路）
├── 搜索 SearchView
│   ├── 搜索框
│   ├── 历史词（按行排布）
│   └── 多源并发搜索 → 去重网格
└── 我的 LibraryView
    ├── 收藏 / 历史 分段
    └── 设置 SettingsView
        ├── 配置地址（可改、可重载）
        ├── 数据源列表
        └── 缓存 / 数据清理
```

详情页 `DetailView`：模糊海报头图 → 播放/收藏 → 线路选择 → 选集网格 → 剧情简介（可展开）→ 导演/主演。

播放器 `PlayerView`：

| 手势 | 行为 |
| --- | --- |
| 单击 | 显隐控制条 |
| 双击左 1/3 | 后退 10 秒 |
| 双击右 1/3 | 前进 10 秒 |
| 双击中间 | 播放 / 暂停 |
| 横向拖动 | 拖拽进度（6pt ≈ 1 秒） |
| 左侧纵向拖动 | 屏幕亮度 |
| 右侧纵向拖动 | 系统音量（借 MPVolumeView） |
| 双指捏合 | 画面 1x ~ 3x 缩放 |

控制条 4 秒无操作自动隐藏；进度、线路、剧集全部落到历史记录，下次进来接着看。

---

## 三、目录结构

```
CloudVideo/
├── project.yml                  # XcodeGen 工程描述
├── CloudVideo/
│   ├── Info.plist
│   ├── App/
│   │   ├── CloudVideoApp.swift   # 入口 + 全局外观
│   │   ├── AppState.swift        # 配置加载 / 源切换（全局状态）
│   │   └── RootView.swift        # 引导页 or 主 Tab
│   ├── Design/
│   │   ├── Theme.swift           # 配色 / 圆角 / 触觉
│   │   └── Components.swift      # 面板、胶囊、空态等基础组件
│   ├── Models/
│   │   ├── Video.swift           # 列表条目 + JSON 容错取值
│   │   ├── SourceBean.swift      # 站点 / 直播源
│   │   └── VodDetail.swift       # 详情 + 线路 + 剧集解析
│   ├── Services/
│   │   ├── NetworkClient.swift   # 请求 + 编码兜底 + 重试
│   │   ├── ConfigParser.swift    # 配置 JSON 解析（注释容错）
│   │   ├── VodService.swift      # CMS 接口（JSON / XML）
│   │   ├── ImagePipeline.swift   # 图片下载 + 内存缓存 + 防盗链
│   │   └── LibraryStore.swift    # 收藏 / 历史（JSON 落盘）
│   └── Features/
│       ├── Setup/                # 首次配置
│       ├── Home/                 # 首页
│       ├── Detail/               # 详情
│       ├── Player/               # 播放器
│       ├── Search/               # 搜索
│       ├── Library/              # 我的
│       ├── Settings/             # 设置
│       └── Live/                 # 直播
└── prototype/
    └── cloudvideo-preview.html   # 界面预览（浏览器直接打开）
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

选中 `CloudVideo` scheme，设置你的开发者 Team，`Cmd + R`。

工程已内置 1024×1024 的 App 图标（蓝紫渐变 + 播放三角），要换就在 `Assets.xcassets/AppIcon.appiconset` 里替换 `icon-1024.png`。

### 没有 Mac 怎么验证？

Windows / Linux 上**无法编译 SwiftUI**（没有 Apple SDK），也**没有 iOS 模拟器**（它是 Xcode 的组件）。替代方案是用 GitHub Actions 的 macOS runner 编译：

`.github/workflows/build.yml` 已经配好，推到 GitHub 后每次 push 会自动：

1. `brew install xcodegen`
2. `xcodegen generate`
3. `xcodebuild -scheme CloudVideo -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
4. 失败时把 `error:` 行单独摘出来，并上传完整 `build.log`

不需要开发者账号，也不需要证书 —— 编译模拟器版本不涉及签名。

本地能做到的最强检查是**语法解析**（tree-sitter-swift），能抓括号、语法结构、非法 token，但抓不到类型错误和 API 误用。真正的类型检查只能在 macOS 上跑。


---

## 五、配置格式

支持标准 TVBox JSON 配置：

```json
{
  "sites": [
    { "key": "demo", "name": "示例源", "type": 1, "api": "https://example.com/api.php/provide/vod/", "searchable": 1, "filterable": 1 }
  ],
  "lives": [
    { "name": "直播", "url": "https://example.com/live.m3u", "group": "默认" }
  ]
}
```

- `type`: `0` = XML，`1` = JSON，`4` = Remote（按 JSON 处理），`3` = JAR（不支持）
- 支持 `//` 和 `/* */` 注释
- 支持 `github.com/.../blob/...` 自动转 raw 地址
- 支持多仓入口（`urls` 数组），会自动尝试子地址

---

## 六、免责声明

本项目仅供 Swift / SwiftUI 技术交流。**不提供、不内置、不分发**任何影视资源或接口地址，所有内容均来自使用者自行导入的第三方接口，相关合法性与版权责任由使用者自行承担。
