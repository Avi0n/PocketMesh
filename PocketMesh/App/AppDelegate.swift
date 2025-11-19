import UIKit
import UserNotifications
import OSLog
import PocketMeshKit  // Add this import
import SwiftData      // Add this import

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "AppDelegate")

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // Add coordinator reference
    weak var appCoordinator: AppCoordinator?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        logger.info("App did finish launching")

        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Configure notification categories
        configureNotificationCategories()

        return true
    }

    private func configureNotificationCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a message..."
        )

        let messageCategory = UNNotificationCategory(
            identifier: "MESSAGE",
            actions: [replyAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([messageCategory])
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        logger.info("Notification action: \(response.actionIdentifier)")

        if response.actionIdentifier == "REPLY",
           let textResponse = response as? UNTextInputNotificationResponse {
            let messageText = textResponse.userText
            logger.info("User replied: \(messageText)")

            // Extract contact info from notification
            let userInfo = response.notification.request.content.userInfo

            guard let publicKeyBase64 = userInfo["contactPublicKey"] as? String,
                  let contactPublicKey = Data(base64Encoded: publicKeyBase64),
                  let contactName = userInfo["contactName"] as? String else {
                logger.error("Missing contact info in notification userInfo")
                completionHandler()
                return
            }

            // Call completion handler immediately, then send reply on main actor
            completionHandler()

            Task { @MainActor in
                await self.sendReplyMessage(
                    text: messageText,
                    contactPublicKey: contactPublicKey,
                    contactName: contactName
                )
            }
        } else {
            completionHandler()
        }
    }

    @MainActor
    private func sendReplyMessage(text: String, contactPublicKey: Data, contactName: String) async {
        logger.info("Attempting to send reply message to \(contactName)")

        // Verify AppCoordinator is available
        guard let coordinator = appCoordinator else {
            logger.error("AppCoordinator not available - cannot send reply")
            return
        }

        // Verify services are initialized
        guard let messageService = coordinator.messageService,
              let device = coordinator.connectedDevice else {
            logger.error("MessageService or device not available - app may not be fully initialized")
            return
        }

        // Look up contact by public key
        let modelContext = PersistenceController.shared.container.mainContext

        do {
            let descriptor = FetchDescriptor<Contact>(
                predicate: #Predicate { contact in
                    contact.publicKey == contactPublicKey
                }
            )

            guard let contact = try modelContext.fetch(descriptor).first else {
                logger.error("Contact not found with public key")
                return
            }

            // Send the reply message
            try await messageService.sendMessage(text: text, to: contact, device: device)
            logger.info("Reply message sent successfully")

        } catch {
            logger.error("Failed to send reply message: \(error.localizedDescription)")
        }
    }
}
