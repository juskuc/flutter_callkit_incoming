import Flutter
import UIKit
import CallKit
import AVFoundation
import WebRTC
import Foundation

@available(iOS 10.0, *)
public class SwiftFlutterCallkitIncomingPlugin: NSObject, FlutterPlugin, CXProviderDelegate {

    static let ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP = "com.hiennv.flutter_callkit_incoming.DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP"

    static let ACTION_CALL_INCOMING = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_INCOMING"
    static let ACTION_CALL_START = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_START"
    static let ACTION_CALL_ACCEPT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"
    static let ACTION_CALL_DECLINE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE"
    static let ACTION_CALL_ENDED = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ENDED"
    static let ACTION_CALL_TIMEOUT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TIMEOUT"
    static let ACTION_CALL_CUSTOM = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CUSTOM"

    static let ACTION_CALL_TOGGLE_HOLD = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_HOLD"
    static let ACTION_CALL_TOGGLE_MUTE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_MUTE"
    static let ACTION_CALL_TOGGLE_DMTF = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_DMTF"
    static let ACTION_CALL_TOGGLE_GROUP = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_GROUP"
    static let ACTION_CALL_TOGGLE_AUDIO_SESSION = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_AUDIO_SESSION"

    @objc public private(set) static var sharedInstance: SwiftFlutterCallkitIncomingPlugin!

    private var streamHandlers: WeakArray<EventCallbackHandler> = WeakArray([])

    private var callManager: CallManager

    private var sharedProvider: CXProvider? = nil

    private var outgoingCall : Call?
    private var answerCall : Call?

    private var data: Data?
    private var isFromPushKit: Bool = false
    private var silenceEvents: Bool = false
    private let devicePushTokenVoIP = "DevicePushTokenVoIP"

    private var activeCallUUID : UUID?
    private var endCallAction: CXEndCallAction?
    private var answerAction: CXAnswerCallAction?
    private var ringingPlayer: AVAudioPlayer?
    private var connectedPlayer: AVAudioPlayer?
    private var endedPlayer: AVAudioPlayer?
    private var reconnectPlayer: AVAudioPlayer?

    private var activatedAVAudioSession: AVAudioSession?
    private var deactivatedAVAudioSession: AVAudioSession?
    private var isVideoCall = false
    private var isCallEndedByCallkitClick = true
    private var shouldClearFile = true
    private var interrupted = false
    private var isSpeakerEnabled = false

    private func sendEvent(_ event: String, _ body: [String : Any?]?) {
        if silenceEvents {
            print(event, " silenced")
            return
        } else {
            streamHandlers.reap().forEach { handler in
                handler?.send(event, body ?? [:])
            }
        }

    }

    @objc public func sendEventCustom(_ event: String, body: NSDictionary?) {
        streamHandlers.reap().forEach { handler in
            handler?.send(event, body ?? [:])
        }
    }

    public static func sharePluginWithRegister(with registrar: FlutterPluginRegistrar) {
        if(sharedInstance == nil){
            sharedInstance = SwiftFlutterCallkitIncomingPlugin(messenger: registrar.messenger())
        }
        sharedInstance.shareHandlers(with: registrar)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        sharePluginWithRegister(with: registrar)
    }

    private static func createMethodChannel(messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
        return FlutterMethodChannel(name: "flutter_callkit_incoming", binaryMessenger: messenger)
    }

    private static func createEventChannel(messenger: FlutterBinaryMessenger) -> FlutterEventChannel {
        return FlutterEventChannel(name: "flutter_callkit_incoming_events", binaryMessenger: messenger)
    }

    public init(messenger: FlutterBinaryMessenger) {
        self.callManager = CallManager()
        super.init()

        setupNotifications()
        setupAudioPlayers()
    }

