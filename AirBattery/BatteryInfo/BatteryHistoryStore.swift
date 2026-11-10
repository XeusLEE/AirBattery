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

    private struct HistoryFile: Codable {
        var version: Int
        var devices: [String: [BatterySample]]
    }
    private static let fileVersion = 1
    /// Minimum time between two writes triggered by `record`.
    private static let saveInterval: TimeInterval = 60

    private let lock = NSLock()
    private var histories: [String: DeviceHistory] = [:]
    private var dirty = false
    private var lastSave: TimeInterval = 0

    /// Reads the history file. A missing file yields an empty store; an unreadable one is
    /// reported, yields an empty store and is replaced on the next save.
    func load() {
        let url = Self.fileURL
        var loaded: [String: DeviceHistory] = [:]
        var replaceFile = false
        if fd.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let file = try JSONDecoder().decode(HistoryFile.self, from: data)
                if file.version == Self.fileVersion {
                    for (id, samples) in file.devices { loaded[id] = DeviceHistory(samples: samples) }
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
            let file = HistoryFile(version: Self.fileVersion, devices: histories.mapValues { $0.samples })
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
