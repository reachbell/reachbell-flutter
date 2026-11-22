import 'dart:io' show Platform;

String? rawOperatingSystemVersion() {
  try {
    return Platform.operatingSystemVersion;
  } catch (_) {
    return null;
  }
}
