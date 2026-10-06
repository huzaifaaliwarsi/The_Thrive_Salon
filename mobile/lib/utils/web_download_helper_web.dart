import 'dart:html' as html;

void downloadCsv(String csvData, String fileName) {
  final blob = html.Blob([csvData], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  
  html.AnchorElement(href: url)
    ..setAttribute("download", "$fileName.csv")
    ..click();

  html.Url.revokeObjectUrl(url);
}
