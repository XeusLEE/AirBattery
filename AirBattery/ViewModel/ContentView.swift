//
//  ContentView.swift
//  AirBattery
//
//  Created by apple on 2023/9/4.
//
import AppKit
import SwiftUI
import WidgetKit
import Combine
//import UserNotifications

/*let test_data: [CGFloat] = [99,80,80,73,70,60,59,51,30,30,25,25,19,18,17,15,12,10,10,9] // 示例数据
struct BarChartView: View {
    let data: [CGFloat] // 电量数据，取值范围 0 到 1
    let barSpacing: CGFloat // 柱子之间的间距
    let barWidth: CGFloat // 柱子宽度

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: barSpacing) { // 设置底部对齐
                ForEach(0..<data.count, id: \.self) { index in
                    let height = (data[index] * geometry.size.height)/100
                    Capsule()
                        .fill(Color(getPowerColor(Int(data[index]))))
                        .frame(width: barWidth, height: height)
                        .padding(.bottom, -barWidth / 2) // 设置底部平坦
                }
            }
        }
    }
}*/

class AppearanceMonitor: ObservableObject {
    @Published var isDarkMode: Bool = false
    private var appearanceChangeCancellable: AnyCancellable?

    init() {
        updateAppearance()
        appearanceChangeCancellable = NotificationCenter.default.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAppearance()
            }
    }
    private func updateAppearance() {
        let appearance = NSApp.effectiveAppearance
        isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

struct MultiBatteryView: View {
    @AppStorage("showThisMac") var showThisMac = "icon"
    @AppStorage("carouselMode") var carouselMode = true
    @AppStorage("appearance") var appearance = "auto"
    @AppStorage("showOn") var showOn = "sbar"
    @AppStorage("widgetInterval") var widgetInterval = 0
    @AppStorage("readBTHID") var readBTHID = true
    @AppStorage("deviceName") var deviceName = "Mac"
    @AppStorage("nearCast") var nearCast = false
    @AppStorage("ncGroupID") var ncGroupID = ""
    
    @StateObject private var appearanceMonitor = AppearanceMonitor()

    @State private var rollCount = 1
    @State private var darkMode = getDarkMode()
    @State private var lastTime = Double(Date().timeIntervalSince1970)
    @State private var batteryList = AirBatteryModel.getAll()
    @State private var lineWidth = 6.0
    
    var body: some View {
        ZStack {
            Group{
                Image(darkMode ? "background_dark" : "background")
                RoundedRectangle(cornerRadius: 23.5, style: RoundedCornerStyle.continuous)
                    .strokeBorder(darkMode ? .white : .black, lineWidth: 2)
                    .frame(width: 104, height: 104)
                    .opacity(darkMode ? 0.25 : 0.0)
                RoundedRectangle(cornerRadius: 23.5, style: RoundedCornerStyle.continuous)
                    .strokeBorder(.black, lineWidth: 1)
                    .frame(width: 104, height: 104)
                    .opacity(darkMode ? 0.55 : 0.2)
            }
            if batteryList.count < 4 {
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth*1.2, lineCap: .round, lineJoin: .round))
                    .foregroundColor(darkMode ? .white : .black)
                    .opacity(darkMode ? 0.2 : 0.13)
                    .rotationEffect(Angle(degrees: 135))
                    .offset(x:-24, y: -24)
                    .frame(width: 38, height: 38, alignment: .center)
            } else {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(batteryList[0..<2], id: \.self) { item in
                            ZStack {
                                Group {
                                    Group {
                                        Circle()
                                            .trim(from: 0.0, to: 0.75)
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth*1.2, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(darkMode ? .white : .black)
                                            .opacity(darkMode ? 0.2 : 0.13)
                                        Circle()
                                            .trim(from: CGFloat(abs((min(Double(item.batteryLevel)/100.0*0.75, 0.75))-0.001)), to: CGFloat(abs((min(Double(item.batteryLevel)/100.0*0.75, 0.75))-0.0005)))
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(Color(getPowerColor(item)))
                                            .shadow(color: .black, radius: lineWidth*0.76, x: 0, y: 0)
                                            .clipShape(
                                                Circle()
                                                    .trim(from: 0.0, to: 0.75)
                                                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            )
                                            .opacity(item.batteryLevel == 100 ? 0 : 1)
                                        Circle()
                                            .trim(from: 0.0, to: Double(item.batteryLevel)/100.0*0.75)
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(Color(getPowerColor(item)))
                                    }.rotationEffect(Angle(degrees: 135))
                                    
                                    if item.deviceType.contains("mac") && showThisMac == "percent"{
                                        Text(String(item.batteryLevel))
                                            .colorScheme(darkMode ? .dark : .light)
                                            .foregroundColor(item.isCharging != 0 ? Color("dark_"+getPowerColor(item)) : .blackWhite)
                                            .font(.custom("Helvetica-Bold", size: item.batteryLevel>99 ? 32 : 42))
                                            .frame(width: 100, alignment: .center)
                                            .scaleEffect(0.5)
                                            .offset(x:-0.2, y:1.5)
                                        
                                    } else {
                                        Image(getDeviceIcon(item))
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .colorScheme(darkMode ? .dark : .light)
                                            .foregroundColor(item.isCharging != 0 ? Color("dark_"+getPowerColor(item)) : .blackWhite)
                                            .offset(y:-1)
                                            .frame(width: 44, height: 43, alignment: .center)
                                            .scaleEffect(0.5)
                                    }
                                }.frame(width: 38, height: 38, alignment: .center)
                                Text(item.hasBattery ? "\(item.batteryLevel)" : "")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(darkMode ? .white : .black)
                                    .scaleEffect(0.5)
                                    .offset(y: 17)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(batteryList[2..<4], id: \.self) { item in
                            ZStack {
                                Group {
                                    Group {
                                        Circle()
                                            .trim(from: 0.0, to: 0.75)
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth*1.2, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(darkMode ? .white : .black)
                                            .opacity(darkMode ? 0.2 : 0.13)
                                        Circle()
                                            .trim(from: CGFloat(abs((min(Double(item.batteryLevel)/100.0*0.75, 0.75))-0.001)), to: CGFloat(abs((min(Double(item.batteryLevel)/100.0*0.75, 0.75))-0.0005)))
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(Color(getPowerColor(item)))
                                            .shadow(color: .black, radius: lineWidth*0.76, x: 0, y: 0)
                                            .clipShape(
                                                Circle()
                                                    .trim(from: 0.0, to: 0.75)
                                                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            )
                                            .opacity(item.batteryLevel == 100 ? 0 : 1)
                                        Circle()
                                            .trim(from: 0.0, to: Double(item.batteryLevel)/100.0*0.75)
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(Color(getPowerColor(item)))
                                    }.rotationEffect(Angle(degrees: 135))
                                    Image(getDeviceIcon(item))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .colorScheme(darkMode ? .dark : .light)
                                        .foregroundColor(item.isCharging != 0 ? Color("dark_"+getPowerColor(item)) : .blackWhite)
                                        .offset(y:-1)
                                        .frame(width: 44, height: 43, alignment: .center)
                                        .scaleEffect(0.5)
                                }.frame(width: 38, height: 38, alignment: .center)
                                Text(item.hasBattery ? "\(item.batteryLevel)" : "")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(darkMode ? .white : .black)
                                    .scaleEffect(0.5)
                                    .offset(y: 17)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 128, height: 128, alignment: .center)
        .onChange(of: appearanceMonitor.isDarkMode) { newValue in
            darkMode = newValue
            NSApp.dockTile.display()
        }
        .onChange(of: appearance) { _ in
            darkMode = getDarkMode()
            NSApp.dockTile.display()
        }
        .onReceive(alertTimer) {_ in batteryAlert() }
        .onReceive(widgetViewTimer) {_ in
            if widgetInterval != -1 { WidgetCenter.shared.reloadAllTimelines() }
        }
        .onReceive(dockTimer) {_ in IDeviceBattery.shared.scanDevices() }
        .onReceive(widgetDataTimer) {_ in
            SPBluetoothDataModel.shared.refeshData (completion: { result in
                DispatchQueue.global(qos: .background).async {
                    MagicBattery.shared.scanDevices()
                    AirBatteryModel.writeData()
                }
            }, error: {
                AirBatteryModel.writeData()
            })
        }
        .onReceive(nearCastTimer) {_ in
            if nearCast && ncGroupID != ""{
                var allDevices = AirBatteryModel.getAll()
                allDevices.insert(ib2ab(InternalBattery.status), at: 0)
                do {
                    let jsonData = try JSONEncoder().encode(allDevices)
                    guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }
                    guard let data = encryptString(jsonString, password: ncGroupID) else { return }
                    let message = NCMessage(id: String(ncGroupID.prefix(15)), sender: systemUUID ?? deviceName, command: "", content: data)
                    netcastService.sendMessage(message)
                } catch {
                    print("Write JSON error：\(error)")
                }
            }
        }
        .onReceive(dockTimer) { t in
            if showOn == "both" || showOn == "dock" {
                var list = AirBatteryModel.getAll()
                let ncFiles = getFiles(withExtension: "json", in: ncFolder)
                for ncFile in ncFiles { list += AirBatteryModel.ncGetAll(url: ncFile) }
                let ibStatus = InternalBattery.status
                let now = Double(t.timeIntervalSince1970)
                
                if !carouselMode { rollCount = 1 }
                if ibStatus.hasBattery && showThisMac != "hidden" { list.insert(ib2ab(ibStatus), at: 0) }
                
                batteryList = sliceList(data: list, length: 4, count: rollCount)
                if batteryList == []{
                    rollCount = 1
                    batteryList = sliceList(data: list, length: 4, count: rollCount)
                }
                
                if now - lastTime >= 20 && list.count > 4 && carouselMode {
                    lastTime = now
                    rollCount = rollCount + 1
                }
                NSApp.dockTile.display()
            }
        }
    }
}

struct BlurView: NSViewRepresentable {
    
    private let material: NSVisualEffectView.Material
    
    init(material: NSVisualEffectView.Material) {
        self.material = material
    }
    
    func makeNSView(context: Context) -> some NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        nsView.material = material
    }
}

struct popover: View {
    var fromDock: Bool = false
    var allDevice: [Device]

    @AppStorage("nearCast") var nearCast = false

    @State private var allDevices: [Device]
    @State private var hiddenDevices = AirBatteryModel.getBlackList()
    @State private var overInfoButton = false
    @State private var overQuitButton = false
    @State private var overSettButton = false
    @State private var overReloButton = false
    @State private var overStack = -1
    @State private var overStack2 = -1
    @State private var overStackNC = -1
    @State private var hidden = [Int]()
    @State private var hidden2 = [Int]()
    @State private var alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
    @State private var pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
    @State private var allNearcast = getFiles(withExtension: "json", in: ncFolder)

    /// The device list is seeded here (not only in `onAppear`) so the first layout pass, which
    /// the Dock window measures through `NSHostingView.fittingSize`, already has the real height.
    init(fromDock: Bool = false, allDevice: [Device]) {
        self.fromDock = fromDock
        self.allDevice = allDevice
        _allDevices = State(initialValue: allDevice)
    }

    private var isEmptyState: Bool {
        return allDevices.count < 1 && hiddenDevices.count < 1
    }

    /// Cards in the main list: the Mac placeholder in the empty state, otherwise the devices
    /// not hidden in this session.
    private var mainCardCount: Int {
        if isEmptyState { return 1 }
        return allDevices.indices.filter { !hidden.contains($0) }.count
    }

    /// One device list per Nearcast peer file, empty groups dropped; nothing when Nearcast is off.
    private var nearcastGroups: [[Device]] {
        guard nearCast else { return [] }
        return allNearcast.map { AirBatteryModel.ncGetAll(url: $0) }.filter { !$0.isEmpty }
    }

    private func cardEstimate(for device: Device) -> Estimate {
        guard showEstimateEnabled() else { return .none }
        if device.deviceID == "@MacInternalBattery" { return internalEstimate(InternalBattery.status) }
        return BatteryHistoryStore.shared.estimate(for: device)
    }

    var body: some View {
        let groups = nearcastGroups
        let hiddenRow = hiddenDevices.count > 0
        let height = PopoverLayout.height(cardCount: mainCardCount + groups.reduce(0) { $0 + $1.count },
                                          sectionCount: groups.count,
                                          hiddenRow: hiddenRow)
        return ZStack {
            if fromDock { Color.clear.background(BlurView(material: .menu)) }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: PopoverLayout.verticalPadding)
                        .onHover { hovering in
                            if hovering {
                                overStack = -1
                                overStack2 = -1
                                overStackNC = -1
                            }
                        }
                    header
                    VStack(alignment: .leading, spacing: PopoverLayout.cardSpacing) {
                        if isEmptyState {
                            DeviceCardView(device: ib2ab(InternalBattery.status),
                                           estimate: cardEstimate(for: ib2ab(InternalBattery.status)),
                                           isHovered: false, hasAlert: false, isPinned: false) {
                                EmptyView()
                            }
                        }
                        ForEach(allDevices.indices, id: \.self) { index in
                            if !hidden.contains(index) {
                                deviceCard(index)
                            }
                        }
                        if hiddenRow {
                            hiddenSection
                        }
                        ForEach(groups.indices, id: \.self) { index in
                            nearcastView(devices: groups[index], mainIndex: index, overStackNC: $overStackNC)
                                .onHover { hovering in
                                    overStack = -1
                                    overStack2 = -1
                                }
                        }
                    }
                    .padding(.horizontal, PopoverLayout.horizontalInset)
                    Color.clear
                        .frame(height: PopoverLayout.verticalPadding)
                        .onHover { hovering in
                            if hovering {
                                overStack = -1
                                overStack2 = -1
                                overStackNC = -1
                            }
                        }
                }
            }
        }
        .frame(width: PopoverLayout.width, height: height)
        .onAppear { allDevices = allDevice }
        .onReceive(mainTimer) { t in
            if !fromDock && menuPopover.isShown {
                allDevices = AirBatteryModel.getAll()
                hiddenDevices = AirBatteryModel.getBlackList()
                hidden = [Int]()
                hidden2 = [Int]()
                let ibStatus = InternalBattery.status
                if ibStatus.hasBattery { allDevices.insert(ib2ab(ibStatus), at: 0) }
                if nearCast { allNearcast = getFiles(withExtension: "json", in: ncFolder) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("AirBattery")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            if !fromDock {
                Button(action: {
                    NSApp.terminate(self)
                }, label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14, weight: .light))
                        .frame(width: 14, height: 14, alignment: .center)
                        .foregroundColor(overQuitButton ? .red : .secondary)
                        .opacity(overQuitButton ? 1 : 0.7)
                })
                .focusable(false)
                .buttonStyle(PlainButtonStyle())
                .onHover{ hovering in overQuitButton = hovering }
            } else {
                Button(action: {
                    dockWindow.orderOut(nil)
                }, label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 14, weight: .light))
                        .frame(width: 14, height: 14, alignment: .center)
                        .foregroundColor(overQuitButton ? .myYellow : .secondary)
                        .opacity(overQuitButton ? 1 : 0.7)
                })
                .focusable(false)
                .buttonStyle(PlainButtonStyle())
                .onHover{ hovering in overQuitButton = hovering }
            }

            Button(action: {
                dockWindow.orderOut(nil)
                statusBarItem.menu?.cancelTracking()
                openAboutPanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                    NSApp.activate(ignoringOtherApps: true)
                }
            }, label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .light))
                    .frame(width: 14, height: 14, alignment: .center)
                    .foregroundColor(overInfoButton ? .accentColor : .secondary)
                    .opacity(overInfoButton ? 1 : 0.7)
            })
            .focusable(false)
            .buttonStyle(PlainButtonStyle())
            .onHover{ hovering in overInfoButton = hovering }
            Button(action: {
                dockWindow.orderOut(nil)
                statusBarItem.menu?.cancelTracking()
                openSettingPanel()
            }, label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13.6, weight: .light))
                    .frame(width: 14, height: 14, alignment: .center)
                    .foregroundColor(overSettButton ? .accentColor : .secondary)
                    .opacity(overSettButton ? 1 : 0.7)
            })
            .focusable(false)
            .buttonStyle(PlainButtonStyle())
            .onHover{ hovering in overSettButton = hovering }
            if nearCast {
                Button(action: {
                    netcastService.refeshAll()
                    if fromDock {
                        dockWindow.orderOut(nil)
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            allDevices = AirBatteryModel.getAll()
                            let ibStatus = InternalBattery.status
                            if ibStatus.hasBattery { allDevices.insert(ib2ab(ibStatus), at: 0) }
                            allNearcast = getFiles(withExtension: "json", in: ncFolder)
                        }
                    }
                }, label: {
                    Image(systemName: "antenna.radiowaves.left.and.right.circle")
                        .font(.system(size: 14, weight: .light))
                        .frame(width: 14, height: 14, alignment: .center)
                        .foregroundColor(overReloButton ? .accentColor : .secondary)
                        .opacity(overReloButton ? 1 : 0.7)
                })
                .focusable(false)
                .buttonStyle(PlainButtonStyle())
                .onHover{ hovering in overReloButton = hovering }
            }
        }
        .frame(height: PopoverLayout.headerHeight)
        .padding(.horizontal, 12)
        .onHover{ hovering in (overStack, overStack2) = (-1, -1) }
    }

    private func deviceCard(_ index: Int) -> some View {
        let device = allDevices[index]
        let isMac = device.deviceID == "@MacInternalBattery"
        return DeviceCardView(device: device,
                              estimate: cardEstimate(for: device),
                              isHovered: overStack == index,
                              hasAlert: alertList.map({ $0.name }).contains(device.deviceName),
                              isPinned: pinnedList.contains(device.deviceName)) {
            DeviceRowActions(device: device, allowPin: !isMac, allowHide: !isMac,
                             alertList: $alertList, pinnedList: $pinnedList,
                             onHide: { hidden.append(index) })
        }
        .onHover { hovering in
            overStack2 = -1
            overStackNC = -1
            if overStack != index { overStack = index }
        }
    }

    /// Section caption plus the row of hidden-device icons; a click on an icon un-hides it.
    private var hiddenSection: some View {
        Group {
            Text("Hidden".local)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.8)
                .textCase(.uppercase)
                .frame(height: PopoverLayout.sectionCaptionHeight)
            HStack(spacing: 5) {
                Image("sunglasses.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.blackWhite)
                    .frame(width: 22, height: 22, alignment: .center)
                Spacer()
                ForEach(hiddenDevices.indices, id: \.self) { index in
                    if !hidden2.contains(index){
                        Button(action: {
                            hidden2.append(index)
                            var blackList = (ud.object(forKey: "blackList") ?? []) as! [String]
                            blackList.removeAll { $0 == hiddenDevices[index].deviceName }
                            ud.set(blackList, forKey: "blackList")
                            let pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
                            if pinnedList.contains(hiddenDevices[index].deviceName){
                                refeshPinnedBar()
                            }
                        }, label: {
                            Image(getDeviceIcon(hiddenDevices[index]))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20, alignment: .center)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                                .background(overStack2 == index ? Color.blackWhite.opacity(0.15) : .clear).cornerRadius(2.5)
                                .onHover{ hovering in
                                    overStack = -1
                                    overStackNC = -1
                                    if overStack2 != index { overStack2 = index }
                                }
                        })
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help(hiddenDevices[index].deviceName)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: PopoverLayout.hiddenRowHeight)
            .onHover{ hovering in overStack = -1 }
        }
    }
}

