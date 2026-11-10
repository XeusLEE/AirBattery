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
