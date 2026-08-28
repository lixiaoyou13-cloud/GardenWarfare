# Notice 功能模块复用指南

> 本文基于 GardenWarfare 当前仓库中的真实实现整理，适用于使用 Rojo 的 Roblox 项目。
>
> 这是一份复用说明，不是自动安装器。把本文复制到其他项目不会自动获得 Notice 功能；目标项目仍需复制或改写 Luau 文件、在 Roblox Studio 搭建 UI、接入自己的玩家存档与保存队列，并发布对应 Place。

## 1. 功能范围

当前 Notice 功能包括：

- 从共享配置读取多期公告。
- 按 `PublishedAt` 选择最新公告，并默认显示最新一期。
- 为每期公告克隆日期按钮，为公告正文克隆标题和内容卡片。
- 支持单段正文和 `Sections` 多分块正文。
- 将正文按句子拆成独立卡片，并高亮符合规则的 CDK。
- 打开/关闭公告面板时处理遮罩与屏幕模糊。
- 从服务端读取“最新公告是否未读”，控制入口红点。
- 玩家查看最新公告后，将稳定的公告 `Id` 写入玩家存档。

它可以拆成三层：

1. **共享配置层**：`NoticeConfig` 定义 RemoteFunction 名称和公告内容，客户端、服务端共用。
2. **客户端表现层**：`NoticeController` 绑定入口/关闭按钮、渲染公告、切换标签、处理红点和模糊。
3. **服务端状态层**：获取最新公告 `Id`，读取/更新 `LastSeenNoticeId`，校验客户端请求并进入项目自己的保存队列。

公告内容本身不是秘密：`NoticeConfig` 位于 `ReplicatedStorage`，客户端可以读取。玩家存档和已读写入必须由服务端控制。

## 2. 本项目当前源文件与目标项目建议映射

GardenWarfare 的 Rojo 映射由 `default.project.json` 定义：

| 当前源文件 | 当前 DataModel 位置 | 目标项目建议位置 | 复用方式 |
| --- | --- | --- | --- |
| `src/shared/NoticeConfig.luau` | `ReplicatedStorage.Shared.NoticeConfig` | `src/shared/NoticeConfig.luau` | 复制后替换公告内容 |
| `src/client/UI/NoticeController.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.NoticeController` | `src/client/UI/NoticeController.luau` | 可复制，按目标 UI/工具结构调整依赖 |
| `src/client/init.client.luau` | `StarterPlayer.StarterPlayerScripts.Client` 的客户端入口 | 目标项目自己的客户端入口 | 只迁移 `require` 和 `Init()`，不要覆盖整个入口 |
| `src/client/Utils/UIEffectUtil.luau` | `StarterPlayer.StarterPlayerScripts.Client.Utils.UIEffectUtil` | 目标项目现有 UI 效果工具，或同目录最小适配模块 | 只要求提供 `SetScreenBlur`，不要盲目复制整个工具 |
| `src/server/PlayerDataManager.luau` | `ServerScriptService.Server.PlayerDataManager` | 建议提取为 `src/server/Services/NoticeReadService.luau`，再接目标项目数据层 | 当前只复用 Notice 相关逻辑，不复制整个文件 |
| `default.project.json` | Rojo 映射入口 | 目标项目自己的 project JSON | 参考映射，不要覆盖目标项目配置 |

本项目没有把 Studio UI 放进 `default.project.json`。因此 UI 层级需要在目标项目的 Roblox Studio 中手动搭建，或由目标项目自己的 UI Rojo 映射提供。

建议目标项目至少保持以下映射语义：

```json
{
  "ReplicatedStorage": {
    "Shared": { "$path": "src/shared" }
  },
  "ServerScriptService": {
    "Server": { "$path": "src/server" }
  },
  "StarterPlayer": {
    "StarterPlayerScripts": {
      "Client": { "$path": "src/client" }
    }
  }
}
```

请合并到目标项目已有的 `tree`，不要直接用此片段覆盖完整的 `default.project.json`。

## 3. Notice 配置契约

### 3.1 顶层字段

`NoticeConfig` 当前有三个公开字段：

| 字段 | 类型 | 当前值/含义 |
| --- | --- | --- |
| `StateRemoteName` | `string` | 当前为 `GetNoticeReadStateRF`，客户端获取已读状态 |
| `MarkSeenRemoteName` | `string` | 当前为 `MarkNoticeSeenRF`，客户端标记最新公告已读 |
| `Notices` | `array<table>` | 公告数组；数组顺序用于按钮排列，最新公告不依赖数组首项 |

