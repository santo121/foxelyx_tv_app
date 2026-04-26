import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tv_app/features/home/data/datasources/playlist_ads_datasource.dart';

void main() {
  group('PlaylistAdsDatasource orientation parsing', () {
    Map<String, dynamic> item(String url, String orientation) =>
        <String, dynamic>{'url': url, 'orientation': orientation};

    test('LANDSCAPE accepts horizontal items', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'success': true,
        'data': <dynamic>[
          item('https://cdn.example.com/video.mp4', 'horizontal'),
          item('https://cdn.example.com/poster.jpg', 'horizontal'),
        ],
      };

      final content = PlaylistAdsDatasource.parseResponseStatic(
        json,
        preferredOrientation: 'landscape',
      );

      expect(content.videoUrls, hasLength(1));
      expect(content.posterUrls, hasLength(1));
      expect(content.youtubeUrls, isEmpty);
    });

    test('PORTRAIT accepts portrait items', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'data': <dynamic>[
          item('https://cdn.example.com/video.mp4', 'portrait'),
          item('https://cdn.example.com/poster.jpg', 'portrait'),
        ],
      };

      final content = PlaylistAdsDatasource.parseResponseStatic(
        json,
        preferredOrientation: 'portrait',
      );

      expect(content.videoUrls, hasLength(1));
      expect(content.posterUrls, hasLength(1));
      expect(content.youtubeUrls, isEmpty);
    });

    test('LANDSCAPE excludes portrait items when matching media exists', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'data': <dynamic>[
          item('https://cdn.example.com/landscape.mp4', 'horizontal'),
          item('https://cdn.example.com/portrait.jpg', 'portrait'),
        ],
      };

      final content = PlaylistAdsDatasource.parseResponseStatic(
        json,
        preferredOrientation: 'landscape',
      );

      expect(content.videoUrls, contains('https://cdn.example.com/landscape.mp4'));
      expect(content.posterUrls, isNot(contains('https://cdn.example.com/portrait.jpg')));
    });

    test('falls back to unfiltered items when strict orientation yields empty', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'data': <dynamic>[
          item('https://cdn.example.com/portrait-video.mp4', 'portrait'),
          item('https://cdn.example.com/portrait-image.jpg', 'portrait'),
        ],
      };

      final content = PlaylistAdsDatasource.parseResponseStatic(
        json,
        preferredOrientation: 'landscape',
      );

      expect(content.videoUrls, hasLength(1));
      expect(content.posterUrls, hasLength(1));
    });

    test('items without orientation are allowed', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'url': 'https://cdn.example.com/video.mp4'},
          <String, dynamic>{'url': 'https://cdn.example.com/poster.jpg'},
        ],
      };

      final content = PlaylistAdsDatasource.parseResponseStatic(
        json,
        preferredOrientation: 'landscape',
      );

      expect(content.videoUrls, hasLength(1));
      expect(content.posterUrls, hasLength(1));
    });

    test('separates youtube urls from regular videos', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'data': <dynamic>[
          item('https://youtube.com/watch?v=abc', 'horizontal'),
          item('https://cdn.example.com/regular.mp4', 'horizontal'),
        ],
      };

      final content = PlaylistAdsDatasource.parseResponseStatic(
        json,
        preferredOrientation: 'landscape',
      );

      expect(content.youtubeUrls, hasLength(1));
      expect(content.videoUrls, hasLength(1));
    });

    test('parses wrapped response body payload', () {
      final String body = jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'Operation successful',
        'data': <dynamic>[
          item('https://cdn.example.com/video.mp4', 'horizontal'),
          item('https://cdn.example.com/poster.jpg', 'horizontal'),
        ],
        'error': null,
      });

      final content = PlaylistAdsDatasource.parseResponseBodyStatic(
        body,
        preferredOrientation: 'landscape',
      );

      expect(content.videoUrls, hasLength(1));
      expect(content.posterUrls, hasLength(1));
    });

    test('throws FormatException on unsupported response body shape', () {
      expect(
        () => PlaylistAdsDatasource.parseResponseBodyStatic('"invalid-shape"'),
        throwsFormatException,
      );
    });
  });
}
