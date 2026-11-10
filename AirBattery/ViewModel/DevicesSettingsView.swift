//
//  DevicesSettingsView.swift
//  AirBattery
//
//  Model and list builder for the Devices settings tab: every device the app
//  knows about (online now, seen in the battery history, or only named in one
//  of the per-device lists) merged into one entry per name.
//

import SwiftUI

// MARK: - Model

/// One row of the Devices tab. Entries are keyed by device name because the
/// per-device lists (blackList, blockedDevices, pinnedList, alertList) are
/// keyed by name as well.
struct KnownDevice: Identifiable, Equatable {
    var id: String { name }
    let name: String
    /// From the model or the history; nil for a name that only appears in a list.
    let deviceID: String?
    /// For the icon; nil when the device is not online (the UI falls back to "general_bt").
    let deviceType: String?
    /// Currently in `AirBatteryModel`, hidden ones included.
    let isOnline: Bool
    /// Only for online devices that have a battery.
    let batteryLevel: Int?
    let isCharging: Bool
    /// Newest history sample for an offline device; nil when online or never seen.
    let lastSeen: TimeInterval?
    /// `blackList`
    var isHidden: Bool
    /// `blockedDevices` (normal mode: blocked; allowlist mode: allowed)
    var isListed: Bool
    /// `pinnedList`
    var isPinned: Bool
    /// `alertList`
    var alert: btAlert?
    /// Number of history samples stored for `deviceID`.
    let sampleCount: Int
}

// MARK: - Builder

enum KnownDeviceList {
    static let macDeviceID = "@MacInternalBattery"

    /// Pure merge of the four sources into one entry per name:
    /// 1. `current` minus the Mac itself → online entries (first wins on a name clash);
    /// 2. history ids whose name is not online → offline entries with `lastSeen`;
    /// 3. names that only appear in one of the four lists → never-seen entries;
    /// 4. sorted online by name, offline by `lastSeen` newest first, never-seen by name.
    static func build(current: [Device], historyNames: [String: String], lastSeen: [String: TimeInterval],
                      sampleCounts: [String: Int], blackList: [String], blocked: [String],
                      pinned: [String], alerts: [btAlert]) -> [KnownDevice] {
        let lists = Lists(blackList: blackList, blocked: blocked, pinned: pinned, alerts: alerts)
        var result: [KnownDevice] = []
        var takenNames = Set<String>()

        // 1. Online devices
        for device in current where device.deviceID != macDeviceID {
            let name = device.deviceName
            if takenNames.contains(name) { continue }
            takenNames.insert(name)
            result.append(lists.entry(name: name,
                                      deviceID: device.deviceID,
                                      deviceType: device.deviceType,
                                      isOnline: true,
                                      batteryLevel: device.hasBattery ? device.batteryLevel : nil,
                                      isCharging: device.isCharging != 0,
                                      lastSeen: nil,
                                      sampleCount: sampleCounts[device.deviceID] ?? 0))
        }

        // 2. Offline devices from the history. Two history ids with the same
        //    name collapse into one entry: the most recently seen id wins
        //    (ties broken by id so the result does not depend on dictionary order).
        var offlineIDs: [String: String] = [:]   // name → chosen deviceID
        for (deviceID, name) in historyNames where !takenNames.contains(name) {
            if let chosen = offlineIDs[name], !newer(deviceID, than: chosen, lastSeen: lastSeen) { continue }
            offlineIDs[name] = deviceID
        }
        for (name, deviceID) in offlineIDs {
            takenNames.insert(name)
            result.append(lists.entry(name: name,
                                      deviceID: deviceID,
                                      deviceType: nil,
                                      isOnline: false,
                                      batteryLevel: nil,
                                      isCharging: false,
                                      lastSeen: lastSeen[deviceID],
                                      sampleCount: sampleCounts[deviceID] ?? 0))
        }

        // 3. Names that only live in one of the lists
        for name in blackList + blocked + pinned + alerts.map({ $0.name }) where !takenNames.contains(name) {
            takenNames.insert(name)
            result.append(lists.entry(name: name,
                                      deviceID: nil,
                                      deviceType: nil,
                                      isOnline: false,
                                      batteryLevel: nil,
                                      isCharging: false,
                                      lastSeen: nil,
                                      sampleCount: 0))
        }

        // 4. Order
        return result.sorted(by: precedes)
    }