客户端和服务端都优先读取配置中的 RemoteFunction 名称；缺字段时，当前代码分别回退为 `GetNoticeReadStateRF` 和 `MarkNoticeSeenRF`。

### 3.2 每期公告字段

| 字段 | 类型 | 是否建议必填 | 说明 |
| --- | --- | --- | --- |
| `Id` | `string` | 是 | 已读持久化使用的稳定唯一标识；发布后不要改、不要复用 |
| `TagText` | `string` | 是 | 左侧/顶部日期模板内 `Name` 文本显示内容，例如 `2026/8/12` |
| `PublishedAt` | `string` | 是 | `YYYY-MM-DD`；客户端和服务端以它选择最新公告 |
| `Title` | `string` | 是 | 单段格式时作为正文标题；也作为缺省显示/ID 回退信息 |
| `Content` | `string` | 单段格式必填 | 单段正文；使用 `Sections` 时可省略 |
| `Sections` | `array<table>` | 多段格式必填 | 每项使用 `Title` 和 `Content`；只要产生了有效分块，就优先渲染分块 |

当前实现会从 `Id`、`PublishedAt`、`TagText`、`Title`、数组索引依次回退生成公告 ID，但跨版本持久化必须显式填写 `Id`。推荐格式：

```text
notice-YYYY-MM-DD-主题短名
```

规则：

- 每期 `Id` 全局唯一且稳定。
- 已发布公告的 `Id` 不随标题、文案或排序改变。
- 同一天多期公告要增加稳定后缀，例如 `notice-2026-08-12-shop`。
- 不要用数组序号作为正式 `Id`；插入旧公告会改变序号。
- 不要复用旧 `Id`，否则已读玩家可能看不到新公告红点。

### 3.3 最新公告选择规则

客户端和服务端使用相同规则：

1. 只把严格匹配 `YYYY-MM-DD` 且月为 `1..12`、日为 `1..31` 的 `PublishedAt` 转成日期分数。
2. 选择日期分数最大的公告。
3. 日期相同时保留数组中更靠前的一项。
4. 没有更大的有效日期时，以数组第一项为默认项。

因此：

- 新公告通常放在数组前面，便于标签顺序阅读。
- `PublishedAt` 必须补零，例如 `2026-08-07`，不要写 `2026-8-7`。
- 这只是格式与粗范围检查，不校验某月实际天数；内容发布流程仍应人工检查日期。

### 3.4 可复制的最小配置

以下示例同时展示单段和分块格式：

```luau
local NoticeConfig = {}

NoticeConfig.StateRemoteName = "GetNoticeReadStateRF"
NoticeConfig.MarkSeenRemoteName = "MarkNoticeSeenRF"

NoticeConfig.Notices = {
    {
        Id = "notice-2026-08-12-update",
        TagText = "2026/8/12",
        PublishedAt = "2026-08-12",
        Title = "August 12 Update",
        Sections = {
            {
                Title = "New Features",
                Content = "A new feature is now available. Enter code TEST100 to claim a reward!",
            },
            {
                Title = "Bug Fixes",
                Content = "Fixed a display issue on mobile devices.",
            },
        },
    },
    {
        Id = "notice-2026-08-01-welcome",
        TagText = "2026/8/1",
        PublishedAt = "2026-08-01",
        Title = "Welcome",
        Content = "Thanks for playing!",
    },
}

return NoticeConfig
```

在 `Sections` 格式中，当前 Controller 实际渲染各个 `section.Title` 与 `section.Content`；顶层 `Title` 仍建议保留，供配置语义、缺省显示和未来扩展使用。

## 4. Roblox Studio UI 契约

### 4.1 必需层级

运行时必须能在玩家的 `PlayerGui` 中找到以下层级；公告面板根路径为 `PlayerGui.BasicGui.NoticeGui`：

```text
PlayerGui
└─ BasicGui
   ├─ PlayProperty
   │  └─ Notice
   │     ├─ [GuiButton，Notice 自身或其任意后代]
   │     └─ Notifications [可选 GuiObject]
   └─ NoticeGui [ScreenGui 或 GuiObject 开关兼容]
      └─ Notice
         ├─ Header
         │  └─ Buttons
         │     └─ [GuiButton，Buttons 自身或其任意后代]
         ├─ TypeButtons
         │  └─ Date [模板，默认隐藏]
         │     ├─ Name [可解析到 TextLabel/TextButton/TextBox]
         │     ├─ Selected [可选]
         │     └─ NotSelected [可选]
         └─ Container
            ├─ Title [文本模板，默认隐藏]
            └─ Content [文本模板，默认隐藏]
```

