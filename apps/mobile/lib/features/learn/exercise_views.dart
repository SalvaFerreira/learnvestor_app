import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../ui/common.dart';
import 'lesson_session.dart';

/// Renders one exercise. [response] is the learner's current answer using ORIGINAL
/// indexes; [displayOrder] is the shuffled order in which options/items are shown.
/// Once [revealed] is true the view is read-only and highlights right/wrong.
class ExerciseView extends StatelessWidget {
  const ExerciseView({
    super.key,
    required this.exercise,
    required this.response,
    required this.displayOrder,
    required this.revealed,
    required this.onChanged,
  });

  final Exercise exercise;
  final Object? response;
  final List<int> displayOrder;
  final bool revealed;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return switch (exercise) {
      InfoExercise(:final title, :final body) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb, color: AppColors.yellow, size: 40),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text(body, style: const TextStyle(fontSize: 18, height: 1.5)),
          ],
        ),
      MultipleChoiceExercise(:final prompt, :final options, :final answer) => _Question(
          hint: l.chooseAnswer,
          prompt: prompt,
          child: _Options(
            labels: options,
            order: displayOrder,
            selected: response as int?,
            correct: answer,
            revealed: revealed,
            onSelected: onChanged,
          ),
        ),
      TrueFalseExercise(:final statement, :final answer) => _Question(
          hint: l.trueOrFalse,
          prompt: statement,
          child: Row(
            children: [
              for (final value in [true, false]) ...[
                Expanded(
                  child: _ChoiceTile(
                    label: value ? l.trueLabel : l.falseLabel,
                    state: _tileState(selected: response == value, isAnswer: answer == value),
                    onTap: revealed ? null : () => onChanged(value),
                    center: true,
                  ),
                ),
                if (value) const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      FillBlankExercise(:final sentence, :final options, :final answer) => _Question(
          hint: l.fillBlankHint,
          prompt: sentence.replaceFirst('___', response == null ? '_____' : '[ ${options[response as int]} ]'),
          child: _Options(
            labels: options,
            order: displayOrder,
            selected: response as int?,
            correct: answer,
            revealed: revealed,
            onSelected: onChanged,
          ),
        ),
      OrderExercise(:final prompt, :final items) => _Question(
          hint: l.orderHint,
          prompt: prompt,
          child: _OrderBoard(
            items: items,
            order: displayOrder,
            chosen: (response as List<int>?) ?? const [],
            revealed: revealed,
            onChanged: onChanged,
          ),
        ),
      MatchExercise(:final prompt, :final left, :final right) => _Question(
          hint: l.matchHint,
          prompt: prompt,
          child: _MatchBoard(
            left: left,
            right: right,
            rightOrder: displayOrder,
            pairs: (response as List<int?>?) ?? List<int?>.filled(left.length, null),
            revealed: revealed,
            onChanged: onChanged,
          ),
        ),
      NumericExercise(:final prompt, :final decimals, :final unit) => _Question(
          hint: l.numericHint,
          prompt: prompt,
          child: _NumericInput(decimals: decimals, unit: unit, revealed: revealed, onChanged: onChanged),
        ),
    };
  }

  _TileState _tileState({required bool selected, required bool isAnswer}) {
    if (!revealed) return selected ? _TileState.selected : _TileState.idle;
    if (isAnswer) return _TileState.correct;
    return selected ? _TileState.wrong : _TileState.idle;
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.hint, required this.prompt, required this.child});

  final String hint;
  final String prompt;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(hint.toUpperCase(), style: const TextStyle(color: AppColors.pink, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 12),
        Text(prompt, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.35)),
        const SizedBox(height: 28),
        child,
      ],
    );
  }
}

class _Options extends StatelessWidget {
  const _Options({
    required this.labels,
    required this.order,
    required this.selected,
    required this.correct,
    required this.revealed,
    required this.onSelected,
  });

  final List<String> labels;
  final List<int> order;
  final int? selected;
  final int correct;
  final bool revealed;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final index in order)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ChoiceTile(
              label: labels[index],
              state: !revealed
                  ? (selected == index ? _TileState.selected : _TileState.idle)
                  : index == correct
                      ? _TileState.correct
                      : (selected == index ? _TileState.wrong : _TileState.idle),
              onTap: revealed ? null : () => onSelected(index),
            ),
          ),
      ],
    );
  }
}

