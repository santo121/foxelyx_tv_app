import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/repositories/auth_repository.dart';
import '../utils/local_data_cleaner.dart';
import '../../features/auth/data/datasources/device_info_datasource.dart';
import '../../features/auth/data/datasources/local_auth_datasource.dart';
import '../../features/auth/data/datasources/remote_auth_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/home/data/datasources/devices_campaign_socket_datasource.dart';
import '../../features/home/data/datasources/playlist_ads_datasource.dart';
import '../../features/home/domain/campaign_playlist_socket.dart';
import '../../features/home/data/datasources/video_cache_datasource.dart';
import '../../features/home/data/repositories/ads_repository_impl.dart';
import '../../features/home/domain/repositories/ads_repository.dart';
import '../../features/home/presentation/cubit/home_cubit.dart';

final GetIt getIt = GetIt.instance;

Future<void> setupDi() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  // Auth: data sources
  getIt.registerLazySingleton<LocalAuthDatasource>(
    () => LocalAuthDatasource(getIt<SharedPreferences>()),
  );
  getIt.registerLazySingleton<RemoteAuthDatasource>(RemoteAuthDatasource.new);
  getIt.registerLazySingleton<DeviceInfoDatasource>(DeviceInfoDatasource.new);
  getIt.registerLazySingleton<LocalDataCleaner>(LocalDataCleaner.new);

  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      getIt<LocalAuthDatasource>(),
      getIt<RemoteAuthDatasource>(),
      getIt<LocalDataCleaner>(),
    ),
  );
  getIt.registerFactory<AuthCubit>(
    () => AuthCubit(getIt<AuthRepository>(), getIt<DeviceInfoDatasource>()),
  );

  // Home / Ads
  getIt.registerLazySingleton<PlaylistAdsDatasource>(
    () => PlaylistAdsDatasource(getIt<AuthRepository>()),
  );
  getIt.registerLazySingleton<CampaignPlaylistSocket>(
    () => DevicesCampaignSocketDatasource(getIt<AuthRepository>()),
  );
  getIt.registerLazySingleton<VideoCacheDatasource>(VideoCacheDatasource.new);
  getIt.registerLazySingleton<AdsRepository>(
    () => AdsRepositoryImpl(
      getIt<PlaylistAdsDatasource>(),
      getIt<VideoCacheDatasource>(),
    ),
  );
  getIt.registerFactory<HomeCubit>(
    () => HomeCubit(
      getIt<AdsRepository>(),
      getIt<CampaignPlaylistSocket>(),
      getIt<AuthRepository>(),
    ),
  );
}
