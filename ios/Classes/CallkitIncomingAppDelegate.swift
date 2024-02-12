//
//  CallkitIncomingAppDelegate.swift
//  flutter_callkit_incoming
//
//  Created by Hien Nguyen on 05/01/2024.
//

import Foundation
import AVFAudio


public protocol CallkitIncomingAppDelegate : NSObjectProtocol {
    func onAccept(_ call: Call);

    func onSilentlyReject(callerRegistrationId: String, rejectedCallUUID: String);

    func onDecline(callerRegistrationId: String, declinedCallUUID: String);

    func onEnd(callerRegistrationId: String, endedCallUUID: String);
    
    func onTimeOut(_ call: Call);

    func onMissedCall();

    func onStartRinging();

    func onEndCallBeep();

    func onEnableSpeaker(isEnabled: Bool);

    func onConnectedCallBeep();

    func didActivateAudioSession(_ audioSession: AVAudioSession)
    
    func didDeactivateAudioSession(_ audioSession: AVAudioSession)

    func sendLog(_ message: String, data: Any)
}
