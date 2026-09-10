import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'matchday.dart';

String tacticsId() => '${DateTime.now().microsecondsSinceEpoch}-${_id++}';
int _id = 0;

class TacticsToken {
  const TacticsToken(
      {required this.id,
      required this.kind,
      required this.label,
      required this.position,
      this.playerId});
  final String id, kind, label;
  final Offset position;
  final String? playerId;
  TacticsToken copyWith({String? label, Offset? position}) => TacticsToken(
      id: id,
      kind: kind,
      label: label ?? this.label,
      position: position ?? this.position,
      playerId: playerId);
  factory TacticsToken.fromJson(Map<String, dynamic> json) => TacticsToken(
      id: json['id'],
      kind: json['kind'],
      label: json['label'],
      position:
          Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble()),
      playerId: json['playerId']);
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'label': label,
        'x': position.dx,
        'y': position.dy,
        if (playerId != null) 'playerId': playerId
      };
}

class TacticsStroke {
  TacticsStroke(
      {required this.id,
      required this.kind,
      required this.color,
      required List<Offset> points})
      : points = List.unmodifiable(points);
  final String id, kind, color;
  final List<Offset> points;
  factory TacticsStroke.fromJson(Map<String, dynamic> json) => TacticsStroke(
      id: json['id'],
      kind: json['kind'],
      color: json['color'],
      points: (json['points'] as List)
          .map((p) =>
              Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
          .toList());
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'color': color,
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList()
      };
}

class TacticsScene {
  TacticsScene(
      {required this.id,
      required this.name,
      List<TacticsToken> tokens = const [],
      List<TacticsStroke> strokes = const []})
      : tokens = List.unmodifiable(tokens),
        strokes = List.unmodifiable(strokes);
  final String id, name;
  final List<TacticsToken> tokens;
  final List<TacticsStroke> strokes;
  TacticsScene copyWith(
          {String? id,
          String? name,
          List<TacticsToken>? tokens,
          List<TacticsStroke>? strokes}) =>
      TacticsScene(
          id: id ?? this.id,
          name: name ?? this.name,
          tokens: tokens ?? this.tokens,
          strokes: strokes ?? this.strokes);
  factory TacticsScene.fromJson(Map<String, dynamic> json) => TacticsScene(
      id: json['id'],
      name: json['name'],
      tokens: (json['tokens'] as List)
          .map((t) => TacticsToken.fromJson(Map<String, dynamic>.from(t)))
          .toList(),
      strokes: (json['strokes'] as List)
          .map((s) => TacticsStroke.fromJson(Map<String, dynamic>.from(s)))
          .toList());
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tokens': tokens.map((t) => t.toJson()).toList(),
        'strokes': strokes.map((s) => s.toJson()).toList()
      };
}

class TacticsDocument {
  TacticsDocument(List<TacticsScene> scenes)
      : scenes = List.unmodifiable(scenes);
  final List<TacticsScene> scenes;
  factory TacticsDocument.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 || (json['scenes'] as List).isEmpty) {
      throw const FormatException('Unbekanntes Taktikboard-Format');
    }
    return TacticsDocument((json['scenes'] as List)
        .map((s) => TacticsScene.fromJson(Map<String, dynamic>.from(s)))
        .toList());
  }
  Map<String, dynamic> toJson() =>
      {'schemaVersion': 1, 'scenes': scenes.map((s) => s.toJson()).toList()};
  String get fingerprint => jsonEncode(toJson());

  factory TacticsDocument.fromLineup(List<LineupPositionModel> positions) =>
      TacticsDocument([
        TacticsScene(
            id: tacticsId(),
            name: 'Grundordnung',
            tokens: positions
                .take(30)
                .map((p) => TacticsToken(
                    id: tacticsId(),
                    kind: 'own',
                    playerId: p.player.id,
                    label: p.player.name.length > 50
                        ? p.player.name.substring(0, 50)
                        : p.player.name,
                    position: Offset(p.x.clamp(.04, .96), p.y.clamp(.04, .96))))
                .toList())
      ]);
}

class TacticsBoardSnapshot {
  const TacticsBoardSnapshot({required this.revision, this.document});
  final int revision;
  final TacticsDocument? document;
  factory TacticsBoardSnapshot.fromJson(Map<String, dynamic> json) =>
      TacticsBoardSnapshot(
          revision: json['revision'] as int,
          document: json['document'] == null
              ? null
              : TacticsDocument.fromJson(
                  Map<String, dynamic>.from(json['document'])));
}

/// Whole gestures form one history entry; resizing never changes stored points.
class TacticsEditor extends ChangeNotifier {
  TacticsEditor(this.document);
  TacticsDocument document;
  int index = 0;
  final _undo = <({TacticsDocument document, int index})>[];
  final _redo = <({TacticsDocument document, int index})>[];
  TacticsScene get scene => document.scenes[index];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void select(int value) {
    index = value;
    notifyListeners();
  }

  void change(TacticsDocument next, {int? selected}) {
    if (next.fingerprint == document.fingerprint) return;
    _undo.add((document: document, index: index));
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
    document = next;
    index = (selected ?? index).clamp(0, next.scenes.length - 1);
    notifyListeners();
  }

  void updateScene(TacticsScene next) => change(TacticsDocument([
        for (var i = 0; i < document.scenes.length; i++)
          i == index ? next : document.scenes[i],
      ]));
  void undo() {
    if (!canUndo) return;
    _redo.add((document: document, index: index));
    final previous = _undo.removeLast();
    document = previous.document;
    index = previous.index;
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add((document: document, index: index));
    final next = _redo.removeLast();
    document = next.document;
    index = next.index;
    notifyListeners();
  }
}
