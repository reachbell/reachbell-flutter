import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../types/push_platform.dart';
import 'os_version_stub.dart' if (dart.library.io) 'os_version_io.dart';

/// The `os`, `osVersion` and `device` fields sent with `POST /subscribers`.
///
/// The API parses the User-Agent first; Dart's `http` sends `Dart/<ver>
/// (dart:io)`, which names no OS or device, so these fields are what the
/// dashboard shows (instead of `Unknown` / `desktop`).
@immutable
class DeviceInfo {
  const DeviceInfo({required this.os, this.osVersion, this.device});

  /// `Android` or `iOS`, the names the Android and iOS SDKs send.
  final String os;

  /// Dotted version such as `17.4`, or null when it cannot be read.
  final String? osVersion;

  /// `mobile` or `tablet` (the values UAParser uses).
  final String? device;

  static DeviceInfo detect(PushPlatform platform) => DeviceInfo(
        os: platform == PushPlatform.ios ? 'iOS' : 'Android',
        osVersion:
            kIsWeb ? null : parseOsVersion(platform, rawOperatingSystemVersion()),
        device: _deviceType(),
      );

  /// Extracts a dotted version from `Platform.operatingSystemVersion`.
  ///
  /// iOS reports `Version 17.4 (Build 21E213)`. On Android the value is not a
  /// documented Android release (it can be a kernel or build string), so it is
  /// only used when it is a plain version number.
  @visibleForTesting
  static String? parseOsVersion(PushPlatform platform, String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    if (platform == PushPlatform.ios) {
      return RegExp(r'\d+(?:\.\d+)*').firstMatch(value)?.group(0);
    }
    return RegExp(r'^\d+(?:\.\d+)*$').hasMatch(value) ? value : null;
  }

  /// `tablet` when the shortest side of the screen is at least 600 logical
  /// pixels (the Android sw600dp breakpoint), otherwise `mobile`.
  static String _deviceType() {
    try {
      final view = ui.PlatformDispatcher.instance.implicitView;
      if (view == null || view.devicePixelRatio <= 0) return 'mobile';
      final size = view.physicalSize / view.devicePixelRatio;
      return size.shortestSide >= 600 ? 'tablet' : 'mobile';
    } catch (_) {
      return 'mobile';
    }
  }
}
