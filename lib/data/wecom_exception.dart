class WeComException implements Exception {
  const WeComException(this.message, {this.errCode, this.httpStatus});

  final String message;
  final int? errCode;
  final int? httpStatus;

  @override
  String toString() {
    final parts = <String>[message];
    if (errCode != null) {
      parts.add('errcode=$errCode');
    }
    if (httpStatus != null) {
      parts.add('HTTP $httpStatus');
    }
    return parts.join(' · ');
  }
}