说明：

- `PlayProperty.Notice` 是入口根节点。它本身可以是 `GuiButton`，否则 Controller 会在其后代中寻找第一个 `GuiButton`。
- `Notifications` 是入口根节点的**直接子级**且需为 `GuiObject`；没有它时公告仍能打开，但不会显示红点。
- `Header.Buttons` 同样可以直接是 `GuiButton`，也可以在其后代中放关闭按钮。
- `Date`、`Title`、`Content` 是克隆模板，必须保留固定名称，并在 Studio 中默认设为 `Visible = false`。Controller 初始化时也会再次隐藏它们。
- `Date.Name` 可以直接是文本对象，也可以是包含文本对象的容器。
- `Title`、`Content` 模板本身可以是 `TextLabel`/`TextButton`/`TextBox`，也可以在后代放可解析文本对象。
- `Selected`、`NotSelected` 是可选视觉节点；存在时，Controller 会按选中状态切换 `Visible` 或兼容的 `Enabled`。

### 4.2 类、开关与层级兼容

当前 `setGuiOpen` 兼容：

- `ScreenGui`：修改 `Enabled`。
- `GuiObject`：修改 `Visible`。
- 其他实例：尝试修改 `Enabled`。

`NoticeGui` 如果是 `ScreenGui`，Controller 会把 `DisplayOrder` 提升到至少 `100`。公告内部和运行时生成的黑色遮罩使用 `ZIndex` 分层：遮罩为 `1`，公告树至少为 `2`。迁移时仍需检查目标项目其他 ScreenGui 的 `DisplayOrder`，避免商城、引导或系统弹窗意外盖住公告。

### 4.3 滚动、自动高度和移动端

推荐：

- `Container` 使用 `ScrollingFrame`。
- 在 `Container` 中配置 `UIListLayout`，让模板克隆按 `LayoutOrder` 纵向排列。
- 将 `AutomaticCanvasSize` 设置为 `Y`，或在目标项目中实现等价的 CanvasSize 更新。
- `Title`/`Content` 模板允许纵向自动尺寸；当前 Controller 会为克隆设置 `AutomaticSize = Y`、正文换行和固定 `TextSize`。
- 给容器预留左右内边距和安全区，不要让滚动条遮住文字。

必须在 Studio 中检查：

- 英文长单词、`Dr. Zomboss` 等短语是否出现不自然换行。
- 中英文、标点、CDK RichText 高亮后是否溢出。
- 手机窄屏、平板、PC 不同比例下标题和正文是否被裁切。
- 触屏滚动是否可用，关闭按钮是否有足够点击面积。
- `DisplayOrder`、`ZIndex`、遮罩 `Active` 是否正确阻挡背后点击。

## 5. 客户端接入

### 5.1 初始化

GardenWarfare 当前在 `src/client/init.client.luau` 中接入：

```luau
local NoticeController = require(script.UI.NoticeController)

-- 其他 Controller 初始化……
NoticeController.Init()
```

目标项目应把这两行合并到自己的客户端入口。不要复制或覆盖 GardenWarfare 的整个 `init.client.luau`。

`NoticeController.Init()` 应只调用一次。它会等待 UI 节点最多 10 秒，绑定按钮、生成标签、选择最新公告并异步读取红点状态。

### 5.2 `UIEffectUtil.SetScreenBlur` 依赖

当前 `NoticeController` 固定通过以下相对路径加载工具：

```luau
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)
```

它只依赖此接口：

```luau
UIEffectUtil.SetScreenBlur(enabled: boolean, overlayFrame: GuiObject?)
```

目标项目已有统一面板/模糊管理器时，优先：

1. 把 Controller 顶部 `require` 改为目标工具路径。
2. 把打开和关闭处的 `UIEffectUtil.SetScreenBlur(...)` 替换为目标接口。
3. 保证多面板同时打开时不会由一个面板错误清除其他面板的模糊。

若目标项目没有该工具，可以新建 `src/client/Utils/UIEffectUtil.luau`，使用以下最小适配实现：

