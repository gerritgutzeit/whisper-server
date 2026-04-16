//
//  MenuBarService.swift
//  WhisperServer
//
//  Manages menu bar UI and user interactions
//

import AppKit
import SwiftUI

/// Service responsible for managing the menu bar interface
final class MenuBarService: ObservableObject {
    // MARK: - Types
    
    private enum MenuItemTags: Int {
        case status = 1000
        case server = 1001
        case download = 1002
        case recentTranscriptions = 1003
    }

    private static let historyTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private let modelManager: ModelManager
    private weak var serverCoordinator: ServerCoordinator?
    private let idleIconName = "waveform"
    private let processingIconName = "waveform.circle.fill"
    private var currentIconName: String?
    private var progressResetWorkItem: DispatchWorkItem?
    private var baseTooltip = "WhisperServer - Ready"
    private var isCurrentlyProcessing = false
    private let progressResetDelay: TimeInterval = 1.0
    private let transcriptionLogWindowController = TranscriptionLogWindowController()
    // MARK: - Initialization
    
    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }
    
    // MARK: - Public Interface
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
#if DEBUG
        print("🔧 DEBUG build detected: Reset menu item enabled.")
#endif
        
        configureStatusButton()
        createMenu()
        setupNotificationObservers()
    }
    
    func setServerCoordinator(_ coordinator: ServerCoordinator) {
        serverCoordinator = coordinator
    }
    
    func updateServerStatus(_ isRunning: Bool, port: Int) {
        guard let menu = statusItem?.menu,
              let serverItem = menu.item(withTag: MenuItemTags.server.rawValue) else { return }
        
        DispatchQueue.main.async {
            if isRunning {
                serverItem.title = "Server: Running on port \(port)"
                serverItem.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
            } else {
                serverItem.title = "Server: Stopped"
                serverItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
            }
        }
    }
    
    func updateMetalStatus(isActive: Bool, modelName: String? = nil, isCaching: Bool = false, failed: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let tooltip: String
            if isCaching {
                tooltip = "WhisperServer - Caching shaders..."
            } else if failed {
                tooltip = "WhisperServer - GPU unavailable (CPU fallback)"
            } else if isActive, let modelName = modelName {
                tooltip = "WhisperServer - Active with \(modelName) model"
            } else {
                tooltip = "WhisperServer - Ready"
            }

            self.baseTooltip = tooltip
            if !self.isCurrentlyProcessing {
                self.updateTooltip(tooltip)
            }
        }
    }
    
    func showModelStatus(_ status: String) {
        guard let menu = statusItem?.menu else { return }
        
        DispatchQueue.main.async {
            let shouldShow = status.lowercased().contains("download") || 
                            status.lowercased().contains("error") || 
                            status.lowercased().contains("preparing")
            
            let statusIndex = menu.items.firstIndex { $0.title.hasPrefix("Model:") } ?? -1
            
            if shouldShow {
                if statusIndex >= 0 {
                    menu.items[statusIndex].title = "Model: \(status)"
                } else {
                    let insertIndex = menu.items.firstIndex { $0.isSeparatorItem } ?? 0
                    let statusItem = NSMenuItem(title: "Model: \(status)", action: nil, keyEquivalent: "")
                    menu.insertItem(statusItem, at: insertIndex)
                }
            } else if statusIndex >= 0 {
                menu.removeItem(at: statusIndex)
            }
        }
    }
    
    func showDownloadProgress(_ progress: Double) {
        guard let menu = statusItem?.menu else { return }

        DispatchQueue.main.async {
            let clampedProgress = max(0.0, min(1.0, progress))
            let progressPercent = Int((clampedProgress * 100).rounded())
            let progressItem = self.ensureDownloadMenuItem(in: menu)
            progressItem.title = "Download: \(progressPercent)%"
            progressItem.isEnabled = false

            if clampedProgress >= 1.0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.hideDownloadProgress()
                }
            }
        }
    }

    func hideDownloadProgress() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let menu = self.statusItem?.menu else { return }
            let index = menu.indexOfItem(withTag: MenuItemTags.download.rawValue)
            if index >= 0 {
                menu.removeItem(at: index)
            }
        }
    }

    func updateTranscriptionProgress(progress: Double, isProcessing: Bool, modelName: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let menu = self.statusItem?.menu else { return }

            self.progressResetWorkItem?.cancel()
            self.progressResetWorkItem = nil

            let clampedProgress = max(0.0, min(1.0, progress))
            let percentValue = Int((clampedProgress * 100).rounded())
            let shouldDisplayProgressItem = isProcessing || clampedProgress > 0.0
            let resolvedModelName = self.resolveModelName(from: modelName)

            if shouldDisplayProgressItem {
                let progressMenuItem = self.ensureProgressMenuItem(in: menu)
                progressMenuItem.title = "\(resolvedModelName): \(percentValue)%"
            } else {
                self.removeProgressMenuItemIfNeeded(in: menu)
            }

            let processingNow = isProcessing || (clampedProgress > 0.0 && clampedProgress < 1.0)
            self.isCurrentlyProcessing = processingNow
            self.applyStatusIcon(isProcessing: processingNow)

            if processingNow {
                self.updateTooltip("WhisperServer - Processing \(resolvedModelName): \(percentValue)%")
            } else {
                self.updateTooltip(self.baseTooltip)
                if shouldDisplayProgressItem {
                    self.scheduleProgressResetIfNeeded(currentPercent: percentValue)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func configureStatusButton() {
        guard let button = statusItem?.button else { return }

        currentIconName = idleIconName
        button.image = NSImage(systemSymbolName: idleIconName, accessibilityDescription: "Whisper Server")
        baseTooltip = "WhisperServer - Initializing..."
        button.toolTip = baseTooltip
    }
    
    private func createMenu() {
        let menu = NSMenu()
        
        // Server status
        let serverItem = NSMenuItem(title: "Server: Waiting for initialization...", action: nil, keyEquivalent: "")
        serverItem.toolTip = "HTTP server will start after initialization is complete"
        serverItem.tag = MenuItemTags.server.rawValue
        menu.addItem(serverItem)

        menu.addItem(NSMenuItem.separator())
        let recentItem = NSMenuItem(title: "Recent Transcriptions", action: nil, keyEquivalent: "")
        recentItem.tag = MenuItemTags.recentTranscriptions.rawValue
        recentItem.toolTip = "Latest completed API transcriptions; click an item to copy full text"
        let recentSubmenu = NSMenu()
        populateRecentTranscriptionsSubmenu(recentSubmenu)
        recentItem.submenu = recentSubmenu
        menu.addItem(recentItem)
        
        // Model selection submenu
        menu.addItem(NSMenuItem.separator())
        createModelSelectionMenu(menu)
        
        // Quit option
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
#if DEBUG
        let resetItem = NSMenuItem(title: "Reset Application Data", action: #selector(resetApplicationData(_:)), keyEquivalent: "")
        resetItem.target = self
        resetItem.toolTip = "Remove all saved preferences and cached models"
        menu.addItem(resetItem)
        print("🔧 Menu items:", menu.items.map { $0.title })
#endif
        
        statusItem?.menu = menu
    }
    
    private func createModelSelectionMenu(_ parentMenu: NSMenu) {
        let modelSelectionMenuItem = NSMenuItem(title: "Select Model", action: nil, keyEquivalent: "")
        let modelSelectionSubmenu = NSMenu()
        populateModelSelectionSubmenu(modelSelectionSubmenu)

        modelSelectionMenuItem.submenu = modelSelectionSubmenu
        parentMenu.addItem(modelSelectionMenuItem)
    }
    
    private func applyStatusIcon(isProcessing: Bool) {
        let desiredIcon = isProcessing ? processingIconName : idleIconName
        guard currentIconName != desiredIcon else { return }

        statusItem?.button?.image = NSImage(systemSymbolName: desiredIcon, accessibilityDescription: "WhisperServer")
        currentIconName = desiredIcon
    }

    private func ensureProgressMenuItem(in menu: NSMenu) -> NSMenuItem {
        if let existingItem = menu.item(withTag: MenuItemTags.status.rawValue) {
            return existingItem
        }

        let progressItem = NSMenuItem(title: "Transcription", action: nil, keyEquivalent: "")
        progressItem.isEnabled = false
        progressItem.toolTip = "Current transcription progress"
        progressItem.tag = MenuItemTags.status.rawValue
        menu.insertItem(progressItem, at: 0)
        return progressItem
    }

    private func ensureDownloadMenuItem(in menu: NSMenu) -> NSMenuItem {
        if let existingItem = menu.item(withTag: MenuItemTags.download.rawValue) {
            return existingItem
        }

        let insertIndex = menu.items.firstIndex { $0.isSeparatorItem } ?? menu.items.count
        let progressItem = NSMenuItem(title: "Download: 0%", action: nil, keyEquivalent: "")
        progressItem.isEnabled = false
        progressItem.toolTip = "Current model download progress"
        progressItem.tag = MenuItemTags.download.rawValue
        menu.insertItem(progressItem, at: insertIndex)
        return progressItem
    }

    private func resolveModelName(from reportedName: String?) -> String {
        if let trimmed = reportedName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }

        if modelManager.selectedProvider == .fluid {
            return FluidTranscriptionService.defaultModel.displayName
        }

        return modelManager.selectedModelName ?? "Selected model"
    }

    private func removeProgressMenuItemIfNeeded(in menu: NSMenu? = nil) {
        guard let menu = menu ?? statusItem?.menu else { return }
        let index = menu.indexOfItem(withTag: MenuItemTags.status.rawValue)
        if index >= 0 {
            menu.removeItem(at: index)
        }
    }

    private func scheduleProgressResetIfNeeded(currentPercent: Int) {
        guard currentPercent != 0 else {
            removeProgressMenuItemIfNeeded()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            self.removeProgressMenuItemIfNeeded()
            self.isCurrentlyProcessing = false
            self.applyStatusIcon(isProcessing: false)
            self.updateTooltip(self.baseTooltip)
            self.progressResetWorkItem = nil
        }

        progressResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + progressResetDelay, execute: workItem)
    }

    private func updateTooltip(_ tooltip: String) {
        statusItem?.button?.toolTip = tooltip
    }
    
    private func populateModelSelectionSubmenu(_ submenu: NSMenu) {
        submenu.removeAllItems()

        #if DEBUG
        print("🔧 populateModelSelectionSubmenu provider:", modelManager.selectedProvider)
        #endif
        let fluidItem = NSMenuItem(title: "FluidAudio (Core ML)", action: #selector(selectFluidProvider), keyEquivalent: "")
        fluidItem.target = self
        fluidItem.state = (modelManager.selectedProvider == .fluid) ? .on : .off
        submenu.addItem(fluidItem)
        submenu.addItem(NSMenuItem.separator())

        if modelManager.availableModels.isEmpty {
            let noModelsItem = NSMenuItem(title: "No models available", action: nil, keyEquivalent: "")
            noModelsItem.isEnabled = false
            submenu.addItem(noModelsItem)
        } else {
            for model in modelManager.availableModels {
                addModelMenuItems(for: model, to: submenu)
            }
        }

        submenu.addItem(NSMenuItem.separator())
        let importItem = NSMenuItem(title: "Import Whisper Model…", action: #selector(importWhisperModel), keyEquivalent: "")
        importItem.target = self
        submenu.addItem(importItem)
    }

    private func addModelMenuItems(for model: Model, to submenu: NSMenu) {
        let modelItem = NSMenuItem(title: model.name, action: #selector(selectModel(_:)), keyEquivalent: "")
        modelItem.target = self
        modelItem.representedObject = model.id
        if modelManager.selectedProvider == .whisper && model.id == modelManager.selectedModelID {
            modelItem.state = .on
        }

        if model.id.hasPrefix("user-") {
            modelItem.toolTip = "Hold Option (⌥) to delete"
        }

        submenu.addItem(modelItem)

        guard model.id.hasPrefix("user-") else { return }

        let deleteTitle = "Delete \(model.name)…"
        let deleteItem = NSMenuItem(title: deleteTitle, action: #selector(confirmDeleteModel(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = model.id
        deleteItem.isAlternate = true
        deleteItem.keyEquivalentModifierMask = [.option]
        deleteItem.toolTip = "Remove this model and its cached files"
        if #available(macOS 11.0, *) {
            deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete model")
        }
        submenu.addItem(deleteItem)
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(refreshModelSelectionMenu), 
            name: .modelManagerDidUpdate, 
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshRecentTranscriptionsMenu),
            name: .transcriptionHistoryDidUpdate,
            object: nil
        )
    }

    private func populateRecentTranscriptionsSubmenu(_ submenu: NSMenu) {
        submenu.removeAllItems()

        let openItem = NSMenuItem(title: "Open Transcription Log…", action: #selector(openTranscriptionLogWindow), keyEquivalent: "")
        openItem.target = self
        openItem.toolTip = "Searchable list and full text in a dedicated window"
        submenu.addItem(openItem)
        submenu.addItem(NSMenuItem.separator())

        let entries = TranscriptionHistoryStore.shared.recentEntries()
        let quickLimit = 8
        if entries.isEmpty {
            let emptyItem = NSMenuItem(title: "No transcriptions yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for entry in entries.prefix(quickLimit) {
                let preview = Self.previewForMenu(from: entry.fullText, maxLength: 40)
                let time = Self.historyTimeFormatter.string(from: entry.date)
                let fileNote = entry.sourceFilename.map { " · \($0)" } ?? ""
                let title = "Copy: \(time)\(fileNote) — \(preview)"
                let item = NSMenuItem(title: title, action: #selector(copyRecentTranscription(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.fullText as NSString
                var tip = entry.fullText
                if tip.count > 800 {
                    tip = String(tip.prefix(800)) + "…"
                }
                item.toolTip = tip
                submenu.addItem(item)
            }
            if entries.count > quickLimit {
                let more = NSMenuItem(
                    title: "… and \(entries.count - quickLimit) older (open log window)",
                    action: nil,
                    keyEquivalent: ""
                )
                more.isEnabled = false
                submenu.addItem(more)
            }
            submenu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear Recent", action: #selector(clearRecentTranscriptions(_:)), keyEquivalent: "")
            clearItem.target = self
            submenu.addItem(clearItem)
        }
    }

    private static func previewForMenu(from text: String, maxLength: Int = 56) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxLength else { return collapsed.isEmpty ? "—" : collapsed }
        let idx = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<idx]) + "…"
    }

    @objc private func refreshRecentTranscriptionsMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let menu = self.statusItem?.menu,
                  let recentItem = menu.item(withTag: MenuItemTags.recentTranscriptions.rawValue),
                  let submenu = recentItem.submenu else { return }
            self.populateRecentTranscriptionsSubmenu(submenu)
        }
    }

    @objc private func copyRecentTranscription(_ sender: NSMenuItem) {
        let raw = sender.representedObject
        let text: String?
        if let s = raw as? String {
            text = s
        } else if let ns = raw as? NSString {
            text = ns as String
        } else {
            text = nil
        }
        guard let body = text, !body.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
    }

    @objc private func clearRecentTranscriptions(_: NSMenuItem) {
        TranscriptionHistoryStore.shared.clear()
    }

    @objc private func openTranscriptionLogWindow() {
        transcriptionLogWindowController.show()
    }
    
    // MARK: - Menu Actions
    
