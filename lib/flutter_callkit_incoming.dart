import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'entities/entities.dart';

/// Instance to use library functions.
/// * showCallkitIncoming(dynamic)
/// * startCall(dynamic)
/// * endCall(dynamic)
/// * endAllCalls()
/// * callConnected(dynamic)

class FlutterCallkitIncoming {
  static const MethodChannel _channel = MethodChannel('flutter_callkit_incoming');
  static const EventChannel _eventChannel = EventChannel('flutter_callkit_incoming_events');

  /// Listen to event callback from [FlutterCallkitIncoming].
  ///
  /// FlutterCallkitIncoming.onEvent.listen((event) {
  /// Event.ACTION_CALL_INCOMING - Received an incoming call
  /// Event.ACTION_CALL_START - Started an outgoing call
  /// Event.ACTION_CALL_ACCEPT - Accepted an incoming call
  /// Event.ACTION_CALL_DECLINE - Declined an incoming call
  /// Event.ACTION_CALL_ENDED - Ended an incoming/outgoing call
  /// Event.ACTION_CALL_TIMEOUT - Missed an incoming call
  /// Event.ACTION_CALL_CALLBACK - only Android (click action `Call back` from missed call notification)
  /// Event.ACTION_CALL_TOGGLE_HOLD - only iOS
  /// Event.ACTION_CALL_TOGGLE_MUTE - only iOS
  /// Event.ACTION_CALL_TOGGLE_DMTF - only iOS
  /// Event.ACTION_CALL_TOGGLE_GROUP - only iOS
  /// Event.ACTION_CALL_TOGGLE_AUDIO_SESSION - only iOS
  /// Event.DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP - only iOS
  /// }
  static Stream<CallEvent?> get onEvent => _eventChannel.receiveBroadcastStream().map(_receiveCallEvent);

  /// Show Callkit Incoming.
  /// On iOS, using Callkit. On Android, using a custom UI.
  static Future showCallkitIncoming(CallKitParams params) async {
    await _channel.invokeMethod("showCallkitIncoming", params.toJson());
  }

  /// Show Miss Call Notification.
  /// Only Android
  static Future showMissCallNotification(CallKitParams params) async {
    await _channel.invokeMethod("showMissCallNotification", params.toJson());
  }

  /// Start an Outgoing call.
  /// On iOS, using Callkit(create a history into the Phone app).
  /// On Android, Nothing(only callback event listener).
  static Future startCall(CallKitParams params, String callId) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod("startCall", params.toJson());

