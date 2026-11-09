//
//  DeviceCardView.swift
//  AirBattery
//
//  One device row of the menu-bar popover as a card: icon, name, status chip,
//  level bar, remaining-time estimate and last-seen / hover actions. Also holds
//  the popover's layout constants and the text formatters the card uses.
//

import SwiftUI

// MARK: - Layout

enum PopoverLayout {
    static let width: CGFloat = 352
    static let cardHeight: CGFloat = 68
    static let cardSpacing: CGFloat = 5
    static let horizontalInset: CGFloat = 10
    static let headerHeight: CGFloat = 26
    static let sectionCaptionHeight: CGFloat = 18
    static let hiddenRowHeight: CGFloat = 34
    static let verticalPadding: CGFloat = 8
    static let maxHeight: CGFloat = 640

    /// headerHeight + verticalPadding*2 + cardCount*cardHeight + max(cardCount-1,0)*cardSpacing
    /// + sectionCount*(sectionCaptionHeight+cardSpacing)
    /// + (hiddenRow ? (cardCount > 0 ? cardSpacing : 0) + sectionCaptionHeight + cardSpacing + hiddenRowHeight : 0)
    /// `sectionCount` is the number of non-empty Nearcast groups; the hidden row carries its own caption.
    static func contentHeight(cardCount: Int, sectionCount: Int, hiddenRow: Bool) -> CGFloat {
        let cards = CGFloat(cardCount) * cardHeight + CGFloat(max(cardCount - 1, 0)) * cardSpacing
        let sections = CGFloat(sectionCount) * (sectionCaptionHeight + cardSpacing)
        let hidden: CGFloat = hiddenRow ? (cardCount > 0 ? cardSpacing : 0) + sectionCaptionHeight + cardSpacing + hiddenRowHeight : 0
        return headerHeight + verticalPadding * 2 + cards + sections + hidden
    }

    static func height(cardCount: Int, sectionCount: Int, hiddenRow: Bool) -> CGFloat {
        return min(contentHeight(cardCount: cardCount, sectionCount: sectionCount, hiddenRow: hiddenRow), maxHeight)
    }
}

// MARK: - Formatters

func estimateText(_ e: Estimate) -> String? {
    switch e {
    case .none:
        return nil
    case .timeToEmpty(let seconds):
        return String(format: "~%@ left".local, durationText(DurationParts.from(seconds: seconds)))
    case .timeToFull(let seconds):
        return String(format: "~%@ to full".local, durationText(DurationParts.from(seconds: seconds)))
    }
}

func durationText(_ p: DurationParts) -> String {
    if p.days > 0 { return String(format: "%d d".local, p.days) }
    if p.hours > 0 {
        let hours = String(format: "%d h".local, p.hours)
        if p.minutes > 0 { return hours + " " + String(format: "%d min".local, p.minutes) }
        return hours
    }
    return String(format: "%d min".local, p.minutes)
}

func lastSeenText(sinceSeconds s: TimeInterval) -> String {
    if s < 60 { return "just now".local }
    if s < 3600 { return String(format: "%d min ago".local, Int(s / 60)) }
    return String(format: "%d h ago".local, Int(s / 3600))
}

func internalEstimate(_ ib: iBattery) -> Estimate {
    if ib.isCharged { return .none }
    guard let minutes = ib.timeRemaining, minutes > 0 else { return .none }
    let seconds = TimeInterval(minutes * 60)
    return ib.isCharging ? .timeToFull(seconds) : .timeToEmpty(seconds)
}

// MARK: - Row actions

struct DeviceRowActions: View {
    let device: Device
    let allowPin: Bool
    let allowHide: Bool
    @Binding var alertList: [btAlert]
    @Binding var pinnedList: [String]
    var onHide: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 3) {
            if !alertList.map({ $0.name }).contains(device.deviceName) {
                RowActionButton(image: "bell.circle", action: addAlert)
            } else {
                RowActionButton(image: "bell.circle.fill", action: editAlert)
            }
            if allowPin {
                if !pinnedList.contains(device.deviceName) {
                    RowActionButton(image: "pin.circle", action: pin)
                } else {
                    RowActionButton(image: "pin.circle.fill", action: unpin)
                }
            }
            if #available(macOS 14, *) {
                RowActionButton(image: "list.clipboard.fill.circle", action: copyName)
            }
            if allowHide {
                RowActionButton(image: "eye.slash.circle", action: hide)
            }
        }
    }

    private func addAlert() {
        let alert = btAlert(name: device.deviceName,
                            full: 80, fullOn: true, fullSound: true,
                            low: 20, lowOn: true, lowSound: true)
        let alertWindowController = AlertWindowController()
        alertWindowController.showAlert(with: alert, iconName: getDeviceIcon(device), onConfirm: { newAlert in
            alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
            alertList.append(newAlert)
            ud.set(object: alertList, forKey: "alertList")
        }, onCancel: {})
    }

    private func editAlert() {
        alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
        if let alert = alertList.first(where: { $0.name == device.deviceName }) {
            let alertWindowController = AlertWindowController()
            alertWindowController.showAlert(with: alert, iconName: getDeviceIcon(device), onConfirm: { newAlert in
                alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
                alertList.removeAll { $0.name == device.deviceName }
                alertList.append(newAlert)
                ud.set(object: alertList, forKey: "alertList")
            }, onCancel: {})
        }
    }

    private func pin() {
        pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
        pinnedList.append(device.deviceName)
        ud.set(pinnedList, forKey: "pinnedList")
        refeshPinnedBar()
    }

    private func unpin() {
        pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
        pinnedList.removeAll(where: { $0 == device.deviceName })
        refeshPinnedBar(unpin: device.deviceName)
        ud.set(pinnedList, forKey: "pinnedList")
    }

    private func copyName() {
        copyToClipboard(device.deviceName)
        DispatchQueue.main.async {
            _ = createAlert(title: "Device Name Copied".local,
                            message: String(format: "Device name \"%@\" has been copied to the clipboard.".local, device.deviceName),
                            button1: "OK".local).runModal()
        }
    }

    private func hide() {
        onHide?()
        var blackList = (ud.object(forKey: "blackList") ?? []) as! [String]
        blackList.append(device.deviceName)
        ud.set(blackList, forKey: "blackList")
        let pinned = (ud.object(forKey: "pinnedList") ?? []) as! [String]
        if pinned.contains(device.deviceName) {
            refeshPinnedBar()
        }
    }
}

