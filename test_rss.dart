import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:webfeed_plus/webfeed_plus.dart';

void main() async {
  print('Starting...');
  final RssService service = RssService();
  final result = await service.fetchNews();
  print('Result length: ${result.length}');
  print('Result: $result');
  exit(0);
}

class RssService {
  static const String rssUrl =
      'https://news.google.com/rss?hl=ml&gl=IN&ceid=IN:ml';

  Future<String> fetchNews() async {
    try {
      print('Fetching from $rssUrl');
      final response = await http.get(Uri.parse(rssUrl));
      print('Status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final rssFeed = RssFeed.parse(response.body);
        if (rssFeed.items != null && rssFeed.items!.isNotEmpty) {
          final top15 = rssFeed.items!.take(15).toList();
          final String concatenatedNews = top15
              .map((item) => item.title?.trim() ?? '')
              .where((title) => title.isNotEmpty)
              .join('   •   ');
          return concatenatedNews;
        } else {
          print('RSS Items empty or null');
        }
      }
    } catch (e) {
      print('Error fetching RSS news: $e');
    }
    return '';
  }
}
