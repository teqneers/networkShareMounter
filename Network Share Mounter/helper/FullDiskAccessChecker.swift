//
//  FullDiskAccessChecker.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 18.05.26.
//  Copyright © 2026 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import AppKit
import Foundation
import OSLog

struct FullDiskAccessChecker {

    // MARK: - Access Check

    /// Returns `true` if the app currently has Full Disk Access.
    ///
    /// Uses `FileHandle` (open syscall) rather than `isReadableFile` (access syscall) because
    /// tccd only intercepts `open()` — this registers the app in the FDA list on first denial.
    static func hasAccess() -> Bool {
        let handle = FileHandle(forReadingAtPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        defer { handle?.closeFile() }
        return handle != nil
    }

    // MARK: - Prompt

    /// Shows a Full Disk Access prompt when required.
    ///
    /// Only shown on macOS 26+, only when the mount path is outside `/Volumes`, and only when FDA
    /// is not already granted. Attempting to read `TCC.db` also registers the app in the FDA
    /// candidate list so the user can enable the toggle in System Settings with a single click.
    ///
    /// - Parameters:
    /// The alert is not modal: `runModal()` would block the main actor, and with it the mounting
    /// of all shares, until the user closes the alert.
    ///
    /// - Parameters:
    ///   - mountPath: The configured default mount path.
    ///   - onOpenSettings: Called when the user chooses to open System Settings.
    @MainActor
    static func promptIfNeeded(
        forMountPath mountPath: String,
        onOpenSettings: @escaping () -> Void
    ) {
        guard #available(macOS 26, *) else { return }
        guard !mountPath.hasPrefix("/Volumes") else { return }
        guard !hasAccess() else { return }
        guard openAlert == nil else { return }

        Logger.app.warning("⚠️ Full Disk Access not granted; mount path is: \(mountPath, privacy: .public)")

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString(
            "Full Disk Access Required",
            comment: "FDA alert title"
        )
        alert.informativeText = NSLocalizedString(
            "Network Share Mounter needs Full Disk Access to mount network shares.\n\nEnable the toggle next to \u{201C}Network Share Mounter\u{201D} in the settings panel that opens. You may be asked for your password or Touch ID.",
            comment: "FDA alert body"
        )
        let button = alert.addButton(withTitle: NSLocalizedString("Open System Settings\u{2026}", comment: "FDA: open settings button"))

        let handler = AlertButtonHandler {
            alert.window.orderOut(nil)
            openAlert = nil
            openAlertHandler = nil
            onOpenSettings()
        }
        button.target = handler
        button.action = #selector(AlertButtonHandler.buttonClicked(_:))
        openAlert = alert
        openAlertHandler = handler

        alert.layout()
        alert.window.level = .floating
        alert.window.center()
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Non-modal alert

    /// The alert that is currently shown and its button handler, kept alive until the button is clicked
    @MainActor private static var openAlert: NSAlert?
    @MainActor private static var openAlertHandler: AlertButtonHandler?

    /// Target for the alert button, which calls the given closure
    private final class AlertButtonHandler: NSObject {
        private let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func buttonClicked(_ sender: Any?) {
            action()
        }
    }
}
