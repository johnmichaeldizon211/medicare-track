Map<String, dynamic>? asStringMap(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

Map<String, dynamic> stringMapFrom(dynamic value) {
  return asStringMap(value) ?? <String, dynamic>{};
}

List<dynamic> listFrom(dynamic value) {
  if (value is Iterable) {
    return value.toList();
  }
  return const [];
}

List<Map<String, dynamic>> mapListFrom(dynamic value) {
  return listFrom(
    value,
  ).map(asStringMap).whereType<Map<String, dynamic>>().toList();
}

List<String> stringListFrom(dynamic value) {
  return listFrom(value)
      .map((item) {
        if (item is Map) {
          return (item['name'] ?? '').toString().trim();
        }
        return item.toString().trim();
      })
      .where((item) => item.isNotEmpty)
      .toList();
}