    /// Feeds `build` from the live model, the history store and UserDefaults.
    static func load() -> [KnownDevice] {
        let store = BatteryHistoryStore.shared
        return build(current: AirBatteryModel.getAll(noFilter: true),
                     historyNames: store.names(),
                     lastSeen: store.lastSeen(),
                     sampleCounts: store.sampleCounts(),
                     blackList: (ud.object(forKey: "blackList") as? [String]) ?? [],
                     blocked: (ud.object(forKey: "blockedDevices") as? [String]) ?? [],
                     pinned: (ud.object(forKey: "pinnedList") as? [String]) ?? [],
                     alerts: ud.get(objectType: [btAlert].self, forKey: "alertList") ?? [])
    }

    // MARK: Helpers

    /// The four per-name lists; stamps the flags onto every entry kind the same way.
    private struct Lists {
        let blackList: [String]
        let blocked: [String]
        let pinned: [String]
        let alerts: [btAlert]

        func entry(name: String, deviceID: String?, deviceType: String?, isOnline: Bool,
                   batteryLevel: Int?, isCharging: Bool, lastSeen: TimeInterval?, sampleCount: Int) -> KnownDevice {
            KnownDevice(name: name,
                        deviceID: deviceID,
                        deviceType: deviceType,
                        isOnline: isOnline,
                        batteryLevel: batteryLevel,
                        isCharging: isCharging,
                        lastSeen: lastSeen,
                        isHidden: blackList.contains(name),
                        isListed: blocked.contains(name),
                        isPinned: pinned.contains(name),
                        alert: alerts.first { $0.name == name },
                        sampleCount: sampleCount)
        }
    }

    /// True when history id `a` was seen more recently than `b` (an id without
    /// samples counts as oldest; equal times fall back to the id itself).
    private static func newer(_ a: String, than b: String, lastSeen: [String: TimeInterval]) -> Bool {
        switch (lastSeen[a], lastSeen[b]) {
        case let (x?, y?) where x != y: return x > y
        case (.some, .none): return true
        case (.none, .some): return false
        default: return a < b
        }
    }

    /// 0 online, 1 offline (seen in the history), 2 never seen.
    private static func rank(_ device: KnownDevice) -> Int {
        if device.isOnline { return 0 }
        return device.deviceID != nil ? 1 : 2
    }

    /// Strict weak ordering for rule 4: group, then `lastSeen` newest first for
    /// the offline group (never-sampled last), then name.
    private static func precedes(_ a: KnownDevice, _ b: KnownDevice) -> Bool {
        let rankA = rank(a), rankB = rank(b)
        if rankA != rankB { return rankA < rankB }
        if rankA == 1 {
            switch (a.lastSeen, b.lastSeen) {
            case let (x?, y?) where x != y: return x > y
            case (.some, .none): return true
            case (.none, .some): return false
            default: break
            }
        }
        return nameBefore(a.name, b.name)
    }

    private static func nameBefore(_ a: String, _ b: String) -> Bool {
        switch a.localizedCaseInsensitiveCompare(b) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a < b
        }
    }
}

// MARK: - Devices tab

/// The Devices settings tab: alert defaults line, device list with a detail panel,
/// and the blocklist footer. Reloads from `KnownDeviceList.load()` on appear, every
/// `dockTimer` tick and after every write; the selection is kept by device name.
struct DevicesTab: View {
    @State private var devices: [KnownDevice] = []
    @State private var selection: String?
    @State private var blockName = ""
    @State private var showDefaults = false
    @AppStorage("whitelistMode") var whitelistMode = false
    @AppStorage("alertDefaultLow") var alertDefaultLow = 20
    @AppStorage("alertDefaultFull") var alertDefaultFull = 80
    @AppStorage("alertDefaultSound") var alertDefaultSound = true

