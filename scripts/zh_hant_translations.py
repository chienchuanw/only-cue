#!/usr/bin/env python3
"""Fill zh-Hant translations into Localizable.xcstrings (OnlyCue #724, Phase 2).

Keyed by quote-normalized English so curly/straight quote differences in the
catalog don't break matching. Every catalog key must be covered or the script
exits non-zero listing the gaps. Keep-English glossary terms keep their English
value but are still marked `translated` (an explicit confirmation, per spec).
"""
import json
import sys

CATALOG = "OnlyCue/Resources/Localizable.xcstrings"

# key (English source) -> zh-Hant value. Straight quotes here; matched against
# the catalog by normalization below.
T = {
    # Format / punctuation / technical — left as-is (glossary: never localize).
    "#": "#",
    "%@ %@": "%@ %@",
    "%@ → %@": "%@ → %@",
    "%lld": "%lld",
    "%lld%%": "%lld%%",
    ".": ".",
    "/ %@": "/ %@",
    "4": "4",
    "HH:MM:SS:FF": "HH:MM:SS:FF",
    "—": "—",
    # Keep-English glossary single terms.
    "BPM": "BPM",
    "GO": "GO",
    "MIDI": "MIDI",
    "OSC": "OSC",
    "Cue": "Cue",
    "grandMA2": "grandMA2",
    "OnlyCue": "OnlyCue",
    "Executor (page.exec)": "Executor (page.exec)",
    # Interpolated / general strings.
    "%@ Mode": "%@ 模式",
    "%@ couldn't be opened from its saved location.": "%@ 無法從儲存位置開啟。",
    "%@ — %lld ch": "%@ — %lld 聲道",
    "%@ → a .lua + .xml plugin you import and run on the console":
        "%@ → 一組 .lua + .xml plugin，匯入後在 console 上執行",
    "%lld commands over telnet.": "透過 telnet 送出 %lld 筆指令。",
    "%lld cues": "%lld 個 cue",
    "%lld hidden lane%@": "%lld 個隱藏軌",
    "%lld media files can't be included": "%lld 個媒體檔案無法納入",
    "%lld points": "%lld 個點",
    "%lld shortcut%@ used by more than one action": "%lld 個快捷鍵被多個動作使用",
    "1 cue": "1 個 cue",
    "1 media file can't be included": "1 個媒體檔案無法納入",
    "About OnlyCue": "關於 OnlyCue",
    "Actual Horizontal Size": "實際水平大小",
    "Add": "新增",
    "Add Cue": "新增 Cue",
    "Add Type": "新增類型",
    "All": "全部",
    "All Type lanes are hidden — show one to see its cues.":
        "所有類型軌都已隱藏 — 顯示其中一個以查看其 cue。",
    "All lines are placed.": "所有歌詞行都已放置。",
    "Audio": "音訊",
    "Auto-Scroll Waveform": "自動捲動 Waveform",
    "Auto-advancing to next media": "自動前往下一個媒體",
    "Back": "返回",
    "Back 1s": "後退 1 秒",
    "Background Color": "背景顏色",
    "Beats / bar": "每小節拍數",
    "Both the .xml and its _PLUGIN.lua are written next to each other.":
        "「.xml」與其「_PLUGIN.lua」會一併寫入同一位置。",
    "Bottom": "底部",
    "Bundle Export Failed": "Bundle 匯出失敗",
    "Bundle Name:": "Bundle 名稱：",
    "Cancel": "取消",
    "Center": "置中",
    "Change Cue Tempo": "變更 Cue 速度",
    "Change Start Timecode": "變更起始 Timecode",
    "Change Timecode Settings": "變更 Timecode 設定",
    "Change Type": "變更類型",
    "Changing the language takes effect after OnlyCue restarts.":
        "變更語言後，需重新啟動 OnlyCue 才會生效。",
    "Channel %lld": "聲道 %lld",
    "Channel Assignment": "聲道指派",
    "Check for Updates…": "檢查更新…",
    "Choose where to save the PotPlayer bookmark folder.": "選擇 PotPlayer 書籤資料夾的儲存位置。",
    "Choose where to save the bundle folder.": "選擇 bundle 資料夾的儲存位置。",
    "Clear": "清除",
    "Clear this binding": "清除此綁定",
    "Click a shortcut to record a new key combination. Press Esc to cancel.":
        "點按一個快捷鍵以錄製新的按鍵組合。按 Esc 取消。",
    "Click to switch between time and beat countdown.": "點按以在時間與拍數倒數之間切換。",
    "Close": "關閉",
    "Color": "顏色",
    "Combine Channels": "合併聲道",
    "Console IP / hostname": "Console IP／主機名稱",
    "Content": "內容",
    "Continue": "繼續",
    "Continue without media": "不使用媒體繼續",
    "Copy": "拷貝",
    "Could not generate waveform": "無法產生 Waveform",
    "Couldn't check for updates": "無法檢查更新",
    "Cue List Import Failed": "Cue List 匯入失敗",
    "Cue Mode": "Cue 模式",
    "Cue Type %lld": "Cue 類型 %lld",
    "Cue name": "Cue 名稱",
    "Cues": "Cue",
    "Delete": "刪除",
    "Delete \"%@\"?": "刪除「%@」？",
    "Delete Line": "刪除歌詞行",
    "Detect": "偵測",
    "Disable LTC to change playback rate.": "停用 LTC 以變更播放速率。",
    "Discovered": "已發現",
    "Don't Pause at Each Cue": "不在每個 Cue 暫停",
    "Done": "完成",
    "Download": "下載",
    "Drag an audio or video file here": "將音訊或影片檔案拖曳到這裡",
    "Drag files here or use ⌘O": "將檔案拖曳到這裡，或使用 ⌘O",
    "Duplicate at Playhead": "在播放頭處複製",
    "Edit Media": "編輯媒體",
    "Edit Media…": "編輯媒體…",
    "Edit Note Overlay Appearance…": "編輯備註疊層外觀…",
    "Edit Notes…": "編輯備註…",
    "Enable LTC output": "啟用 LTC 輸出",
    "Enable OSC server": "啟用 OSC 伺服器",
    "English name": "英文名稱",
    "Export": "匯出",
    "Export Bundle…": "匯出 Bundle…",
    "Export Cue List…": "匯出 Cue List…",
    "Export Cues": "匯出 Cue",
    "Export Cues…": "匯出 Cue…",
    "Export PotPlayer Bookmarks…": "匯出 PotPlayer 書籤…",
    "Export grandMA2 plugin": "匯出 grandMA2 plugin",
    "Export grandMA2 plugin…": "匯出 grandMA2 plugin…",
    "Export…": "匯出…",
    "Filter by Type": "依類型篩選",
    "Folder Name:": "資料夾名稱：",
    "Font Scale": "字體縮放",
    "Format": "格式",
    "Forward 1s": "前進 1 秒",
    "Framerate": "影格率",
    "GO cue type": "GO cue 類型",
    "GO walks": "GO 前進方式",
    "GO — next cue": "GO — 下一個 cue",
    "General": "一般",
    "Get Started": "開始使用",
    "Go": "前往",
    "Goto": "跳至",
    "Hide Inspector": "隱藏檢閱器",
    "Hide Lyrics Overlay": "隱藏歌詞疊層",
    "Hide Notes Overlay": "隱藏備註疊層",
    "Hide Tempo Grid": "隱藏速度格線",
    "Hide Timeline Breakdown": "隱藏時間軌分解",
    "Hide the %@ lane": "隱藏「%@」軌",
    "Import": "匯入",
    "Import Cue List…": "匯入 Cue List…",
    "Import Media (⌘O)": "匯入媒體 (⌘O)",
    "Import Media…": "匯入媒體…",
    "Import a media file to start adding cues.": "匯入媒體檔案以開始新增 cue。",
    "Import a media item to add lyrics.": "匯入媒體項目以新增歌詞。",
    "Import audio or video to preview": "匯入音訊或影片以預覽",
    "Info": "資訊",
    "Input device": "輸入裝置",
    "Inspector width": "檢閱器寬度",
    "Interval": "間隔",
    "Keyboard": "鍵盤",
    "Keyboard Shortcuts": "鍵盤快捷鍵",
    "Keyboard shortcuts": "鍵盤快捷鍵",
    "LTC output level": "LTC 輸出電平",
    "LTC playhead": "LTC 播放頭",
    "Language": "語言",
    "Later": "稍後",
    "Layout": "版面配置",
    "Learn": "學習",
    "Leave all unchecked to export every cue.": "全部不勾選則匯出所有 cue。",
    "Leave all unchecked to push every cue.": "全部不勾選則推送所有 cue。",
    "Listen port": "監聽埠",
    "Load Template…": "載入範本…",
    "Looping current media": "循環播放目前媒體",
    "Lyric Mode": "歌詞模式",
    "Lyrics": "歌詞",
    "MIDI Monitor…": "MIDI 監視器…",
    "Manage Types": "管理類型",
    "Manage Types…": "管理類型…",
    "Manage Workspaces": "管理工作區",
    "Manage Workspaces…": "管理工作區…",
    "Media": "媒體",
    "Media Start Timecodes": "媒體起始 Timecode",
    "Missing media": "缺少媒體",
    "Move a control…": "操作一個控制器…",
    "Mute LTC": "靜音 LTC",
    "Mute LTC for this clip": "為此片段靜音 LTC",
    "Name": "名稱",
    "New from Template…": "從範本新增…",
    "Next Cue": "下一個 Cue",
    "No MIDI input connected — choose one in Settings → MIDI.":
        "未連接 MIDI 輸入 — 請在「設定 → MIDI」中選擇。",
    "No channel is assigned to LTC.": "沒有聲道指派給 LTC。",
    "No conflicts": "沒有衝突",
    "No cues yet": "尚無 cue",
    "No media": "沒有媒體",
    "No media imported": "尚未匯入媒體",
    "No messages received yet — move a fader or press a button.":
        "尚未收到訊息 — 請移動推桿或按下按鈕。",
    "No messages received yet.": "尚未收到訊息。",
    "No recent projects": "沒有最近的專案",
    "No types in this project.": "此專案中沒有類型。",
    "None": "無",
    "Note Overlay Appearance": "備註疊層外觀",
    "Notes — %@": "備註 — %@",
    "Nudge Back": "微調後退",
    "Nudge Forward": "微調前進",
    "Numbers are assigned to the selected cues in time order.": "編號會依時間順序指派給所選的 cue。",
    "OK": "好",
    "OSC Monitor…": "OSC 監視器…",
    "Off = music only (mutes the detected timecode channel)":
        "關閉 = 僅音樂（靜音偵測到的 timecode 聲道）",
    "OnlyCue %@ is available — you have %@.": "OnlyCue %@ 已推出 — 您目前的版本是 %@。",
    "OnlyCue %@ is the latest release.": "OnlyCue %@ 已是最新版本。",
    "Output device": "輸出裝置",
    "Paste Lyrics from Clipboard": "從剪貼板貼上歌詞",
    "Pause at Each Cue": "在每個 Cue 暫停",
    "Placed": "已放置",
    "Plan and run lighting cues against your media.": "針對您的媒體規劃並執行燈光 cue。",
    "Play Music Only": "僅播放音樂",
    "Play Original Source Audio": "播放原始來源音訊",
    "Play Original Source Audio (with timecode)": "播放原始來源音訊（含 timecode）",
    "Play original source audio (with timecode)": "播放原始來源音訊（含 timecode）",
    "Play/Pause": "播放／暫停",
    "Playback": "播放",
    "Playback rate (click to adjust)": "播放速率（點按以調整）",
    "Plugin export failed": "Plugin 匯出失敗",
    "Position": "位置",
    "PotPlayer Export Failed": "PotPlayer 匯出失敗",
    "Press M to add a cue at the playhead.": "按 M 在播放頭處新增 cue。",
    "Press a shortcut…": "按下快捷鍵…",
    "Previous Cue": "上一個 Cue",
    "Push complete.": "推送完成。",
    "Push…": "推送…",
    "Read the docs on GitHub ↗": "在 GitHub 上閱讀文件 ↗",
    "Read-only — Show Mode": "唯讀 — 演出模式",
    "Recent Projects": "最近的專案",
    "Recent messages": "最近的訊息",
    "Refresh Devices": "重新整理裝置",
    "Relaunch": "重新啟動",
    "Relaunch to apply?": "重新啟動以套用？",
    "Release Notes…": "發行說明…",
    "Relink media…": "重新連結媒體…",
    "Remove": "移除",
    "Remove from Recents": "從最近項目中移除",
    "Rename": "重新命名",
    "Renumber": "重新編號",
    "Renumber %lld Cues": "重新編號 %lld 個 Cue",
    "Renumber Selected…": "重新編號所選…",
    "Replace": "取代",
    "Replace and Push": "取代並推送",
    "Replace the existing cues with the imported ones, or add the imported cues alongside them?":
        "以匯入的 cue 取代現有的 cue，還是將匯入的 cue 一併加入？",
    "Rescan devices": "重新掃描裝置",
    "Reset All…": "全部重設…",
    "Reset Routing": "重設路由",
    "Reset Speed": "重設速度",
    "Reset to 1.0×": "重設為 1.0×",
    "Reset to Default": "重設為預設值",
    "Reset to default (%@)": "重設為預設值（%@）",
    "Restore Defaults": "回復預設值",
    "Save": "儲存",
    "Save Current Layout As…": "將目前版面配置另存為…",
    "Save Template As…": "將範本另存為…",
    "Scan": "掃描",
    "Scanning…": "掃描中…",
    "Send Back to Unplaced": "送回未放置",
    "Send to grandMA2": "送到 grandMA2",
    "Send to grandMA2…": "送到 grandMA2…",
    "Sequence name": "Sequence 名稱",
    "Sequence slot": "Sequence 插槽",
    "Set Playback Mode": "設定播放模式",
    "Set a tempo on a cue to enable beat countdown. Click to switch back to time.":
        "在 cue 上設定速度以啟用拍數倒數。點按以切換回時間。",
    "Set from Playhead": "從播放頭設定",
    "Set grandMA2 Target": "設定 grandMA2 目標",
    "Show All": "顯示全部",
    "Show Cue Number Prefix": "顯示 Cue 編號前綴",
    "Show Lyrics Overlay": "顯示歌詞疊層",
    "Show Mode": "演出模式",
    "Show Notes Overlay": "顯示備註疊層",
    "Show Tempo Grid": "顯示速度格線",
    "Show Timeline Breakdown": "顯示時間軌分解",
    "Show a hidden Type lane": "顯示隱藏的類型軌",
    "Show hidden lanes": "顯示隱藏的軌",
    "Show in Finder": "在 Finder 中顯示",
    "Slow Down": "放慢",
    "Snap to Nearest Bar": "貼齊最近的小節",
    "Snap to Nearest Beat": "貼齊最近的拍",
    "Snap to Playhead": "貼齊播放頭",
    "Solid Background": "純色背景",
    "Speed Up": "加快",
    "Split Channels": "分割聲道",
    "Stamp Lyric Line": "標記歌詞行",
    "Start": "開始",
    "Start timecode": "起始 timecode",
    "Supported address patterns": "支援的位址格式",
    "Sync Offset": "同步偏移",
    "System": "系統",
    "System Default": "系統預設",
    "TC command": "TC 指令",
    "Target": "目標",
    "Telnet port": "Telnet 埠",
    "Tempo — %@": "速度 — %@",
    "Tempo…": "速度…",
    "Text Color": "文字顏色",
    "The OSC server is off — enable it in Settings → OSC.":
        "OSC 伺服器已關閉 — 請在「設定 → OSC」中啟用。",
    "The PotPlayer bookmarks could not be exported.": "無法匯出 PotPlayer 書籤。",
    "The built-in Default workspace can't be renamed or deleted.":
        "內建的「Default」工作區無法重新命名或刪除。",
    "The bundle could not be exported.": "無法匯出 bundle。",
    "The cue list could not be exported.": "無法匯出 cue list。",
    "The cue list file could not be read.": "無法讀取 cue list 檔案。",
    "The cue list was exported from \"%@\" (%@). The selected song is \"%@\" (%@).\n\nImport the cues anyway?":
        "此 cue list 匯出自「%@」（%@）。所選的歌曲是「%@」（%@）。\n\n仍要匯入這些 cue 嗎？",
    "The file is not a valid OnlyCue cue list.": "此檔案不是有效的 OnlyCue cue list。",
    "The workspace is removed. Windows keep their current arrangement.":
        "工作區已移除。視窗會維持目前的排列。",
    "These files couldn't be located on this Mac, so no bookmarks will be written for them. Export the rest anyway?":
        "這些檔案無法在此 Mac 上找到，因此不會為它們寫入書籤。仍要匯出其餘檔案嗎？",
    "These files couldn't be located on this Mac, so they won't be in the bundle and the recipient will need to relink them. Export the rest anyway?":
        "這些檔案無法在此 Mac 上找到，因此不會包含在 bundle 中，接收者需要重新連結它們。仍要匯出其餘檔案嗎？",
    "This cue list is from a different song": "此 cue list 來自不同的歌曲",
    "This cue list was created by a newer version of OnlyCue and can't be opened.":
        "此 cue list 由較新版本的 OnlyCue 建立，無法開啟。",
    "This song already has cues": "此歌曲已有 cue",
    "Timecode Settings": "Timecode 設定",
    "Timecode Settings…": "Timecode 設定…",
    "Timecode slot": "Timecode 插槽",
    "Tools": "工具",
    "Top": "頂部",
    "Type name": "類型名稱",
    "Unmute LTC for this clip": "取消此片段的 LTC 靜音",
    "Unplaced · Next to place": "未放置 · 下一個待放置",
    "Unsupported file": "不支援的檔案",
    "Untitled": "未命名",
    "Update Available": "有可用更新",
    "Welcome to OnlyCue": "歡迎使用 OnlyCue",
    "Workspace": "工作區",
    "Workspace name": "工作區名稱",
    "You're running a newer build (%@) than the latest release (%@).":
        "您執行的版本（%@）比最新發行版（%@）還新。",
    "You're up to date": "您已是最新版本",
    "Zoom In Horizontally": "水平放大",
    "Zoom Out Horizontally": "水平縮小",
    "inherited": "繼承",
    "lyric line": "歌詞行",
    "or press ⌘O": "或按 ⌘O",
    "New Project": "新增專案",
    "Open Other…": "開啟其他…",
    "Sets the LTC signal level independently of the music — raise it if a decoder drops frames. It can't exceed the Mac's system output volume; for full independence, route LTC to an audio-interface channel.":
        "獨立於音樂設定 LTC 訊號電平 — 若解碼器掉格可調高。它無法超過 Mac 的系統輸出音量；若要完全獨立，請將 LTC 路由到音訊介面的聲道。",
    "The LTC generator plays onto the channel assigned \"LTC\". A 4-channel interface can carry LTC on one channel and stereo track audio on two others.":
        "LTC 產生器會在指派為「LTC」的聲道上播放。4 聲道的音訊介面可用一個聲道傳送 LTC，另外兩個傳送立體聲 track 音訊。",
    "When on, OnlyCue generates SMPTE LTC and sends it — plus the media's audio on the Track channels — to the chosen output device. The media's normal audio output is muted while LTC is on.":
        "開啟時，OnlyCue 會產生 SMPTE LTC 並將其送出 — 連同媒體在 Track 聲道上的音訊 — 到所選的輸出裝置。LTC 開啟期間，媒體的一般音訊輸出會被靜音。",
}


def normalize(s: str) -> str:
    """Fold curly quotes/apostrophes to straight so key matching is robust."""
    return (s.replace("’", "'").replace("‘", "'")
             .replace("“", '"').replace("”", '"'))


def main() -> int:
    catalog = json.load(open(CATALOG))
    lookup = {normalize(k): v for k, v in T.items()}
    if len(lookup) != len(T):
        print("ERROR: duplicate normalized keys in translation table", file=sys.stderr)
        return 2

    missing = []
    for key in catalog["strings"]:
        value = lookup.get(normalize(key))
        if value is None:
            missing.append(key)
            continue
        catalog["strings"][key]["localizations"] = {
            "zh-Hant": {"stringUnit": {"state": "translated", "value": value}}
        }

    if missing:
        print(f"ERROR: {len(missing)} catalog keys have no translation:", file=sys.stderr)
        for key in sorted(missing):
            print("  " + repr(key), file=sys.stderr)
        return 1

    json.dump(catalog, open(CATALOG, "w"), ensure_ascii=False, indent=2)
    open(CATALOG, "a").write("\n")
    print(f"Translated {len(catalog['strings'])} entries into zh-Hant.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
