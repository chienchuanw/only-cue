import Foundation

// MARK: - v17 through v23

extension CuelistMigrationFixture {

    /// **Authored here** — no v17 fixture existed anywhere in the suite.
    ///
    /// Deliberately the richest document of the set: it is the only one with a
    /// *multi-element* `includedTypeIDs`. That matters because the field is a
    /// `Set<UUID>` whose JSON array order is randomised per process, so without a
    /// case like this the vector would never exercise the sort that keeps the drift
    /// guard stable.
    static let v17 = """
    {
      "schemaVersion": 17,
      "id": "11110000-1111-0000-1111-000011110000",
      "name": "doc",
      "cuePointTypes": [
        {
          "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#FFFFFF",
          "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
          "isVisible":true,"isExportEnabled":true
        },
        {
          "id":"AAAA0002-0000-0000-0000-000000000002","name":"Spot","colorHex":"#FF6B6B",
          "defaultFadeTime":1.5,"defaultNamePattern":"Spot","hotkey":2,
          "isVisible":true,"isExportEnabled":true
        }
      ],
      "items": [{
        "id": "22220000-2222-0000-2222-000022220000",
        "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
        "cues": [],
        "startTimecodeFrames": 0,
        "ltcMuted": false,
        "alternateName": null,
        "lyrics": {"offsetSeconds": 0, "lines": []},
        "ma2PushTarget": {
          "sequenceSlot": 12, "timecodeSlot": 3,
          "executorPage": 2, "executorNumber": 5,
          "timecodeCommand": "goto",
          "includedTypeIDs": [
            "AAAA0002-0000-0000-0000-000000000002",
            "AAAA0001-0000-0000-0000-000000000001"
          ],
          "sequenceName": "Act One"
        }
      }],
      "activeItemID": null,
      "timecodeSettings": {"framerate":"30"},
      "playbackMode": "playOnce"
    }
    """

    static let v18 = """
    {
      "schemaVersion": 18,
      "id": "11110000-1111-0000-1111-000011110000",
      "name": "doc",
      "cuePointTypes": [{
        "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#FFFFFF",
        "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
        "isVisible":true,"isExportEnabled":true
      }],
      "items": [{
        "id": "22220000-2222-0000-2222-000022220000",
        "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
        "cues": [],
        "startTimecodeFrames": 0,
        "ltcMuted": false,
        "alternateName": null,
        "lyrics": {"offsetSeconds": 0, "lines": []}
      }],
      "activeItemID": null,
      "timecodeSettings": {"framerate":"30"},
      "playbackMode": "playOnce"
    }
    """

    static let v19 = """
    {
      "schemaVersion": 19,
      "id": "11110000-1111-0000-1111-000011110000",
      "name": "doc",
      "cuePointTypes": [{
        "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#FFFFFF",
        "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
        "isVisible":true,"isExportEnabled":true
      }],
      "items": [{
        "id": "22220000-2222-0000-2222-000022220000",
        "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
        "cues": [],
        "startTimecodeFrames": 0,
        "ltcMuted": false,
        "alternateName": null,
        "lyrics": {"offsetSeconds": 0, "lines": []},
        "playsOriginalSourceAudio": false
      }],
      "activeItemID": null,
      "timecodeSettings": {"framerate":"30"},
      "playbackMode": "playOnce"
    }
    """

    /// v20 is where `executorPage` / `executorNumber` became optional (#764).
    static let v20 = """
    {
      "schemaVersion": 20,
      "id": "11110000-1111-0000-1111-000011110000",
      "name": "doc",
      "cuePointTypes": [{
        "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#FFFFFF",
        "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
        "isVisible":true,"isExportEnabled":true
      }],
      "items": [{
        "id": "22220000-2222-0000-2222-000022220000",
        "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
        "cues": [],
        "startTimecodeFrames": 0,
        "ltcMuted": false,
        "alternateName": null,
        "lyrics": {"offsetSeconds": 0, "lines": []},
        "playsOriginalSourceAudio": false,
        "ma2PushTarget": {
          "sequenceSlot": 12, "timecodeSlot": 3,
          "executorPage": 2, "executorNumber": 5,
          "timecodeCommand": "goto", "includedTypeIDs": []
        }
      }],
      "activeItemID": null,
      "timecodeSettings": {"framerate":"30"},
      "playbackMode": "playOnce"
    }
    """

