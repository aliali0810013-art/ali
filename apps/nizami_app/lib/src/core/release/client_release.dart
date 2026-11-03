/// Metadata attached to every NineSoft API request.
/// Keep these values aligned with `pubspec.yaml`.
final class ClientRelease {
  const ClientRelease._();

  static const String version = '0.29.27';
  static const int buildNumber = 75;

  static const String buildHeaderName = 'X-NineSoft-Client-Build';
  static const String versionHeaderName = 'X-NineSoft-Client-Version';
  static const String platformHeaderName = 'X-NineSoft-Client-Platform';

  static Map<String, String> addHeaders(
    Map<String, String> headers, {
    required String platform,
  }) => {
    ...headers,
    buildHeaderName: '$buildNumber',
    versionHeaderName: version,
    platformHeaderName: platform,
  };
}
