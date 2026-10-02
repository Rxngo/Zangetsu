import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/people_service.dart';
import 'package:watch_app/core/models/person.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Object? Function(Uri uri) respond;

  @override
  Future<ResponseBody> fetch(RequestOptions o, _, _) async {
    return ResponseBody.fromString(
      jsonEncode(respond(o.uri)),
      200,
      headers: {'content-type': ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  PeopleService build(Object? Function(Uri uri) respond) =>
      PeopleService(Dio()..httpClientAdapter = _Adapter(respond));

  const person = {
    'name': 'Bryan Cranston',
    'profile_path': '/p.jpg',
    'biography': 'An actor.',
    'known_for_department': 'Acting',
  };

  Object? credits(List<Map<String, Object?>> cast) => {'cast': cast};

  Map<String, Object?> credit(
    String title,
    String character,
    int? order,
  ) => {
    'title': title,
    'poster_path': '/t.jpg',
    'character': character,
    'order': order,
    'popularity': 10,
  };

  Future<PersonProfile?> load(List<Map<String, Object?>> cast) => build(
    (uri) => uri.path.endsWith('/combined_credits')
        ? credits(cast)
        : person,
  ).load(const PersonRef(id: 1, source: PersonSource.tmdb, name: 'X'));

  test('top-billed TMDB credits read as Main, the rest as Supporting', () async {
    final p = await load([
      credit('Breaking Bad', 'Walter White', 0),
      credit('Malcolm', 'Hal', 5),
    ]);

    final byTitle = {for (final w in p!.works) w.title: w.subtitle};
    expect(byTitle['Breaking Bad'], 'Main · Walter White');
    expect(byTitle['Malcolm'], 'Supporting · Hal');
  });

  test('a credit with no billing order keeps the name-only line', () async {
    final p = await load([credit('Indie Film', 'Stranger', null)]);

    expect(p!.works.single.subtitle, 'Stranger');
  });

  test('a nameless credit still gets its role label', () async {
    final p = await load([credit('Mystery Show', '', 1)]);

    expect(p!.works.single.subtitle, 'Main');
  });
}
