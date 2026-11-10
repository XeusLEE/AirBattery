//
//  BatteryHistoryStore.swift
//  AirBattery
//
//  Collects battery samples of external devices, persists them to disk and
//  answers remaining-time estimates from the collected history.
//

import Foundation

final class BatteryHistoryStore {
    static let shared = BatteryHistoryStore()
    static let fileURL: URL = fd.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("AirBattery/battery-history.json")

    /// On-disk layout. Version 1 had no `names`; version 2 adds the last seen name of
    /// every device so offline devices can still be listed by name.
    private struct HistoryFile: Codable {
        var version: Int
        var devices: [String: [BatterySample]]
        var names: [String: String]

        private enum CodingKeys: String, CodingKey { case version, devices, names }

        init(version: Int, devices: [String: [BatterySample]], names: [String: String]) {
            self.version = version
            self.devices = devices
            self.names = names
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            devices = try container.decode([String: [BatterySample]].self, forKey: .devices)
            names = try container.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
        }
    }
    private static let fileVersion = 2
    /// Minimum time between two writes triggered by `record`.
    private static let saveInterval: TimeInterval = 60

    private let lock = NSLock()
    private var histories: [String: DeviceHistory] = [:]
    /// deviceID → the name the device last reported.
    private var deviceNames: [String: String] = [:]
    private var dirty = false
    private var lastSave: TimeInterval = 0

    /// Reads the history file. A missing file yields an empty store; an unreadable one is
    /// reported, yields an empty store and is replaced on the next save.
    func load() {
        let url = Self.fileURL
        var loaded: [String: DeviceHistory] = [:]
        var loadedNames: [String: String] = [:]
        var replaceFile = false
        if fd.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let file = try JSONDecoder().decode(HistoryFile.self, from: data)
                if file.version == 1 || file.version == Self.fileVersion {
                    for (id, samples) in file.devices { loaded[id] = DeviceHistory(samples: samples) }
                    loadedNames = file.names
                } else {
                    print("⚠️ battery history version \(file.version) not supported, starting empty")
                    replaceFile = true
                }
            } catch {
                print("⚠️ battery history unreadable: \(error)")
                replaceFile = true
            }
        }
        lock.lock()
        histories = loaded
        deviceNames = loadedNames
        dirty = replaceFile
        lock.unlock()
    }

    /// Stores a sample for an external device. The Mac's internal battery has its own
    /// time estimate from IOKit and devices without a battery carry no information.
    func record(_ device: Device) {
        guard device.hasBattery, !device.deviceID.isEmpty, device.deviceID != "@MacInternalBattery" else { return }
        let now = Date().timeIntervalSince1970
        lock.lock()
        if histories[device.deviceID, default: DeviceHistory()].record(level: device.batteryLevel, charging: device.isCharging != 0, at: now) {
            dirty = true
        }
        if deviceNames[device.deviceID] != device.deviceName {
            deviceNames[device.deviceID] = device.deviceName
            dirty = true
        }
        lock.unlock()
        saveIfNeeded()
    }

    func estimate(for device: Device) -> Estimate {
        lock.lock()
        let history = histories[device.deviceID]
        lock.unlock()
        guard let history = history else { return .none }
        return Estimator.estimate(history)
    }

    // MARK: - Inspection

    /// Number of devices with a history and the size of the history file (0 when missing).
    func summary() -> (deviceCount: Int, bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        let attributes = try? fd.attributesOfItem(atPath: Self.fileURL.path)
        let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return (histories.count, bytes)
    }

    /// deviceID → the name the device last reported.
    func names() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return deviceNames
    }

    /// deviceID → time of the newest sample. Devices without samples are left out.
    func lastSeen() -> [String: TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return lastSeenLocked()
    }

    func sampleCounts() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return histories.mapValues { $0.samples.count }
    }

    /// Caller holds `lock`.
    private func lastSeenLocked() -> [String: TimeInterval] {
        var result: [String: TimeInterval] = [:]
        for (id, history) in histories {
            if let newest = history.samples.map({ $0.t }).max() { result[id] = newest }
        }
        return result
    }

    // MARK: - Maintenance

    /// Drops every device and writes the empty file.
    func clear() {
        lock.lock()
        histories = [:]
        deviceNames = [:]
        dirty = true
        lock.unlock()
        saveIfNeeded(force: true)
    }

    /// Drops one device's samples and name and writes the file.
    func remove(deviceID: String) {
        lock.lock()
        let removedHistory = histories.removeValue(forKey: deviceID) != nil
        let removedName = deviceNames.removeValue(forKey: deviceID) != nil
        if removedHistory || removedName { dirty = true }
        lock.unlock()
        saveIfNeeded(force: true)
    }

    /// Drops devices whose newest sample is older than `age` (or that have no samples) unless
    /// their stored name is in `names`. Returns how many devices were dropped.
    @discardableResult
    func pruneUnseen(olderThan age: TimeInterval, keeping names: Set<String>) -> Int {
        let now = Date().timeIntervalSince1970
        lock.lock()
        let lastSeen = lastSeenLocked()
        let ids = Set(histories.keys).union(deviceNames.keys)
        var removed = 0
        for id in ids {
            guard now - (lastSeen[id] ?? 0) > age, !names.contains(deviceNames[id] ?? "") else { continue }
            histories[id] = nil
            deviceNames[id] = nil
            removed += 1
        }
        if removed > 0 { dirty = true }
        lock.unlock()
        saveIfNeeded(force: true)
        return removed
    }

    /// Writes the history when it changed and at least `saveInterval` passed since the last
    /// write; `force` skips the interval. Never throws: a failed write is reported and retried
    /// on the next call.
    func saveIfNeeded(force: Bool = false) {
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        guard dirty, force || now - lastSave >= Self.saveInterval else { return }
        let url = Self.fileURL
        do {
            try fd.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let file = HistoryFile(version: Self.fileVersion, devices: histories.mapValues { $0.samples }, names: deviceNames)
            let data = try JSONEncoder().encode(file)
            try data.write(to: url, options: .atomic)
            dirty = false
            lastSave = now
        } catch {
            print("⚠️ battery history not saved: \(error)")
            lastSave = now
        }
    }
}
