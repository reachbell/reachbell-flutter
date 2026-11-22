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
  /// iOS reports `Version 17.4 (Build 21E213)`. On Android the value is a
  /// kernel or build string, not the Android release, and reading the release
  /// would need a plugin, so Android gets null (the field is omitted).
  @visibleForTesting
  static String? parseOsVersion(PushPlatform platform, String? raw) {
    if (platform != PushPlatform.ios) return null;
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    return RegExp(r'\d+(?:\.\d+)*').firstMatch(value)?.group(0);
  }

  /// `tablet` when the shortest side of the physical display is at least 600
  /// logical pixels (the Android sw600dp breakpoint), otherwise `mobile`.
  ///
  /// Uses the display rather than the window, so split screen, freeform
  /// windows and iPad multitasking do not turn a tablet into `mobile`. Falls
  /// back to the window when the engine reports no display size.
  static String _deviceType() {
    try {
      final view = ui.PlatformDispatcher.instance.implicitView;
      if (view == null) return 'mobile';
      ui.Size? displaySize;
      double displayRatio = 0;
      try {
        final display = view.display;
        displaySize = display.size;
        displayRatio = display.devicePixelRatio;
      } catch (_) {
        displaySize = null;
      }
      return deviceTypeFor(
        displaySize: displaySize,
        displayPixelRatio: displayRatio,
        windowSize: view.physicalSize,
        windowPixelRatio: view.devicePixelRatio,
      );
    } catch (_) {
      return 'mobile';
    }
  }

  /// Classifies physical pixel sizes: the display when it has a size and a
  /// pixel ratio, otherwise the window.
  @visibleForTesting
  static String deviceTypeFor({
    ui.Size? displaySize,
    double displayPixelRatio = 0,
    ui.Size? windowSize,
    double windowPixelRatio = 0,
  }) {
    ui.Size? logical;
    if (displaySize != null && !displaySize.isEmpty && displayPixelRatio > 0) {
      logical = displaySize / displayPixelRatio;
    } else if (windowSize != null &&
        !windowSize.isEmpty &&
        windowPixelRatio > 0) {
      logical = windowSize / windowPixelRatio;
    }
    if (logical == null) return 'mobile';
    return logical.shortestSide >= 600 ? 'tablet' : 'mobile';
  }
}
