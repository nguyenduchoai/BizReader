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
    expect((json['notes'] as List), hasLength(40));
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
