String browserFailureMessage(String description) {
  final detail = description.toUpperCase();
  if (detail.contains('CONNECTION_RESET')) {
    return 'The site reset the connection. Retry, or clear cached files and retry.';
  }
  if (detail.contains('NAME_NOT_RESOLVED') || detail.contains('HOST_LOOKUP')) {
    return 'The site address could not be found. Check the address or try another result.';
  }
  if (detail.contains('TIMED_OUT') || detail.contains('TIMEOUT')) {
    return 'The site took too long to respond. Try again when your connection is stable.';
  }
  if (detail.contains('SSL') || detail.contains('CERT')) {
    return 'The site could not establish a secure connection. Try again later or contact the site.';
  }
  return 'This page could not be loaded. Retry or clear cached files and retry.';
}
