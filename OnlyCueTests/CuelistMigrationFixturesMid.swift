import Foundation

// MARK: - v9 through v16

extension CuelistMigrationFixture {

    /// From `ProjectTimecodeSettingsTests` — the only v6 document in the suite.
    /// Empty `items`, which is worth keeping: it pins that an empty show migrates.
    static let v6 = """
    {
      "schemaVersion": 6,
      "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
      "name": "Legacy v6 show",
      "activeItemID": null,
      "cuePointTypes": [
        {
          "id": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "name": "General",
          "colorHex": "#4ECDC4",
          "defaultFadeTime": 0,
          "defaultNamePattern": "Cue",
          "hotkey": null,
          "isVisible": true,
          "isExportEnabled": true
        }
      ],
      "items": []
    }
    """

    /// v7 had the project-wide `startOffsetFrames` that later fans out onto items.
    static let v7 = """
    {
      "schemaVersion": 7,
      "id": "7E7E7E7E-7E7E-7E7E-7E7E-7E7E7E7E7E7E",
      "name": "Show",
      "cuePointTypes": [
        {
          "id": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "name": "General",
          "colorHex": "#4ECDC4",
          "defaultFadeTime": 0,
          "defaultNamePattern": "Cue",
          "isVisible": true,
          "isExportEnabled": true
        }
      ],
      "items": [
        {
          "id": "AABBCCDD-1111-2222-3333-444455556666",
          "media": {
            "displayName": "act1.wav",
            "kind": "audio",
            "duration": 100,
            "bookmarkData": "AQID"
          },
          "cues": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "cueNumber": 1,
              "name": "Cue 1",
              "time": 5.0,
              "notes": "",
              "fadeTime": { "fadeIn": 0, "fadeOut": 0 }
            }
          ]
        }
      ],
      "activeItemID": "AABBCCDD-1111-2222-3333-444455556666",
      "timecodeSettings": { "framerate": "25", "startOffsetFrames": 90000 }
    }
    """

    /// Fractional `cueNumber` survives the widening to `Double?`.
    static let v8 = """
    {
      "schemaVersion": 8,
      "id": "88888888-8888-8888-8888-888888888888",
      "name": "ShowV8",
      "cuePointTypes": [
        {
          "id": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "name": "General",
          "colorHex": "#4ECDC4",
          "defaultFadeTime": 0,
          "defaultNamePattern": "Cue",
          "isVisible": true,
          "isExportEnabled": true
        }
      ],
      "items": [
        {
          "id": "AABBCCDD-1111-2222-3333-444455556666",
          "media": {
            "displayName": "act1.wav",
            "kind": "audio",
            "duration": 100,
            "bookmarkData": "AQID"
          },
          "cues": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "cueNumber": 1,
              "name": "Cue 1",
              "time": 5.0,
              "notes": "",
              "fadeTime": { "fadeIn": 0, "fadeOut": 0 }
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "cueNumber": 1.5,
              "name": "Cue 1.5",
              "time": 7.5,
              "notes": "",
              "fadeTime": { "fadeIn": 0, "fadeOut": 0 }
            },
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "cueNumber": 2,
              "name": "Cue 2",
              "time": 10.0,
              "notes": "",
              "fadeTime": { "fadeIn": 0, "fadeOut": 0 }
            }
          ],
          "tempoMap": { "sections": [] }
        }
      ],
      "activeItemID": "AABBCCDD-1111-2222-3333-444455556666",
      "timecodeSettings": { "framerate": "25", "startOffsetFrames": 90000 }
    }
    """

    /// Two items and a project offset, so the fan-out onto `startTimecodeFrames`
    /// is pinned for more than one item.
    static let v9 = """
    {
      "schemaVersion": 9,
      "id": "AAAA9999-AAAA-9999-AAAA-9999AAAA9999",
      "name": "ShowV9",
      "cuePointTypes": [],
      "items": [
        {
          "id": "11110000-1111-0000-1111-000011110000",
          "media": {
            "displayName": "act1.wav",
            "kind": "audio",
            "duration": 60,
            "bookmarkData": "AQID"
          },
          "cues": [],
          "tempoMap": { "sections": [] }
        },
        {
          "id": "22220000-2222-0000-2222-000022220000",
          "media": {
            "displayName": "act2.wav",
            "kind": "audio",
            "duration": 90,
            "bookmarkData": "AQID"
          },
          "cues": [],
          "tempoMap": { "sections": [] }
        }
      ],
      "activeItemID": null,
      "timecodeSettings": { "framerate": "25", "startOffsetFrames": 90000 }
    }
    """