#if DEBUG
    @objc private func resetApplicationData(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Reset Application Data?"
        alert.informativeText = "All downloaded models, cached assets, and saved preferences will be removed. The app will close after the reset."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset & Quit")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        serverCoordinator?.stopServer()
        WhisperTranscriptionService.cleanup()

        do {
            try modelManager.resetAllData()
            
            // Successfully reset, quit the app
            NSApp.terminate(nil)
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Unable to reset data"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .warning
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
            
            // Restart server on error
            serverCoordinator?.startServer()
        }
    }
#endif

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String else { return }
        
        if modelId != modelManager.selectedModelID || modelManager.selectedProvider != .whisper {
            let modelName = modelManager.availableModels.first(where: { $0.id == modelId })?.name ?? "Unknown"
            print("🔄 Changing model to: \(modelName) (id: \(modelId))")
            
            serverCoordinator?.stopServer()
            modelManager.selectModel(id: modelId)
            refreshModelSelectionMenu()
            serverCoordinator?.restartServer()
        }
    }
    
    @objc private func selectFluidProvider() {
        guard modelManager.selectedProvider != .fluid else { return }
        
        print("🔄 Switching engine to FluidAudio")
        serverCoordinator?.stopServer()
        modelManager.selectProvider(.fluid)
        refreshModelSelectionMenu()
        serverCoordinator?.restartServer()
    }
    
    @objc private func refreshModelSelectionMenu() {
        guard let menu = statusItem?.menu else { return }
        
        for item in menu.items {
            guard item.title == "Select Model", let submenu = item.submenu else { continue }
            populateModelSelectionSubmenu(submenu)
            break
        }
    }

    @objc private func importWhisperModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedFileTypes = ["bin", "zip", "mlmodelc"]
        panel.treatsFilePackagesAsDirectories = false
        panel.title = "Import Whisper Model"
        panel.message = "Select a Whisper .bin model file and optionally its .mlmodelc bundle."

        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        guard response == .OK else { return }

        let urls = panel.urls
        guard !urls.isEmpty else { return }

        guard urls.contains(where: { $0.pathExtension.lowercased() == "bin" }) else {
            let alert = NSAlert()
            alert.messageText = "Whisper model import failed"
            alert.informativeText = "Please select at least one .bin model file."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        serverCoordinator?.stopServer()
        defer { serverCoordinator?.restartServer() }

        do {
            let model = try modelManager.importUserModel(from: urls)
            print("📥 Imported user model: \(model.name) [\(model.id)]")
            refreshModelSelectionMenu()
        } catch {
            print("❌ Failed to import model: \(error.localizedDescription)")
        }
    }
    
    @objc private func confirmDeleteModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String,
              let model = modelManager.availableModels.first(where: { $0.id == modelId }) else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \"\(model.name)\"?"
        alert.informativeText = "This removes the model and its associated Core ML bundles."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        serverCoordinator?.stopServer()
        defer { serverCoordinator?.restartServer() }

        do {
            try modelManager.deleteUserModel(id: modelId)
            refreshModelSelectionMenu()
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Unable to delete model"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .warning
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(self)
    }

}
