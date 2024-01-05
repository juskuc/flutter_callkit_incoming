//
//  CallkitIncomingAppDelegate.swift
//  flutter_callkit_incoming
//
//  Created by Hien Nguyen on 05/01/2024.
//

import Foundation
import AVFAudio


public protocol CallkitIncomingAppDelegate : NSObjectProtocol {

    func didActivateAudioSession(_ audioSession: AVAudioSession)
    
    func didDeactivateAudioSession(_ audioSession: AVAudioSession)
    
}
