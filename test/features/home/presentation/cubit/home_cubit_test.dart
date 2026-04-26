import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tv_app/core/domain/entities/vehicle_session.dart';
import 'package:flutter_tv_app/core/domain/repositories/auth_repository.dart';
import 'package:flutter_tv_app/features/home/domain/campaign_playlist_socket.dart';
import 'package:flutter_tv_app/features/home/domain/entities/ad_content.dart';
import 'package:flutter_tv_app/features/home/domain/repositories/ads_repository.dart';
import 'package:flutter_tv_app/features/home/presentation/cubit/home_cubit.dart';
import 'package:flutter_tv_app/features/home/presentation/cubit/home_state.dart';

class _FakeCampaignPlaylistSocket implements CampaignPlaylistSocket {
  int startCalls = 0;
  int disposeCalls = 0;
  void Function()? onPlaylistRefresh;

  @override
  Future<void> start({required void Function() onPlaylistRefresh}) async {
    startCalls++;
    this.onPlaylistRefresh = onPlaylistRefresh;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<void> clearSession() async {}

  @override
  Future<String?> getAccessToken() async => 'token';

  @override
  Future<VehicleSession?> getStoredSession() async => const VehicleSession(
    deviceId: 'dev',
    pairingCode: 'pair',
    vehicleId: 'veh',
    accessToken: 'token',
    secret: 'secret',
  );

  @override
  Future<VehicleSession> register(String pairingCode) async =>
      throw UnimplementedError();

  @override
  Future<bool> refreshDeviceAuth() async => true;
}

class _FakeAdsRepository implements AdsRepository {
  _FakeAdsRepository({
    required this.getAdsResult,
    required this.refreshSequence,
  });

  final AdContent getAdsResult;
  final List<Future<AdContent> Function()> refreshSequence;

  int getAdsCalls = 0;
  int refreshAdsCalls = 0;

  @override
  Future<void> cachePlayedVideo(String url) async {}

  @override
  Future<AdContent> getAds() async {
    getAdsCalls++;
    return getAdsResult;
  }

  @override
  Future<void> purgeMissingCachedVideos(Set<String> activeVideoUrls) async {}

  @override
  Future<AdContent> refreshAds() async {
    refreshAdsCalls++;
    final int index = refreshAdsCalls - 1;
    if (index >= refreshSequence.length) {
      return const AdContent(videoUrls: <String>[], posterUrls: <String>[]);
    }
    return refreshSequence[index]();
  }

  @override
  Future<AdContent> warmupForPlayback(AdContent content, int videoIndex) async =>
      content;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeCubit refresh flow', () {
    testWidgets(
      'coalesces in-flight refresh and applies trailing update',
      (WidgetTester tester) async {
        final Completer<AdContent> firstRefresh = Completer<AdContent>();
        const AdContent firstContent = AdContent(
          videoUrls: <String>[],
          posterUrls: <String>[],
        );
        const AdContent secondContent = AdContent(
          videoUrls: <String>[],
          posterUrls: <String>['https://cdn.example.com/ad.jpg'],
        );

        final repo = _FakeAdsRepository(
          getAdsResult: firstContent,
          refreshSequence: <Future<AdContent> Function()>[
            () => firstRefresh.future,
            () async => secondContent,
          ],
        );
        final socket = _FakeCampaignPlaylistSocket();
        final auth = _FakeAuthRepository();
        final cubit = HomeCubit(repo, socket, auth);

        final Future<void> firstCall = cubit.refreshPlaylistFromServer();
        await tester.pump();

        final Future<void> secondCall = cubit.refreshPlaylistFromServer();
        await tester.pump();

        firstRefresh.complete(firstContent);
        await Future.wait(<Future<void>>[firstCall, secondCall]);
        await tester.pump();

        expect(repo.refreshAdsCalls, 2);
        final AdContent state = _contentFromState(cubit.state);
        expect(state.videoUrls, secondContent.videoUrls);
        expect(state.posterUrls, secondContent.posterUrls);

        await cubit.close();
      },
    );

    testWidgets(
      'updates from empty playlist to non-empty on later refresh',
      (WidgetTester tester) async {
        const AdContent emptyContent = AdContent(
          videoUrls: <String>[],
          posterUrls: <String>[],
        );
        const AdContent populatedContent = AdContent(
          videoUrls: <String>[],
          posterUrls: <String>['https://cdn.example.com/updated.jpg'],
        );

        final repo = _FakeAdsRepository(
          getAdsResult: emptyContent,
          refreshSequence: <Future<AdContent> Function()>[
            () async => emptyContent,
            () async => populatedContent,
          ],
        );
        final socket = _FakeCampaignPlaylistSocket();
        final auth = _FakeAuthRepository();
        final cubit = HomeCubit(repo, socket, auth);

        await cubit.refreshPlaylistFromServer();
        await tester.pump();
        final AdContent firstState = _contentFromState(cubit.state);
        expect(firstState.videoUrls, isEmpty);
        expect(firstState.posterUrls, isEmpty);

        await cubit.refreshPlaylistFromServer();
        await tester.pump();
        expect(repo.refreshAdsCalls, 2);
        final AdContent secondState = _contentFromState(cubit.state);
        expect(secondState.videoUrls, populatedContent.videoUrls);
        expect(secondState.posterUrls, populatedContent.posterUrls);

        await cubit.close();
      },
    );
  });
}

AdContent _contentFromState(HomeState state) {
  if (state is HomeContentReady) return state.content;
  if (state is HomeLoaded) return state.content;
  throw StateError('Unexpected state: $state');
}
