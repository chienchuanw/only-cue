# Spec — 大檔波形效能:部分指紋 + 降取樣率 + 時間解析度 + 漸進渲染

**Status:** drafted 2026-08-09 (grilled), awaiting approval
**Issue:** #729 — `perf: when import a bigger file, it takes much longer to generate waveform`
**Builds on:** 現行 `WaveformGenerator` / `WaveformCache` / `WaveformPrewarmer`（RMS 包絡 #632、per-file 正規化 #538、連續位移渲染 #675、多聲道 lane #720、music-only #715）

## Goal

兩者兼顧:讓大檔波形**真正變快**,並在無法即時完成時**讓使用者感覺到它在動**。速度是前置——漸進渲染在「先把整個檔案 hash 過一遍」這道牆拆掉前沒有意義。

**目標成功標準**：匯入/開啟高位元率影片或長時間工作帶時,不再有「先讀滿整個檔案」的固定等待;點開已暖好的檔案瞬間出圖;未暖好者邊算邊畫。

## 背景 / 問題

使用者回報:匯入大檔(10–20GB 的 mov/mp4,或整場三小時演唱會工作帶,影或音)波形要「等很久」,且只有一顆轉圈圈 spinner。實際使用情境:

- **最常見**:10 分鐘內的音訊檔(小、快,非痛點)。
- **偶發**:10–20GB mov/mp4(時間不長、位元率高)、以及三小時工作帶(影/音都大)。

讀 code 後確認**兩種不同的病**:

1. **`WaveformCache.fileHash` 把整個檔案 SHA256**(`WaveformCache.swift:88`,1MB 一塊讀到底)——只是為了拿快取鍵。50GB 影片等於先讀滿 50GB。**高位元率但不長的影片,痛點幾乎全在這。** `VideoPosterCache` 也重用同一顆 hash,海報縮圖有一模一樣的病。
2. **`WaveformGenerator` 用 44100Hz 解碼整條音軌、逐 sample 跑 RMS 迴圈**(`WaveformGenerator.swift:358`)。三小時 ×44100 ≈ 4.7 億 sample,即使修好 hash 仍慢。**長工作帶的痛點在這。**

另外抓到的既有缺陷:

- **Prewarmer 白工**:`WaveformPrewarmer` 背景算 **512** 格(`WaveformPrewarmer.swift:9`),但前景 `WaveformContainer` 讀 **12,000** 格(`WaveformContainer.swift:24`);快取鍵含解析度 → **永不命中**,匯入時算的暖快取完全用不到。
- **Prewarmer 無併發上限**:`withTaskGroup` 對每個匯入檔各開一個 task,一次匯入多個大檔會同時開炸。
- **zoom 細節是假的**:深度 zoom 吃固定 12,000 格,三小時 = **每格 0.9 秒**,給不出拍點級細節,只是把粗資料內插拉寬。

## 使用者工作流(決定設計的關鍵事實)

- **靠眼睛在波形上找最尖的瞬態、或自己算節拍來放 cue;不套 Tempo 節拍格線 snap。** → 必須能**看到瞬態峰值**,現況 RMS-only 會抹軟瞬態、對不準。

## 釐清過程的關鍵決定(2026-08-09 grilling)

