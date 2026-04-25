import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:webfeed_plus/webfeed_plus.dart';

class RssService {
  static const String rssUrl =
      'https://news.google.com/rss?hl=ml&gl=IN&ceid=IN:ml';

  Future<String> fetchNews() async {
    try {
      final response = await http.get(
        Uri.parse(rssUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/rss+xml, application/xml, text/xml',
        },
      );
      if (response.statusCode == 200) {
        final rssFeed = RssFeed.parse(response.body);
        if (rssFeed.items != null && rssFeed.items!.isNotEmpty) {
          final top15 = rssFeed.items!.take(15).toList();
          final String concatenatedNews = top15.map((item) {
            String title = item.title?.trim() ?? '';
            if (title.isEmpty) return '';
            
            // 1. Strip out any URLs or weird link artifacts (like http://, https://, or //:)
            title = title.replaceAll(RegExp(r'(https?://|//:)[^\s]*'), '');
            
            // 2. Decode common HTML entities sometimes found in RSS
            title = title.replaceAll('&quot;', '"')
                         .replaceAll('&#39;', "'")
                         .replaceAll('&amp;', '&')
                         .replaceAll('&lt;', '<')
                         .replaceAll('&gt;', '>')
                         .replaceAll('&nbsp;', ' ')
                         .replaceAll('&#8211;', '-')
                         .replaceAll('&#8216;', "'")
                         .replaceAll('&#8217;', "'");
            
            // 3. Remove the channel name from the trailing " - Source" Format
            final dashIndex = title.lastIndexOf(' - ');
            if (dashIndex != -1 && dashIndex < title.length - 3) {
              return title.substring(0, dashIndex).trim();
            }
            return title.trim();
          }).where((t) => t.isNotEmpty).join('     ✦     ');
          return concatenatedNews;
        }
      } else {
        log('Error fetching RSS news: HTTP ${response.statusCode}');
      }
    } catch (e) {
      log('Error fetching RSS news: $e');
    }
    return '';
  }
}
