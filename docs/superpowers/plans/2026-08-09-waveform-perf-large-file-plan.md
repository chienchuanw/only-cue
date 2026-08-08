# Plan — #729 大檔波形效能

**Spec:** `docs/superpowers/specs/2026-08-09-waveform-perf-large-file-design.md`
**Parent issue:** #729

## 拆分為 4 個依序 issue

依風險與相依性排序,前三個低/中風險可平順推進,第四個是最高風險、獨立驗證。

### Issue A — fast fingerprint(波形 + 海報共用)
- **範圍**:新增共用 helper `fastFingerprint(url) = 大小 + SHA256(頭1MB ‖ 尾1MB)`,不含 mtime。`WaveformCache` 與 `VideoPosterCache` 兩邊改用。
- **相依**:無。可先行、獨立合併,立刻治好高位元率影片的開檔卡頓。
- **TDD**:
  - 給定內容相同的兩檔(不同 mtime)→ 指紋相同(不誤重算)。
  - 大小不同 / 頭不同 / 尾不同 → 指紋不同。
  - 常數時間:不因檔案大小而變(以中段差異、頭尾相同的大檔驗證「只讀頭尾」)。
- **風險**:低。快取鍵改變 → 舊快取一次性作廢(可接受)。

### Issue B — 產生管線 + 快取 v4
- **範圍**:`WaveformGenerator` 改 8000Hz 解碼、10ms 時間格、每格存峰值(max-abs)+ RMS、**存原始未正規化值**、改吐 `AsyncStream`。`WaveformCache` `formatVersion` 3→4、鍵改 `-<每格ms>`。
- **相依**:A(用新指紋當鍵)。
- **TDD**:
  - 10ms 格數 = ceil(時長/10ms)。
  - 每格同時產出峰值與 RMS;峰值 ≥ RMS。
  - 未正規化:輸出未被全域最大值除(與「渲染時正規化」對齊)。
  - `AsyncStream` 逐步 yield 且最終總格數正確;取消可中止。
  - 靜音檔仍為平(silenceFloor 行為保留)。
- **風險**:中。核心演算法改動,但有測試守門。

### Issue C — actor 合流 + prewarmer(甲)
- **範圍**:新增進行中工作合流 actor(key→共享 `AsyncStream`);`WaveformPrewarmer` 解析度對齊全高解析、加併發上限 2–3、匯入時暖所有檔;前景 `WaveformContainer` 接漸進更新 + 16ms 節流。
- **相依**:B。
- **TDD**:
  - 同 key 併發請求只觸發一次解碼(合流)。
  - prewarmer 併發不超過上限。
  - 前景在 prewarm 進行中點開 → 接上同一條 stream,不另開解碼。
- **風險**:中。並行/時序,測試需用可控 fake generator。

### Issue D — 雙包絡渲染器(⚠ 最高風險)
- **範圍**:`WaveformView` / `WaveformPeakBucketer` / #675 連續位移渲染改吃(峰值 + RMS)兩層;全景收合用 RMS(能量平均)、深度 zoom 用峰值(取 max);渲染時以「已載入格最大值」正規化。
- **相依**:B(資料格式)、C(漸進來源)。
- **TDD / 回歸**:
  - 收合:峰值取 max、RMS 取能量平均,兩者分流正確。
  - 渲染時正規化:全載入後與現況等價。
  - **回歸守門(UITest / 手動)**:click-to-seek、context-menu、`.sheet(item:)`、無障礙 hit-test、多聲道 lane(#720)、LTC strip 對齊(#663)全數不退化。
- **風險**:高。手勢 / seek / 無障礙密集區(CLAUDE.md 警告)。

## 建議推進順序

A → B → C → D,各自獨立 PR。A 可立即帶來可感收益(海報 + 波形開檔不再讀滿全檔)。

## 待你確認

- 是否同意「開 4 個 sub-issue、掛在 #729 底下」?或你偏好「單一 #729 分階段做」?
- 確認後我依 `gh-dev` 開分支、`gh-issue` 建 issue(依既有模板),從 Issue A 起跑 TDD。