    /// The one rung that mints cue identifiers: two tempo sections fan out, and the
    /// section that has no cue within tolerance gets a synthetic "Tempo" cue with a
    /// fresh `UUID()`. That is why the vector normalises minted ids.
    static let v10 = """
    {
      "schemaVersion": 10,
      "id": "11110000-1111-0000-1111-000011110000",
      "name": "doc",
      "cuePointTypes": [{
        "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#fff",
        "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
        "isVisible":true,"isExportEnabled":true
      }],
      "items": [{
        "id": "22220000-2222-0000-2222-000022220000",
        "media": {"displayName":"x","kind":"audio","duration":60,"bookmarkData":"AQID"},
        "cues": [{
          "id":"BBBB0001-0000-0000-0000-000000000001","typeID":"AAAA0001-0000-0000-0000-000000000001","cueNumber":null,
          "name":"c","time":0.0,"notes":"","fadeTime":{"fadeIn":0,"fadeOut":0}
        }],
        "tempoMap": {"sections":[
          {
            "id":"33330000-3333-0000-3333-000033330000",
            "startSeconds":0.0,"bpm":120.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.0
          },
          {
            "id":"44440000-4444-0000-4444-000044440000",
            "startSeconds":30.0,"bpm":75.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.0
          }
        ]},
        "startTimecodeFrames": 0,
        "ltcMuted": false
      }],
      "activeItemID": null,
      "timecodeSettings": {"framerate":"30"}
    }
    """

    static let v11 = """
    {
      "schemaVersion": 11,
      "id": "11110000-1111-0000-1111-000011110000",
      "name": "doc",
      "cuePointTypes": [{
        "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#fff",
        "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
        "isVisible":true,"isExportEnabled":true
      }],
      "items": [{
        "id": "22220000-2222-0000-2222-000022220000",
        "media": {"displayName":"song.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
        "cues": [],
        "startTimecodeFrames": 240,
        "ltcMuted": true
      }],
      "activeItemID": null,
      "timecodeSettings": {"framerate":"30"}
    }
    """

    static let v12 = """
    {
      "schemaVersion": 12,
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
        "cues": [{
          "id":"BBBB0001-0000-0000-0000-000000000001","typeID":"AAAA0001-0000-0000-0000-000000000001",
          "cueNumber":null,"name":"c","time":1.5,"notes":"n","fadeTime":{"fadeIn":0,"fadeOut":0}
        }],
        "startTimecodeFrames": 90,
        "ltcMuted": true,
        "alternateName": "Act 1"
      }],
      "activeItemID": null,
      "timecodeSettings": {"framerate":"30"}
    }
    """

    /// v13 wrote a concrete `time` on every lyric line; v14 made it optional.
    static let v13 = """
    {
      "schemaVersion": 13,
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
        "lyrics": {"offsetSeconds": 12, "lines": [
          {"id":"CCCC0001-0000-0000-0000-000000000001","time":3.5,"text":"hello"}
        ]}
      }],
      "activeItemID": null,
      "timecodeSettings": {"framerate":"30"}
    }
    """

    static let v14 = """
    {
      "schemaVersion": 14,
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
        "lyrics": {"lines": [], "offsetSeconds": 0}
      }],
      "activeItemID": null,
      "timecodeSettings": {"framerate":"30"}
    }
    """

    static let v15 = """
    {
      "schemaVersion": 15,
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

    /// v16 is the first version that can carry an `ma2PushTarget`, but not yet a
    /// `sequenceName`.
    static let v16 = """
    {
      "schemaVersion": 16,
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
        "ma2PushTarget": {
          "sequenceSlot": 12, "timecodeSlot": 3,
          "executorPage": 2, "executorNumber": 5,
          "timecodeCommand": "go", "includedTypeIDs": []
        }
      }],
      "activeItemID": null,
      "timecodeSettings": {"framerate":"30"},
      "playbackMode": "playOnce"
    }
    """

}
