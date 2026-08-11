enum BizSleepMode { calendar, photo }

class BizNote {
  const BizNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final int updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt,
  };

  factory BizNote.fromJson(Map<String, Object?> json) => BizNote(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
  );
}

class BizTodo {
  const BizTodo({
    required this.id,
    required this.title,
    this.done = false,
    this.due = '',
    this.updatedAt = 0,
  });

  final String id;
  final String title;
  final bool done;
  final String due;
  final int updatedAt;

  BizTodo copyWith({bool? done, int? updatedAt}) => BizTodo(
    id: id,
    title: title,
    done: done ?? this.done,
    due: due,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'done': done,
    'due': due,
    'updatedAt': updatedAt,
  };
  factory BizTodo.fromJson(Map<String, Object?> json) => BizTodo(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    done: json['done'] as bool? ?? false,
    due: json['due'] as String? ?? '',
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
  );
}

class BizDeletedItem {
  const BizDeletedItem({required this.id, required this.updatedAt});

  final String id;
  final int updatedAt;

  Map<String, Object?> toJson() => {'id': id, 'updatedAt': updatedAt};

  factory BizDeletedItem.fromJson(Map<String, Object?> json) => BizDeletedItem(
    id: json['id'] as String? ?? '',
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
  );
}

class BizCalendarEvent {
  const BizCalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    this.time = '',
    this.location = '',
  });

  final String id;
  final String title;
  final String date;
  final String time;
  final String location;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'date': date,
    'time': time,
    'location': location,
  };
  factory BizCalendarEvent.fromJson(Map<String, Object?> json) =>
      BizCalendarEvent(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        date: json['date'] as String? ?? '',
        time: json['time'] as String? ?? '',
        location: json['location'] as String? ?? '',
      );
}

class BizWeather {
  const BizWeather({
    this.location = 'Hà Nội',
    this.condition = 'Chưa cập nhật',
    this.temperature = 0,
    this.high = 0,
    this.low = 0,
    this.updatedAt = 0,
  });

  final String location;
  final String condition;
  final int temperature;
  final int high;
  final int low;
  final int updatedAt;

  Map<String, Object?> toJson() => {
    'location': location,
    'condition': condition,
    'temperature': temperature,
    'high': high,
    'low': low,
    'updatedAt': updatedAt,
  };
  factory BizWeather.fromJson(Map<String, Object?> json) => BizWeather(
    location: json['location'] as String? ?? 'Hà Nội',
    condition: json['condition'] as String? ?? 'Chưa cập nhật',
    temperature: (json['temperature'] as num?)?.round() ?? 0,
    high: (json['high'] as num?)?.round() ?? 0,
    low: (json['low'] as num?)?.round() ?? 0,
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
  );
}

class BizContent {
  const BizContent({
    this.notes = const [],
    this.todos = const [],
    this.events = const [],
    this.deletedNotes = const [],
    this.deletedTodos = const [],
    this.weather = const BizWeather(),
    this.sleepMode = BizSleepMode.calendar,
    this.wallpaperPath,
    this.updatedAt = 0,
  });

  final List<BizNote> notes;
  final List<BizTodo> todos;
  final List<BizCalendarEvent> events;
  final List<BizDeletedItem> deletedNotes;
  final List<BizDeletedItem> deletedTodos;
  final BizWeather weather;
  final BizSleepMode sleepMode;
  final String? wallpaperPath;
  final int updatedAt;

  BizContent copyWith({
    List<BizNote>? notes,
    List<BizTodo>? todos,
    List<BizCalendarEvent>? events,
    List<BizDeletedItem>? deletedNotes,
    List<BizDeletedItem>? deletedTodos,
    BizWeather? weather,
    BizSleepMode? sleepMode,
    String? wallpaperPath,
    bool clearWallpaper = false,
    int? updatedAt,
  }) => BizContent(
    notes: notes ?? this.notes,
    todos: todos ?? this.todos,
    events: events ?? this.events,
    deletedNotes: deletedNotes ?? this.deletedNotes,
    deletedTodos: deletedTodos ?? this.deletedTodos,
    weather: weather ?? this.weather,
    sleepMode: sleepMode ?? this.sleepMode,
    wallpaperPath: clearWallpaper ? null : wallpaperPath ?? this.wallpaperPath,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'version': 2,
    'updatedAt': updatedAt,
    'notes': notes.take(40).map((item) => item.toJson()).toList(),
    'todos': todos.take(60).map((item) => item.toJson()).toList(),
    'events': events.take(60).map((item) => item.toJson()).toList(),
    'deleted': {
      'notes': deletedNotes.take(80).map((item) => item.toJson()).toList(),
      'todos': deletedTodos.take(120).map((item) => item.toJson()).toList(),
    },
    'weather': weather.toJson(),
    'sleep': {
      'mode': sleepMode.name,
      'hasPhoto': wallpaperPath != null,
      'photoFilename': wallpaperPath == null ? '' : 'sleep.bmp',
    },
  };

