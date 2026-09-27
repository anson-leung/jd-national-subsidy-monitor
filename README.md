# 京东国补商品监控助手（HarmonyOS NEXT）

实时监控京东指定商品的**价格与库存**，命中目标价时**振动响铃提醒**并**自动加入购物车**，一键跳转京东完成付款。

---

## 功能一览

| 功能 | 说明 |
|---|---|
| 扫码登录 | App 内加载京东 H5 登录页，登录后自动提取并加密保存 Cookie |
| 粘贴 Cookie | 兜底方案，支持 `pt_key=xxx; pt_pin=yyy` 格式，自动解析 URL 编码 |
| 链接解析 | 支持商品分享链接、短链（`3.cn` / `u.jd.com`，自动跟随跳转）、纯 skuId |
| 自动获取信息 | 抓取商品标题、主图、当前价、划线价、库存状态 |
| 目标价监控 | 设定目标价格，低于等于该价时触发 |
| 库存条件 | 可要求「必须有货才触发」，避免下单失败 |
| 独立轮询频率 | 每个任务可单独设置 3s / 5s / 10s / 30s / 60s |
| 强提醒 | 持续振动 + 节奏振动 + 系统通知，静音模式下振动仍生效 |
| 自动加购 | 命中后自动加入购物车，便于快速结算 |
| 一键下单 | 拉起京东 App 原生界面，未安装则降级浏览器打开 |
| 后台监控 | 通过长时任务保持后台轮询不中断 |
| 失败退避 | 连续失败自动延长间隔（5s→10s→20s→40s→60s 封顶） |
| 登录态检测 | 自动识别 Cookie 失效并暂停任务、发出提醒 |

---

## 环境要求

- **DevEco Studio** 5.0 或以上
- **HarmonyOS SDK** API 12（5.0.0）及以上
- 真机或模拟器（HarmonyOS NEXT）

> 说明：本项目为纯 ArkTS 工程，不含 Android 兼容层。HarmonyOS NEXT 已移除 AOSP，不支持 APK。

---

## 构建与运行

1. 用 **DevEco Studio** 打开本目录（`JdMonitor`）
2. 等待 `hvigor` 自动同步依赖（首次打开约需 1–3 分钟）
3. 配置签名：`File → Project Structure → Signing Configs → 勾选 Automatically generate signature`（需登录华为开发者账号）
4. 连接真机或启动模拟器
5. 点击 **Run**

若提示缺少 `local.properties`，点击 DevEco 的 **Sync Now** 会自动生成。

---

## 使用步骤

### 1. 登录京东账号

首页右上角 → **去登录**，两种方式任选：

**方式 A：扫码登录（推荐）**
- 在 App 内直接打开京东登录页，用京东 App 扫码完成登录
- 登录成功后凭证自动保存

**方式 B：粘贴 Cookie**
- 电脑浏览器登录京东 → `F12` → `Application` → `Cookies` → `jd.com`
- 找到 `pt_key` 和 `pt_pin`，复制其值
- 按 `pt_key=xxx; pt_pin=yyy` 格式粘贴

> Cookie 使用 AES-GCM 加密后存储在本机，不会上传到任何服务器。

### 2. 添加监控商品

1. 点击底部 **+ 添加监控商品**
2. 在京东 App 里点商品 → **分享** → **复制链接**，粘贴到输入框（或点「从剪贴板粘贴」）
3. 点 **解析商品**，自动抓取商品信息
4. 设置**目标价格**（默认自动填当前价下浮 5%）
5. 按需开启「必须有货才触发」「命中后自动加购」
6. 选择检查频率，点 **开始监控**

### 3. 等待命中

命中目标价时：
- 手机持续振动 + 节奏振动提醒
- 弹出系统通知
- 自动将商品加入购物车（如已开启）
- 进入任务详情点 **打开京东下单** 即可跳转结算

> **付款必须由你本人完成** —— 这是设计如此，见下方「关于自动下单」。

---

## 关于「自动下单」

本项目采用**半自动**策略，这是有意为之：

| 方案 | 可行性 | 风险 |
|---|---|---|
| 直接调用京东下单接口 | 需逆向 `h5st` / `_sign` 签名算法 | 签名随时变更导致失效；高频请求易触发风控，**可能导致账号被限制** |
| **本项目：加购 + 跳转 + 强提醒** | 长期稳定 | 无账号风险，体验几乎无差别 |

实际流程中，**最后一步付款无论如何都需要人工确认**（输入密码 / 指纹 / 面容）。因此半自动方案在体验上几乎没有损失，却规避了封号风险。

---

## 项目结构

