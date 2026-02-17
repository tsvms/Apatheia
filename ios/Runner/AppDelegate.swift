import UIKit
import Flutter
import flutter_local_notifications

@UIApplicationMain // Χρησιμοποιούμε αυτό αντί για @main για καλύτερη συμβατότητα
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // Αυτό είναι το κρίσιμο σημείο για να δουλέψουν τα κουμπιά (actions) στις ειδοποιήσεις
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
        GeneratedPluginRegistrant.register(with: registry)
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}