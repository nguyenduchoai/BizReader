import 'package:flutter/material.dart';

import '../models/reader_preferences.dart';

class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.preferences,
    required this.onChanged,
  });

  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onChanged;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderPreferences _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.preferences;
  }

  void _update(ReaderPreferences value) {
    setState(() => _draft = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = _draft.theme;
    return Material(
      color: theme.surface,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.muted.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Tùy chỉnh đọc',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: theme.text),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Màu nền',
                style: TextStyle(
                  color: theme.secondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final item in readerThemes)
                    _ThemeSwatch(
                      theme: item,
                      selected: item.id == _draft.themeId,
                      onTap: () => _update(_draft.copyWith(themeId: item.id)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'serif', label: Text('Serif')),
                  ButtonSegment(value: 'sans', label: Text('Sans')),
                  ButtonSegment(value: 'system', label: Text('Hệ thống')),
                ],
                selected: {_draft.fontFamily},
                onSelectionChanged: (value) =>
                    _update(_draft.copyWith(fontFamily: value.first)),
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(theme.text),
                  side: WidgetStatePropertyAll(
                    BorderSide(color: theme.muted.withValues(alpha: 0.45)),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _StepperRow(
                label: 'Cỡ chữ',
                value: '${_draft.fontSize.round()}',
                textColor: theme.text,
                secondaryColor: theme.secondary,
                onDecrease: _draft.fontSize <= 14
                    ? null
                    : () => _update(
                        _draft.copyWith(fontSize: _draft.fontSize - 1),
                      ),
                onIncrease: _draft.fontSize >= 24
                    ? null
                    : () => _update(
                        _draft.copyWith(fontSize: _draft.fontSize + 1),
                      ),
              ),
              const SizedBox(height: 18),
              _SliderRow(
                label: 'Giãn dòng',
                value: _draft.lineHeight,
                min: 1.35,
                max: 2.05,
                divisions: 7,
                display: _draft.lineHeight.toStringAsFixed(2),
                theme: theme,
                onChanged: (value) =>
                    _update(_draft.copyWith(lineHeight: value)),
              ),
              _SliderRow(
                label: 'Lề trang',
                value: _draft.margin,
                min: 16,
                max: 40,
                divisions: 6,
                display: '${_draft.margin.round()}',
                theme: theme,
                onChanged: (value) => _update(_draft.copyWith(margin: value)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Căn chữ',
                    style: TextStyle(
                      color: theme.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'left',
                        icon: Tooltip(
                          message: 'Căn trái',
                          child: Icon(Icons.format_align_left),
                        ),
                      ),
                      ButtonSegment(
                        value: 'justify',
                        icon: Tooltip(
                          message: 'Căn đều',
                          child: Icon(Icons.format_align_justify),
                        ),
                      ),
                    ],
                    selected: {_draft.textAlign},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) =>
                        _update(_draft.copyWith(textAlign: value.first)),
                    style: ButtonStyle(
                      foregroundColor: WidgetStatePropertyAll(theme.text),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ReaderThemeSpec theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: theme.name,
      child: InkResponse(
        radius: 28,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.background,
            border: Border.all(
              color: selected ? theme.accent : const Color(0xFFB8BBC0),
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 18, color: theme.text)
              : null,
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.textColor,
    required this.secondaryColor,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final String value;
  final Color textColor;
  final Color secondaryColor;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        IconButton.outlined(
          tooltip: 'Giảm cỡ chữ',
          onPressed: onDecrease,
          icon: const Icon(Icons.text_decrease),
        ),
        SizedBox(
          width: 42,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton.outlined(
          tooltip: 'Tăng cỡ chữ',
          onPressed: onIncrease,
          icon: const Icon(Icons.text_increase),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.theme,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ReaderThemeSpec theme;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(color: theme.text, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              display,
              style: TextStyle(
                color: theme.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: theme.accent,
          inactiveColor: theme.muted.withValues(alpha: 0.3),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
