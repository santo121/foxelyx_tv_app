/// Indicates playlist fetch requires device re-authentication.
class PlaylistAuthRequiredException implements Exception {
  const PlaylistAuthRequiredException(this.statusCode);

  final int statusCode;

  @override
  String toString() =>
      'PlaylistAuthRequiredException(statusCode: $statusCode)';
}