      return;
    }
    await _channel.invokeMethod("startCall", {'params': params.toJson(), 'callId': callId});
  }

  /// Muting an Ongoing call.
  /// On iOS, using Callkit(update the ongoing call ui).
  /// On Android, Nothing(only callback event listener).
  static Future muteCall(String id, {bool isMuted = true}) async {
    await _channel.invokeMethod("muteCall", {'id': id, 'isMuted': isMuted});
  }

  /// Get Callkit Mic Status (muted/unmuted).
  /// On iOS, using Callkit(update call ui).
  /// On Android, Nothing(only callback event listener).
  static Future<bool> isMuted(String id) async {
    return (await _channel.invokeMethod("isMuted", {'id': id})) as bool? ?? false;
  }

  /// Hold an Ongoing call.
  /// On iOS, using Callkit(update the ongoing call ui).
  /// On Android, Nothing(only callback event listener).
  static Future holdCall(String id, {bool isOnHold = true}) async {
    await _channel.invokeMethod("holdCall", {'id': id, 'isOnHold': isOnHold});
  }

  /// End an Incoming/Outgoing call.
  /// On iOS, using Callkit(update a history into the Phone app).
  /// On Android, Nothing(only callback event listener).
  static Future endCall(String id) async {
    await _channel.invokeMethod("endCall", {'id': id});
  }

  /// Set call has been connected successfully.
  /// On iOS, using Callkit(update a history into the Phone app).
  /// On Android, Nothing(only callback event listener).
  static Future setCallConnected(String id, bool isVideo) async {
    await _channel.invokeMethod("callConnected", {'id': id, 'isVideo': isVideo});
  }

  /// End all calls.
  static Future endAllCalls() async {
    await _channel.invokeMethod("endAllCalls");
  }

  /// Get active calls.
  /// On iOS: return active calls from Callkit.
  /// On Android: only return last call
  static Future<dynamic> activeCalls() async {
    return await _channel.invokeMethod("activeCalls");
  }

  /// Get device push token VoIP.
  /// On iOS: return deviceToken for VoIP.
  /// On Android: return Empty
  static Future getDevicePushTokenVoIP() async {
    return await _channel.invokeMethod("getDevicePushTokenVoIP");
  }

  /// Silence CallKit events
  static Future silenceEvents() async {
    return await _channel.invokeMethod("silenceEvents", true);
  }

  /// Unsilence CallKit events
  static Future unsilenceEvents() async {
    return await _channel.invokeMethod("silenceEvents", false);
  }

  /// Request permisstion show notification for Android(13)
  /// Only Android: show request permission post notification for Android 13+
  static Future requestNotificationPermission(dynamic data) async {
    return await _channel.invokeMethod("requestNotificationPermission", data);
  }

  static Future updateCallerName(String id, {String callerName = 'Unknown'}) async {
    await _channel.invokeMethod("updateCallerName", {'id': id, 'callerName': callerName});
  }

  /// Start incoming call
  /// On iOS: start connection timer
  /// On Android: not implemented
  static Future startIncomingCall() async {
    await _channel.invokeMethod("startCallIncoming");
  }

  static CallEvent? _receiveCallEvent(dynamic data) {
    Event? event;
    Map<String, dynamic> body = {};

    if (data is Map) {
      event = Event.values.firstWhere((e) => e.name == data['event']);
      body = Map<String, dynamic>.from(data['body']);
      return CallEvent(body, event);
    }
    return null;
  }

  static Future setValueInUserDefaults(String key, dynamic value) async {
    await _channel.invokeMethod("setValueInUserDefaults", {'key': key, 'value': value});
  }

  static Future retrieveFromUserDefaults(String key) async {
    return await _channel.invokeMethod("retrieveFromUserDefaults", {'key': key});
  }

  static Future deleteFromUserDefaults(String key) async {
    return await _channel.invokeMethod("deleteFromUserDefaults", {'key': key});
  }

  static Future toggleSpeaker(bool isOn) async {
    await _channel.invokeMethod("toggleSpeaker", {'isOn': isOn});
  }

  static Future enableWebRTCAudio(bool isReconnect) async {
    await _channel.invokeMethod("enableWebRTCAudio", {'isReconnect': isReconnect});
  }

  static Future disableWebRTCAudio() async {
    await _channel.invokeMethod("disableWebRTCAudio");
  }

  static Future reconnectWebRTCAudio() async {
    await _channel.invokeMethod("reconnectWebRTCAudio");
  }

  static Future fulfillEndCall() async {
    await _channel.invokeMethod("fulfillEndCall");
  }

  static Future exit() async {
    await _channel.invokeMethod("exit");
  }

  static Future getActiveCallUUID() async {
    return await _channel.invokeMethod("getActiveCallUUID");
  }

  static Future setActiveCallUUID(String callId) async {
    await _channel.invokeMethod("setActiveCallUUID", {'callId': callId});
  }

  static Future clearActiveCallUUID() async {
    await _channel.invokeMethod("clearActiveCallUUID");
  }

  static Future setIsSpeakerEnabled(bool isSpeakerEnabled) async {
    await _channel.invokeMethod("setIsSpeakerEnabled", {'isSpeakerEnabled': isSpeakerEnabled});
  }
}
