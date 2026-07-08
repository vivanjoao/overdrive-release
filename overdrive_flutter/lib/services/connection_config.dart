/// User-configured location of the OverDrive head unit (or its tunnel).
///
/// The head unit exposes the same HTTP server on multiple fronts:
///  * LAN:        `http://192.168.1.50:8080`
///  * Cloudflared: `https://random.trycloudflare.com`
///  * Zrok:        `https://name.share.zrok.io`
///  * Tailscale:   `http://car.tail-scale.ts.net:8080`
///
/// Rather than splitting host/port/TLS into separate fields (which then has
/// to handle every tunnel's quirks), we store a single [baseUrl] string the
/// user pastes wholesale. The optional [label] is shown in the UI so users
/// with multiple tunnels ("Home LAN", "Zrok", etc.) can tell them apart.
class ConnectionConfig {
  const ConnectionConfig({
    this.baseUrl = '',
    this.label = 'Head unit',
  });

  /// Fully-qualified origin of the head unit (scheme + host + optional port).
  /// Empty string means "no connection configured".
  final String baseUrl;

  /// Friendly name shown in the UI. Defaults to "Head unit".
  final String label;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// Normalizes the URL: trims whitespace, strips any trailing slash so
  /// feature code can safely concatenate paths.
  String get normalizedBaseUrl {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Joins [normalizedBaseUrl] with a relative [path], ensuring exactly one
  /// slash between them. Returns an empty string when not configured.
  String resolve(String path) {
    if (!isConfigured) return '';
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$normalizedBaseUrl$cleanPath';
  }

  ConnectionConfig copyWith({String? baseUrl, String? label}) {
    return ConnectionConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      label: label ?? this.label,
    );
  }

  @override
  String toString() => 'ConnectionConfig($label @ $baseUrl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionConfig &&
          other.baseUrl == baseUrl &&
          other.label == label;

  @override
  int get hashCode => Object.hash(baseUrl, label);
}
