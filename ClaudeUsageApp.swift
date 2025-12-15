import Cocoa
import Security
import SwiftUI

// MARK: - Metric Type Enum

enum MetricType: String, CaseIterable {
    case fiveHour = "5-hour Limit"
    case sevenDay = "7-day Limit (All Models)"
    case sevenDaySonnet = "7-day Limit (Sonnet)"

    var displayName: String { rawValue }
}

// MARK: - Display Style Enums

enum NumberDisplayStyle: String, CaseIterable {
    case none = "None"
    case percentage = "Percentage (42%)"
    case threshold = "Threshold (42|85)"

    var displayName: String { rawValue }
}

enum ProgressIconStyle: String, CaseIterable {
    case none = "None"
    case circle = "Circle (◕)"
    case braille = "Braille (⣇)"
    case barAscii = "Bar [===  ]"
    case barBlocks = "Bar ▓▓░░░"
    case barSquares = "Bar ■■□□□"
    case barCircles = "Bar ●●○○○"
    case barLines = "Bar ━━───"

    var displayName: String { rawValue }
}

// MARK: - Login Item Manager

class LoginItemManager {
    static let shared = LoginItemManager()
    private let appPath = "/Applications/ClaudeUsage.app"

    var isLoginItemEnabled: Bool {
        let script = """
            tell application "System Events"
                get the name of every login item
            end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if let items = result.coerce(toDescriptorType: typeAEList) {
            for i in 1...items.numberOfItems {
                if let item = items.atIndex(i)?.stringValue, item == "ClaudeUsage" {
                    return true
                }
            }
        }
        return false
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        if enabled {
            addLoginItem()
        } else {
            removeLoginItem()
        }
    }

    private func addLoginItem() {
        let script = """
            tell application "System Events"
                make login item at end with properties {path:"\(appPath)", hidden:false}
            end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    private func removeLoginItem() {
        let script = """
            tell application "System Events"
                delete login item "ClaudeUsage"
            end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}

// MARK: - Preferences Manager

class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    private let metricTypeKey = "selectedMetricType"
    private let numberDisplayStyleKey = "numberDisplayStyle"
    private let progressIconStyleKey = "progressIconStyle"
    private let showStatusEmojiKey = "showStatusEmoji"

    private static let keychainService = "com.claude.usage"
    private static let sessionKeyAccount = "sessionKey"
    private static let organizationIdAccount = "organizationId"

    var sessionKey: String? {
        get { Self.readKeychain(account: Self.sessionKeyAccount) }
        set {
            if let value = newValue {
                Self.writeKeychain(account: Self.sessionKeyAccount, value: value)
            } else {
                Self.deleteKeychain(account: Self.sessionKeyAccount)
            }
            // Clean up legacy UserDefaults storage
            defaults.removeObject(forKey: "claudeSessionKey")
        }
    }

    var organizationId: String? {
        get { Self.readKeychain(account: Self.organizationIdAccount) }
        set {
            if let value = newValue {
                Self.writeKeychain(account: Self.organizationIdAccount, value: value)
            } else {
                Self.deleteKeychain(account: Self.organizationIdAccount)
            }
            // Clean up legacy UserDefaults storage
            defaults.removeObject(forKey: "claudeOrganizationId")
        }
    }

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(account: String, value: String) {
        deleteKeychain(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: value.data(using: .utf8)!
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    func migrateFromUserDefaults() {
        if let key = defaults.string(forKey: "claudeSessionKey"), readKeychain(account: Self.sessionKeyAccount) == nil {
            Self.writeKeychain(account: Self.sessionKeyAccount, value: key)
            defaults.removeObject(forKey: "claudeSessionKey")
        }
        if let orgId = defaults.string(forKey: "claudeOrganizationId"), readKeychain(account: Self.organizationIdAccount) == nil {
            Self.writeKeychain(account: Self.organizationIdAccount, value: orgId)
            defaults.removeObject(forKey: "claudeOrganizationId")
        }
    }

    private func readKeychain(account: String) -> String? {
        Self.readKeychain(account: account)
    }

    var selectedMetric: MetricType {
        get {
            if let rawValue = defaults.string(forKey: metricTypeKey),
               let metric = MetricType(rawValue: rawValue) {
                return metric
            }
            return .sevenDay
        }
        set {
            defaults.set(newValue.rawValue, forKey: metricTypeKey)
        }
    }

    var numberDisplayStyle: NumberDisplayStyle {
        get {
            if let rawValue = defaults.string(forKey: numberDisplayStyleKey),
               let style = NumberDisplayStyle(rawValue: rawValue) {
                return style
            }
            return .percentage // default to showing percentage
        }
        set {
            defaults.set(newValue.rawValue, forKey: numberDisplayStyleKey)
        }
    }

    var progressIconStyle: ProgressIconStyle {
        get {
            if let rawValue = defaults.string(forKey: progressIconStyleKey),
               let style = ProgressIconStyle(rawValue: rawValue) {
                return style
            }
            return .none
        }
        set {
            defaults.set(newValue.rawValue, forKey: progressIconStyleKey)
        }
    }

    var showStatusEmoji: Bool {
        get {
            if defaults.object(forKey: showStatusEmojiKey) == nil {
                return true // default to showing emoji
            }
            return defaults.bool(forKey: showStatusEmojiKey)
        }
        set {
            defaults.set(newValue, forKey: showStatusEmojiKey)
        }
    }
}

// MARK: - Pasteable Text Fields

struct PasteableTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PasteableTextField
        init(_ parent: PasteableTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }
    }
}

struct PasteableSecureField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PasteableSecureField
        init(_ parent: PasteableSecureField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }
    }
}

// MARK: - Settings Window Controller

class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()

        self.init(window: window)

        let settingsView = SettingsView { [weak self] in
            self?.close()
        }
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView
    }
}

struct SettingsView: View {
    let onClose: () -> Void

    @State private var selectedTab = 0
    @State private var sessionKey: String = Preferences.shared.sessionKey ?? ""
    @State private var organizationId: String = Preferences.shared.organizationId ?? ""
    @State private var selectedMetric: MetricType = Preferences.shared.selectedMetric
    @State private var numberDisplayStyle: NumberDisplayStyle = Preferences.shared.numberDisplayStyle
    @State private var progressIconStyle: ProgressIconStyle = Preferences.shared.progressIconStyle
    @State private var showStatusEmoji: Bool = Preferences.shared.showStatusEmoji
    @State private var launchAtLogin: Bool = LoginItemManager.shared.isLoginItemEnabled
    @State private var logText: String = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            settingsTab
                .tabItem { Text("Settings") }
                .tag(0)
            logTab
                .tabItem { Text("Log") }
                .tag(1)
        }
        .frame(width: 520, height: 580)
    }

    var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Claude Usage Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Key:")
                        .font(.headline)

                    PasteableSecureField(placeholder: "Enter your Claude session key", text: $sessionKey)
                        .frame(height: 22)

                    Text("Find this in your browser's cookies at claude.ai")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Organization ID:")
                        .font(.headline)

                    PasteableTextField(placeholder: "Enter your organization ID", text: $organizationId)
                        .frame(height: 22)

                    Text("Find this in any claude.ai API request URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Metric:")
                        .font(.headline)

                    Picker("", selection: $selectedMetric) {
                        ForEach(MetricType.allCases, id: \.self) { metric in
                            Text(metric.displayName).tag(metric)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Menu Bar Display")
                        .font(.headline)

                    HStack(alignment: .top, spacing: 30) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Number:")
                                .font(.subheadline)
                            Picker("", selection: $numberDisplayStyle) {
                                ForEach(NumberDisplayStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Progress Icon:")
                                .font(.subheadline)
                            Picker("", selection: $progressIconStyle) {
                                ForEach(ProgressIconStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        }
                    }

                    Toggle("Show Status Emoji", isOn: $showStatusEmoji)
                        .toggleStyle(.checkbox)

                    Text("Status: ✳️ on track, 🚀 borderline, ⚠️ exceeding")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)

                Spacer()

                HStack {
                    Spacer()
                    Button("Save") {
                        Preferences.shared.sessionKey = sessionKey
                        Preferences.shared.organizationId = organizationId
                        Preferences.shared.selectedMetric = selectedMetric
                        Preferences.shared.numberDisplayStyle = numberDisplayStyle
                        Preferences.shared.progressIconStyle = progressIconStyle
                        Preferences.shared.showStatusEmoji = showStatusEmoji
                        LoginItemManager.shared.setLoginItemEnabled(launchAtLogin)

                        NotificationCenter.default.post(name: .settingsChanged, object: nil)

                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
    }

    var logTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Application Log")
                    .font(.headline)
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
                Button("Refresh") {
                    loadLog()
                }
            }

            TextEditor(text: .constant(logText))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Log file: ~/.claude-usage/app.log")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .onAppear { loadLog() }
    }

    private func loadLog() {
        let path = AppDelegate.logFile
        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            let lines = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
            logText = lines.joined(separator: "\n")
        } else {
            logText = "(no log file found)"
        }
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var usageData: UsageResponse?
    var timer: Timer?
    var settingsWindowController: SettingsWindowController?

    // Fetch reliability tracking
    var logEntries: [(Date, String)] = []
    var consecutiveFailures: Int = 0
    let maxRetries = 3
    let maxLogEntries = 50

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.shared.migrateFromUserDefaults()
        cleanOldLogs()
        addLog("App launched")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "⏱️"
            button.action = #selector(showMenu)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        menu = NSMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .settingsChanged,
            object: nil
        )

        fetchUsageData()

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchUsageData()
        }
    }

    @objc func handleSettingsChanged() {
        fetchUsageData()
    }

    @objc func showMenu() {
        menu.removeAllItems()

        let currentMetric = Preferences.shared.selectedMetric

        if let data = usageData {
            // 5-hour limit
            if let fiveHour = data.five_hour {
                let item = NSMenuItem(
                    title: "\(formatUtilization(fiveHour.utilization))% 5-hour Limit",
                    action: currentMetric == .fiveHour ? nil : #selector(switchToFiveHour),
                    keyEquivalent: ""
                )
                if currentMetric == .fiveHour {
                    item.state = .on
                }
                menu.addItem(item)
                menu.addItem(NSMenuItem(title: "  t: \(metricDetailString(limit: fiveHour, metric: .fiveHour))", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            }

            // 7-day limit (all models)
            if let sevenDay = data.seven_day {
                let item = NSMenuItem(
                    title: "\(formatUtilization(sevenDay.utilization))% 7-day Limit (All Models)",
                    action: currentMetric == .sevenDay ? nil : #selector(switchToSevenDay),
                    keyEquivalent: ""
                )
                if currentMetric == .sevenDay {
                    item.state = .on
                }
                menu.addItem(item)
                menu.addItem(NSMenuItem(title: "  t: \(metricDetailString(limit: sevenDay, metric: .sevenDay))", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            }

            // 7-day Sonnet
            if let sevenDaySonnet = data.seven_day_sonnet {
                let item = NSMenuItem(
                    title: "\(formatUtilization(sevenDaySonnet.utilization))% 7-day Limit (Sonnet)",
                    action: currentMetric == .sevenDaySonnet ? nil : #selector(switchToSevenDaySonnet),
                    keyEquivalent: ""
                )
                if currentMetric == .sevenDaySonnet {
                    item.state = .on
                }
                menu.addItem(item)
                menu.addItem(NSMenuItem(title: "  t: \(metricDetailString(limit: sevenDaySonnet, metric: .sevenDaySonnet))", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            }

            // 7-day Opus (if available)
            if let sevenDayOpus = data.seven_day_opus {
                menu.addItem(NSMenuItem(title: "\(formatUtilization(sevenDayOpus.utilization))% 7-day Limit (Opus)", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "  t: \(metricDetailString(limit: sevenDayOpus, metric: .sevenDay))", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            }
        } else {
            menu.addItem(NSMenuItem(title: "Loading...", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
        }

        // Log section
        let logItem = NSMenuItem(title: "Log", action: nil, keyEquivalent: "")
        let logSubmenu = NSMenu()
        if logEntries.isEmpty {
            logSubmenu.addItem(NSMenuItem(title: "No entries", action: nil, keyEquivalent: ""))
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let recentLogs = logEntries.prefix(15)
            for (date, message) in recentLogs {
                let title = "\(formatter.string(from: date)) \(message)"
                logSubmenu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
            }
        }
        logItem.submenu = logSubmenu
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func switchToFiveHour() {
        Preferences.shared.selectedMetric = .fiveHour
        updateMenuBarIcon()
    }

    func metricDetailString(limit: UsageLimit, metric: MetricType) -> String {
        guard let resetDate = limit.resets_at else {
            return "?%, —"
        }
        let expected = calculateExpectedUsage(resetDateString: resetDate, metric: metric)
        let expectedStr = expected != nil ? formatUtilization(expected!) : "?"
        return "\(expectedStr)%, \(formatResetTime(resetDate))"
    }

    @objc func switchToSevenDay() {
        Preferences.shared.selectedMetric = .sevenDay
        updateMenuBarIcon()
    }

    @objc func switchToSevenDaySonnet() {
        Preferences.shared.selectedMetric = .sevenDaySonnet
        updateMenuBarIcon()
    }

    @objc func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func refreshClicked() {
        fetchUsageData()
    }

    @objc func quitClicked() {
        NSApplication.shared.terminate(self)
    }

    static let logDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/.claude-usage"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }()
    static let logFile: String = "\(logDir)/app.log"

    func cleanOldLogs() {
        let path = AppDelegate.logFile
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let lines = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
        let cutoff = Date().addingTimeInterval(-86400)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let kept = lines.filter { line in
            guard line.count > 21,
                  let start = line.index(line.startIndex, offsetBy: 1, limitedBy: line.endIndex),
                  let end = line.index(start, offsetBy: 19, limitedBy: line.endIndex),
                  let date = formatter.date(from: String(line[start..<end])) else {
                return true
            }
            return date > cutoff
        }
        let result = kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n")
        try? result.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        DispatchQueue.main.async {
            let entry = (Date(), message)
            self.logEntries.insert(entry, at: 0)
            if self.logEntries.count > self.maxLogEntries {
                self.logEntries.removeLast(self.logEntries.count - self.maxLogEntries)
            }
        }

        // Prepend to file (newest first)
        let path = AppDelegate.logFile
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path),
               let existing = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                var combined = data
                combined.append(existing)
                try? combined.write(to: URL(fileURLWithPath: path))
            } else {
                FileManager.default.createFile(atPath: path, contents: data, attributes: nil)
            }
        }
    }

    func fetchUsageData() {
        fetchUsageData(retryCount: 0)
    }

    private func fetchUsageData(retryCount: Int) {
        var sessionKey = Preferences.shared.sessionKey
        var organizationId = Preferences.shared.organizationId

        if sessionKey == nil || sessionKey?.isEmpty == true {
            sessionKey = ProcessInfo.processInfo.environment["CLAUDE_SESSION_KEY"]
        }

        if organizationId == nil || organizationId?.isEmpty == true {
            organizationId = ProcessInfo.processInfo.environment["CLAUDE_ORGANIZATION_ID"]
        }

        guard let sessionKey = sessionKey, !sessionKey.isEmpty else {
            let msg = "No session key configured"
            addLog(msg)
            DispatchQueue.main.async {
                self.consecutiveFailures += 1
                self.statusItem.button?.title = "❌"
            }
            return
        }

        guard let organizationId = organizationId, !organizationId.isEmpty else {
            let msg = "No organization ID configured"
            addLog(msg)
            DispatchQueue.main.async {
                self.consecutiveFailures += 1
                self.statusItem.button?.title = "❌"
            }
            return
        }

        let urlString = "https://claude.ai/api/organizations/\(organizationId)/usage"
        guard let url = URL(string: urlString) else {
            addLog("Invalid URL: \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.addValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.addValue("*/*", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.addValue("1.0.0", forHTTPHeaderField: "anthropic-client-version")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Network error
            if let error = error {
                let msg = "Network error: \(error.localizedDescription)"
                self.addLog(msg)
                self.handleFetchFailure(retryCount: retryCount)
                return
            }

            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let msg = "HTTP \(httpResponse.statusCode) from API"
                self.addLog(msg)
                self.handleFetchFailure(retryCount: retryCount)
                return
            }

            guard let data = data else {
                self.addLog("Empty response body")
                self.handleFetchFailure(retryCount: retryCount)
                return
            }

            do {
                let decoder = JSONDecoder()
                let usageData = try decoder.decode(UsageResponse.self, from: data)

                DispatchQueue.main.async {
                    self.consecutiveFailures = 0
                    self.usageData = usageData
                    self.updateMenuBarIcon()
                    self.addLog("Fetch OK")
                }
            } catch {
                self.addLog("JSON decode error: \(error)")
                self.handleFetchFailure(retryCount: retryCount)
            }
        }

        task.resume()
    }

    private func handleFetchFailure(retryCount: Int) {
        if retryCount < maxRetries {
            let delay = pow(2.0, Double(retryCount)) // 1s, 2s, 4s
            addLog("Retrying in \(Int(delay))s (attempt \(retryCount + 1)/\(maxRetries))")
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.fetchUsageData(retryCount: retryCount + 1)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.consecutiveFailures += 1
                self.addLog("Failed after \(self.maxRetries) retries (consecutive: \(self.consecutiveFailures))")
                if self.consecutiveFailures >= 3 {
                    self.statusItem.button?.title = "❌"
                }
            }
        }
    }

    func getSelectedMetricData(from data: UsageResponse, metric: MetricType) -> (Double, String?, String)? {
        switch metric {
        case .fiveHour:
            guard let limit = data.five_hour else { return nil }
            return (limit.utilization, limit.resets_at, "5-hour Limit")
        case .sevenDay:
            guard let limit = data.seven_day else { return nil }
            return (limit.utilization, limit.resets_at, "7-day Limit")
        case .sevenDaySonnet:
            guard let limit = data.seven_day_sonnet else { return nil }
            return (limit.utilization, limit.resets_at, "7-day Sonnet")
        }
    }

    func updateMenuBarIcon() {
        guard let data = usageData,
              let button = statusItem.button else { return }

        let metric = Preferences.shared.selectedMetric
        let numberDisplayStyle = Preferences.shared.numberDisplayStyle
        let progressIconStyle = Preferences.shared.progressIconStyle
        let showStatusEmoji = Preferences.shared.showStatusEmoji

        guard let (utilization, resetDateString, _) = getSelectedMetricData(from: data, metric: metric) else {
            button.title = "❌"
            return
        }

        // Calculate status and expected usage
        let status: UsageStatus
        let expectedUsage: Double?
        if let resetDate = resetDateString {
            status = calculateStatus(utilization: utilization, resetDateString: resetDate, metric: metric)
            expectedUsage = calculateExpectedUsage(resetDateString: resetDate, metric: metric)
        } else {
            status = utilization >= 80 ? .exceeding : (utilization >= 50 ? .borderline : .onTrack)
            expectedUsage = nil
        }

        // Build the display string
        var displayParts: [String] = []

        // Add status emoji if enabled
        if showStatusEmoji {
            displayParts.append(getStatusIcon(for: status))
        }

        // Add number display based on style
        switch numberDisplayStyle {
        case .none:
            break
        case .percentage:
            displayParts.append("\(formatUtilization(utilization))%")
        case .threshold:
            let expectedStr = expectedUsage != nil ? formatUtilization(expectedUsage!) : "?"
            displayParts.append("\(formatUtilization(utilization))|\(expectedStr)")
        }

        // Add progress icon based on style
        switch progressIconStyle {
        case .none:
            break
        case .circle:
            displayParts.append(getCircleIcon(for: utilization))
        case .braille:
            displayParts.append(getBrailleIcon(for: utilization))
        case .barAscii:
            displayParts.append(getProgressBar(for: utilization, filled: "=", empty: " ", prefix: "[", suffix: "]"))
        case .barBlocks:
            displayParts.append(getProgressBar(for: utilization, filled: "▓", empty: "░", prefix: "", suffix: ""))
        case .barSquares:
            displayParts.append(getProgressBar(for: utilization, filled: "■", empty: "□", prefix: "", suffix: ""))
        case .barCircles:
            displayParts.append(getProgressBar(for: utilization, filled: "●", empty: "○", prefix: "", suffix: ""))
        case .barLines:
            displayParts.append(getProgressBar(for: utilization, filled: "━", empty: "─", prefix: "", suffix: ""))
        }

        // Fallback if nothing is selected
        if displayParts.isEmpty {
            displayParts.append("\(formatUtilization(utilization))%")
        }

        button.title = displayParts.joined(separator: " ")
    }

    enum UsageStatus {
        case onTrack
        case borderline
        case exceeding
    }

    func calculateStatus(utilization: Double, resetDateString: String, metric: MetricType) -> UsageStatus {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let resetDate = formatter.date(from: resetDateString) else {
            // Fallback to simple threshold-based status
            if utilization >= 80 { return .exceeding }
            else if utilization >= 50 { return .borderline }
            else { return .onTrack }
        }

        let windowDuration: TimeInterval
        switch metric {
        case .fiveHour:
            windowDuration = 5 * 3600
        case .sevenDay, .sevenDaySonnet:
            windowDuration = 7 * 24 * 3600
        }

        let now = Date()
        let timeRemaining = resetDate.timeIntervalSince(now)

        guard timeRemaining > 0 && timeRemaining <= windowDuration else {
            if utilization >= 80 { return .exceeding }
            else if utilization >= 50 { return .borderline }
            else { return .onTrack }
        }

        let timeElapsed = windowDuration - timeRemaining
        let expectedConsumption = (timeElapsed / windowDuration) * 100.0

        if utilization < expectedConsumption - 5 {
            return .onTrack
        } else if utilization <= expectedConsumption + 5 {
            return .borderline
        } else {
            return .exceeding
        }
    }

    func getStatusIcon(for status: UsageStatus) -> String {
        switch status {
        case .onTrack: return "✳️"
        case .borderline: return "🚀"
        case .exceeding: return "⚠️"
        }
    }

    func getCircleIcon(for utilization: Double) -> String {
        // ○ ◔ ◑ ◕ ●
        if utilization < 12.5 { return "○" }
        else if utilization < 37.5 { return "◔" }
        else if utilization < 62.5 { return "◑" }
        else if utilization < 87.5 { return "◕" }
        else { return "●" }
    }

    func getBrailleIcon(for utilization: Double) -> String {
        // ⠀ ⠁ ⠃ ⠇ ⡇ ⣇ ⣧ ⣿
        if utilization < 12.5 { return "⠀" }
        else if utilization < 25 { return "⠁" }
        else if utilization < 37.5 { return "⠃" }
        else if utilization < 50 { return "⠇" }
        else if utilization < 62.5 { return "⡇" }
        else if utilization < 75 { return "⣇" }
        else if utilization < 87.5 { return "⣧" }
        else { return "⣿" }
    }

    func getProgressBar(for utilization: Double, filled: String, empty: String, prefix: String, suffix: String) -> String {
        let totalBlocks = 5
        let filledBlocks = Int((utilization / 100.0) * Double(totalBlocks) + 0.5)
        let emptyBlocks = totalBlocks - filledBlocks
        let filledStr = String(repeating: filled, count: filledBlocks)
        let emptyStr = String(repeating: empty, count: emptyBlocks)
        return "\(prefix)\(filledStr)\(emptyStr)\(suffix)"
    }

    func getIconForUtilization(_ utilization: Double) -> String {
        if utilization >= 80 {
            return "⚠️"
        } else if utilization >= 50 {
            return "🚀"
        } else {
            return "✳️"
        }
    }

    func formatUtilization(_ value: Double) -> String {
        return String(format: "%.0f", value)
    }

    func formatResetTime(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval < 0 {
            return "soon"
        }

        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours >= 24 {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s")"
        } else if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "< 1m"
        }
    }

    func calculateExpectedUsage(resetDateString: String, metric: MetricType) -> Double? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let resetDate = formatter.date(from: resetDateString) else {
            return nil
        }

        let windowDuration: TimeInterval
        switch metric {
        case .fiveHour:
            windowDuration = 5 * 3600
        case .sevenDay, .sevenDaySonnet:
            windowDuration = 7 * 24 * 3600
        }

        let now = Date()
        let timeRemaining = resetDate.timeIntervalSince(now)

        guard timeRemaining > 0 && timeRemaining <= windowDuration else {
            return nil
        }

        let timeElapsed = windowDuration - timeRemaining
        return (timeElapsed / windowDuration) * 100.0
    }
}

// MARK: - Data Models

struct UsageResponse: Codable {
    let five_hour: UsageLimit?
    let seven_day: UsageLimit?
    let seven_day_oauth_apps: UsageLimit?
    let seven_day_opus: UsageLimit?
    let seven_day_sonnet: UsageLimit?
    let seven_day_cowork: UsageLimit?
    let iguana_necktie: UsageLimit?
    let extra_usage: ExtraUsage?
}

struct UsageLimit: Codable {
    let utilization: Double
    let resets_at: String?
}

struct ExtraUsage: Codable {
    let is_enabled: Bool?
    let monthly_limit: Double?
    let used_credits: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        is_enabled = try container.decodeIfPresent(Bool.self, forKey: .is_enabled)
        monthly_limit = try container.decodeIfPresent(Double.self, forKey: .monthly_limit)
        used_credits = try container.decodeIfPresent(Double.self, forKey: .used_credits)
    }
}

// MARK: - Main Entry Point

@main
struct ClaudeUsageApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
