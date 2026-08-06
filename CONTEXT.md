# OnlyCue domain glossary

Single-context domain glossary (see `docs/agents/domain.md`). Created for the
zh-Hant localization work (spec:
`docs/superpowers/specs/2026-08-06-zh-hant-localization-design.md`); extend it as
other terms get resolved.

## Localization: translate vs. keep English

OnlyCue localizes into 繁體中文 (zh-Hant) with a **hybrid** policy — matching how
Taiwanese lighting designers actually talk, where entrenched console/industry
jargon stays in English.

**Rules:**

1. **Translate** general UI: verbs and nouns a non-technical macOS user would
   expect in their language — Save, Import, Cancel, Delete, Settings, "Are you
   sure?", empty-state prose, error messages, tooltips describing an action.
2. **Keep English** the terms in the keep-English list below. Do not invent
   Chinese for them; they read as wrong to the professionals who use them.
3. When a kept term appears inside a translated sentence, leave the term in
   English and translate around it (e.g. 「將 Cue 送到 grandMA2」).
4. **Never localize technical formats**: timecode (`HH:MM:SS:FF`, `HH:MM:SS;FF`
   drop-frame), raw numbers, BPM digits, note/OSC addresses, hex, file paths.

The keep-English list is the source of truth for where the line falls. When a new
string forces a judgement call, resolve it here first, then translate.

### Keep-English terms

Console / show-control jargon that stays in English in every language:

- **Cue**, **Cue list**, **Cue number**
- **Executor**, **Sequence**, **Page** (in the `page.exec` sense)
- **Timecode**, **LTC** (linear timecode), **SMPTE**, **drop-frame** / **DF**
- **MA2**, **grandMA2**, **MA**
- **MIDI** (and **MTC**, **MSC**, note/CC/program-change names)
- **OSC**
- **Fixture**
- **GO** (and transport verbs shown as console labels)
- **Blackout**
- **BPM**, **beat grid**, **downbeat**
- **Waveform**
- **DMX** (if surfaced)

Product / proper nouns that stay as-is: **OnlyCue**, **Finder**, macOS.

## Notes

- The English source strings live in `OnlyCue/Resources/Localizable.xcstrings`
  (the String Catalog). Xcode extracts `Text("…")` and `String(localized:)` keys
  on build; `LocalizationCompletenessTests` guards catalog integrity.
