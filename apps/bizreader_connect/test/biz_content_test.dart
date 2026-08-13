import 'package:bizreader_connect/src/models/biz_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('content snapshot keeps the BLE v2 device contract bounded', () {
    final content = BizContent(
      notes: [
        for (var index = 0; index < 45; index++)
          BizNote(
            id: '$index',
            title: 'Ghi chú $index',
            body: 'Nội dung',
            updatedAt: index,
          ),
      ],
      todos: const [BizTodo(id: 'todo', title: 'Đọc sách', due: 'Hôm nay')],
      events: const [
        BizCalendarEvent(
          id: 'event',
          title: 'Họp',
          date: '2026-08-10',
          time: '09:30',
        ),
      ],
      weather: const BizWeather(
        location: 'Đà Nẵng',
        condition: 'Nắng',
        temperature: 31,
        high: 34,
        low: 27,
      ),
      sleepMode: BizSleepMode.photo,
      wallpaperPath: '/tmp/sleep.bmp',
      updatedAt: 123,
    );

    final json = content.toJson();

    expect(json['version'], 2);
    final notes = json['notes'] as List;
    expect(notes, hasLength(40));
    expect((notes.first as Map)['id'], '5');
    expect((notes.last as Map)['id'], '44');
    expect((json['sleep'] as Map)['mode'], 'photo');
    expect(json, isNot(contains('wallpaperPath')));
  });

  test('merge keeps newest items and tombstones deleted items', () {
    final local = BizContent(
      notes: const [
        BizNote(id: 'keep', title: 'App', body: 'Mới', updatedAt: 20),
        BizNote(id: 'gone', title: 'Xóa', body: '', updatedAt: 10),
      ],
      todos: const [BizTodo(id: 'task', title: 'Đọc sách', updatedAt: 10)],
      deletedNotes: const [BizDeletedItem(id: 'gone', updatedAt: 30)],
      updatedAt: 30,
    );
    final remote = BizContent(
      notes: const [
        BizNote(id: 'keep', title: 'Máy', body: 'Cũ', updatedAt: 15),
      ],
      todos: const [
        BizTodo(id: 'task', title: 'Đọc sách', done: true, updatedAt: 40),
      ],
      updatedAt: 40,
    );

    final merged = BizContent.merge(local, remote);

    expect(merged.notes.single.title, 'App');
    expect(merged.notes.where((item) => item.id == 'gone'), isEmpty);
    expect(merged.todos.single.done, isTrue);
    expect(merged.updatedAt, 40);
  });

  test('merge caps newest records and deduplicates tombstones', () {
    final local = BizContent(
      notes: [
        for (var index = 0; index < 50; index++)
          BizNote(
            id: 'note-$index',
            title: '$index',
            body: '',
            updatedAt: index,
          ),
      ],
      deletedNotes: const [
        BizDeletedItem(id: 'deleted', updatedAt: 10),
        BizDeletedItem(id: 'deleted', updatedAt: 20),
      ],
      updatedAt: 50,
    );
    final remote = BizContent(
      notes: [
        for (var index = 50; index < 100; index++)
          BizNote(
            id: 'note-$index',
            title: '$index',
            body: '',
            updatedAt: index,
          ),
      ],
      deletedNotes: const [BizDeletedItem(id: 'deleted', updatedAt: 15)],
      updatedAt: 100,
    );

    final merged = BizContent.merge(local, remote);

    expect(merged.notes, hasLength(40));
    expect(merged.notes.first.id, 'note-60');
    expect(merged.notes.last.id, 'note-99');
    expect(merged.deletedNotes, hasLength(1));
    expect(merged.deletedNotes.single.updatedAt, 20);
  });

  test('device task changes do not discard app-owned utility data', () {
    final local = BizContent(
      events: const [
        BizCalendarEvent(id: 'meeting', title: 'Họp', date: '2026-08-13'),
      ],
      weather: const BizWeather(location: 'Huế', updatedAt: 20),
      sleepMode: BizSleepMode.calendar,
      updatedAt: 20,
    );
    final remote = BizContent(
      todos: const [
        BizTodo(id: 'task', title: 'Đọc', done: true, updatedAt: 100),
      ],
      updatedAt: 100,
    );

    final merged = BizContent.merge(local, remote);

    expect(merged.events.single.id, 'meeting');
    expect(merged.weather.location, 'Huế');
    expect(merged.todos.single.done, isTrue);
  });

  test('tombstones filter stale items before the retained set is capped', () {
    final local = BizContent(
      deletedNotes: [
        for (var index = 0; index < 81; index++)
          BizDeletedItem(id: 'deleted-$index', updatedAt: 100 + index),
      ],
      updatedAt: 200,
    );
    const remote = BizContent(
      notes: [
        BizNote(id: 'deleted-0', title: 'Bản cũ', body: '', updatedAt: 99),
      ],
      updatedAt: 99,
    );

    final merged = BizContent.merge(local, remote);

    expect(merged.notes, isEmpty);
    expect(merged.deletedNotes, hasLength(80));
    expect(
      merged.deletedNotes.where((item) => item.id == 'deleted-0'),
      isEmpty,
    );
  });

  test('restores editable content from local storage JSON', () {
    final restored = BizContent.fromJson({
      'updatedAt': 99,
      'notes': [
        {'id': 'n1', 'title': 'Ý tưởng', 'body': 'Nội dung', 'updatedAt': 80},
      ],
      'todos': const [],
      'events': const [],
      'weather': {'location': 'Huế', 'condition': 'Mưa', 'temperature': 26},
      'sleep': {'mode': 'calendar'},
      'wallpaperPath': '/data/sleep.bmp',
    });

    expect(restored.notes.single.title, 'Ý tưởng');
    expect(restored.weather.location, 'Huế');
    expect(restored.sleepMode, BizSleepMode.calendar);
    expect(restored.wallpaperPath, '/data/sleep.bmp');
  });
}
