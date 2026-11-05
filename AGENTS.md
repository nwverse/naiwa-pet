# AGENTS.md

naiwa-pet：macOS 桌面上的奶蛙。空闲时按一天的时段换一只慢慢地动，Claude Code 干活时沉溺在水里、等你时睁眼转过来看你、干完惊鸿一瞥（镜头推近，斜着瞥你一眼）。用法见 [README.md](README.md)。

## 约定

- `[必须]` 保持小：不引入第三方依赖，只用系统框架（AppKit、AVFoundation）。只有在播片段时才开取帧定时器；空闲和干活的循环只在窗口看得见时播，被挡住、锁屏、屏幕睡了、切走用户要停（`Pet.updateVisibility`）。改播放相关代码后用 `top -pid` 量 CPU：现在播放约 3–4%（release），锁屏 0%。
- `[必须]` `naiwa hook` 必须快（现在约 5 毫秒）、不输出任何东西、永远返回 0。理由：Claude 每调一次工具都会先跑它。
- `[禁止]` 用模型判断「做完没有」：按时长和有没有调工具在本地算，不花 token。
- `[必须]` 透明的地方让鼠标穿过去，点奶蛙不抢焦点（`nonactivatingPanel` + 按当前帧的像素切换 `ignoresMouseEvents`）。改窗口或鼠标逻辑后，要在真机上确认点它背后的窗口还能点到。
- `[必须]` `naiwa hooks install` 只做文本插入，写之前确认新旧 settings.json 除了这一条以外完全一致。理由：这是别人的全局配置，不能重排、不能丢字段。
- `[禁止]` 仓库里出现内网地址、主机名、个人路径和 key。
- `[禁止]` 仓库里出现素材作者的名字、主页或署名。
- `[必须]` 奶蛙保持原梗的样子：不穿衣戴帽、不换脸。换新画先给维护者看静帧。`[禁止]` 用自建的 3D 模型或手写动作代替，笑起来不像。
- `[禁止]` 加声音：吵。
- `[禁止]` README 里写参考了哪个项目、用了哪些工具和服务、素材是怎么做出来的。
- `[必须]` 哪个时段出来哪几只、干活时是哪只要能让用户自己换：默认安排在 `assets/assets.json` 的 `idle` / `work`，用户的在 `~/.config/naiwa/config.json`（右键菜单读写、手改自动生效）。新加的奶蛙进 `assets.json` 的 `pets` 和 `clips` 就会出现在菜单里，不要在代码里写死名字。
- 悬停换只：空闲时指针停在奶蛙不透明处 0.7 秒换下一只（`Pet.pickNext`），离开整个窗口才能再来一次（换了形状以后指针可能落在透明处，不能算离开）；换出来的只管到下个时段。播放器只留当前这只和干活 / 等你 / 做完要用的。
- README 里的动图是 `docs/pets/*.webp` 和 `docs/demo.webp`：带透明通道的动态 WebP（240px，GitHub 浅色、深色主题都干净；GIF 只有 1 位透明，边缘有锯齿）。加了新奶蛙要补一张。
- 整个仓库 MIT，见 LICENSE。

## 踩过的坑

- 素材是带透明通道的 HEVC，按预乘 alpha 解释：换素材时编码前必须预乘，否则边缘发白。
- 显示：`AVPlayerItemVideoOutput` 取 IOSurface 做底的 BGRA 帧，直接设成图层的 `contents`（`PetView.show`），并给 IOSurface 标上 sRGB。复制成 CGImage 再贴，空闲循环要多占 6–8% CPU。命中测试直接读这一帧的像素缓冲。不要用 `AVPlayerLayer`：画面由系统单独合成，没法验证。
- 锁屏时窗口的遮挡状态仍是「看得见」：要单独听 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`，启动时也先查一次（`CGSessionCopyCurrentDictionary`）。
- 看不到屏幕时（沙箱、锁屏）验证画面：截窗口（`CGWindowListCreateImage`）在锁屏或没有录屏权限时全是透明的；`layer.render(in:)` 不画 IOSurface 内容。用 `CARenderer(mtlTexture:)` 把一个以当前 IOSurface 为内容的图层离屏合成到 Metal 纹理再读回（先 `CATransaction.flush()`；读回来是上下颠倒的，放个标记块判断方向）。
- 状态之间硬切：两个透明画面叠化会出重影。干活 / 等你 / 做完是同一只（沉溺奶蛙），切过去不跳。
- 在 Naiwa.app 里拿自己的 bundle id 当 `UserDefaults(suiteName:)` 会返回 nil。
- CFMessagePort 回调给的 CFData 只在回调期间有效：必须当场复制再丢到主线程，直接桥接成 `Data` 会读到垃圾。
- 「等你」只看 `Notification` 的 `notification_type`（`permission_prompt` 等），不要按提示语猜：`idle_prompt` 和别的提醒文案不止一种，按文字过滤会在没人要权限时显示「等你确认」。
- bash 里变量后面直接跟中文标点要写成 `${VAR}`，否则会被当成变量名的一部分。

## 分支与提交

- `main` 只通过 PR 合入，squash 合并。PR 标题和正文、commit 信息用英文；文档和 issue 用中文。