    private func setupAudioPlayers() {
        // Prepare the ringing sound player
        if let ringingUrl = Bundle(for: type(of: self)).url(forResource: "sound_outgoing_call", withExtension: "mp3") {
            do {
                ringingPlayer = try AVAudioPlayer(contentsOf: ringingUrl)
                ringingPlayer?.numberOfLoops = -1 // Loop indefinitely
            } catch {
                print("Could not load ringing sound file")
            }
        }


        // Prepare the connected sound player
        if let connectedUrl = Bundle(for: type(of: self)).url(forResource: "sound_pickup", withExtension: "mp3") {
            do {
                connectedPlayer = try AVAudioPlayer(contentsOf: connectedUrl)
                connectedPlayer?.numberOfLoops = 0 // Play once
            } catch {
                print("Could not load connected sound file")
            }
        }

        if let endedUrl = Bundle(for: type(of: self)).url(forResource: "sound_end", withExtension: "mp3") {
            do {
                endedPlayer = try AVAudioPlayer(contentsOf: endedUrl)
                endedPlayer?.numberOfLoops = 0 // Play once
            } catch {
                print("Could not load ended sound file")
            }
        }

        if let reconnectUrl = Bundle(for: type(of: self)).url(forResource: "sound_reconnecting", withExtension: "mp3") {
            do {
                reconnectPlayer = try AVAudioPlayer(contentsOf: reconnectUrl)
                reconnectPlayer?.numberOfLoops = -1 // Play once
            } catch {
                print("Could not load reconnect sound file")
            }
        }
    }

