class Blob {
  Blob(List<String> data, String mimeType);
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

class AnchorElement {
  String? href;
  String? download;
  AnchorElement({this.href});
  void click() {}
}