import Testing
@testable import PocketMeshServices

@Suite("DevicePlatform Detection Tests")
struct DevicePlatformTests {

    // MARK: - ESP32 Devices

    @Test("Heltec V2 detected as ESP32")
    func heltecV2() {
        #expect(DevicePlatform.detect(from: "Heltec V2") == .esp32)
    }

    @Test("Heltec V3 detected as ESP32")
    func heltecV3() {
        #expect(DevicePlatform.detect(from: "Heltec V3") == .esp32)
    }

    @Test("Heltec V4 detected as ESP32")
    func heltecV4() {
        #expect(DevicePlatform.detect(from: "Heltec V4") == .esp32)
    }

    @Test("Heltec Tracker detected as ESP32",
          .bug("https://github.com/pocketmesh/pocketmesh/issues/0",
               "Was wrongly matched as nRF52 by 'Tracker' substring"))
    func heltecTracker() {
        #expect(DevicePlatform.detect(from: "Heltec Tracker") == .esp32)
    }

    @Test("Heltec E290 detected as ESP32")
    func heltecE290() {
        #expect(DevicePlatform.detect(from: "Heltec E290") == .esp32)
    }

    @Test("Heltec E213 detected as ESP32")
    func heltecE213() {
        #expect(DevicePlatform.detect(from: "Heltec E213") == .esp32)
    }

    @Test("Heltec T190 detected as ESP32")
    func heltecT190() {
        #expect(DevicePlatform.detect(from: "Heltec T190") == .esp32)
    }

    @Test("Heltec CT62 detected as ESP32")
    func heltecCT62() {
        #expect(DevicePlatform.detect(from: "Heltec CT62") == .esp32)
    }

    @Test("T-Beam detected as ESP32")
    func tBeam() {
        #expect(DevicePlatform.detect(from: "T-Beam") == .esp32)
    }

    @Test("T-Deck detected as ESP32")
    func tDeck() {
        #expect(DevicePlatform.detect(from: "T-Deck") == .esp32)
    }

    @Test("T-LoRa detected as ESP32")
    func tLora() {
        #expect(DevicePlatform.detect(from: "T-LoRa") == .esp32)
    }

    @Test("TLora detected as ESP32")
    func tLoraAlt() {
        #expect(DevicePlatform.detect(from: "TLora") == .esp32)
    }

    @Test("Xiao S3 WIO detected as ESP32",
          .bug("https://github.com/pocketmesh/pocketmesh/issues/0",
               "Was wrongly matched as nRF52 by 'Seeed' vendor prefix"))
    func xiaoS3WIO() {
        #expect(DevicePlatform.detect(from: "Xiao S3 WIO") == .esp32)
    }

    @Test("Xiao C3 detected as ESP32",
          .bug("https://github.com/pocketmesh/pocketmesh/issues/0",
               "Was wrongly matched as nRF52 by 'Seeed' vendor prefix"))
    func xiaoC3() {
        #expect(DevicePlatform.detect(from: "Xiao C3") == .esp32)
    }

    @Test("Xiao C6 detected as ESP32",
          .bug("https://github.com/pocketmesh/pocketmesh/issues/0",
               "Was wrongly matched as nRF52 by 'Seeed' vendor prefix"))
    func xiaoC6() {
        #expect(DevicePlatform.detect(from: "Xiao C6") == .esp32)
    }

    @Test("RAK 3112 detected as ESP32",
          .bug("https://github.com/pocketmesh/pocketmesh/issues/0",
               "Was wrongly matched as nRF52 by 'RAK' vendor prefix"))
    func rak3112() {
        #expect(DevicePlatform.detect(from: "RAK 3112") == .esp32)
    }

    @Test("Station G2 detected as ESP32")
    func stationG2() {
        #expect(DevicePlatform.detect(from: "Station G2") == .esp32)
    }

    @Test("Meshadventurer detected as ESP32")
    func meshadventurer() {
        #expect(DevicePlatform.detect(from: "Meshadventurer") == .esp32)
    }

    @Test("Generic ESP32 detected as ESP32")
    func genericESP32() {
        #expect(DevicePlatform.detect(from: "Generic ESP32") == .esp32)
    }

    @Test("ThinkNode M2 detected as ESP32",
          .bug("https://github.com/pocketmesh/pocketmesh/issues/0",
               "Was wrongly matched as nRF52 by 'Seeed' or other vendor prefix"))
    func thinkNodeM2() {
        #expect(DevicePlatform.detect(from: "ThinkNode M2") == .esp32)
    }

    // MARK: - nRF52 Devices

    @Test("MeshPocket detected as nRF52")
    func meshPocket() {
        #expect(DevicePlatform.detect(from: "MeshPocket") == .nrf52)
    }

    @Test("Mesh Pocket (with space) detected as nRF52")
    func meshPocketSpace() {
        #expect(DevicePlatform.detect(from: "Mesh Pocket") == .nrf52)
    }

    @Test("T114 detected as nRF52")
    func t114() {
        #expect(DevicePlatform.detect(from: "T114") == .nrf52)
    }

