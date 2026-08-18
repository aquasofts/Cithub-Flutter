void appendUniqueBy<T, K>(
  List<T> target,
  Iterable<T> incoming,
  K Function(T item) keyOf,
) {
  final existing = target.map(keyOf).toSet();
  target.addAll(incoming.where((item) => existing.add(keyOf(item))));
}