```
JdMonitor/
├── AppScope/                          应用级配置与资源
│   ├── app.json5                      bundleName / 版本 / 图标
│   └── resources/base/
│       ├── element/string.json        应用名
│       └── media/app_icon.png         应用图标
├── entry/
│   ├── build-profile.json5            模块构建配置
│   ├── oh-package.json5               模块依赖
│   └── src/main/
│       ├── module.json5               权限声明、页面入口
│       ├── ets/
│       │   ├── entryability/
│       │   │   └── EntryAbility.ets   应用生命周期、后台任务、监控启动
│       │   ├── common/
│       │   │   ├── Const.ets          接口地址、常量（失效时改这里）
│       │   │   ├── Logger.ets         日志封装
│       │   │   ├── JdLinkParser.ets   分享链接 / 短链 / 口令解析
│       │   │   └── UiUtil.ets         格式化工具、主题色
│       │   ├── model/
│       │   │   └── MonitorTask.ets    任务、快照、账号数据模型
│       │   ├── service/
│       │   │   ├── HttpService.ets    网络层（Cookie 注入、重定向、超时）
│       │   │   ├── ProductService.ets 商品信息抓取、加购、结算链接
│       │   │   ├── LoginService.ets   扫码/Cookie 登录、登录态校验
│       │   │   ├── StorageService.ets 偏好存储、Cookie 加解密
│       │   │   ├── MonitorService.ets 监控调度、退避、命中判定
│       │   │   ├── AlertService.ets   振动、通知
│       │   │   └── BackgroundTaskService.ets  后台长时任务
│       │   ├── components/
│       │   │   └── TaskCard.ets       任务卡片组件
│       │   └── pages/
│       │       ├── Index.ets          首页：任务列表
│       │       ├── LoginPage.ets      登录页：扫码 / Cookie 双 Tab
│       │       ├── AddTaskPage.ets    添加任务：解析链接、设目标价
│       │       ├── TaskDetailPage.ets 详情页：实时数据、加购下单
│       │       └── SettingsPage.ets   设置页：账号、校验、说明
│       └── resources/
│           ├── base/element/          字符串、颜色
│           ├── base/media/            图标
│           ├── base/profile/main_pages.json   页面路由注册
│           └── zh_CN, en_US/          多语言
└── .check/                            本地校验脚本（不参与打包）
    ├── check-ets.js                   语法与依赖校验
    ├── audit.js                       路由/资源一致性审查
    └── logic-test.js                  核心算法单元测试
```

---

## 权限说明

| 权限 | 用途 |
|---|---|
| `ohos.permission.INTERNET` | 访问京东接口获取价格库存 |
| `ohos.permission.VIBRATE` | 命中时振动提醒 |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 后台持续监控 |
| `ohos.permission.NOTIFICATION_CONTROLLER` | 发送命中通知 |
| `ohos.permission.GET_NETWORK_INFO` | 检测网络状态 |

---

## 接口失效怎么修

京东接口会不定期调整。所有端点集中在 `common/Const.ets`，失效时优先改这里：

```
PRICE_API   价格接口    https://p.3.cn/prices/mgets
ITEM_API    商品业务    https://item-soa.jd.com/getWareBusiness
ITEM_PAGE   商品页兜底  https://item.m.jd.com/product/
CART_API    加入购物车  https://cart.jd.com/gate.action
```

抓取逻辑在 `service/ProductService.ets`，采用**三路兜底**：价格接口 → 业务接口 → 商品页 HTML 解析。单路失效不影响整体。

---

## 本地校验

工程附带了不依赖 DevEco 的校验脚本（需 Node.js）：

```bash
node .check/check-ets.js entry/src/main/ets   # 语法 + 依赖路径
node .check/audit.js                          # 路由 + 资源一致性
node .check/logic-test.js                     # 核心算法测试
```

当前状态：**19 个 .ets 文件 0 语法问题，0 一致性问题，26 项算法测试全部通过。**

---

## 已知限制

1. **未在真机编译验证** —— 本工程在无 DevEco 环境下产出，已做静态语法与逻辑校验，但首次在 DevEco 打开时可能需微调（如个别 API 版本差异）。
2. **库存字段依赖京东返回** —— 部分商品接口不返回精确实时库存，此时按「可售/无货」二值判断。
3. **风控风险** —— 检查频率过快可能触发京东限流，建议 5 秒以上。
4. **Cookie 有效期** —— 约 30 天，失效后 App 会提醒重新登录。
5. **后台存活** —— 部分厂商的省电策略可能终止长时任务，建议将本应用加入电池优化白名单。

---

## 合规声明

- 本工具仅用于**个人比价与到货提醒**，请勿用于批量抢购、倒卖等商业用途
- Cookie 仅加密存储于本机，不上传任何第三方服务器
- 最终订单提交由用户在京东官方渠道完成
- 请遵守京东用户协议，合理设置请求频率