struct nearcastView: View {
    var devices: [Device]
    var mainIndex: Int
    @Binding var overStackNC: Int
    @State private var overStack = -1
    @State private var alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
    @State private var pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]

    var body: some View {
        VStack(alignment: .leading, spacing: PopoverLayout.cardSpacing) {
            Text("Nearcast".local + " · " + (devices.first?.deviceName ?? ""))
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.8)
                .textCase(.uppercase)
                .frame(height: PopoverLayout.sectionCaptionHeight)
            ForEach(devices.indices, id: \.self) { index in
                DeviceCardView(device: devices[index],
                               estimate: .none,
                               isHovered: overStackNC == mainIndex && overStack == index,
                               hasAlert: alertList.map({ $0.name }).contains(devices[index].deviceName),
                               isPinned: pinnedList.contains(devices[index].deviceName)) {
                    DeviceRowActions(device: devices[index], allowPin: true, allowHide: false,
                                     alertList: $alertList, pinnedList: $pinnedList)
                }
                .onHover{ hovering in overStack = index }
            }
        }
        .onHover{ hovering in overStackNC = mainIndex }
    }
}

func openAboutPanel() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(nil)
}

func openSettingPanel() {
    dockWindow.orderOut(nil)
    NSApp.activate(ignoringOtherApps: true)
    if #available(macOS 14, *) {
        NSApp.mainMenu?.items.first?.submenu?.item(at: 2)?.performAction()
    }else if #available(macOS 13, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        guard let w = NSApp.windows.first(where: { ($0.identifier?.rawValue ?? "").contains("Settings") || $0.contentView?.className.contains("SettingsView") == true }) ?? NSApp.keyWindow else { return }
        w.setFrameAutosaveName("AirBatterySettingsWindow")
        if !w.setFrameUsingName("AirBatterySettingsWindow") { w.center() }
        w.makeKeyAndOrderFront(nil); w.orderFrontRegardless()
    }
}

func findNSSplitVIew(view: NSView?) -> NSSplitView? {
    var queue = [NSView]()
    if let root = view {
        queue.append(root)
    }
    while !queue.isEmpty {
        let current = queue.removeFirst()
        if current is NSSplitView {
            return current as? NSSplitView
        }
        for subview in current.subviews {
            queue.append(subview)
        }
    }
    return nil
}