    @Test("Mesh Solar detected as nRF52")
    func meshSolar() {
        #expect(DevicePlatform.detect(from: "Mesh Solar") == .nrf52)
    }

    @Test("Xiao-nrf52 detected as nRF52")
    func xiaoNrf52Dash() {
        #expect(DevicePlatform.detect(from: "Xiao-nrf52") == .nrf52)
    }

    @Test("Xiao_nrf52 detected as nRF52")
    func xiaoNrf52Underscore() {
        #expect(DevicePlatform.detect(from: "Xiao_nrf52") == .nrf52)
    }

    @Test("WM1110 detected as nRF52")
    func wm1110() {
        #expect(DevicePlatform.detect(from: "WM1110") == .nrf52)
    }

    @Test("Wio Tracker detected as nRF52")
    func wioTracker() {
        #expect(DevicePlatform.detect(from: "Wio Tracker") == .nrf52)
    }

    @Test("T1000-E detected as nRF52")
    func t1000E() {
        #expect(DevicePlatform.detect(from: "T1000-E") == .nrf52)
    }

    @Test("SenseCap Solar detected as nRF52")
    func senseCapSolar() {
        #expect(DevicePlatform.detect(from: "SenseCap Solar") == .nrf52)
    }

    @Test("WisMesh Tag detected as nRF52")
    func wisMeshTag() {
        #expect(DevicePlatform.detect(from: "WisMesh Tag") == .nrf52)
    }

    @Test("RAK 4631 detected as nRF52")
    func rak4631() {
        #expect(DevicePlatform.detect(from: "RAK 4631") == .nrf52)
    }

    @Test("RAK 3401 detected as nRF52")
    func rak3401() {
        #expect(DevicePlatform.detect(from: "RAK 3401") == .nrf52)
    }

    @Test("T-Echo detected as nRF52")
    func tEcho() {
        #expect(DevicePlatform.detect(from: "T-Echo") == .nrf52)
    }

    @Test("ThinkNode-M1 detected as nRF52")
    func thinkNodeM1() {
        #expect(DevicePlatform.detect(from: "ThinkNode-M1") == .nrf52)
    }

    @Test("ThinkNode M3 detected as nRF52")
    func thinkNodeM3() {
        #expect(DevicePlatform.detect(from: "ThinkNode M3") == .nrf52)
    }

    @Test("ThinkNode-M6 detected as nRF52")
    func thinkNodeM6() {
        #expect(DevicePlatform.detect(from: "ThinkNode-M6") == .nrf52)
    }

    @Test("Ikoka detected as nRF52")
    func ikoka() {
        #expect(DevicePlatform.detect(from: "Ikoka") == .nrf52)
    }

    @Test("ProMicro detected as nRF52")
    func proMicro() {
        #expect(DevicePlatform.detect(from: "ProMicro") == .nrf52)
    }

    @Test("Minewsemi detected as nRF52")
    func minewsemi() {
        #expect(DevicePlatform.detect(from: "Minewsemi") == .nrf52)
    }

    @Test("Meshtiny detected as nRF52")
    func meshtiny() {
        #expect(DevicePlatform.detect(from: "Meshtiny") == .nrf52)
    }

    @Test("Keepteen detected as nRF52")
    func keepteen() {
        #expect(DevicePlatform.detect(from: "Keepteen") == .nrf52)
    }

    @Test("Nano G2 Ultra detected as nRF52")
    func nanoG2Ultra() {
        #expect(DevicePlatform.detect(from: "Nano G2 Ultra") == .nrf52)
    }

    // MARK: - Regression: Vendor prefix no longer causes wrong match

    @Test("Bare 'Heltec' vendor name is unknown (not assumed ESP32)",
          .bug("https://github.com/pocketmesh/pocketmesh/issues/0",
               "Old code matched 'Heltec' prefix as ESP32, but Heltec ships nRF52 devices too"))
    func bareHeltecUnknown() {
        #expect(DevicePlatform.detect(from: "Heltec") == .unknown)
    }

    // MARK: - Edge Cases

    @Test("Empty model string returns unknown")
    func emptyString() {
        #expect(DevicePlatform.detect(from: "") == .unknown)
    }

    @Test("Unrecognized device returns unknown")
    func unrecognizedDevice() {
        #expect(DevicePlatform.detect(from: "SomeNewDevice XYZ") == .unknown)
    }

    // MARK: - Pacing Values

    @Test("ESP32 pacing is 60ms")
    func esp32Pacing() {
        #expect(DevicePlatform.esp32.recommendedWritePacing == 0.060)
    }

    @Test("nRF52 pacing is 25ms")
    func nrf52Pacing() {
        #expect(DevicePlatform.nrf52.recommendedWritePacing == 0.025)
    }

    @Test("Unknown pacing is 60ms (conservative default)")
    func unknownPacing() {
        #expect(DevicePlatform.unknown.recommendedWritePacing == 0.060)
    }
}
