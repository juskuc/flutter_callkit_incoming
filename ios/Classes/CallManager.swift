//
//  CallManager.swift
//  flutter_callkit_incoming
//
//  Created by Hien Nguyen on 07/10/2021.
//

import Foundation
import CallKit

@available(iOS 10.0, *)
class CallManager: NSObject {
    
    let callController = CXCallController()
    private var sharedProvider: CXProvider? = nil
    private(set) var calls = [Call]()
    
    public override init() {
        super.init()
    }
    
    
    func setSharedProvider(_ sharedProvider: CXProvider) {
        self.sharedProvider = sharedProvider
    }

    func updateCallerName(uuid: UUID, callerName: String) {
        let callUpdate = CXCallUpdate()
        callUpdate.localizedCallerName = callerName
        self.sharedProvider?.reportCall(with: uuid, updated: callUpdate)
    }
    
    func startCall(_ data: Data) {
        let handle = CXHandle(type: .generic, value: data.nameCaller)
        let uuid = UUID(uuidString: data.uuid)
        let startCallAction = CXStartCallAction(call: uuid!, handle: handle)
        startCallAction.isVideo = data.type > 0
        let callTransaction = CXTransaction(action: startCallAction)

        self.requestCall(callTransaction)
    }
    
    func muteCall(call: Call, isMuted: Bool) {
        let muteAction = CXSetMutedCallAction(call: call.uuid, muted: isMuted)
        let callTransaction = CXTransaction()
        callTransaction.addAction(muteAction)
        self.requestCall(callTransaction)
    }
    
    func holdCall(call: Call, onHold: Bool) {
        let muteAction = CXSetHeldCallAction(call: call.uuid, onHold: onHold)
        let callTransaction = CXTransaction()
        callTransaction.addAction(muteAction)
        self.requestCall(callTransaction)
    }
    
    func endCall(call: Call) {
        let endCallAction = CXEndCallAction(call: call.uuid)
        let callTransaction = CXTransaction()
        callTransaction.addAction(endCallAction)
        self.requestCall(callTransaction)
    }
    
    func connectedCall(call: Call) {
        let callItem = self.callWithUUID(uuid: call.uuid)
        callItem?.connectedCall(completion: nil)
    }
    
    func endCallAlls() {
        let calls = callController.callObserver.calls
        for call in calls {
            let endCallAction = CXEndCallAction(call: call.uuid)
            let callTransaction = CXTransaction(action: endCallAction)

            self.requestCall(callTransaction)
        }
    }
    
    func activeCalls() -> [[String: Any]] {
        let calls = callController.callObserver.calls
        var json = [[String: Any]]()
        for call in calls {
            let callItem = self.callWithUUID(uuid: call.uuid)
            if(callItem != nil){
                let item: [String: Any] = callItem!.data.toJSON()
                json.append(item)
            }else {
                let item: [String: String] = ["id": call.uuid.uuidString]
                json.append(item)
            }
        }
        return json
    }
    
    
    func setHold(call: Call, onHold: Bool) {
        let handleCall = CXSetHeldCallAction(call: call.uuid, onHold: onHold)
        let callTransaction = CXTransaction()
        callTransaction.addAction(handleCall)
        //requestCall
    }
    
    
    private func requestCall(_ transaction: CXTransaction) {
        callController.request(transaction){ error in
            if let error = error {
                print("[FLUTTER][requestTransaction] Error: \(error.localizedDescription)")
            }
        }
    }
    
    
    private func getHandleType(_ handleType: String?) -> CXHandle.HandleType {
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
    
    
    static let callsChangedNotification = Notification.Name("CallsChangedNotification")
    var callsChangedHandler: (() -> Void)?
    
    func callWithUUID(uuid: UUID) -> Call?{
        guard let idx = calls.firstIndex(where: { $0.uuid == uuid }) else { return nil }
        return calls[idx]
    }
    
    func addCall(_ call: Call){
        calls.append(call)
        call.stateDidChange = { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.callsChangedHandler?()
            strongSelf.postCallNotification()
        }
        callsChangedHandler?()
        postCallNotification()
    }
    
    func removeCall(_ call: Call){
        guard let idx = calls.firstIndex(where: { $0 === call }) else { return }
        calls.remove(at: idx)
        callsChangedHandler?()
        postCallNotification()
    }
    
    func removeAllCalls() {
        calls.removeAll()
        callsChangedHandler?()
        postCallNotification()
    }
    
    private func postCallNotification(){
        NotificationCenter.default.post(name: type(of: self).callsChangedNotification, object: self)
    }
    
    
}