    private func shareHandlers(with registrar: FlutterPluginRegistrar) {
        registrar.addMethodCallDelegate(self, channel: Self.createMethodChannel(messenger: registrar.messenger()))
        let eventsHandler = EventCallbackHandler()
        self.streamHandlers.append(eventsHandler)
        Self.createEventChannel(messenger: registrar.messenger()).setStreamHandler(eventsHandler)
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0]
    }

    func writeToFile(content: String) {
        let fileURL = getDocumentsDirectory().appendingPathComponent("call.txt")

        // Create the file if it does not exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error writing to file: \(error)")
        }
    }

    func writeExistingCallTimestampToFile() {
        let fileURL = getDocumentsDirectory().appendingPathComponent("call_timestamp.txt")

        // Create the file if it does not exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        // Write unix timestamp in milliseconds
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            try String(timestamp).write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error writing to file: \(error)")
        }
    }

    func readCrashFlagFile() -> Bool {
        let fileURL = getDocumentsDirectory().appendingPathComponent("crash_flag.txt")

        // Check if the file exists before reading
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
              // Read if content is true or false
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                return content == "true"
            } catch {
                return false
            }
        } else {
            return false
        }
    }

    func readFromFile() -> String? {
        let fileURL = getDocumentsDirectory().appendingPathComponent("call.txt")

        // Check if the file exists before reading
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                return try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                print("Error reading file: \(error)")
                return nil
            }
        } else {
            return nil
        }
    }

    func clearFile() {
        let fileURL = getDocumentsDirectory().appendingPathComponent("call.txt")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("Error deleting file: \(error)")
            }
        }
    }

    func setValueInUserDefaults(value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.synchronize()
    }

    func retrieveFromUserDefaults(key: String) -> Any? {
        return UserDefaults.standard.value(forKey: key)
    }

    func deleteFromUserDefaults(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.synchronize()
    }

    func reconnectWebRTCAudio() {
        if (reconnectPlayer?.isPlaying == true) {
            return
        }

        reconnectPlayer?.play()
    }

    func enableWebRTCAudio(isReconnect: Bool = false) {
        // Stop ringing player
        self.reconnectPlayer?.stop()
        self.ringingPlayer?.stop()
        self.connectedPlayer?.play()

        DispatchQueue.main.asyncAfter(deadline:  .now() + 1.0) {
            let timerInterval = 100.0 // Adjust the interval in milliseconds (e.g., 100ms)
            let maxRuns = 100 // Maximum number of times to run

            var runCount = 0
            var timer: Timer?

            timer = Timer.scheduledTimer(withTimeInterval: timerInterval / 1000, repeats: true) { [weak self] _ in
                runCount += 1

                if runCount >= maxRuns {
                    self?.reconnectPlayer?.stop()
                    self?.ringingPlayer?.stop()
                    timer?.invalidate() // Stop the timer after maxRuns even if activatedAVAudioSession is still nil
                } else if let activatedAVAudioSession = self?.activatedAVAudioSession {
                    self?.reconnectPlayer?.stop()
                    self?.ringingPlayer?.stop()

                    if isReconnect {
                        RTCAudioSession.sharedInstance().audioSessionDidActivate(AVAudioSession.sharedInstance())
                    } else {
                        RTCAudioSession.sharedInstance().audioSessionDidActivate(activatedAVAudioSession)
                    }
                    RTCAudioSession.sharedInstance().isAudioEnabled = true

                    timer?.invalidate() // Stop the timer after running the code
                }
            }
        }
    }

    func disableWebRTCAudio() {
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setIsSpeakerEnabled":
            guard let args = call.arguments as? [String: Any] ,
                  let isSpeakerEnabled = args["isSpeakerEnabled"] as? Bool else {
                result("OK")
                return
            }
            self.isSpeakerEnabled = isSpeakerEnabled

            defineAndSetOutput()
            result("OK")
            break
        case "clearActiveCallUUID":
            self.activeCallUUID = nil
            result("OK")
            break
        case "setActiveCallUUID":
            guard let args = call.arguments as? [String: Any] ,
                  let callId = args["id"] as? String else {
                result("OK")
                return
            }

            if (self.activeCallUUID != nil) {
                result(false)
                return
            }

            self.activeCallUUID = UUID(uuidString: callId)
            result(true)
            break
        case "getActiveCallUUID":
            result(self.activeCallUUID?.uuidString.lowercased())
            break
        case "exit":
            exit(0)
            break
        case "reconnectWebRTCAudio":
            reconnectWebRTCAudio()
            result("OK")
            break
        case "enableWebRTCAudio":
            guard let args = call.arguments as? [String: Any] ,
                  let isReconnect = args["isReconnect"] as? Bool else {
                result("OK")
                return
            }
            enableWebRTCAudio(isReconnect: isReconnect)
            result("OK")
            break
        case "disableWebRTCAudio":
            disableWebRTCAudio()
            result("OK")
            break
        case "setValueInUserDefaults":
            guard let args = call.arguments as? [String: Any] ,
                  let value = args["value"] as? String,
                  let key = args["key"] as? String else {
                result("OK")
                return
            }
            writeToFile(content: value)
            result("OK")
            break
        case "showCallkitIncoming":
           RTCAudioSession.sharedInstance().useManualAudio = true
           RTCAudioSession.sharedInstance().isAudioEnabled = false

            guard let args = call.arguments else {
                result("OK")
                return
            }
            if let getArgs = args as? [String: Any] {
                self.data = Data(args: getArgs)
                let callerRegistrationId = getArgs["callerRegistrationId"] as? String ?? ""
                let completion = getArgs["completion"] as? ((Error?) -> Void)? ?? nil
                showCallkitIncoming(self.data!, fromPushKit: false, callerRegistrationId: callerRegistrationId, completion: completion)
            }
            result("OK")
            break
        case "showMissCallNotification":
            result("OK")
            break
        case "startCall":
            guard let args = call.arguments else {
                result("OK")
                return
            }

            self.isCallEndedByCallkitClick = true

            if let getArgs = args as? [String: Any] {
                self.data = Data(args: getArgs["params"] as! [String: Any])
                let callId = getArgs["callId"] as? String ?? ""
                self.isVideoCall = self.data!.type > 0 ? true : false
                self.isSpeakerEnabled = self.isVideoCall
                if (self.activeCallUUID != nil) {
                    self.callManager.endCallAlls()
                }

                configureRTCAudioSession(isVideoCall: self.isVideoCall)
                self.ringingPlayer?.stop()
                self.ringingPlayer?.play()

                self.activeCallUUID = UUID(uuidString: callId)

                self.startCall(self.data!, fromPushKit: false)
            }
            result("OK")
            break
        case "endCall":
            self.isCallEndedByCallkitClick = false
            guard let args = call.arguments else {
                result("OK")
                return
            }
            if (self.isFromPushKit){
                self.endCall(self.data!)
            } else{
                if let getArgs = args as? [String: Any] {
                    self.data = Data(args: getArgs)
                    self.endCall(self.data!)
                }
            }
            result("OK")
            break
        case "muteCall":
            guard let args = call.arguments as? [String: Any] ,
                  let callId = args["id"] as? String,
                  let isMuted = args["isMuted"] as? Bool else {
                result("OK")
                return
            }

            self.muteCall(callId, isMuted: isMuted)
            result("OK")
            break
        case "isMuted":
            guard let args = call.arguments as? [String: Any] ,
                  let callId = args["id"] as? String else{
                result(false)
                return
            }
            guard let callUUID = UUID(uuidString: callId),
                  let call = self.callManager.callWithUUID(uuid: callUUID) else {
                result(false)
                return
            }
            result(call.isMuted)
            break
        case "holdCall":
            guard let args = call.arguments as? [String: Any] ,
                  let callId = args["id"] as? String,
                  let onHold = args["isOnHold"] as? Bool else {
                result("OK")
                return
            }
            self.holdCall(callId, onHold: onHold)
            result("OK")
            break
        case "fulfillEndCall":
            if (self.shouldClearFile) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.clearFile()
                    self.endCallAction?.fulfill()
                    self.endCallAction = nil
                }
                result("OK")
                return
            }

            self.endCallAction?.fulfill()
            self.endCallAction = nil
            result("OK")
        case "callConnected":
            guard let args = call.arguments else {
                result("OK")
                return
            }
            if(self.isFromPushKit){
                self.connectedCall(self.data!)
            }else{
                if let getArgs = args as? [String: Any] {
                    self.data = Data(args: getArgs)
                    self.connectedCall(self.data!)
                }
            }
            result("OK")
            break
        case "toggleSpeaker":
            guard let args = call.arguments as? [String: Any] ,
                  let isOn = args["isOn"] as? Bool else {
                result("OK")
                return
            }
            toggleAudioRoute(toSpeaker: isOn)
            result("OK")
            break
        case "activeCalls":
            result(self.callManager.activeCalls())
            break;
        case "endAllCalls":
            self.isCallEndedByCallkitClick = false
            self.callManager.endCallAlls()
            result("OK")
            break
        case "getDevicePushTokenVoIP":
            result(self.getDevicePushTokenVoIP())
            break;
        case "startCallIncoming":
            self.answerAction?.fulfill()
            result("OK")
            break
        case "silenceEvents":
            guard let silence = call.arguments as? Bool else {
                result("OK")
                return
            }

            self.silenceEvents = silence
            result("OK")
            break;
        case "requestNotificationPermission":
            result("OK")
            break
        case "hideCallkitIncoming":
            result("OK")
            break
        case "endNativeSubsystemOnly":
            result("OK")
            break
        case "setAudioRoute":
            result("OK")
            break
        case "updateCallerName":
            // Christmas tree :PP
            if let args = call.arguments as? [String: Any] {


                if let callId = args["id"] as? String {


                    if let nameCaller = args["callerName"] as? String {


                        let callUpdate = CXCallUpdate()
                        callUpdate.localizedCallerName = nameCaller

                        if let uuid = UUID(uuidString: callId) {
                            self.sharedProvider?.reportCall(with: uuid, updated: callUpdate)
                            result("OK")
                        } else {

                            // Handle invalid UUID string
                        }
                    } else {

                        // Handle case where callerName is not a string
                    }
                } else {

                    // Handle case where id is not a string
                }
            } else {

                // Handle case where arguments are not a dictionary
            }
            break
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @objc public func setDevicePushTokenVoIP(_ deviceToken: String) {
        UserDefaults.standard.set(deviceToken, forKey: devicePushTokenVoIP)
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP, ["deviceTokenVoIP":deviceToken])
    }

    @objc public func getDevicePushTokenVoIP() -> String {
        return UserDefaults.standard.string(forKey: devicePushTokenVoIP) ?? ""
    }

    @objc public func getAcceptedCall() -> Data? {
        NSLog("Call data ids \(String(describing: data?.uuid)) \(String(describing: answerCall?.uuid.uuidString))")
        if data?.uuid.lowercased() == answerCall?.uuid.uuidString.lowercased() {
            return data
        }
        return nil
    }

    @objc public func showCallkitIncoming(
        _ data: Data,
        fromPushKit: Bool,
        callerRegistrationId: String,
        completion: ((Error?) -> Void)?
    ) {
        let uuid = UUID(uuidString: data.uuid)

        let isCrashFlagExisting = readCrashFlagFile()

        if (isCrashFlagExisting) {
            activeCallUUID = nil
        }

        if (activeCallUUID != nil)  {
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.onSilentlyReject(callerRegistrationId: callerRegistrationId, rejectedCallUUID: uuid!.uuidString)
            }

            self.sharedProvider?.reportCall(with: uuid!, endedAt: Date(), reason: .answeredElsewhere)

            completion?(nil)
            return
        }
        self.activeCallUUID = uuid
        writeExistingCallTimestampToFile()
        writeToFile(content: callerRegistrationId)
        self.isVideoCall = data.type > 0 ? true : false
        self.isSpeakerEnabled = self.isVideoCall

        self.isFromPushKit = fromPushKit
        if(fromPushKit){
            self.data = data
        }

        var handle: CXHandle?
        handle = CXHandle(type: self.getHandleType(data.handleType), value: data.getEncryptHandle())

        let callUpdate = CXCallUpdate()
        callUpdate.remoteHandle = handle
        callUpdate.supportsDTMF = data.supportsDTMF
        callUpdate.supportsHolding = data.supportsHolding
        callUpdate.supportsGrouping = data.supportsGrouping
        callUpdate.supportsUngrouping = data.supportsUngrouping
        callUpdate.hasVideo = data.type > 0 ? true : false
        callUpdate.localizedCallerName = data.nameCaller

        self.sharedProvider?.reportNewIncomingCall(with: uuid!, update: callUpdate) { error in
            completion?(error)

            if(error == nil) {
                let call = Call(uuid: uuid!, data: data)
                call.handle = data.handle
                self.callManager.addCall(call)
                self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_INCOMING, data.toJSON())
                self.endCallNotExist(data)
            } else {
                NSLog("[FLUTTER] [SWIFT] Report new incoming call completion, error: \(String(describing: error))")
            }
        }
    }

    @objc public func startCall(_ data: Data, fromPushKit: Bool) {
        self.isVideoCall = data.type > 0 ? true : false
        self.isFromPushKit = fromPushKit
        if(fromPushKit){
            self.data = data
        }
        self.callManager.startCall(data)
    }

    @objc public func muteCall(_ callId: String, isMuted: Bool) {
        guard let callId = UUID(uuidString: callId),
              let call = self.callManager.callWithUUID(uuid: callId) else {
            return
        }
        if call.isMuted == isMuted {
            self.sendMuteEvent(callId.uuidString, isMuted)
        } else {
            self.callManager.muteCall(call: call, isMuted: isMuted)
        }
    }

    @objc public func holdCall(_ callId: String, onHold: Bool) {
        guard let callId = UUID(uuidString: callId),
              let call = self.callManager.callWithUUID(uuid: callId) else {
            return
        }
        if call.isOnHold == onHold {
            self.sendMuteEvent(callId.uuidString,  onHold)
        } else {
            self.callManager.holdCall(call: call, onHold: onHold)
        }
    }

    @objc public func endCall(_ data: Data) {
        var call: Call? = nil
        if(self.isFromPushKit){
            call = Call(uuid: UUID(uuidString: self.data!.uuid)!, data: data)
            self.isFromPushKit = false
            self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, data.toJSON())
        }else {
            call = Call(uuid: UUID(uuidString: data.uuid)!, data: data)
        }
        self.callManager.endCall(call: call!)
    }

    @objc public func connectedCall(_ data: Data) {
        var call: Call? = nil
        if(self.isFromPushKit){
            call = Call(uuid: UUID(uuidString: self.data!.uuid)!, data: data)
            self.isFromPushKit = false
        }else {
            call = Call(uuid: UUID(uuidString: data.uuid)!, data: data)
        }
        self.callManager.connectedCall(call: call!)
    }

    @objc public func activeCalls() -> [[String: Any]] {
        return self.callManager.activeCalls()
    }

    @objc public func endAllCalls() {
        self.isFromPushKit = false
        self.callManager.endCallAlls()
    }

    public func saveEndCall(_ uuid: String, _ reason: Int) {
        switch reason {
        case 1:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.failed)
            break
        case 2, 6:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.remoteEnded)
            break
        case 3:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.unanswered)
            break
        case 4:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.answeredElsewhere)
            break
        case 5:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.declinedElsewhere)
            break
        default:
            break
        }
    }


    func endCallNotExist(_ data: Data) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(data.duration)) {
            let call = self.callManager.callWithUUID(uuid: UUID(uuidString: data.uuid)!)
            if (call != nil && self.answerCall == nil && self.outgoingCall == nil) {
                self.callEndTimeout(data)
            }
        }
    }



    func callEndTimeout(_ data: Data) {
        self.activeCallUUID = nil
        self.saveEndCall(data.uuid, 3)
        guard let call = self.callManager.callWithUUID(uuid: UUID(uuidString: data.uuid)!) else {
            return
        }
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, data.toJSON())
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onMissedCall()
            appDelegate.onTimeOut(call)
        }
    }

    func getHandleType(_ handleType: String?) -> CXHandle.HandleType {
        var typeDefault = CXHandle.HandleType.generic
        switch handleType {
        case "number":
            typeDefault = CXHandle.HandleType.phoneNumber
            break
        case "email":
            typeDefault = CXHandle.HandleType.emailAddress
        default:
            typeDefault = CXHandle.HandleType.generic
        }
        return typeDefault
    }

    public func createCXProvider() {
        let configuration = CXProviderConfiguration(localizedName: "Skyda")

        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1

        configuration.supportedHandleTypes = [
            CXHandle.HandleType.generic,
            CXHandle.HandleType.emailAddress,
            CXHandle.HandleType.phoneNumber
        ]

        if let image = UIImage(named: "CallKitLogo") {
            configuration.iconTemplateImageData = image.pngData()
        }

        let provider = CXProvider(configuration: configuration)
        provider.setDelegate(self, queue: nil)
        self.sharedProvider = provider
        self.callManager.setSharedProvider(provider)
    }

    func createConfiguration(_ data: Data) -> CXProviderConfiguration {
        let configuration = CXProviderConfiguration(localizedName: data.appName)
        configuration.supportsVideo = data.supportsVideo
        configuration.maximumCallGroups = data.maximumCallGroups
        configuration.maximumCallsPerCallGroup = data.maximumCallsPerCallGroup

        configuration.supportedHandleTypes = [
            CXHandle.HandleType.generic,
            CXHandle.HandleType.emailAddress,
            CXHandle.HandleType.phoneNumber
        ]
        if #available(iOS 11.0, *) {
            configuration.includesCallsInRecents = data.includesCallsInRecents
        }
        if !data.iconName.isEmpty {
            if let image = UIImage(named: data.iconName) {
                configuration.iconTemplateImageData = image.pngData()
            } else {
                print("Unable to load icon \(data.iconName).");
            }
        }
        if !data.ringtonePath.isEmpty || data.ringtonePath != "system_ringtone_default"  {
            configuration.ringtoneSound = data.ringtonePath
        }
        return configuration
    }

    func sendDefaultAudioInterruptionNofificationToStartAudioResource(){
        //         var userInfo : [AnyHashable : Any] = [:]
        //         let intrepEndeRaw = AVAudioSession.InterruptionType.ended.rawValue
        //         userInfo[AVAudioSessionInterruptionTypeKey] = intrepEndeRaw
        //         userInfo[AVAudioSessionInterruptionOptionKey] = AVAudioSession.InterruptionOptions.shouldResume.rawValue
        //         NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: self, userInfo: userInfo)
    }

    func configureRTCAudioSession(isVideoCall: Bool){
        let session = RTCAudioSession.sharedInstance()

        var options: AVAudioSession.CategoryOptions = []

        if isVideoCall {
            options.insert(.defaultToSpeaker)
        }

        options.insert(.allowBluetoothA2DP)
        options.insert(.allowAirPlay)
        options.insert(.allowBluetooth)

        do {
            session.lockForConfiguration()
            try session.setCategory(AVAudioSession.Category.playAndRecord.rawValue, with: options)
            if isVideoCall {
                try session.setMode(AVAudioSession.Mode.videoChat.rawValue)
            } else {
                try session.setMode(AVAudioSession.Mode.voiceChat.rawValue)
            }
            try session.setPreferredSampleRate(data?.audioSessionPreferredSampleRate ?? 44100.0)
            try session.setPreferredIOBufferDuration(data?.audioSessionPreferredIOBufferDuration ?? 0.005)
            try session.overrideOutputAudioPort(isVideoCall ? .speaker : .none)
            session.unlockForConfiguration()
        } catch {
            print("Error setting audio session properties: \(error)")
        }
    }

    func toggleAudioRoute(toSpeaker: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            let output = toSpeaker ? AVAudioSession.PortOverride.speaker : .none
            try session.setCategory(AVAudioSession.Category.playAndRecord, options: [
                .allowBluetoothA2DP, .allowAirPlay, .allowBluetooth])

            try session.overrideOutputAudioPort(output)
            try session.setActive(true)
            NSLog("done overriding audio port to speaker: \(toSpeaker)")
        } catch {
            print("Failed to toggle audio route: \(error)")
        }
    }

    func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do{
            try session.setActive(false)
        } catch{
            NSLog("flutter: deactivateAudioSession() Error setting audio session properties: \(error)")
            print(error)
        }
    }

    func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do{
            try session.setActive(true)
        } catch{
            NSLog("flutter: activateAudioSession() Error setting audio session properties: \(error)")
            print(error)
        }
    }

    func getAudioSessionMode(_ audioSessionMode: String?) -> AVAudioSession.Mode {
        var mode = AVAudioSession.Mode.default
        switch audioSessionMode {
        case "gameChat":
            mode = AVAudioSession.Mode.gameChat
            break
        case "measurement":
            mode = AVAudioSession.Mode.measurement
            break
        case "moviePlayback":
            mode = AVAudioSession.Mode.moviePlayback
            break
        case "spokenAudio":
            mode = AVAudioSession.Mode.spokenAudio
            break
        case "videoChat":
            mode = AVAudioSession.Mode.videoChat
            break
        case "videoRecording":
            mode = AVAudioSession.Mode.videoRecording
            break
        case "voiceChat":
            mode = AVAudioSession.Mode.voiceChat
            break
        case "voicePrompt":
            if #available(iOS 12.0, *) {
                mode = AVAudioSession.Mode.voicePrompt
            } else {
                // Fallback on earlier versions
            }
            break
        default:
            mode = AVAudioSession.Mode.default
        }
        return mode
    }

    public func providerDidBegin(_ provider: CXProvider) {

    }

    public func providerDidReset(_ provider: CXProvider) {
        for call in self.callManager.calls {
            call.endCall()
        }
        self.callManager.removeAllCalls()
    }

    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let call = Call(uuid: action.callUUID, data: self.data!, isOutGoing: true)
        call.handle = action.handle.value
        call.hasStartedConnectDidChange = { [weak self] in
            self?.sharedProvider?.reportOutgoingCall(with: call.uuid, startedConnectingAt: call.connectData)
        }
        call.hasConnectDidChange = { [weak self] in
            self?.sharedProvider?.reportOutgoingCall(with: call.uuid, connectedAt: call.connectedData)
        }
        self.outgoingCall = call;
        self.callManager.addCall(call)
        action.fulfill()
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_START, self.data?.toJSON())
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else{
            action.fail()
            return
        }
        call.hasConnectDidChange = { [weak self] in
            self?.sharedProvider?.reportOutgoingCall(with: call.uuid, connectedAt: call.connectedData)
        }
        self.answerCall = call
        self.answerAction = action
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ACCEPT, self.data?.toJSON())
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onAccept(call)
        }
    }


    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        self.shouldClearFile = false
        let isEndedByMeThroughCallkit = isCallEndedByCallkitClick
        self.isCallEndedByCallkitClick = true
        ringingPlayer?.stop()
        self.activeCallUUID = nil
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else {
            if(self.answerCall == nil && self.outgoingCall == nil){
                sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, self.data?.toJSON())
            } else {
                sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, self.data?.toJSON())
            }
            action.fulfill()
            self.outgoingCall = nil
            return
        }
        call.endCall()
        self.endCallAction = action
        self.callManager.removeCall(call)
        if (self.answerCall == nil && self.outgoingCall == nil) {
            sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_DECLINE, self.data?.toJSON())
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                if (isEndedByMeThroughCallkit) {
                    let callerRegistrationId = readFromFile()
                    self.shouldClearFile = true
                    appDelegate.onDecline(callerRegistrationId: callerRegistrationId ?? "", declinedCallUUID: action.callUUID.uuidString.lowercased())
                } else {
                    appDelegate.onMissedCall();
                }
            }
        } else {
            sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, call.data.toJSON())
            if (isEndedByMeThroughCallkit) {
                if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                    let callerRegistrationId = readFromFile()
                    self.shouldClearFile = true
                    appDelegate.onEnd(callerRegistrationId: callerRegistrationId ?? "", endedCallUUID: action.callUUID.uuidString.lowercased())
                }
            } else {
                action.fulfill()
            }
        }

        self.outgoingCall = nil
    }


    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }
        call.isOnHold = action.isOnHold
        call.isMuted = action.isOnHold
        self.callManager.setHold(call: call, onHold: action.isOnHold)
        sendHoldEvent(action.callUUID.uuidString, action.isOnHold)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }
        call.isMuted = action.isMuted
        sendMuteEvent(action.callUUID.uuidString, action.isMuted)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
        guard (self.callManager.callWithUUID(uuid: action.callUUID)) != nil else {
            action.fail()
            return
        }
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_GROUP, [ "id": action.callUUID.uuidString, "callUUIDToGroupWith" : action.callUUIDToGroupWith?.uuidString])
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        guard (self.callManager.callWithUUID(uuid: action.callUUID)) != nil else {
            action.fail()
            return
        }
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_DMTF, [ "id": action.callUUID.uuidString, "digits": action.digits, "type": action.type ])
        action.fulfill()
    }


    public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.uuid) else {
            action.fail()
            return
        }
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, self.data?.toJSON())
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onTimeOut(call)
        }
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.sendLog("AudioSession didActivate", data: [])
        }
        activatedAVAudioSession = audioSession

        if (self.outgoingCall != nil) {
            self.ringingPlayer?.stop()
            self.ringingPlayer?.play()
        }

        if (self.answerCall != nil) {
            self.connectedPlayer?.play()
        }

        self.outgoingCall?.startCall(withAudioSession: audioSession) {success in
            if success {
                self.callManager.addCall(self.outgoingCall!)
                self.outgoingCall?.startAudio()
            }
        }

        self.answerCall?.ansCall(withAudioSession: audioSession) { success in
            if success{
                self.answerCall?.startAudio()
            }
        }
        sendDefaultAudioInterruptionNofificationToStartAudioResource()

        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_AUDIO_SESSION, [ "isActivate": true ])
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        let audioSession = AVAudioSession.sharedInstance()
        endedPlayer?.play()

        self.outgoingCall?.endCall()
        if(self.outgoingCall != nil){
            self.outgoingCall = nil
        }

        self.answerCall?.endCall()
        if(self.answerCall != nil){
            self.answerCall = nil
        }

        self.callManager.removeAllCalls()

        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = false

        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.didDeactivateAudioSession(audioSession)
        }
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_AUDIO_SESSION, [ "isActivate": false ])
    }

    private func sendMuteEvent(_ id: String, _ isMuted: Bool) {
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_MUTE, [ "id": id, "isMuted": isMuted ])
    }

    private func sendHoldEvent(_ id: String, _ isOnHold: Bool) {
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_HOLD, [ "id": id, "isOnHold": isOnHold ])
    }

    func setupNotifications() {
        // Get the default notification center instance.
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(handleRouteChange),
                       name: AVAudioSession.routeChangeNotification,
                       object: nil)
    }


    @objc func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        guard let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .override:
            /*checkIfInterruptionUnhandled*/()
        case .oldDeviceUnavailable, .newDeviceAvailable:
            defineAndSetOutput()
        case .categoryChange:
            break
        default:
            break
        }

        if (reason != .override) {
            defineAndSetOutput()
        }


        let rtcSession = RTCAudioSession.sharedInstance()

        if !interrupted,
           rtcSession.category != AVAudioSession.Category.playAndRecord.rawValue {
            NSLog("rtc session category is not playAndRecord")
        }
    }

    func checkIfInterruptionUnhandled() {
          guard interrupted else { return }
          defineAndSetOutput()
      }


    private func defineAndSetOutput() {
        let rtcSession = RTCAudioSession.sharedInstance()
        do {
            rtcSession.lockForConfiguration()
            if self.isSpeakerEnabled {
                 setOutputToSpeaker()
            } else {
                setOutputToDevice()
            }
            rtcSession.unlockForConfiguration()
        } catch {
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.sendLog("defineAndSetOutput error: \(error)", data: [])
            }
            NSLog("defineAndSetOutput error: \(error)")
        }
   }

   private func setOutputToDevice() {
       let rtcSession = RTCAudioSession.sharedInstance()
       do {
           try rtcSession.overrideOutputAudioPort(.none)
       } catch {
           if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
               appDelegate.sendLog("RTC setOutputToDevice error: \(error)", data: [])
           }
           NSLog("setOutputToDevice error: \(error)")
       }

       let audioSession = AVAudioSession.sharedInstance()

       do {
            try audioSession.overrideOutputAudioPort(.none)
       } catch {
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                 appDelegate.sendLog("AV setOutputToDevice error: \(error)", data: [])
            }
            NSLog("setOutputToDevice error: \(error)")
       }
   }

   func setOutputToSpeaker() {
       let rtcSession = RTCAudioSession.sharedInstance()
       do {
           try rtcSession.overrideOutputAudioPort(.speaker)
       } catch {
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                 appDelegate.sendLog("RTC setOutputToSpeaker error: \(error)", data: [])
            }
           NSLog("setOutputToSpeaker error: \(error)")
       }

       let audioSession = AVAudioSession.sharedInstance()

       do {
            try audioSession.overrideOutputAudioPort(.speaker)
       } catch {
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                 appDelegate.sendLog("AV setOutputToSpeaker error: \(error)", data: [])
            }
            NSLog("setOutputToSpeaker error: \(error)")
       }
   }
}

class EventCallbackHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    public func send(_ event: String, _ body: Any) {
        let data: [String : Any] = [
            "event": event,
            "body": body
        ]
        eventSink?(data)
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
