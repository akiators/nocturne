import Foundation

/// Встроенные пресеты 10-полосного эквалайзера (31 Гц … 16 кГц).
/// Кастомные пресеты и per-track пресеты хранятся в LibraryStore — бесплатны,
/// в отличие от Mimose Plus, где пресеты и per-track EQ продаются.
enum BuiltInEQPresets {
    static let flat = EQPreset(id: "builtin_flat", name: "Ровный",
                               gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], trackKey: nil)
    static let bassBoost = EQPreset(id: "builtin_bass", name: "Басы",
                                    gains: [6, 5, 3.5, 1.5, 0, 0, 0, 0, 0, 0], trackKey: nil)
    static let vocal = EQPreset(id: "builtin_vocal", name: "Вокал",
                                gains: [-2, -1, 0, 2.5, 4, 4, 2.5, 1, 0, -1], trackKey: nil)
    static let rock = EQPreset(id: "builtin_rock", name: "Рок",
                               gains: [4.5, 3.5, 1.5, -1, -1.5, 0, 2.5, 4, 4.5, 3.5], trackKey: nil)
    static let electronic = EQPreset(id: "builtin_edm", name: "Электроника",
                                     gains: [5.5, 4.5, 1.5, 0, -1.5, 1.5, 0.5, 2.5, 5, 5.5], trackKey: nil)
    static let jazz = EQPreset(id: "builtin_jazz", name: "Джаз",
                               gains: [3.5, 2.5, 1, 1.5, 2, 2.5, 1.5, 1.5, 2.5, 2], trackKey: nil)
    static let classical = EQPreset(id: "builtin_classic", name: "Классика",
                                    gains: [3, 2.5, 2, 1, -0.5, -0.5, 1, 2.5, 3, 3.5], trackKey: nil)
    static let nightMode = EQPreset(id: "builtin_night", name: "Ночной",
                                    gains: [-3, -2.5, 0, 2, 3, 3, 2, 1.5, 0, -2], trackKey: nil)

    static var all: [EQPreset] {
        [flat, bassBoost, vocal, rock, electronic, jazz, classical, nightMode]
    }
}
