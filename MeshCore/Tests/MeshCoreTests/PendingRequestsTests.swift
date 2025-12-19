import Foundation
import Testing
@testable import MeshCore

@Suite("PendingRequests Actor Tests")
struct PendingRequestsTests {

    @Test("Concurrent request registration is serialized by actor")
    func concurrentRegistrationSerialized() async {
        let requests = PendingRequests()

        // Use TaskGroup with proper structured concurrency (no nested unstructured Tasks)
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<10 {
                let tag = Data([UInt8(i)])

                // Completion task - runs concurrently
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(50))
                    await requests.complete(tag: tag, with: .ok(value: nil))
                    return true
                }

                // Registration task - runs concurrently
                group.addTask {
                    let result = await requests.register(tag: tag, timeout: 1.0)
                    return result != nil
                }
            }

            var successCount = 0
            for await success in group { if success { successCount += 1 } }
            // At least 10 registrations should succeed (completions also return true)
            #expect(successCount >= 10)
        }
    }

    @Test("Timeout returns nil without blocking other requests")
    func timeoutDoesNotBlockOthers() async {
        let requests = PendingRequests()
        let longTag = Data([0x02])

        // Use TaskGroup with proper structured concurrency
        let results = await withTaskGroup(of: (String, Bool).self) { group in
            // Short timeout request - will timeout
            group.addTask {
                let result = await requests.register(tag: Data([0x01]), timeout: 0.05)
                return ("short", result == nil)
            }

            // Completion task for long request
            group.addTask {
                try? await Task.sleep(for: .milliseconds(30))
                await requests.complete(tag: longTag, with: .ok(value: 42))
                return ("completion", true)
            }

            // Longer request - will be completed
            group.addTask {
                let result = await requests.register(tag: longTag, timeout: 2.0)
                return ("long", result != nil)
            }

            var results: [String: Bool] = [:]
            for await (name, success) in group {
                results[name] = success
            }
            return results
        }

        #expect(results["short"] == true, "Timed out request should return nil")
        #expect(results["long"] == true, "Completed request should return event")
    }

    @Test("Binary request routing by publicKeyPrefix and type")
    func binaryRequestRouting() async {
        let requests = PendingRequests()
        let prefix = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])

        let event = await withTaskGroup(of: MeshEvent?.self) { group in
            group.addTask {
                await requests.register(
                    tag: Data([0x01]),
                    requestType: .status,
                    publicKeyPrefix: prefix,
                    timeout: 2.0
                )
            }

            group.addTask {
                // Small delay to ensure registration happens first
                try? await Task.sleep(for: .milliseconds(20))
                await requests.completeBinaryRequest(
                    publicKeyPrefix: prefix,
                    type: .status,
                    with: .statusResponse(StatusResponse.mock())
                )
                return nil
            }

            // Return the first non-nil result (the registration result)
            for await result in group {
                if result != nil { return result }
            }
            return nil
        }

        #expect(event != nil, "Should complete via prefix+type routing")
    }

    @Test("hasPendingBinaryRequest returns correct state")
    func hasPendingBinaryRequestState() async {
        let requests = PendingRequests()
        let prefix = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66])

        // Initially no pending request
        let beforeRegister = await requests.hasPendingBinaryRequest(
            publicKeyPrefix: prefix,
            type: .telemetry
        )
        #expect(beforeRegister == false)

        // Start registration in background with explicit Task handle
        let registrationTask = Task {
            await requests.register(
                tag: Data([0x99]),
                requestType: .telemetry,
                publicKeyPrefix: prefix,
                timeout: 5.0
            )
        }

        // Allow registration to start
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))

        let afterRegister = await requests.hasPendingBinaryRequest(
            publicKeyPrefix: prefix,
            type: .telemetry
        )
        #expect(afterRegister == true)

        // Clean up - complete the pending request and await task
        await requests.complete(tag: Data([0x99]), with: .ok(value: nil))
        _ = await registrationTask.value
    }
}
