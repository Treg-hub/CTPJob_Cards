import Flutter
import UIKit
import CoreLocation
import FirebaseFirestore
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate {
  private let channelName = "ctp/geofence"
  private var locationManager: CLLocationManager?
  private var currentClockNo: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    locationManager = CLLocationManager()
    locationManager?.delegate = self
    locationManager?.requestAlwaysAuthorization()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: engineBridge.binaryMessenger)
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "startGeofence":
        if let args = call.arguments as? [String: Any],
           let clockNo = args["clockNo"] as? String,
           let lat = args["lat"] as? Double,
           let lng = args["lng"] as? Double,
           let radius = args["radius"] as? Double {
          self?.startGeofence(clockNo: clockNo, lat: lat, lng: lng, radius: radius, result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing arguments", details: nil))
        }
      case "stopGeofence":
        self?.stopGeofence(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startGeofence(clockNo: String, lat: Double, lng: Double, radius: Double, result: FlutterResult) {
    currentClockNo = clockNo
    let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
    let region = CLCircularRegion(center: center, radius: radius, identifier: "company_geofence_\(clockNo)")
    region.notifyOnEntry = true
    region.notifyOnExit = true

    locationManager?.startMonitoring(for: region)
    result("Geofence started")
  }

  private func stopGeofence(result: FlutterResult) {
    if let regions = locationManager?.monitoredRegions {
      for region in regions {
        if region.identifier.hasPrefix("company_geofence_") {
          locationManager?.stopMonitoring(for: region)
        }
      }
    }
    result("Geofence stopped")
  }

  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    if region.identifier.hasPrefix("company_geofence_") {
      updateFirestoreAndNotify(entering: true)
    }
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    if region.identifier.hasPrefix("company_geofence_") {
      updateFirestoreAndNotify(entering: false)
    }
  }

  private func updateFirestoreAndNotify(entering: Bool) {
    guard let clockNo = currentClockNo else { return }

    let db = Firestore.firestore()
    db.collection("employees").document(clockNo).updateData(["isOnSite": entering]) { error in
      if let error = error {
        print("Error updating Firestore: \(error)")
      }
      // Send local notification regardless
      self.sendLocalNotification(entering: entering)
    }
  }

  private func sendLocalNotification(entering: Bool) {
    let content = UNMutableNotificationContent()
    content.title = entering ? "✅ On-Site Detected" : "📍 Left Site Area"
    content.body = entering ? "Within 2km of CTP. Ready for jobs." : "Off-site. Filtering updated."
    content.sound = .default

    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("Error sending notification: \(error)")
      }
    }
  }
}
