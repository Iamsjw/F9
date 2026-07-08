// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void downloadWebCsv(String csvContent, String fileName) {
  downloadWebText(csvContent, fileName, 'text/csv;charset=utf-8');
}

void downloadWebText(String content, String fileName, String mimeType) {
  final blob = html.Blob(['\uFEFF', content], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
