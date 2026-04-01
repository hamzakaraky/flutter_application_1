import UIKit
import Flutter
import CoreLocation
import UserNotifications

@objc class AppDelegate: FlutterAppDelegate {

    // MARK: - Constants
    private let beaconUUID  = UUID(uuidString: "FDA50693-A4E2-4FB1-AFCF-C6EB07647825")!
    private let beaconMajor: CLBeaconMajorValue = 1
    private let beaconMinor: CLBeaconMinorValue = 1
    private let regionID    = "com.smartroom.beacon.region"
    private let channelName = "com.smartroom/focus"

    // MARK: - State
    private var channel: FlutterMethodChannel?
    private let locationManager = CLLocationManager()
    private var debounceEnterTimer: Timer?
    private var debounceExitTimer:  Timer?
    private var currentlyInRoom = false

    // MARK: - Application Lifecycle ✅ الترتيب الذهبي
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // 1. أول شيء: سجّل Flutter لضمان رسم الشاشة فوراً
        GeneratedPluginRegistrant.register(with: self)

        // 2. ابدأ Flutter
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        // 3. كل منطق البيكون بعد ما Flutter يستقر
        DispatchQueue.main.async {
            self.setupFlutterChannel()
            self.setupLocationManager()
            self.setupNotificationCenter()
            self.startBeaconMonitoring()
        }

        return result
    }

    // MARK: - Flutter Channel
    private func setupFlutterChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            print("[SmartSilent] ⚠️ FlutterViewController not ready")
            return
        }

        channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: controller.binaryMessenger
        )

        channel?.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "startMonitoring":
                self.startBeaconMonitoring()
                result(true)
            case "stopMonitoring":
                self.stopBeaconMonitoring()
                result(true)
            case "requestAlwaysPermission":
                self.locationManager.requestAlwaysAuthorization()
                result(true)
            case "getCurrentState":
                result(self.currentlyInRoom ? "detected" : "scanning")
            case "openShortcuts":
                if let url = URL(string: "shortcuts://") {
                    UIApplication.shared.open(url)
                }
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - CoreLocation
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates    = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - Beacon Monitoring
    private func startBeaconMonitoring() {
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            locationManager.requestAlwaysAuthorization()
            return
        }

        let region = CLBeaconRegion(
            uuid: beaconUUID,
            major: beaconMajor,
            minor: beaconMinor,
            identifier: regionID
        )
        region.notifyOnEntry             = true
        region.notifyOnExit              = true
        region.notifyEntryStateOnDisplay = true

        locationManager.startMonitoring(for: region)
        locationManager.requestState(for: region)
        print("[SmartSilent] ✅ Monitoring started")
    }

    private func stopBeaconMonitoring() {
        locationManager.monitoredRegions.forEach {
            locationManager.stopMonitoring(for: $0)
        }
    }

    // MARK: - Debounce
    private func scheduleRoomEntered() {
        debounceExitTimer?.invalidate()
        guard !currentlyInRoom else { return }
        debounceEnterTimer?.invalidate()
        debounceEnterTimer = Timer.scheduledTimer(
            withTimeInterval: 5.0,
            repeats: false
        ) { [weak self] _ in
            self?.applyRoomEntered()
        }
    }

    private func scheduleRoomExited() {
        debounceEnterTimer?.invalidate()
        guard currentlyInRoom else { return }
        debounceExitTimer?.invalidate()
        debounceExitTimer = Timer.scheduledTimer(
            withTimeInterval: 8.0,
            repeats: false
        ) { [weak self] _ in
            self?.applyRoomExited()
        }
    }

    // MARK: - State Application
    private func applyRoomEntered() {
        currentlyInRoom = true
        DispatchQueue.main.async {
            self.channel?.invokeMethod("onRoomEntered", arguments: nil)
        }
        sendNotification(
            id:       "room_entered",
            title:    "🔇 Smart Room Detected",
            body:     "Tap to activate silent mode via Shortcuts.",
            category: "BEACON_ENTERED"
        )
    }

    private func applyRoomExited() {
        currentlyInRoom = false
        DispatchQueue.main.async {
            self.channel?.invokeMethod("onRoomExited", arguments: nil)
        }
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["room_entered"])
        sendNotification(
            id:       "room_exited",
            title:    "🔔 Left Smart Room",
            body:     "Sound restored to normal.",
            category: "BEACON_EXITED"
        )
    }

    // MARK: - Notifications
    private func setupNotificationCenter() {
        UNUserNotificationCenter.current().delegate = self

        let activateAction = UNNotificationAction(
            identifier: "ACTIVATE_FOCUS",
            title:      "🔇 Open Shortcuts",
            options:    [.foreground]
        )
        let enteredCategory = UNNotificationCategory(
            identifier:        "BEACON_ENTERED",
            actions:           [activateAction],
            intentIdentifiers: [],
            options:           .customDismissAction
        )
        let exitedCategory = UNNotificationCategory(
            identifier:        "BEACON_EXITED",
            actions:           [],
            intentIdentifiers: [],
            options:           []
        )
        UNUserNotificationCenter.current()
            .setNotificationCategories([enteredCategory, exitedCategory])

        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            print("[SmartSilent] Notifications granted: \(granted)")
        }
    }

    private func sendNotification(
        id: String,
        title: String,
        body: String,
        category: String
    ) {
        let content                = UNMutableNotificationContent()
        content.title              = title
        content.body               = body
        content.categoryIdentifier = category
        content.sound              = .default

        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id])

        let request = UNNotificationRequest(
            identifier: id,
            content:    content,
            trigger:    nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - CLLocationManagerDelegate
extension AppDelegate: CLLocationManagerDelegate {

    func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard region.identifier == regionID else { return }
        print("[SmartSilent] 📍 Entered region")
        scheduleRoomEntered()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        guard region.identifier == regionID else { return }
        print("[SmartSilent] 📍 Exited region")
        scheduleRoomExited()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didDetermineState state: CLRegionState,
        for region: CLRegion
    ) {
        guard region.identifier == regionID else { return }
        switch state {
        case .inside:
            scheduleRoomEntered()
        case .outside:
            if currentlyInRoom { scheduleRoomExited() }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            startBeaconMonitoring()
        }
        let s: String
        switch status {
        case .authorizedAlways:    s = "always"
        case .authorizedWhenInUse: s = "whenInUse"
        case .denied, .restricted: s = "denied"
        default:                   s = "notDetermined"
        }
        DispatchQueue.main.async {
            self.channel?.invokeMethod("onPermissionChanged", arguments: s)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        print("[SmartSilent] ❌ \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.channel?.invokeMethod("onError", arguments: error.localizedDescription)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "ACTIVATE_FOCUS" {
            if let url = URL(string: "shortcuts://") {
                UIApplication.shared.open(url)
            }
        }
        completionHandler()
    }
}

                                