import 'package:flutter/services.dart';

class CalendarNotifications {
  CalendarNotifications._();
  static const _channel = MethodChannel('dapoer/calendar_notifications');

  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> enabled() async =>
      await _channel.invokeMethod<bool>('getEnabled') ?? false;

  static Future<void> setEnabled(bool value) =>
      _channel.invokeMethod<void>('setEnabled', {'enabled': value});

  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  }) => _channel.invokeMethod<void>('schedule', {
    'id': id,
    'title': title,
    'body': body,
    'atMillis': at.millisecondsSinceEpoch,
  });

  static Future<void> cancel(int id) =>
      _channel.invokeMethod<void>('cancel', {'id': id});

  static Future<void> cancelAll() => _channel.invokeMethod<void>('cancelAll');
}