enum _TileState { idle, selected, correct, wrong }

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.label, required this.state, required this.onTap, this.center = false});

  final String label;
  final _TileState state;
  final VoidCallback? onTap;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _TileState.idle => AppColors.border,
      _TileState.selected => AppColors.blue,
      _TileState.correct => AppColors.green,
      _TileState.wrong => AppColors.red,
    };
    return Material(
      color: state == _TileState.idle ? AppColors.surface : color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2),
          ),
          child: Text(
            label,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// Tap items from the bank to build the sequence; tap a placed item to remove it.
class _OrderBoard extends StatelessWidget {
  const _OrderBoard({
    required this.items,
    required this.order,
    required this.chosen,
    required this.revealed,
    required this.onChanged,
  });

  final List<String> items;
  final List<int> order;
  final List<int> chosen;
  final bool revealed;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final remaining = order.where((i) => !chosen.contains(i)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: Column(
            children: [
              for (final (position, index) in chosen.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ChoiceTile(
                    label: '${position + 1}. ${items[index]}',
                    state: !revealed ? _TileState.selected : (index == position ? _TileState.correct : _TileState.wrong),
                    onTap: revealed ? null : () => onChanged([...chosen]..remove(index)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (final index in remaining)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ChoiceTile(
              label: items[index],
              state: _TileState.idle,
              onTap: revealed ? null : () => onChanged([...chosen, index]),
            ),
          ),
      ],
    );
  }
}

const _pairColors = [AppColors.blue, AppColors.purple, AppColors.orange, AppColors.yellow, AppColors.pink];

/// Tap a term, then its definition. Tapping a paired term again removes the pair.
class _MatchBoard extends StatefulWidget {
  const _MatchBoard({
    required this.left,
    required this.right,
    required this.rightOrder,
    required this.pairs,
    required this.revealed,
    required this.onChanged,
  });

  final List<String> left;
  final List<String> right;
  final List<int> rightOrder;
  final List<int?> pairs; // pairs[leftIndex] = rightIndex
  final bool revealed;
  final ValueChanged<List<int?>> onChanged;

  @override
  State<_MatchBoard> createState() => _MatchBoardState();
}

class _MatchBoardState extends State<_MatchBoard> {
  int? _selectedLeft;

  void _tapLeft(int i) {
    if (widget.pairs[i] != null) {
      widget.onChanged([...widget.pairs]..[i] = null);
      setState(() => _selectedLeft = i);
    } else {
      // Always select (never toggle off): after a pair the next term is pre-selected, and
      // tapping it is the natural next step.
      setState(() => _selectedLeft = i);
    }
  }

  void _tapRight(int r) {
    final left = _selectedLeft;
    if (left == null) return;
    final pairs = [for (final p in widget.pairs) p == r ? null : p]..[left] = r;
    widget.onChanged(pairs);
    setState(() => _selectedLeft = pairs.indexWhere((p) => p == null) == -1 ? null : pairs.indexWhere((p) => p == null));
  }

  _TileState _leftState(int i) {
    if (!widget.revealed) return _selectedLeft == i ? _TileState.selected : _TileState.idle;
    return widget.pairs[i] == i ? _TileState.correct : _TileState.wrong;
  }

  @override
  Widget build(BuildContext context) {
    Color? colorFor(int leftIndex) => widget.revealed ? null : _pairColors[leftIndex % _pairColors.length];
    Widget tile(String label, _TileState state, VoidCallback? onTap, Color? pairColor) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Stack(
            children: [
              _ChoiceTile(label: label, state: state, onTap: onTap),
              if (pairColor != null)
                Positioned(left: 0, top: 8, bottom: 8, child: Container(width: 5, color: pairColor)),
            ],
          ),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < widget.left.length; i++)
                tile(
                  widget.left[i],
                  _leftState(i),
                  widget.revealed ? null : () => _tapLeft(i),
                  widget.pairs[i] != null ? colorFor(i) : null,
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            children: [
              for (final r in widget.rightOrder)
                () {
                  final owner = widget.pairs.indexOf(r);
                  final state = !widget.revealed
                      ? (owner >= 0 ? _TileState.selected : _TileState.idle)
                      : (owner == r ? _TileState.correct : (owner >= 0 ? _TileState.wrong : _TileState.idle));
                  return tile(widget.right[r], state, widget.revealed ? null : () => _tapRight(r), owner >= 0 ? colorFor(owner) : null);
                }(),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumericInput extends StatefulWidget {
  const _NumericInput({required this.decimals, required this.unit, required this.revealed, required this.onChanged});

  final int decimals;
  final String? unit;
  final bool revealed;
  final ValueChanged<double?> onChanged;

  @override
  State<_NumericInput> createState() => _NumericInputState();
}

class _NumericInputState extends State<_NumericInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: !widget.revealed,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-\s]'))],
      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
      decoration: InputDecoration(labelText: context.l10n.answerLabel, suffixText: widget.unit),
      onChanged: (text) => widget.onChanged(parseNumericAnswer(text, widget.decimals)),
    );
  }
}

/// Text of the right answer, shown after a mistake.
String correctAnswerText(BuildContext context, Exercise exercise) => switch (exercise) {
      MultipleChoiceExercise(:final options, :final answer) => options[answer],
      FillBlankExercise(:final options, :final answer) => options[answer],
      TrueFalseExercise(:final answer) => answer ? context.l10n.trueLabel : context.l10n.falseLabel,
      OrderExercise(:final items) => items.join(' → '),
      MatchExercise(:final left, :final right) => [for (var i = 0; i < left.length; i++) '${left[i]} → ${right[i]}'].join('; '),
      NumericExercise(:final answer, :final decimals, :final unit) =>
        '${NumberFormat.decimalPatternDigits(locale: Localizations.localeOf(context).toLanguageTag(), decimalDigits: decimals).format(answer)}${unit == null ? '' : ' $unit'}',
      InfoExercise() => '',
    };

String explanationOf(Exercise exercise) => switch (exercise) {
      MultipleChoiceExercise(:final explanation) ||
      TrueFalseExercise(:final explanation) ||
      FillBlankExercise(:final explanation) ||
      OrderExercise(:final explanation) ||
      MatchExercise(:final explanation) ||
      NumericExercise(:final explanation) =>
        explanation,
      InfoExercise() => '',
    };
