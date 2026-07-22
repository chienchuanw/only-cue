# PotPlayer 書籤匯出 — 設計 (Design Spec)

- 日期:2026-07-23
- 狀態:已核准 (brainstorming approved),待 writing-plans
- 相關文件:`docs/` 匯出章節、`BundleExportAction`、`CueExportFilter`

## 問題 (Problem)

OnlyCue 是 macOS 專屬 App,無法在 Windows 環境執行。燈光設計者在 Windows 端只有 PotPlayer 可用,目前無法看到 OnlyCue 裡規劃的 cue 點。需求:把 cue 匯出成 PotPlayer 能讀的書籤 (`.pbf`),讓 Windows 端**至少能看到歌曲與 cue 點、並可跳點預覽**。

## 目標 (Goal)

新增一個**獨立**的「匯出 PotPlayer 書籤」動作:把專案裡每支(啟用的)影片複製到一個目標資料夾,並在旁邊放一個同名 `.pbf`,使 PotPlayer 自動掛載,可在時間軸上跳點預覽。

### 非目標 (Non-goals)

- 不呈現 cue 的顏色/型別色塊(PotPlayer 書籤無此欄位;型別改以文字前綴呈現)。
- 不承載 fade in/out、notes、BPM 等欄位。
- 不寫出 `.cuelist`(這是獨立匯出,不是 Bundle Export)。
- 不修改 OnlyCue 內部的原始 cue 資料。

## 使用者決策紀錄 (Decisions)

| # | 決策 |
|---|------|
| 用途 | 跳點預覽(在 PotPlayer 點書籤跳到該秒數看畫面) |
| 標題格式 | `[型別] 編號 名稱`,例:`[Lighting] 12 副歌` |
| 型別區分 | 接受無色塊,以文字前綴 `[型別]` 呈現 |
| 匯出範圍 | 一次全匯(bundle 式:所有啟用影片 + 對應 `.pbf`) |
| 檔案關聯 | 影片與 `.pbf` 同名同層,PotPlayer 自動掛載;對不上時手動匯入為可接受 fallback |
| 整合方式 | (B) 獨立匯出,不夾帶 `.cuelist` |
| cue 過濾 | 沿用 `isExportEnabled` 型別過濾 |
| 空影片 | 仍產生只有 `[Bookmark]` 標頭的空 `.pbf` |
| 分隔符衝突 | 標題內 `*`、換行自動替換成空白(只動 `.pbf`) |
| 檔名碰撞 | 自動加後綴 `-2`、`-3`;影片與 `.pbf` 套用同一後綴 |
| 時間基準 | `毫秒 = round(cue.time × 1000)`,忽略 `startTimecodeFrames` |

## 架構與元件邊界 (Architecture)

### `PBFExporter`(純函式,可獨立測試)
- **輸入**:一支影片的 cues + 型別名稱查詢表 (`typeID -> name`) + `isExportEnabled` 過濾。
- **輸出**:一段 `.pbf` 文字 (`String`)。
- **不碰**檔案系統與 UI。這是 TDD 的核心單元。

### `PotPlayerExportAction`(協調層)
- 解析每支 `MediaItem` 的 security-scoped bookmark 取得影片 URL。
- 複製影片到使用者選定的目標資料夾(共用既有媒體複製機制,參考 `BundleWriter`)。
- 呼叫 `PBFExporter` 產生 `.pbf`,寫到影片旁(同名同層)。
- **不**寫出 `.cuelist`。
- 處理檔名碰撞去重。

### 沿用既有機制
- `isExportEnabled` 型別過濾(與 CSV/MA2 匯出一致)。
- `MediaReference` / `Bookmarks` 解析。
- 既有影片複製邏輯。

## `.pbf` 產生規則 (Format Rules)

檔案內容:
```ini
[Bookmark]
1=<毫秒>*<標題>*
2=<毫秒>*<標題>*
```

- 每行 `N=<毫秒>*<標題>*`,第三欄(縮圖)留空,`N` 從 1 遞增。
- **毫秒** = `round(cue.time × 1000)`。
- **標題** = `[型別] 編號 名稱`:
  - 型別:由 `cue.typeID` 查 `CuePointType.name`。
  - 編號:`cue.cueNumber` 為整數時不帶小數(`12`),分數保留(`12.5`);為 `nil` 時省略該段(→ `[型別] 名稱`)。
- **淨化**:標題內的 `*`、`\n`、`\r` 一律替換成空白(不動 OnlyCue 原始資料)。
- **排序**:書籤依毫秒遞增;同毫秒再依 `cueNumber`。
- **過濾**:僅輸出所屬型別 `isExportEnabled == true` 的 cue。
- **編碼**:UTF-8。

## 輸出結構與邊界情況 (Output & Edge Cases)

- 使用者選一個目標資料夾;內部為**扁平**的成對檔案:`歌名.mp4` + `歌名.pbf`,同層同名。
- **空影片**(過濾後無 cue):仍產生只有 `[Bookmark]` 標頭的 `.pbf`。
- **檔名碰撞**(兩支 basename 相同):自動加後綴 `-2`、`-3`,影片與 `.pbf` 共用同一後綴以維持配對。

## 測試策略 (TDD)

### `PBFExporter` 單元測試
- 多 cue 依毫秒排序。
- 毫秒進位(`round`)。
- 標題格式 `[型別] 編號 名稱`。
- 編號:整數 / 分數 / `nil` 三種。
- 標題淨化:`*`、`\n`、`\r` → 空白。
- `isExportEnabled` 過濾(停用型別的 cue 不出現)。
- 空影片 → 僅 `[Bookmark]` 標頭。

### 協調層測試
- 檔名碰撞自動加後綴,且影片與 `.pbf` 配對一致。
- 成對輸出(每支啟用影片一個 `.pbf`)。
- 忽略 `startTimecodeFrames`(時間基準以 `cue.time` 為準)。

### 手動驗證
- 以含中文標題的測試影片實測,確認 PotPlayer(Windows)能正確讀取 UTF-8 標題並跳點。

## 開放風險 (Risks)

- PotPlayer 對 `.pbf` 編碼/BOM 的容忍度需以實機驗證(預設 UTF-8,無 BOM)。
- 若 Windows 端影片檔名與匯出不一致,自動掛載失效,需手動匯入(已為可接受 fallback)。