```luau
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local UIEffectUtil = {}
local blurRequests = 0

local blurEffect = Lighting:FindFirstChild("UIBlur")
if not blurEffect or not blurEffect:IsA("BlurEffect") then
    blurEffect = Instance.new("BlurEffect")
    blurEffect.Name = "UIBlur"
    blurEffect.Size = 0
    blurEffect.Parent = Lighting
end

function UIEffectUtil.SetScreenBlur(enabled, overlayFrame)
    if enabled then
        blurRequests += 1
    else
        blurRequests = math.max(0, blurRequests - 1)
    end

    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    local targetBlur = blurRequests > 0 and 20 or 0
    TweenService:Create(blurEffect, tweenInfo, { Size = targetBlur }):Play()

    if overlayFrame and overlayFrame:IsA("GuiObject") then
        if enabled then
            overlayFrame.Visible = true
        end

        local targetTransparency = enabled and 0.5 or 1
        local tween = TweenService:Create(overlayFrame, tweenInfo, {
            BackgroundTransparency = targetTransparency,
        })
        tween:Play()

        if not enabled then
            tween.Completed:Once(function()
                if overlayFrame then
                    overlayFrame.Visible = false
                end
            end)
        end
    end
end

return UIEffectUtil
```

这只是 Notice 所需的最小接口，不包含 GardenWarfare `UIEffectUtil` 中的物品视口、提示、礼花等其他功能。

### 5.3 Boss 强制关闭钩子

`NoticeController.ForceCloseForBoss()` 是 GardenWarfare 为僵王 Boss 进场强制关闭阻挡 UI 提供的项目特有钩子。通用项目可以：

- 保留该函数但不调用；或
- 删除 `ForceCloseForBoss`、`forceCloseForBossImpl` 及对应赋值。

其他项目不需要复制 `src/client/Utils/ZombossUICleanup.luau`，也不应为了 Notice 引入整套 Zomboss 客户端逻辑。

## 6. 服务端已读持久化

### 6.1 数据契约

目标项目默认玩家数据增加：

```luau
LastSeenNoticeId = ""
```

加载旧存档后归一化：

```luau
if type(data.LastSeenNoticeId) ~= "string" then
    data.LastSeenNoticeId = ""
end
```

读取状态返回：

```luau
{
    LatestNoticeId = "notice-2026-08-12-update",
    LastSeenNoticeId = "notice-2026-08-01-welcome",
    HasUnreadLatest = true,
}
```

含义：

- `LatestNoticeId`：服务端按 `PublishedAt` 算出的最新稳定 ID。
- `LastSeenNoticeId`：玩家存档中的最后已读最新公告 ID。
- `HasUnreadLatest`：最新 ID 非空，且和玩家已读 ID 不同。

只记录最新一期是否已读，不记录每一期的完整阅读历史。

### 6.2 网络安全规则

- 两个 Remote 必须是服务端创建的 `RemoteFunction`。
- `StateRemoteName` 与 `MarkSeenRemoteName` 必须是两个不同的名称；若误配为同名，同一 `RemoteFunction.OnServerInvoke` 会被后一次绑定覆盖。
- 服务端独立从 `NoticeConfig` 计算最新 `Id`，不能相信客户端传来的“最新公告”。
- 标记已读时，只接受等于当前最新 `Id` 的值。
- 不允许客户端提交任意旧 ID、伪造 ID 或整张数据表。
- 数据未加载时不要写默认表、不要新开另一套 DataStore，也不要让 `OnServerInvoke` 无限等待。
- 更新后必须进入目标项目已有的 session/profile 保存队列。

### 6.3 可复制的适配器式服务示例

建议在目标项目新建独立服务，例如 `src/server/Services/NoticeReadService.luau`。下面代码不绑定任何 DataStore 名称；`getPlayerData` 和 `queueSave` 必须由目标项目注入：

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NoticeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NoticeConfig"))

local NoticeReadService = {}
local DATA_WAIT_TIMEOUT = 5
local adapter = nil

