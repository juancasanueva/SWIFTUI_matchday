//
//  UserNotificationSender.swift
//  matchday
//
//  `NotificationSender` backed by `UNUserNotificationCenter` (`Notifier.send`
//  in the original). Permission is requested lazily, on the first alert or the
//  Test button. Clicking an alert opens its ESPN match page.
//

import AppKit
import OSLog
import UserNotifications

nonisolated final class UserNotificationSender: NSObject, NotificationSender, UNUserNotificationCenterDelegate,
    @unchecked Sendable {
    /// `userInfo` key holding the match URL.
    static let urlKey = "url"

    private let center: UNUserNotificationCenter
    /// Local PNG of a team crest, when one is cached; attached to the alert.
    private let crestFile: @Sendable (Team) async -> URL?

    init(center: UNUserNotificationCenter = .current(),
         crestFile: @escaping @Sendable (Team) async -> URL? = { _ in nil }) {
        self.center = center
        self.crestFile = crestFile
        super.init()
    }

    /// Becomes the center's delegate so clicks open matches and alerts show while
    /// the panel is in front. Call once at launch.
    func activate() {
        center.delegate = self
    }

    func send(_ notification: MatchNotification) {
        Task { await deliver(notification) }
    }

    private func deliver(_ notification: MatchNotification) async {
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        if let url = notification.url {
            content.userInfo = [Self.urlKey: url.absoluteString]
        }
        if let team = notification.team, let attachment = await attachment(for: team, id: notification.id) {
            content.attachments = [attachment]
        }
        // The same identifier replaces the previous alert (a newer goal of the same match).
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            Logger.notifications.error("Could not show notification: \(error.localizedDescription)")
        }
    }

    /// Asks for permission the first time; afterwards follows the user's choice.
    private func isAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// The system moves attachment files, so the cached crest is copied first.
    private func attachment(for team: Team, id: String) async -> UNNotificationAttachment? {
        guard let source = await crestFile(team) else { return nil }
        let copy = FileManager.default.temporaryDirectory.appending(path: "crest-\(UUID().uuidString).png")
        do {
            try FileManager.default.copyItem(at: source, to: copy)
            return try UNNotificationAttachment(identifier: "crest-\(id)", url: copy)
        } catch {
            return nil
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let text = response.notification.request.content.userInfo[Self.urlKey] as? String,
              let url = Self.openableURL(text)
        else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }

    /// Only web links are opened (`open_url` in the original).
    static func openableURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}
