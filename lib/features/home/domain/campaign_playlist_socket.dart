/// Listens for server campaign events and triggers playlist refresh (pure Dart).
abstract class CampaignPlaylistSocket {
  Future<void> start({required void Function() onPlaylistRefresh});

  Future<void> dispose();
}