  Map<String, Object?> toStorageJson() => {
    ...toJson(),
    'wallpaperPath': wallpaperPath,
  };

  factory BizContent.fromJson(Map<String, Object?> json) {
    List<T> readList<T>(String key, T Function(Map<String, Object?>) decode) {
      final values = json[key];
      if (values is! List) return const [];
      return values
          .whereType<Map>()
          .map((value) => decode(value.cast<String, Object?>()))
          .toList();
    }

    final sleep = json['sleep'];
    final sleepJson = sleep is Map
        ? sleep.cast<String, Object?>()
        : const <String, Object?>{};
    final weather = json['weather'];
    final deleted = json['deleted'];
    final deletedJson = deleted is Map
        ? deleted.cast<String, Object?>()
        : const <String, Object?>{};
    List<BizDeletedItem> readDeleted(String key) {
      final values = deletedJson[key];
      if (values is! List) return const [];
      return values
          .whereType<Map>()
          .map(
            (value) => BizDeletedItem.fromJson(value.cast<String, Object?>()),
          )
          .where((item) => item.id.isNotEmpty)
          .toList();
    }

    return BizContent(
      notes: readList('notes', BizNote.fromJson),
      todos: readList('todos', BizTodo.fromJson),
      events: readList('events', BizCalendarEvent.fromJson),
      deletedNotes: readDeleted('notes'),
      deletedTodos: readDeleted('todos'),
      weather: weather is Map
          ? BizWeather.fromJson(weather.cast<String, Object?>())
          : const BizWeather(),
      sleepMode: sleepJson['mode'] == 'photo'
          ? BizSleepMode.photo
          : BizSleepMode.calendar,
      wallpaperPath: json['wallpaperPath'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  static BizContent merge(BizContent local, BizContent remote) {
    List<T> mergeItems<T>(
      List<T> first,
      List<T> second,
      List<BizDeletedItem> deleted,
      String Function(T) idOf,
      int Function(T) updatedAtOf,
    ) {
      final items = <String, T>{};
      for (final item in [...first, ...second]) {
        final id = idOf(item);
        if (id.isEmpty) continue;
        final previous = items[id];
        if (previous == null || updatedAtOf(item) > updatedAtOf(previous)) {
          items[id] = item;
        }
      }
      final deletedAt = <String, int>{};
      for (final item in deleted) {
        deletedAt[item.id] = item.updatedAt > (deletedAt[item.id] ?? 0)
            ? item.updatedAt
            : deletedAt[item.id]!;
      }
      return items.values
          .where((item) => updatedAtOf(item) > (deletedAt[idOf(item)] ?? -1))
          .toList();
    }

    List<BizDeletedItem> mergeDeleted(
      List<BizDeletedItem> first,
      List<BizDeletedItem> second,
    ) {
      final values = <String, int>{};
      for (final item in [...first, ...second]) {
        values[item.id] = item.updatedAt > (values[item.id] ?? 0)
            ? item.updatedAt
            : values[item.id]!;
      }
      return values.entries
          .map((item) => BizDeletedItem(id: item.key, updatedAt: item.value))
          .toList();
    }

    final deletedNotes = mergeDeleted(local.deletedNotes, remote.deletedNotes);
    final deletedTodos = mergeDeleted(local.deletedTodos, remote.deletedTodos);
    final newest = local.updatedAt >= remote.updatedAt ? local : remote;
    return BizContent(
      notes: mergeItems(
        local.notes,
        remote.notes,
        deletedNotes,
        (item) => item.id,
        (item) => item.updatedAt,
      ),
      todos: mergeItems(
        local.todos,
        remote.todos,
        deletedTodos,
        (item) => item.id,
        (item) => item.updatedAt,
      ),
      events: newest.events,
      deletedNotes: deletedNotes,
      deletedTodos: deletedTodos,
      weather: newest.weather,
      sleepMode: newest.sleepMode,
      wallpaperPath: local.wallpaperPath,
      updatedAt: local.updatedAt > remote.updatedAt
          ? local.updatedAt
          : remote.updatedAt,
    );
  }
}
