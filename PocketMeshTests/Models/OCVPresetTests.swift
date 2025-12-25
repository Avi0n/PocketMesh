import Testing
@testable import PocketMeshServices

@Suite("OCVPreset Tests")
struct OCVPresetTests {

    @Test("All presets have exactly 11 values")
    func presetsHaveCorrectLength() {
        for preset in OCVPreset.allCases where preset != .custom {
            #expect(preset.ocvArray.count == 11, "Preset \(preset) should have 11 values")
        }
    }

    @Test("All preset arrays are descending")
    func presetsAreDescending() {
        for preset in OCVPreset.allCases where preset != .custom {
            let array = preset.ocvArray
            for i in 0..<(array.count - 1) {
                #expect(array[i] > array[i + 1], "Preset \(preset) should be descending at index \(i)")
            }
        }
    }

    @Test("All presets have display names")
    func presetsHaveDisplayNames() {
        for preset in OCVPreset.allCases {
            #expect(!preset.displayName.isEmpty, "Preset \(preset) should have a display name")
        }
    }

    @Test("Selectable presets excludes custom")
    func selectablePresetsExcludesCustom() {
        #expect(!OCVPreset.selectablePresets.contains(.custom))
        #expect(OCVPreset.selectablePresets.count == OCVPreset.allCases.count - 1)
    }

    @Test("Li-Ion preset has expected values")
    func liIonPresetValues() {
        let expected = [4190, 4050, 3990, 3890, 3800, 3720, 3630, 3530, 3420, 3300, 3100]
        #expect(OCVPreset.liIon.ocvArray == expected)
    }

    @Test("WisMesh Tag preset has expected values")
    func wisMeshTagPresetValues() {
        let expected = [4240, 4112, 4029, 3970, 3906, 3846, 3824, 3802, 3776, 3650, 3072]
        #expect(OCVPreset.wisMeshTag.ocvArray == expected)
    }
}
