# Spec — 多聲道波形判讀改善(每聲道 lane + LTC 排除)

**Status:** drafted 2026-08-05 (grilled), approved
**Issue:** #720
**Builds on:** v0.20.0 source-audio "Music only" / music-only waveform (#715)

## Goal

讓多聲道來源音檔的波形更好判讀,並確保偵測到的 LTC 聲道永遠不會混進畫出來的波形。分兩件事:

1. **修/確認波形的 LTC 排除**(bug)。
2. **新增可切換的「每聲道 lane」顯示**(feature,預設關)。

## 背景 / 問題

匯入 **L=音樂 / R=LTC** 的 striped 檔:播放已正確 music-only(只聽到音樂),但**波形看起來仍混入 LTC**。此外,現況所有檔案畫的是**單條合併(mono downmix)**波形——遇到左右聲道內容不同的立體聲音樂時,不易逐聲道判讀。

## 釐清過程的關鍵決定(2026-08-05 grilling)

1. **LTC 聲道不畫成等高完整波形。** LTC 是 biphase-mark 方波,振幅近乎固定滿格 → RMS/peak 波形是一條**無起伏、無資訊的實心塊**;#715 規格已評估並否決「上音樂、下 LTC」雙軌,改用 badge。本 spec 維持此結論。
2. **多聲道顯示做成開關、預設關。** 大多數音樂 L≈R,一律拆兩條只會把高度砍半、資訊沒多多少,且會回歸到 app 裡**每一個**立體聲檔。故做成 app 全域偏好、預設關,零回歸;要比對 L/R 時再打開。
3. **開關打開時,只畫音樂聲道的 lane;LTC 聲道用強化 badge 表示。**
4. **開關為顯示用途,不改播放。** 靜音仍由 LTC 偵測 + 既有 per-clip 來源音訊模式(`playsOriginalSourceAudio`)決定;**不**做混音台式 per-channel mute UI。

## ① 修 bug:波形的 LTC 排除

- **現象:** music-only 波形應排除 LTC 聲道,實測仍似混入。最可能為 `excludingChannel` 產生時為 `nil` → 退回全聲道 mono downmix(把 LTC 混回);亦可能為快取/時序 artifact。
- **現況 code 讀起來是對的**:`.stripedTimecodeReader` 的 environment 有涵蓋 `WaveformContainer`(`DocumentView.swift:129` 包住整個 `NavigationSplitView`);`excludingChannel = stripedTimecode?.ltcChannel` 有接到 `cache.read` / `WaveformGenerator.peaks` / `cache.write`;`WaveformLoadKey` 含 `excludingChannel`,偵測非同步解出後會重跑。→ **需實機重現才能定位**,亦可能無 bug。
- **動作:** 重現 → 確認根因 → 修到「striped 檔波形只畫音樂聲道」。
- **相關檔案:** `WaveformContainer.swift`、`WaveformGenerator.swift`(`musicOnlyPeaks`)、`WaveformCache.swift`、`PreviewPane.swift`、`StripedTimecodeHost.swift`。

## ② 功能:每聲道波形 lane(開關,預設關)

- **開關「分離聲道 / Split Channels」**:View 選單或波形上的小控制;**app 全域偏好**(比照 `@AppStorage` 的 `showTempoGrid` / `autoScrollWaveform`);**預設關**。
- **關閉(預設):** 維持現在的單條合併波形(mono downmix,已排除 LTC)。單聲道與此路徑須與現況 **byte-identical**。
- **打開:**
  - 每個**音樂**聲道各一條**垂直堆疊** lane,共用同一時間軸。
  - 播放頭、cue 標記、tempo 格線、時間尺、點擊 seek、歌詞軌 **橫跨** 所有 lane(不切開)。
  - 純立體聲音樂 → 2 條(L/R);單聲道 → 1 條;>2 音樂聲道 → N 條(通用,少見)。
  - **偵測到的 LTC 聲道不畫成 lane**;改為**強化現有 badge**,明講「哪個聲道是 LTC 且已靜音」(例:`R = LTC(靜音)· 起始 TC`),避免與既有 **LTC 輸出 strip**(#663/#669)撞名。

## 驗收條件(Gherkin)

```gherkin
Scenario: LTC 檔在開關關閉時只顯示乾淨音樂波形
  Given 一個 L=音樂、R=LTC 的匯入檔
  And 「分離聲道」開關關閉(預設)
  Then 波形只畫音樂聲道,不含 LTC 的實心塊
  And badge 標示偵測到的 LTC 起始時間碼

Scenario: 打開分離聲道顯示純立體聲音樂
  Given 一個左右都是音樂的立體聲檔
  When 打開「分離聲道」開關
  Then 波形顯示上下兩條 lane(L / R),共用同一時間軸
  And 播放頭、cue 標記、點擊 seek 橫跨兩條 lane 且行為不變

Scenario: 打開分離聲道時 LTC 聲道不佔一條 lane
  Given 一個偵測到 LTC 的檔
  When 打開「分離聲道」開關
  Then 只顯示音樂聲道的 lane
  And badge 明確標示哪個聲道是 LTC 且已靜音

Scenario: 開關關閉零回歸
  Given 任一既有檔案
  And 「分離聲道」開關關閉
  Then 波形與 v0.20.0 的顯示 byte-identical(不變矮、不改觀感)
```

## 技術方案與風險(非決策,標記成本)

- **快取格式:** `WaveformCache` 由單一 `[Float]` 擴為每聲道 peaks(格式/快取鍵調整;與現有 `excludingChannel` 鍵並存,關閉路徑不受影響)。
- **渲染最佳化:** #681 的「render 一次、逐幀平移」需擴到 N 條 lane(N 個 Canvas 層);高 zoom 下效能須維持。
- **對齊:** 多 lane 排版須維持 LTC 輸出 strip 的對齊(#663/#669)與 `PreviewLayout` 的內縮共享。
- **命名區隔:** 來源 LTC(此 spec)vs LTC 輸出 strip 須在 UI 文案上清楚分開,延續 #715 的區隔原則。

## 不在範圍內(v1)

- 把 LTC 聲道畫成完整或薄的波形軌(否決理由如上)。
- 任何播放路徑變更。
- 混音台式 per-channel mute / solo 控制。
- 每聲道獨立的顏色/增益/垂直 zoom。
