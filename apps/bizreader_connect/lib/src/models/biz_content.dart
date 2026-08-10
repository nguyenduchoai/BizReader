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
  });

  final String id;
  final String title;
  final bool done;
  final String due;

  BizTodo copyWith({bool? done}) =>
      BizTodo(id: id, title: title, done: done ?? this.done, due: due);
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'done': done,
    'due': due,
  };
  factory BizTodo.fromJson(Map<String, Object?> json) => BizTodo(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    done: json['done'] as bool? ?? false,
    due: json['due'] as String? ?? '',
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
    this.weather = const BizWeather(),
    this.sleepMode = BizSleepMode.calendar,
    this.wallpaperPath,
    this.updatedAt = 0,
  });

  final List<BizNote> notes;
  final List<BizTodo> todos;
  final List<BizCalendarEvent> events;
  final BizWeather weather;
  final BizSleepMode sleepMode;
  final String? wallpaperPath;
  final int updatedAt;

  BizContent copyWith({
    List<BizNote>? notes,
    List<BizTodo>? todos,
    List<BizCalendarEvent>? events,
    BizWeather? weather,
    BizSleepMode? sleepMode,
    String? wallpaperPath,
    bool clearWallpaper = false,
    int? updatedAt,
  }) => BizContent(
    notes: notes ?? this.notes,
    todos: todos ?? this.todos,
    events: events ?? this.events,
    weather: weather ?? this.weather,
    sleepMode: sleepMode ?? this.sleepMode,
    wallpaperPath: clearWallpaper ? null : wallpaperPath ?? this.wallpaperPath,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'updatedAt': updatedAt,
    'notes': notes.take(40).map((item) => item.toJson()).toList(),
    'todos': todos.take(60).map((item) => item.toJson()).toList(),
    'events': events.take(60).map((item) => item.toJson()).toList(),
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
    return BizContent(
      notes: readList('notes', BizNote.fromJson),
      todos: readList('todos', BizTodo.fromJson),
      events: readList('events', BizCalendarEvent.fromJson),
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
}