private struct RowActionButton: View {
    let image: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action, label: {
            Image(image)
                .resizable().scaledToFit()
                .frame(width: 18, height: 18, alignment: .center)
                .foregroundColor(hovered ? .accentColor : .secondary)
        })
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in hovered = hovering }
    }
}

// MARK: - Status chip

/// The one condition a card calls out, first match wins. `nil` for devices without a battery
/// and for a plain discharging device above 20%.
private enum DeviceStatus {
    case charging, low, gettingLow, full, pluggedIn

    init?(_ device: Device) {
        guard device.hasBattery else { return nil }
        if device.isCharging != 0 && device.isCharging != 5 && !device.isCharged {
            self = .charging
        } else if device.batteryLevel <= 10 {
            self = .low
        } else if device.batteryLevel <= 20 {
            self = .gettingLow
        } else if device.isCharged {
            self = .full
        } else if device.acPowered || device.isCharging == 5 {
            self = .pluggedIn
        } else {
            return nil
        }
    }

    var text: String {
        switch self {
        case .charging: return "Charging".local
        case .low: return "Low".local
        case .gettingLow: return "Getting low".local
        case .full: return "Full".local
        case .pluggedIn: return "Plugged in".local
        }
    }

    var color: Color {
        switch self {
        case .charging: return .myGreen
        case .low: return .myRed
        case .gettingLow: return .myYellow
        case .full, .pluggedIn: return .secondary
        }
    }

    var symbol: String? {
        switch self {
        case .charging: return "bolt.fill"
        case .pluggedIn: return "powerplug.fill"
        case .low, .gettingLow, .full: return nil
        }
    }

    /// Full / Plugged in carry no urgency; the meta row repeats them when there is no estimate.
    var isPowerState: Bool {
        return self == .full || self == .pluggedIn
    }
}

private struct StatusChip: View {
    let status: DeviceStatus

    var body: some View {
        HStack(spacing: 3) {
            if let symbol = status.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(status.text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(status.color)
        .padding(.vertical, 2)
        .padding(.horizontal, 7)
        .background(Capsule().fill(status.color.opacity(0.16)))
        .fixedSize()
    }
}

// MARK: - Card

struct DeviceCardView<Actions: View>: View {
    let device: Device
    let estimate: Estimate
    let isHovered: Bool
    let hasAlert: Bool
    let isPinned: Bool
    @ViewBuilder let actions: () -> Actions

    init(device: Device, estimate: Estimate, isHovered: Bool, hasAlert: Bool, isPinned: Bool,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.device = device
        self.estimate = estimate
        self.isHovered = isHovered
        self.hasAlert = hasAlert
        self.isPinned = isPinned
        self.actions = actions
    }

    private static var cardShape: RoundedRectangle {
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    private var status: DeviceStatus? {
        return DeviceStatus(device)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            topRow
            if device.hasBattery { levelBar }
            metaRow
        }
        .frame(height: PopoverLayout.cardHeight)
        .padding(.horizontal, 10)
        .background(cardBackground)
        .clipShape(Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Color.blackWhite.opacity(0.04)))
    }

    private var cardBackground: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)
            isHovered ? Color.blackWhite.opacity(0.06) : Color.clear
        }
    }

    private var topRow: some View {
        HStack(spacing: 9) {
            Image(getDeviceIcon(device))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.blackWhite)
                .frame(width: 22, height: 22, alignment: .center)
            HStack(spacing: 4) {
                Text(device.deviceName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.blackWhite)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if hasAlert {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blackWhite)
                }
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blackWhite)
                }
            }
            Spacer(minLength: 4)
            if let status = status {
                StatusChip(status: status)
            }
            if device.hasBattery {
                Text("\(device.batteryLevel)%")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundColor(device.batteryLevel <= 10 ? Color.darkMyRed : .primary)
                    .fixedSize()
            }
        }
    }

    private var levelBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.blackWhite.opacity(0.08))
                Capsule().fill(Color(getPowerColor(device)))
                    .frame(width: barWidth(in: geometry.size.width))
            }
        }
        .frame(height: 5)
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        if device.batteryLevel <= 0 { return 0 }
        return min(width, max(3, width * CGFloat(device.batteryLevel) / 100))
    }

    private var metaRow: some View {
        HStack(spacing: 4) {
            Text(leadingMetaText)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isHovered {
                actions()
            } else {
                lastSeen
            }
        }
    }

    private var leadingMetaText: String {
        guard device.hasBattery else { return "" }
        if let text = estimateText(estimate) { return text }
        if let status = status, status.isPowerState { return status.text }
        return ""
    }

    private var lastSeen: some View {
        let updated = device.realUpdate != 0 ? device.realUpdate : device.lastUpdate
        let seconds = Date().timeIntervalSince1970 - updated
        let stale = seconds / 60 > staleAfterMinutes
        return HStack(spacing: 3) {
            if stale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
            }
            Text(lastSeenText(sinceSeconds: seconds))
                .font(.system(size: 10.5))
        }
        .foregroundColor(stale ? .orange : .secondary)
    }
}