    static let v21 = """
    {
      "schemaVersion": 21,
      "id": "11110000-1111-0000-1111-000011110000",
      "name": "doc",
      "cuePointTypes": [{
        "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#FFFFFF",
        "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
        "isVisible":true,"isExportEnabled":true
      }],
      "items": [{
        "id": "22220000-2222-0000-2222-000022220000",
        "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
        "cues": [],
        "startTimecodeFrames": 0,
        "ltcMuted": true,
        "alternateName": "Overture",
        "lyrics": {"offsetSeconds": 0, "lines": []},
        "playsOriginalSourceAudio": false
      }],
      "activeItemID": "22220000-2222-0000-2222-000022220000",
      "timecodeSettings": {"framerate":"30"},
      "playbackMode": "playOnce"
    }
    """

    static let v22 = """
    {
      "schemaVersion": 22,
      "id": "11110000-1111-0000-1111-000011110000",
      "name": "doc",
      "cuePointTypes": [{
        "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#FFFFFF",
        "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
        "isVisible":true,"isExportEnabled":true
      }],
      "items": [{
        "id": "22220000-2222-0000-2222-000022220000",
        "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
        "cues": [],
        "startTimecodeFrames": 0,
        "ltcMuted": true,
        "alternateName": "Overture",
        "lyrics": {"offsetSeconds": 0, "lines": []},
        "playsOriginalSourceAudio": false,
        "colorHex": "#FF6B6B"
      }],
      "activeItemID": "22220000-2222-0000-2222-000022220000",
      "timecodeSettings": {"framerate":"30"},
      "playbackMode": "playOnce"
    }
    """

    /// **Authored here** — the suite had no document already at the current
    /// version. Carries the v23-era fields (`rememberedLTC` with its `validFrom` /
    /// `validUntil` window, and a non-`auto` `ltcChannelSelection`, which encodes as
    /// the flat string `"channel:1"` rather than a nested object).
    static let v23 = """
    {
      "schemaVersion": 23,
      "id": "11110000-1111-0000-1111-000011110000",
      "name": "doc",
      "cuePointTypes": [{
        "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#FFFFFF",
        "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
        "isVisible":true,"isExportEnabled":true
      }],
      "items": [{
        "id": "22220000-2222-0000-2222-000022220000",
        "media": {
          "displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID",
          "bundlePath":"/Volumes/Show/x.wav"
        },
        "cues": [{
          "id":"BBBB0001-0000-0000-0000-000000000001",
          "typeID":"AAAA0001-0000-0000-0000-000000000001",
          "cueNumber":1.5,"name":"c","time":1.25,"notes":"n",
          "fadeTime":{"fadeIn":0.5,"fadeOut":2},
          "bpm":128.0,"beatsPerBar":4
        }],
        "startTimecodeFrames": 90,
        "ltcMuted": true,
        "alternateName": "Overture",
        "lyrics": {"offsetSeconds": 1.5, "lines": [
          {"id":"CCCC0001-0000-0000-0000-000000000001","time":3.5,"text":"hello"},
          {"id":"CCCC0002-0000-0000-0000-000000000002","text":"unplaced"}
        ]},
        "playsOriginalSourceAudio": true,
        "colorHex": "#FF6B6B",
        "ltcChannelSelection": "channel:1",
        "rememberedLTC": {
          "anchorTimecode": {"rate":"30","hours":0,"minutes":0,"seconds":30,"frames":0},
          "anchorPlaybackSeconds": 2.0,
          "ltcChannel": 1,
          "validFrom": 0.0,
          "validUntil": 55.0
        }
      }],
      "activeItemID": "22220000-2222-0000-2222-000022220000",
      "timecodeSettings": {"framerate":"30"},
      "playbackMode": "loop"
    }
    """

    /// Version → document, in ladder order. The vector walks this.
    static let all: [(version: Int, json: String)] = [
        (1, v1), (2, v2), (3, v3), (4, v4), (5, v5), (6, v6), (7, v7), (8, v8),
        (9, v9), (10, v10), (11, v11), (12, v12), (13, v13), (14, v14), (15, v15),
        (16, v16), (17, v17), (18, v18), (19, v19), (20, v20), (21, v21),
        (22, v22), (23, v23)
    ]
}