    private var selectedDevice: KnownDevice? { devices.first { $0.name == selection } }
    private var trimmedBlockName: String { blockName.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Empty and duplicate names are rejected; every `blockedDevices` name is in `devices` (builder rule 3).
    private var canAdd: Bool {
        !trimmedBlockName.isEmpty && !devices.contains { $0.isListed && $0.name == trimmedBlockName }
    }

    var body: some View {
        VStack(spacing: 10) {
            defaultsRow
            HStack(alignment: .top, spacing: 10) {
                deviceList
                detailPane
            }
            footer
        }
        .padding()
        .frame(width: 560)
        .onAppear {
            reload()
            if selection == nil { selection = devices.first?.name }
        }
        .onReceive(dockTimer) { _ in reload() }
        .onChange(of: whitelistMode) { _ in reload() }
    }

    // MARK: Pieces

    private var defaultsRow: some View {
        HStack(spacing: 6) {
            Text(String(format: "New device alert defaults: low %d%%, full %d%%".local, alertDefaultLow, alertDefaultFull))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button("Edit") { showDefaults = true }
                .controlSize(.small)
                .popover(isPresented: $showDefaults, arrowEdge: .bottom) {
                    VStack(spacing: 10) {
                        SSteper("Default low", value: $alertDefaultLow, min: 1, max: 99)
                        SSteper("Default full", value: $alertDefaultFull, min: 1, max: 100)
                        SToggle("Play sound", isOn: $alertDefaultSound)
                    }
                    .padding()
                    .frame(width: 240)
                }
        }
    }

    private var deviceList: some View {
        ZStack {
            List(devices, selection: $selection) { device in
                DeviceRow(device: device, allowlistMode: whitelistMode).tag(device.name)
            }
            if devices.isEmpty {
                Text("No devices yet".local).foregroundColor(.secondary)
            }
        }
        .frame(width: 210, height: 208)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder private var detailPane: some View {
        if let device = selectedDevice {
            DeviceDetailView(device: device, allowlistMode: whitelistMode, onChange: reload)
                .id(device.name)
                .frame(maxWidth: .infinity, alignment: .top)
        } else {
            Text("Select a device".local)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TextField((whitelistMode ? "Allow by name…" : "Block by name…").local, text: $blockName, onCommit: addBlockedName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90, idealWidth: 150, maxWidth: 150)
            Button("Add", action: addBlockedName)
                .disabled(!canAdd)
                .fixedSize()
            Button("Remove unseen devices", action: removeUnseen)
                .fixedSize()
            Spacer()
            SToggle("Allowlist Mode", isOn: $whitelistMode)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: Actions

    private func reload() {
        devices = KnownDeviceList.load()
        if let name = selection, !devices.contains(where: { $0.name == name }) { selection = nil }
    }

    /// Adds the typed name to `blockedDevices`; in normal mode that blocks it, so a
    /// matching online device leaves the model at once (as the Blocked toggle does).
    private func addBlockedName() {
        guard canAdd else { return }
        let name = trimmedBlockName
        DeviceLists.set(name, in: "blockedDevices", present: true)
        if !whitelistMode { AirBatteryModel.Devices.removeAll { $0.deviceName == name } }
        blockName = ""
        reload()
        selection = name
    }

    private func removeUnseen() {
        let alerts = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
        let keep = Set(DeviceLists.names("blackList") + DeviceLists.names("blockedDevices")
                       + DeviceLists.names("pinnedList") + alerts.map { $0.name })
        let removed = BatteryHistoryStore.shared.pruneUnseen(olderThan: 7 * 86400, keeping: keep)
        reload()
        _ = createAlert(level: .informational,
                        title: "Remove unseen devices".local,
                        message: String(format: "Removed %d devices".local, removed),
                        button1: "OK".local).runModal()
    }
}

/// One list row: icon, name and the state suffix (`blocked` / `not allowed` first,
/// then `hidden`, then `offline`).
private struct DeviceRow: View {
    let device: KnownDevice
    let allowlistMode: Bool

    var body: some View {
        HStack(spacing: 6) {
            deviceIcon(device)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            Text(device.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if let suffix = suffix {
                Text("· " + suffix)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var suffix: String? {
        if allowlistMode ? !device.isListed : device.isListed {
            return (allowlistMode ? "not allowed" : "blocked").local
        }
        if device.isHidden { return "hidden".local }
        if !device.isOnline { return "offline".local }
        return nil
    }
}

// MARK: - Detail panel

/// Header plus two group boxes for one device. Every control writes through
/// UserDefaults and then calls `onChange` so the owner reloads the list.
struct DeviceDetailView: View {
    let device: KnownDevice
    let allowlistMode: Bool
    let onChange: () -> Void

    @AppStorage("alertDefaultLow") var alertDefaultLow = 20
    @AppStorage("alertDefaultFull") var alertDefaultFull = 80
    @AppStorage("alertDefaultSound") var alertDefaultSound = true

    var body: some View {
        SForm(spacing: 10, noSpacer: true) {
            header
            SGroupBox {
                SPicker("Visibility", selection: visibility, style: .segmented) {
                    Text("Show").tag(false)
                    Text("Hide").tag(true)
                }
                SDivider()
                SToggle(LocalizedStringKey(allowlistMode ? "Allowed" : "Blocked"), isOn: listed)
                SDivider()
                SToggle("Pin to menu bar", isOn: pinned)
                    .disabled(!device.isOnline && !device.isPinned)
            }
            SGroupBox {
                HStack(spacing: 8) {
                    SToggle("Low battery alert", isOn: lowOn)
                    SSteper("", value: low, min: 1, max: 99)
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(!alertLowOn)
                }
                HStack(spacing: 8) {
                    SToggle("Full battery alert", isOn: fullOn)
                    SSteper("", value: full, min: 1, max: 100)
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(!alertFullOn)
                }
                SToggle("Play sound", isOn: sound)
                    .disabled(!alertLowOn && !alertFullOn)
                SDivider()
                SButton("Delete history for this device", buttonTitle: "Clear") {
                    guard let id = device.deviceID else { return }
                    BatteryHistoryStore.shared.remove(deviceID: id)
                    onChange()
                }
                .disabled(device.deviceID == nil || device.sampleCount == 0)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            deviceIcon(device)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 3) {
                    if device.isOnline {
                        if let level = device.batteryLevel { Text(verbatim: "\(level)%") }
                        if device.isCharging { Image(systemName: "bolt.fill") }
                    } else {
                        Text(lastSeenLine)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(height: 13)
            }
            Spacer(minLength: 0)
        }
    }

    /// `Last seen …` relative within 24 h, as a short date/time beyond that; `Never seen` without a sample.
    private var lastSeenLine: String {
        guard let seen = device.lastSeen else { return "Never seen".local }
        let age = Date().timeIntervalSince1970 - seen
        let when: String
        if age < 86400 {
            when = lastSeenText(sinceSeconds: max(age, 0))
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            when = formatter.string(from: Date(timeIntervalSince1970: seen))
        }
        return String(format: "Last seen %@".local, when)
    }

    // MARK: List bindings

    /// `blackList` membership; also flips the model's `isHidden` flag so the popover follows at once.
    private var visibility: Binding<Bool> {
        Binding(get: { device.isHidden }, set: { hidden in
            DeviceLists.set(device.name, in: "blackList", present: hidden)
            if hidden { AirBatteryModel.hideDevice(device.name) } else { AirBatteryModel.unhideDevice(device.name) }
            if device.isPinned { refeshPinnedBar() }
            onChange()
        })
    }

    /// `blockedDevices` membership. When the change makes the device invisible to the
    /// scanner (blocked in normal mode, no longer allowed in allowlist mode) it leaves
    /// the model immediately; it comes back on the next scan once visible again.
    private var listed: Binding<Bool> {
        Binding(get: { device.isListed }, set: { listed in
            DeviceLists.set(device.name, in: "blockedDevices", present: listed)
            let invisible = allowlistMode ? !listed : listed
            if invisible {
                AirBatteryModel.Devices.removeAll { $0.deviceName == device.name }
                if device.isPinned { refeshPinnedBar() }
            }
            onChange()
        })
    }

    /// `pinnedList` membership plus the menu bar item.
    private var pinned: Binding<Bool> {
        Binding(get: { device.isPinned }, set: { pinned in
            if pinned {
                DeviceLists.set(device.name, in: "pinnedList", present: true)
                refeshPinnedBar()
            } else {
                // refeshPinnedBar(unpin:) reads pinnedList itself and returns early when the
                // list is empty, so the item must be removed before the name leaves the list.
                refeshPinnedBar(unpin: device.name)
                DeviceLists.set(device.name, in: "pinnedList", present: false)
            }
            onChange()
        })
    }

    // MARK: Alert bindings

    private var alertLowOn: Bool { device.alert?.lowOn ?? false }
    private var alertFullOn: Bool { device.alert?.fullOn ?? false }

    private var lowOn: Binding<Bool> {
        Binding(get: { alertLowOn }, set: { on in updateAlert { $0.with(lowOn: on) } })
    }

    private var fullOn: Binding<Bool> {
        Binding(get: { alertFullOn }, set: { on in updateAlert { $0.with(fullOn: on) } })
    }

    private var low: Binding<Int> {
        Binding(get: { device.alert?.low ?? alertDefaultLow }, set: { value in updateAlert { $0.with(low: value) } })
    }

    private var full: Binding<Int> {
        Binding(get: { device.alert?.full ?? alertDefaultFull }, set: { value in updateAlert { $0.with(full: value) } })
    }

    /// Sound for the enabled alerts; shows the default while no record exists.
    private var sound: Binding<Bool> {
        Binding(get: { device.alert.map { ($0.lowOn && $0.lowSound) || ($0.fullOn && $0.fullSound) } ?? alertDefaultSound },
                set: { on in updateAlert { $0.with(sound: on) } })
    }

    /// Reads `alertList`, applies `change` to this device's record (starting from the
    /// defaults when there is none), keeps the record only while at least one alert is
    /// on, writes the list back and reloads.
    private func updateAlert(_ change: (btAlert) -> btAlert) {
        var alerts = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
        let index = alerts.firstIndex { $0.name == device.name }
        let current = index.map { alerts[$0] }
            ?? btAlert(name: device.name, full: alertDefaultFull, fullOn: false, fullSound: alertDefaultSound,
                       low: alertDefaultLow, lowOn: false, lowSound: alertDefaultSound)
        let updated = change(current)
        let keep = updated.lowOn || updated.fullOn
        switch (index, keep) {
        case let (i?, true): alerts[i] = updated
        case let (i?, false): alerts.remove(at: i)
        case (nil, true): alerts.append(updated)
        case (nil, false): break
        }
        ud.set(object: alerts, forKey: "alertList")
        onChange()
    }
}

// MARK: - Helpers

/// The three name lists in UserDefaults: `blackList`, `blockedDevices`, `pinnedList`.
private enum DeviceLists {
    static func names(_ key: String) -> [String] {
        (ud.object(forKey: key) as? [String]) ?? []
    }

    /// Adds `name` to (or removes it from) the list under `key`, keeping the order
    /// of the other names, and writes the list back.
    static func set(_ name: String, in key: String, present: Bool) {
        var list = names(key)
        if present {
            if !list.contains(name) { list.append(name) }
        } else {
            list.removeAll { $0 == name }
        }
        ud.set(list, forKey: key)
    }
}

private extension btAlert {
    /// Copy with the given fields replaced; `sound` sets both `lowSound` and `fullSound`.
    func with(full: Int? = nil, fullOn: Bool? = nil, low: Int? = nil, lowOn: Bool? = nil, sound: Bool? = nil) -> btAlert {
        btAlert(name: name,
                full: full ?? self.full,
                fullOn: fullOn ?? self.fullOn,
                fullSound: sound ?? fullSound,
                low: low ?? self.low,
                lowOn: lowOn ?? self.lowOn,
                lowSound: sound ?? lowSound)
    }
}

/// Icon for a known device through `getDeviceIcon` on a stand-in `Device`; entries
/// without a type (offline, never seen) get the generic Bluetooth symbol, and a name
/// without an asset falls back to a system question mark.
private func deviceIcon(_ device: KnownDevice) -> Image {
    let standIn = Device(deviceID: device.deviceID ?? "",
                         deviceType: device.deviceType ?? "general_bt",
                         deviceName: device.name,
                         batteryLevel: device.batteryLevel ?? 0,
                         isCharging: device.isCharging ? 1 : 0,
                         lastUpdate: 0)
    let name = getDeviceIcon(standIn)
    return NSImage(named: name) != nil ? Image(name) : Image(systemName: "questionmark.circle")
}