local function parseDateScore(value)
    if type(value) ~= "string" then
        return nil
    end

    local year, month, day = string.match(value, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not (year and month and day) or month < 1 or month > 12 or day < 1 or day > 31 then
        return nil
    end

    return year * 10000 + month * 100 + day
end

local function getNoticeId(notice, index)
    if type(notice) ~= "table" then
        return ""
    end

    return tostring(notice.Id or notice.PublishedAt or notice.TagText or notice.Title
        or ("Notice_" .. tostring(index)))
end

local function getLatestNoticeId()
    local notices = NoticeConfig.Notices
    if type(notices) ~= "table" or #notices == 0 then
        return ""
    end

    local latestIndex = 1
    local bestScore = parseDateScore(notices[1].PublishedAt)
    for index = 2, #notices do
        local score = parseDateScore(notices[index].PublishedAt)
        if score and (not bestScore or score > bestScore) then
            latestIndex = index
            bestScore = score
        end
    end

    return getNoticeId(notices[latestIndex], latestIndex)
end

local function getOrCreateRemoteFunction(name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing then
        assert(existing:IsA("RemoteFunction"), name .. " must be a RemoteFunction")
        return existing
    end

    local remote = Instance.new("RemoteFunction")
    remote.Name = name
    remote.Parent = ReplicatedStorage
    return remote
end

local function waitForPlayerData(player)
    local deadline = os.clock() + DATA_WAIT_TIMEOUT
    repeat
        local data = adapter.getPlayerData(player)
        if type(data) == "table" then
            return data
        end
        task.wait(0.1)
    until not player.Parent or os.clock() >= deadline

    return nil
end

local function buildState(data)
    local latestNoticeId = getLatestNoticeId()
    if type(data) ~= "table" then
        -- 数据不可用时关闭红点，避免错误状态和无限 InvokeServer 等待。
        return {
            LatestNoticeId = latestNoticeId,
            LastSeenNoticeId = "",
            HasUnreadLatest = false,
            Ready = false,
        }
    end

    local lastSeenNoticeId = type(data.LastSeenNoticeId) == "string"
        and data.LastSeenNoticeId or ""
    return {
        LatestNoticeId = latestNoticeId,
        LastSeenNoticeId = lastSeenNoticeId,
        HasUnreadLatest = latestNoticeId ~= "" and lastSeenNoticeId ~= latestNoticeId,
        Ready = true,
    }
end

function NoticeReadService.Init(projectAdapter)
    assert(type(projectAdapter) == "table", "NoticeReadService requires an adapter")
    assert(type(projectAdapter.getPlayerData) == "function", "adapter.getPlayerData is required")
    assert(type(projectAdapter.queueSave) == "function", "adapter.queueSave is required")
    adapter = projectAdapter

    local stateRemote = getOrCreateRemoteFunction(
        NoticeConfig.StateRemoteName or "GetNoticeReadStateRF"
    )
    local markSeenRemote = getOrCreateRemoteFunction(
        NoticeConfig.MarkSeenRemoteName or "MarkNoticeSeenRF"
    )

    stateRemote.OnServerInvoke = function(player)
        return buildState(waitForPlayerData(player))
    end

    markSeenRemote.OnServerInvoke = function(player, noticeId)
        local data = waitForPlayerData(player)
        if not data then
            return false, buildState(nil)
        end

        local latestNoticeId = getLatestNoticeId()
        -- 严格要求客户端显式提交当前最新 Id。
        if latestNoticeId == "" or tostring(noticeId or "") ~= latestNoticeId then
            return false, buildState(data)
        end

        if data.LastSeenNoticeId ~= latestNoticeId then
            local previousId = data.LastSeenNoticeId
            data.LastSeenNoticeId = latestNoticeId

            local queued, saveError = adapter.queueSave(player, "notice read state")
            if queued ~= true then
                data.LastSeenNoticeId = previousId
                warn("[NoticeReadService] Failed to queue save: " .. tostring(saveError))
                return false, buildState(data)
            end
        end

        return true, buildState(data)
    end
end

return NoticeReadService
```

目标项目服务端入口示例：

```luau
local NoticeReadService = require(script.Services.NoticeReadService)
local PlayerDataService = require(script.PlayerDataService) -- 替换为目标项目真实模块

NoticeReadService.Init({
    getPlayerData = function(player)
        -- 必须返回该玩家已加载的 session/profile 数据表；未加载时返回 nil。
        return PlayerDataService.GetSessionData(player)
    end,
    queueSave = function(player, context)
        -- 必须进入目标项目自己的保存队列，并返回 success, error。
        return PlayerDataService.QueueSave(player, context)
    end,
})
```

上面的 `PlayerDataService`、`GetSessionData`、`QueueSave` 是**适配位置示意**，不是 GardenWarfare 中存在的接口。必须替换成目标项目的真实数据服务。

不要复制 GardenWarfare 的 `MyGameData_V18`，不要为了 Notice 复制整个 `PlayerDataManager`，也不要创建与目标项目 session/profile 并行的第二份玩家存档。否则可能出现覆盖、回档、会话锁冲突或 DataStore 预算浪费。

### 6.4 与当前等待行为的差别

GardenWarfare 当前 `buildNoticeReadState` 和 `markLatestNoticeSeen` 会在玩家仍在线但 `sessionData` 未出现时循环等待。上面的通用示例改为最多等待 5 秒并返回安全状态，避免数据加载失败时 `RemoteFunction:InvokeServer()` 长时间卡住客户端线程。

这是跨项目复用的安全改进，不代表 GardenWarfare 当前源码已经使用有限等待。目标项目可以调整超时时间，但不建议无限等待。

## 7. 可选：无持久化红点精简方案

如果目标项目只需要公告浏览，不需要跨会话已读状态，可以不创建两个 RemoteFunction，但必须同步修改 `NoticeController`。不要把“等待 10 秒后 Remote 为 `nil` 的兼容退化”当成正式精简方案；原 Controller 仍会等待 Remote 名称，并保留面向服务端状态的 `InvokeServer` 分支，既增加初始化延迟，也让接入契约含混。

两种明确方案：

### 方案 A：完全关闭红点

- 删除/替换 `noticeStateRF` 和 `markNoticeSeenRF` 的 `WaitForChild`。
- 删除 `refreshNoticeReadState`、`markLatestNoticeSeen` 及相应调用。
- 初始化时固定 `Notifications.Visible = false`。
- 保留公告按钮、标签和内容渲染逻辑。

### 方案 B：仅本次客户端会话显示一次红点

- 不创建 RemoteFunction。
- 初始化时若存在公告，设置本地 `hasUnreadLatest = true`。
- 玩家第一次打开最新公告时隐藏红点，并把本地变量设为 `false`。
- 重进游戏会再次显示红点，这是该方案的预期行为。

无论选择哪一种，都必须把客户端 `InvokeServer` 调用删掉或替换为本地逻辑。

## 8. 内容渲染行为

### 8.1 分块与切句

- `Sections` 是有效数组时，每个有效 section 生成一个标题块和若干正文句子块。
- 没有有效 `Sections` 时，使用顶层 `Title` 和 `Content` 生成单个块。
- 多个分块时，显示标题会自动增加 `1. `、`2. ` 等序号。
- 正文按 `.`, `!`, `?`, `。`, `！`, `？` 和换行切句。
- 换行只作为分隔符，不保留在句子末尾；其他标点保留。
- 数字两侧的小数点不会切句，例如 `2.5%` 保持完整。

当前小数保护只覆盖“数字`.`数字”。版本号、域名、缩写等含点文本仍需在 Studio 实测，必要时用换行主动控制分句，或调整目标项目的切句器。

### 8.2 CDK 高亮与 RichText

当前高亮模式识别：

- 以一个或多个大写英文字母开头；
- 后面至少出现一个数字；
- 剩余字符只能是大写字母或数字；
- 例如 `TEST100`、`TB1234` 会显示为黄色粗体。

渲染前会转义 `&`、`<`、`>`、`"`，再插入受控的 `<font>`/`<b>` 标签，避免公告内容被当成任意 RichText 标记。迁移或扩展高亮规则时必须保留转义步骤，不能直接把运营输入拼进 RichText。

如果目标项目支持多语言：

- 不要把所有语言正文硬塞进一个字符串再由客户端猜语言。
- 可以让配置保存本地化 key，由目标项目 LocalizationTable 解析；或按 locale 维护明确字段。
- 切句标点、字体、字号、自动高度必须覆盖目标语言。
- 公告属于玩家可见文本，发布前检查语言一致性和 Roblox 文本过滤/平台政策要求。

## 9. 迁移步骤

### 9.1 代码侧

1. 核对目标项目 `default.project.json` 的 `ReplicatedStorage`、`ServerScriptService`、`StarterPlayerScripts` 映射。
2. 复制 `NoticeConfig.luau` 到共享目录，换成目标项目公告内容，并检查每期稳定唯一 `Id`。
3. 复制 `NoticeController.luau` 到客户端 UI 目录。
4. 接入目标项目的 `SetScreenBlur`，或加入本文最小适配模块。
5. 在目标客户端入口 `require` Controller 并调用一次 `Init()`。
6. 在目标默认数据中加入 `LastSeenNoticeId = ""`，在旧存档加载后做类型归一化。
7. 新建 Notice 已读服务或把相关逻辑接入目标数据服务；实现有限数据等待、两个 RemoteFunction、最新 ID 校验和保存排队。
8. 确保服务端入口在玩家调用 RemoteFunction 前初始化已读服务。

### 9.2 Studio 侧（小佑/目标项目编辑器协作者）

1. 按第 4 节搭建 `BasicGui.PlayProperty.Notice` 和 `BasicGui.NoticeGui` 完整层级。
2. 确认入口与关闭位置能找到 `GuiButton`。
3. 确认 `Date`、`Title`、`Content` 模板存在且默认隐藏。
4. 配置 `UIListLayout`、滚动容器、自动 Canvas、高度、换行和移动端尺寸。
5. 检查 `Notifications` 红点的默认状态、锚点、ZIndex。
6. 检查 Notice 面板与其他全屏 UI 的 `DisplayOrder`、模糊、遮罩和输入阻挡关系。

本文不会也不能代替这些 Studio 操作。完成代码同步后仍需人工检查 UI 对象。

### 9.3 验证与发布侧

1. 运行 `git diff --check`。
2. 运行目标项目的 Rojo build，确认 require 路径和语法有效。
3. 用启用 API Services 的专门测试环境测试旧/新存档，不直接拿正式账号做首次存档实验。
4. 在 Studio 单人和多人 Play Test 验证 UI、红点和保存。
5. 发布到正确的 Roblox Place；体验有多个独立 Place 时，发布所有运行对应客户端/服务端代码的 Place。
6. 用新服务器验证。已经运行的旧服务器不会自动获得新发布脚本。

## 10. 测试清单

### 配置与排序

- 两期日期乱序时，仍默认打开 `PublishedAt` 最大的一期。
- 同日期公告按数组靠前项作为最新。
- 单段 `Content` 和多段 `Sections` 都能渲染。
- 空公告数组不会报错，入口打开后无生成内容。
- 每个 `Id` 唯一，修改标题/排序不会改变已发布 `Id`。

### UI

- 入口和关闭按钮只绑定一次。
- 日期按钮数量与配置一致，切换后 Selected/NotSelected 正确。
- 模板保持隐藏，运行时克隆可见。
- 反复切换不会累积旧生成节点。
- 打开时遮罩/模糊出现，关闭时消失且不继续挡点击。
- 与其他全屏面板同时操作时，模糊计数不被错误清零。
- PC、手机、平板正文均可完整滚动，标题/英文短语/CDK 不异常换行。

### 文本

- 英文和中文标点正确切句。
- `2.5%` 不被拆开。
- `TEST100` 高亮，普通单词和纯数字不误高亮。
- `<`, `>`, `&`, `"` 显示为文本，不注入 RichText。
- 本地化字体和字号可读。

### 服务端与存档

- 新玩家默认 `LastSeenNoticeId = ""`，最新公告红点显示。
- 旧存档字段缺失/类型错误时归一化为空字符串。
- 打开最新公告后红点消失，并进入保存队列。
- 等待保存完成、离开并重进后红点不再显示。
- 发布新 `Id` 后，老玩家重新看到红点。
- 客户端提交旧 ID、空 ID、伪造 ID 时服务端拒绝且不改存档。
- 玩家数据加载失败时 RemoteFunction 在有限时间内返回安全状态，不永久卡住。
- 保存排队失败时日志可定位，且不会伪报已持久化。
- 多人同时查看只修改各自 session 数据，不串号。

## 11. 常见问题

### 点击入口没有反应

检查 `PlayerGui.BasicGui.PlayProperty.Notice` 内是否存在 `GuiButton`，以及 `NoticeController.Init()` 是否执行。再查看客户端是否出现 `Missing UI object` 或 `Notice UI binding is incomplete`。

### 初始化要等很久

检查 UI 固定名称和两个 RemoteFunction 是否按配置创建。若采用无持久化方案，必须删除/替换客户端 Remote 等待和 `InvokeServer` 逻辑。

### 红点一直显示

检查：

- 客户端和服务端加载的是不是同一份 `NoticeConfig`。
- `PublishedAt` 是否使用 `YYYY-MM-DD`。
- `LatestNoticeId` 是否与最新公告显式 `Id` 一致。
- `queueSave` 是否成功，离开前是否完成保存。
- 是否误改了已发布公告的 `Id`。

### 红点永远不显示

检查 `Notifications` 是否为入口 `Notice` 的直接子级 `GuiObject`，服务端状态是否 `Ready`，以及 `HasUnreadLatest` 是否为 `true`。

### 公告内容重叠或不能滚动

检查 `Container` 的 `UIListLayout`、`AutomaticCanvasSize`、模板 `AutomaticSize`、内边距和滚动方向。当前 Controller 负责克隆与部分卡片样式，不会替目标项目修复错误的容器布局。

### 文本被截断或短语换行

检查模板文本对象的宽度、`TextWrapped`、字体和设备缩放；缩小固定字号或增加卡片宽度前，要在手机和 PC 同时回归。运营文案可用更短句子或显式换行改善布局。

### 新公告没有成为最新

检查 `PublishedAt` 格式和日期大小，不要只依赖数组位置。相同日期时把希望作为最新的项放在前面。

## 12. 数据安全、网络安全与兼容性注意事项

- 不信任客户端提供的公告 ID；服务端只接受自己计算出的当前最新 ID。
- 不允许客户端直接提交 `LastSeenNoticeId` 数据表或指定其他玩家。
- RemoteFunction 名称必须在客户端和服务端共享配置一致，且实例类必须是 `RemoteFunction`。
- Notice 已读状态必须复用目标项目现有 session/profile 和保存队列。
- 不复制其他项目的 DataStore 名、会话锁、版本号或整份玩家数据管理器。
- 数据不可用时返回安全状态；不要无限等待，也不要用空默认数据覆盖真实存档。
- 发布后保持旧公告 `Id` 稳定，避免红点语义错乱。
- 公告内容在客户端可见，不在配置中放管理密钥、私有链接令牌或任何秘密。
- RichText 内容先转义后高亮，避免配置文本注入标记。
- Controller 会创建名为 `NoticeBlurOverlay` 的 Frame；目标 UI 中不要用同名非遮罩对象。
- 当前 Controller 会为标题/内容克隆增加 `NoticeGenerated` Attribute；不要给必须保留的手工节点设置该 Attribute 为 `true`。
- 目标项目若有统一面板管理、输入锁、模糊栈或导航栈，应把 Notice 接入统一系统，避免独立开关冲突。

## 13. 本项目当前实现与通用版差异

| 项目 | GardenWarfare 当前实现 | 跨项目通用建议 |
| --- | --- | --- |
| 已读状态位置 | 直接嵌入 `src/server/PlayerDataManager.luau` 的 `sessionData`、默认数据和保存队列 | 提取独立 `NoticeReadService`，通过 `getPlayerData(player)` / `queueSave(player, context)` 适配目标数据层 |
| 数据等待 | 玩家在线且 session 未出现时循环等待 | 使用有限等待；超时返回无红点的安全状态，避免 `InvokeServer` 卡死 |
| 标记参数 | 校验当前最新 ID；当前实现对缺省参数有兼容回退 | 通用服务建议要求客户端显式提交且严格等于当前最新 ID |
| 模糊工具 | 依赖 `src/client/Utils/UIEffectUtil.luau` 的 `SetScreenBlur` | 接目标项目统一 UI 效果管理器，或只实现本文最小接口 |
| Boss 钩子 | 暴露 `NoticeController.ForceCloseForBoss()`，供僵王流程关闭 UI | 非 GardenWarfare 项目可删除；不要复制 `ZombossUICleanup` |
| DataStore | Notice 跟随 GardenWarfare 当前玩家存档；文件中存在项目专属 `MyGameData_V18` | 绝对不要复制该名称或另开并行玩家存档；使用目标项目自己的 profile/session |
| UI 来源 | UI 不在当前 `default.project.json` 映射中，依赖 Studio 已有 `BasicGui` 层级 | 目标项目可手搭 Studio UI，或明确把 UI 纳入自己的 Rojo 映射 |

## 14. 最终交付边界

完成复用至少应产出：

- 目标项目内可加载的 `NoticeConfig`。
- 目标项目内可初始化的 `NoticeController`。
- 满足固定名称和类型要求的 Studio UI。
- 可用的 `SetScreenBlur` 替换接口。
- 接入目标 session/profile 的 `LastSeenNoticeId`、两个 RemoteFunction 和保存队列。
- Rojo build、Studio 多设备 UI、服务端参数校验、离开重进持久化测试结果。
- 已发布到正确 Roblox Place 的新版本。

仅拥有本 Markdown 文件不代表 Notice 功能已安装，也不代表其他项目的 Studio UI、DataStore 或发布已经完成。
