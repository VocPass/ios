<div align="center">

# VocPass

**高職通用校務查詢系統**

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20watchOS-blue?logo=apple)](https://github.com/VocPass/ios)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange?logo=swift)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-17.0+-blue)](https://developer.apple.com/ios/)
[![Android](https://img.shields.io/badge/android-6.0+-green)](https://github.com/VocPass/android)
[![License](https://img.shields.io/badge/license-GPL--3.0-green)](https://github.com/VocPass/server/blob/main/LICENSE)

> 此為 [HansHans135/shin-her](https://github.com/HansHans135/shin-her) 的原生 App 版本，與 Claude Code 協作開發

</div>

---

## ✨ 功能特色

| 功能 | 說明 |
|------|------|
| 📅 **課表查詢** | 查看每週課表，支援離線快取，無需每次重新載入 |
| 📊 **成績查詢** | 第一、二學期及學年成績，各科目一覽無遺 |
| 🕐 **缺曠統計** | 自動統計曠課、事假、病假、公假，即時掌握距 1/3 門檻狀況 |
| ⭐ **獎懲記錄** | 功過明細、核定日期、銷過狀態完整呈現 |
| 🏝️ **Dynamic Island / 鎖定畫面小工具** | 課表即時活動與桌面 Widget，當前與下一節課盡在掌握 |
| ⌚ **Apple Watch 支援** | 獨立 Watch App，隨時查看課表與好友共享課表 |
| 🔐 **驗證碼自動辨識** | 使用 Vision OCR 自動辨識登入驗證碼，免除手動輸入 |
| 💬 **校園論壇** | 匿名發文、標籤分類、檢舉與審核 |
| 🍜 **吃啥？** | 學校周邊餐廳推薦與投稿 |
| 📅 **揪團（When2Meet）** | 建立活動、統計大家的可用時段 |
| 🖼️ **課表桌布產生器** | 依個人課表一鍵產生手機桌布 |
| 👀 **好友課表** | 追蹤並查看好友的課表 |

---

## 📱 支援平台

- **iOS / iPadOS** >= 17.0
- **watchOS**（隨附 Apple Watch App）
- **macOS** >= 11.0（Apple Silicon Only）

## 🏫 支援學校

學校擴充支援請至 [Server](https://github.com/VocPass/server) 查看。

## 🛠️ 技術棧

- **SwiftUI** — 全 UI 框架，含主 App 與 Watch App
- **ActivityKit + WidgetKit** — Dynamic Island / 鎖定螢幕 / 桌面小工具
- **Vision** — 驗證碼 OCR 辨識
- **WKWebView** — 學校系統登入與資料擷取
- **WatchConnectivity** — iPhone 與 Apple Watch 課表同步
- **UserDefaults** — 本地快取與帳號記憶

## 📂 專案結構

```
VocPass/               # 主 App（SwiftUI Views、Services）
VocPassWidget/         # 桌面 Widget 與 Dynamic Island Live Activity
VocPassWatch Watch App/# Apple Watch 獨立 App
```

## 🚀 安裝

### 從 Xcode 建置

```bash
git clone https://github.com/VocPass/ios.git
```

以 Xcode 開啟 `VocPass.xcodeproj`，選擇目標裝置並執行（⌘ + R）。

> 需 Xcode 15+ 及 Apple Developer 帳號（免費帳號限安裝於個人裝置）

## 🤝 貢獻

歡迎提交 Issue 或 PR！

- **新增學校支援**：前往 [Server](https://github.com/VocPass/server) 貢獻
- **功能建議**：開 Issue 討論
- **Bug 回報**：請附上裝置型號、系統版本與重現步驟

## 相關專案

| Repo | 說明 |
|------|------|
| [VocPass/server](https://github.com/VocPass/server) | 後端 API 伺服器 |
| [VocPass/android](https://github.com/VocPass/android) | Android App（Flutter） |
| [VocPass/bot](https://github.com/VocPass/bot) | Discord 狀態機器人 |

## 📄 授權

本專案採用 GPL-3.0 授權。