1. **兩者兼顧,速度優先**:速度是漸進渲染的前置。
2. **架構走「提高固定解析度 + 快取」(方案 X),不做「可見視窗即時重算」(方案 Y)**。一份全長高解析陣列才幾 MB(3hr@10ms=4.3MB),又有磁碟快取、同檔反覆開;視窗重算的視窗管理/取消/淘汰/改渲染器屬過度工程。
3. **正規化搬到渲染時(方案 c)**:化解「漸進填充時不知道全域最大值」與 per-file 正規化(#538/#632)的衝突;載完與現況等價。
4. **每格存峰值 + RMS 雙值、雙包絡渲染(方案 A)**:同時滿足「眼睛找瞬態」與 #632「brickwall 母帶全景不糊成一塊」。接受它會動到渲染器(最高風險項)。
5. **Prewarmer 走 甲**:匯入時對**所有**檔案背景算全高解析並暖快取;點開即時。**加併發上限**。
6. **漸進機制**:`AsyncStream` + actor 合流 + 每 16ms 節流 yield。
7. **部分指紋不含 mtime、不加「重新產生」逃生口**:內容沒變不該重算(`touch` 不得誤觸重算)。使用者明確接受「拆掉最後一張安全網」的取捨。
8. **海報縮圖一起治**(共用 fast fingerprint)。

## ① 快取鍵:部分指紋(fast fingerprint)

- **配方**:`檔案大小 + SHA256(開頭 1MB ‖ 結尾 1MB)`,**不含 mtime**。50GB 也是常數時間。
- 做成**共用 helper**,**波形與 `VideoPosterCache` 兩邊一起換掉**,一次治好兩者的開檔卡頓。
- **風險(使用者已簽字接受)**:無 mtime、無逃生口 → 若真有人「原地改中段但保住大小與頭尾」會永久卡錯波形。對真實媒體工作流近乎不可能(重編碼改大小、剪輯動頭尾)。
- **不**加「重新產生波形」選單。

## ② 解碼降取樣率

- 分析用 **8000Hz**(現為 44100),砍約 5.5 倍解碼與逐 sample 迭代量。
- 與每格 10ms 相乘 = **每格約 80 sample** 算 RMS/峰值(穩)。
- 不影響聲道分離;LTC 偵測為另一套路徑,不吃此取樣率。
- 實作槓桿(非決策):內層可用 vDSP 取代純量迴圈進一步加速。

## ③ 時間定義的解析度

- 每格 **10ms**(取代固定 12,000 格)。陣列長度隨時長變動。
  - 10 分鐘 = 6 萬格 = 240KB;3 小時 = 108 萬格。
- 快取鍵從 `-<格數>` 改為 `-<每格ms>`(如 `-10ms`)。

## ④ 峰值 + RMS 雙包絡(⚠ 最高風險項)

- 每格存兩個 float:**峰值(max-abs)+ RMS**。3hr ≈ 8.6MB。
- 渲染成**雙包絡**:
  - **全景收合**用 **RMS**(收合取能量平均)→ 保 #632 動態可讀。
  - **深度 zoom** 看**峰值**輪廓(收合取 max)→ 使用者眼睛找最尖瞬態。
- **動到渲染器**:`WaveformView`、`WaveformPeakBucketer`、#675 連續位移渲染要從吃單一 `[Float]` 改成同時帶峰值 + RMS 兩層、收合邏輯分流。
- **回歸守門**:此區有手勢 / 點擊 seek / 無障礙 hit-test(CLAUDE.md SwiftUI 手勢警告 + `minimumDistance`)。改動後須驗:click-to-seek、context-menu、`.sheet(item:)`、無障礙 hit-test、多聲道 lane(#720)、LTC strip 對齊(#663)全數不退化。

## ⑤ 正規化搬到渲染時

- 快取改存**原始未正規化**的峰值 / RMS。
- 渲染時用「**目前已載入格的最大值**」即時除;收合降採樣本來就在跑,順手取 max 近乎零成本。
- 效果:漸進填充自洽、無結尾 snap、全部載完時「目前最大值 = 全域最大值」→ 與現況 byte-equivalent。

## ⑥ 漸進渲染 + 合流機制

- **`WaveformGenerator` 改吐 `AsyncStream`**:每次 yield「目前累積到第 N 格」的(峰值 + RMS)資料;配合 ⑤ 前景收到即畫。
- **actor 做 key→進行中工作合流**:prewarm 與前景共用同一條 stream,杜絕 甲 造成的重複解碼(匯入後立刻點開仍在暖的大檔時)。工作完成寫入快取。
- **節流**:每 **16ms** yield 一次(對齊畫面更新),避免百萬格淹沒 UI。
- 已存在的 `Task.checkCancellation()` 取消路徑保留。

## ⑦ Prewarmer(甲)

- 匯入時對**所有**檔案背景算全高解析(10ms 雙值)並暖快取 → 點開即時。
- **加併發上限(2–3)**,修 `withTaskGroup` 無上限缺陷。
- 解析度對齊前景(修「白工」缺陷)。
- 漸進渲染成為「尚未暖好 / 快取失效」時的後備路徑。

## ⑧ 快取格式版本

- `WaveformCache.formatVersion` **3 → 4**(改存原始未正規化 + 峰值/RMS 雙值 + 時間解析度)。舊快取自動作廢重算。
- 鍵格式:`<fingerprint>-<每格ms>[-xc<N> | -ch<N>]-v4.peaks`(沿用既有 `xc`/`ch` 後綴語意)。

## 相關檔案

- `OnlyCue/Media/WaveformCache.swift`（fast fingerprint、formatVersion、鍵格式）
- `OnlyCue/Media/WaveformGenerator.swift`（8000Hz、10ms 格、峰值+RMS、AsyncStream、去正規化)
- `OnlyCue/Media/WaveformPrewarmer.swift`（解析度對齊、併發上限）
- `OnlyCue/Media/VideoPosterCache.swift`（共用 fast fingerprint）
- `OnlyCue/UI/WaveformContainer.swift` + `WaveformContainer+Lanes.swift`（漸進更新、合流、去正規化渲染接線）
- `OnlyCue/UI/WaveformView.swift`、`OnlyCue/Media/WaveformPeakBucketer.swift`（雙包絡渲染、收合分流）— **最高風險**
- 新增:進行中工作合流的 actor（`OnlyCue/Media/`）

## 不在本 spec 範圍

- 「可見視窗即時重算」(方案 Y)。
- 「重新產生波形」逃生口。
- vDSP 內層最佳化(可作為後續 perf 迭代)。

## 待辦流程(依 CLAUDE.md)

spec →(核准)→ plan → GitHub issue(s) → TDD 實作 → CI green → PR → review → merge。**本 spec 核准前不動任何實作碼。**

拆分建議(plan 階段細化):

1. fast fingerprint(波形 + 海報共用) — 相對獨立、低風險,可先行。
2. 產生管線(8000Hz + 10ms + 峰值/RMS + 去正規化 + AsyncStream)+ 快取 v4。
3. actor 合流 + prewarmer(甲、併發上限、解析度對齊)。
4. 雙包絡渲染器改動(**最高風險**,獨立 issue,重回歸驗證)。
