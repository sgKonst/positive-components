abstract class DataSource<T> {
  Stream<Iterable<T>> connect();
  void disconnect();

  factory DataSource.fromStream(Stream<List<T>> stream) {
    return StreamDataSource(stream);
  }
  factory DataSource.fromList(List<T> list) {
    return DataSource.fromStream(Stream.fromIterable([list]));
  }
}

class StreamDataSource<T> implements DataSource<T> {
  final Stream<Iterable<T>> _stream;

  StreamDataSource(this._stream);

  @override
  Stream<Iterable<T>> connect() {
    return _stream;
  }

  @override
  void disconnect() {}
}
