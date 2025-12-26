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

    // MARK: - Category Tests

    @Test("Battery chemistry presets include only chemistry types")
    func batteryChemistryPresetsIncludeOnlyChemistryTypes() {
        let presets = OCVPreset.batteryChemistryPresets

        #expect(presets.contains(.liIon))
        #expect(presets.contains(.liFePO4))
        #expect(presets.contains(.leadAcid))
        #expect(presets.contains(.alkaline))
        #expect(presets.contains(.niMH))
        #expect(presets.contains(.lto))
        #expect(presets.count == 6)
    }

    @Test("Battery chemistry presets exclude device-specific presets")
    func batteryChemistryPresetsExcludeDeviceSpecific() {
        let presets = OCVPreset.batteryChemistryPresets

        #expect(!presets.contains(.trackerT1000E))
        #expect(!presets.contains(.heltecPocket5000))
        #expect(!presets.contains(.custom))
    }

    @Test("Li-Ion is battery chemistry category")
    func liIonIsBatteryChemistry() {
        #expect(OCVPreset.liIon.category == .batteryChemistry)
    }

    @Test("Tracker T1000-E is device specific category")
    func trackerIsDeviceSpecific() {
        #expect(OCVPreset.trackerT1000E.category == .deviceSpecific)
    }

    @Test("Custom is device specific category")
    func customIsDeviceSpecific() {
        #expect(OCVPreset.custom.category == .deviceSpecific)
    }
}
