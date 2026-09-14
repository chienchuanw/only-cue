import Foundation

/// One representative `.cuelist` document per schema version, 1 through 23.
///
/// These are the *inputs* of `golden/cuelist-migration-v1.json`. The expected
/// outputs are not written by hand — they are whatever the real Swift ladder
/// produces, so the vector cannot drift away from the shipping behaviour without
/// the drift guard noticing.
///
/// Most are lifted verbatim from the existing per-version migration suites, so the
/// two stay in sync by construction. v17 and v23 had no fixture anywhere and are
/// authored here; both are noted below.
enum CuelistMigrationFixture {

    /// v1 carried a single project-level `media` and a flat `cues` array. Migrating
    /// mints both a default `CuePointType` and a `MediaItem` id.
    static let v1 = """
    {
      "schemaVersion": 1,
      "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
      "name": "Opening Number",
      "media": {
        "displayName": "act1.wav",
        "kind": "audio",
        "duration": 184.32,
        "bookmarkData": "AQID"
      },
      "cues": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Spot up SR",
          "time": 4.25,
          "colorHex": "#FF6B6B",
          "notes": ""
        }
      ]
    }
    """

    /// v2 moved media per-item but still had no cue point types.
    static let v2 = """
    {
      "schemaVersion": 2,
      "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
      "name": "Show A",
      "items": [
        {
          "id": "AABBCCDD-1111-2222-3333-444455556666",
          "media": {
            "displayName": "act1.wav",
            "kind": "audio",
            "duration": 184.32,
            "bookmarkData": "AQID"
          },
          "cues": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Spot up SR",
              "time": 4.25,
              "colorHex": "#FF6B6B",
              "notes": ""
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "Wash full",
              "time": 12.0,
              "colorHex": "#4ECDC4",
              "notes": ""
            }
          ]
        }
      ],
      "activeItemID": "AABBCCDD-1111-2222-3333-444455556666"
    }
    """

    /// Cues deliberately out of time order, so the vector pins the sort too. The last
    /// two share `time: 15.0` and are listed with the *higher* id first, so the pair
    /// only comes out in `id.uuidString` order if the tie-break in
    /// `assignCueNumbersBySort` is applied — a port that leant on its language's stable
    /// sort instead would hand them the opposite `cueNumber`s.
    static let v3 = """
    {
      "schemaVersion": 3,
      "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
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
              "name": "C",
              "time": 30.0,
              "colorHex": "#FF6B6B",
              "notes": ""
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "name": "A",
              "time": 5.0,
              "colorHex": "#4ECDC4",
              "notes": ""
            },
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "name": "B",
              "time": 15.0,
              "colorHex": "#4ECDC4",
              "notes": ""
            },
            {
              "id": "04444444-4444-4444-4444-444444444444",
              "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "name": "B stacked",
              "time": 15.0,
              "colorHex": "#4ECDC4",
              "notes": ""
            }
          ]
        }
      ],
      "activeItemID": "AABBCCDD-1111-2222-3333-444455556666"
    }
    """

    static let v4 = """
    {
      "schemaVersion": 4,
      "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
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
              "colorHex": "#FF6B6B",
              "notes": ""
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "cueNumber": 2,
              "name": "Cue 2",
              "time": 15.0,
              "colorHex": "#4ECDC4",
              "notes": ""
            }
          ]
        }
      ],
      "activeItemID": "AABBCCDD-1111-2222-3333-444455556666"
    }
    """

    static let v5 = """
    {
      "schemaVersion": 5,
      "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
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
              "colorHex": "#FF6B6B",
              "notes": "",
              "fadeTime": { "fadeIn": 1.5, "fadeOut": 1.5 }
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "cueNumber": 2,
              "name": "Cue 2",
              "time": 15.0,
              "colorHex": "#4ECDC4",
              "notes": "",
              "fadeTime": { "fadeIn": 1.0, "fadeOut": 2.0 }
            }
          ]
        }
      ],
      "activeItemID": "AABBCCDD-1111-2222-3333-444455556666"
    }
    """

}
