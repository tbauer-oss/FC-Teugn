import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/models/matchday.dart';
import '../../core/models/tactics_board.dart';
import '../../core/widgets/adaptive_layout.dart';
import 'tactics_pitch.dart';

/// Private match preparation, deliberately separate from the actual lineup.
class TacticsBoardPage extends StatefulWidget {
  const TacticsBoardPage(
      {super.key,
      required this.title,
      required this.ownTeam,
      required this.opponent,
      required this.initialPositions,
      required this.players,
      required this.load,
      required this.save});
  final String title, ownTeam, opponent;
  final List<LineupPositionModel> initialPositions;
  final List<MatchPlayer> players;
  final Future<TacticsBoardSnapshot> Function() load;
  final Future<int> Function(TacticsDocument document, int revision) save;
  @override
  State<TacticsBoardPage> createState() => _TacticsBoardPageState();
}

class _TacticsBoardPageState extends State<TacticsBoardPage> {
  TacticsEditor? _editor;
  int _revision = 0;
  String _saved = '', _tool = 'move', _color = 'yellow';
  String? _error;
  bool _loading = true,
      _saving = false,
      _presentation = false,
      _allowPop = false;
  bool _hasEdits = false;
  List<Offset> _points = [];
  String? _dragId;
  Offset? _dragPosition, _dragStart, _pointerDown;
  final _transform = TransformationController();
  Size? _lastSize;
  bool get _dirty => _hasEdits;
  bool get _editable => !_saving && !_presentation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _editor?.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() => _hasEdits = _editor!.document.fingerprint != _saved);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final board = await widget.load();
      if (!mounted) return;
      _editor?.dispose();
      final document =
          board.document ?? TacticsDocument.fromLineup(widget.initialPositions);
      _editor = TacticsEditor(document)..addListener(_changed);
      _revision = board.revision;
      _saved = document.fingerprint;
      _hasEdits = false;
    } catch (_) {
      if (mounted) {
        _error =
            'Das Taktikboard konnte nicht geladen werden. Bitte die Verbindung prüfen.';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  scrollable: true,
                  title: Text(title),
                  content: Text(message),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Abbrechen')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(action)),
                  ])) ==
      true;

  Future<void> _close() async {
    if (_saving) return;
    if (_dirty &&
        !await _confirm(
            'Ungespeicherte Taktik',
            'Deine Änderungen sind noch nicht gespeichert. Wirklich schließen und verwerfen?',
            'Verwerfen')) {
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _save() async {
    if (_editor == null || _saving) return;
    setState(() => _saving = true);
    try {
      final document = _editor!.document;
      final revision = await widget.save(document, _revision);
      if (!mounted) return;
      setState(() {
        _revision = revision;
        _saved = document.fingerprint;
        _hasEdits = false;
      });
      _message('Taktik gespeichert · nur für das Trainerteam');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (error is DioException && error.response?.statusCode == 409) {
        // Never overwrite or silently reload a conflicting local draft.
        await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
                  scrollable: true,
                  title: const Text('Ein anderer Trainer war schneller'),
                  content: const Text(
                      'Dein Entwurf bleibt hier erhalten. Der gespeicherte Stand wurde '
                      'zwischenzeitlich geändert. Du kannst deinen Entwurf weiter ansehen oder über das Menü '
                      'den aktuellen Stand neu laden. Dabei wirst du vor dem Verwerfen gefragt.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Entwurf behalten'))
                  ],
                ));
      } else {
        _message(
            'Nicht gespeichert. Dein Entwurf bleibt geöffnet. Bitte Verbindung prüfen und erneut speichern.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _askText(String title,
      {String initial = '', int max = 50}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              scrollable: true,
              title: Text(title),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: max,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Bezeichnung'),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      Navigator.pop(ctx, value.trim());
                    }
                  }),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Abbrechen')),
                FilledButton(
                    onPressed: () {
                      if (controller.text.trim().isNotEmpty) {
                        Navigator.pop(ctx, controller.text.trim());
                      }
                    },
                    child: const Text('Übernehmen'))
              ],
            ));
    // The closing dialog may still be animating its text field.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    return result;
  }

  void _toolSelect(String tool) => setState(() {
        _tool = tool;
        _points = [];
        _dragId = null;
      });

  Future<void> _add(String kind) async {
    final editor = _editor!;
    if (editor.scene.tokens.length >= 40) {
      _message('Maximal 40 Elemente pro Spielzug.');
      return;
    }
    String? label, playerId;
    if (kind == 'own') {
      final available = widget.players
          .where((p) => !editor.scene.tokens.any((t) => t.playerId == p.id))
          .toList();
      if (available.isEmpty) {
        label = await _askText('Eigenen Spieler hinzufügen',
            initial:
                'Spieler ${editor.scene.tokens.where((t) => t.kind == 'own').length + 1}');
      } else {
        final player = await showModalBottomSheet<MatchPlayer>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            builder: (ctx) => SizedBox(
                height: MediaQuery.sizeOf(ctx).height * .65,
                child: Column(children: [
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Spieler aus dem Kader',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      child: ListView(children: [
                    for (final p in available)
                      ListTile(
                          title: Text(p.name),
                          leading: const Icon(Icons.person_add_outlined),
                          onTap: () => Navigator.pop(ctx, p))
                  ])),
                ])));
        if (player == null) return;
        label = player.name.length > 50
            ? player.name.substring(0, 50)
            : player.name;
        playerId = player.id;
      }
    } else if (kind == 'ball') {
      label = 'Ball';
    } else {
      label = await _askText(
          kind == 'text' ? 'Beschriftung' : 'Gegner eintragen',
          initial: kind == 'text'
              ? ''
              : '${editor.scene.tokens.where((t) => t.kind == 'opponent').length + 1}');
    }
    if (label == null || !mounted) return;
    final count = editor.scene.tokens.where((t) => t.kind == kind).length;
    final point = kind == 'ball' || kind == 'text'
        ? const Offset(.5, .5)
        : Offset(.2 + (count % 4) * .2,
            (kind == 'opponent' ? .18 : .62) + (count ~/ 4 % 3) * .08);
    editor.updateScene(editor.scene.copyWith(tokens: [
      ...editor.scene.tokens,
      TacticsToken(
          id: tacticsId(),
          kind: kind,
          label: label,
          playerId: playerId,
          position: point)
    ]));
    _toolSelect('move');
  }

  Future<void> _editToken(TacticsToken token) async {
    if (!_editable || token.kind == 'ball') return;
    final label = await _askText('Element beschriften', initial: token.label);
    if (!mounted || label == null) return;
    _editor!.updateScene(_editor!.scene.copyWith(tokens: [
      for (final t in _editor!.scene.tokens)
        t.id == token.id ? t.copyWith(label: label) : t
    ]));
  }

  Future<void> _menu(String action) async {
    if (_saving || _editor == null) return;
    final editor = _editor!;
    if (action == 'reload') {
      if (_dirty &&
          !await _confirm('Aktuellen Stand laden?',
              'Dein ungespeicherter Entwurf wird verworfen.', 'Neu laden')) {
        return;
      }
      if (mounted) await _load();
    } else if (action == 'new' || action == 'copy') {
      if (editor.document.scenes.length >= 8) {
        _message('Maximal acht Spielzüge pro Spiel.');
        return;
      }
      final name = await _askText(
          action == 'copy' ? 'Spielzug duplizieren' : 'Neuer Spielzug',
          initial: action == 'copy'
              ? '${editor.scene.name} Kopie'.characters.take(80).toString()
              : 'Spielzug ${editor.document.scenes.length + 1}',
          max: 80);
      if (!mounted || name == null) return;
      final scene = action == 'copy'
          ? editor.scene.copyWith(id: tacticsId(), name: name)
          : TacticsDocument.fromLineup(widget.initialPositions)
              .scenes
              .first
              .copyWith(name: name);
      editor.change(TacticsDocument([...editor.document.scenes, scene]),
          selected: editor.document.scenes.length);
    } else if (action == 'rename') {
      final name = await _askText('Spielzug umbenennen',
          initial: editor.scene.name, max: 80);
      if (mounted && name != null) {
        editor.updateScene(editor.scene.copyWith(name: name));
      }
    } else if (action == 'delete') {
      if (editor.document.scenes.length == 1) {
        _message('Mindestens ein Spielzug bleibt bestehen.');
        return;
      }
      if (await _confirm(
              'Spielzug löschen?',
              '„${editor.scene.name}“ wird entfernt. Rückgängig bleibt möglich.',
              'Löschen') &&
          mounted) {
        editor.change(TacticsDocument(editor.document.scenes
            .where((s) => s.id != editor.scene.id)
            .toList()));
      }
    } else if (action == 'clear') {
      if (await _confirm(
              'Zeichnungen entfernen?',
              'Spieler und Gegner bleiben stehen. Rückgängig bleibt möglich.',
              'Entfernen') &&
          mounted) {
        editor.updateScene(editor.scene.copyWith(strokes: []));
      }
    } else if (action == 'lineup') {
      if (await _confirm(
              'Aufstellung übernehmen?',
              'Eigene Spieler werden auf die Ausgangsaufstellung gesetzt. Gegner und Zeichnungen bleiben erhalten.',
              'Übernehmen') &&
          mounted) {
        final own = TacticsDocument.fromLineup(widget.initialPositions)
            .scenes
            .first
            .tokens;
        final other =
            editor.scene.tokens.where((t) => t.kind != 'own').toList();
        if (own.length + other.length > 40) {
          _message('Bitte zuerst Elemente entfernen (maximal 40).');
          return;
        }
        editor.updateScene(editor.scene.copyWith(tokens: [...other, ...own]));
      }
    }
  }

  Widget _button(String label, IconData icon, VoidCallback? onTap,
          {bool selected = false}) =>
      Tooltip(
          message: label,
          child: TextButton.icon(
              key: ValueKey('tactics-$label'),
              onPressed: onTap,
              style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: selected ? tacticsInk : Colors.white,
                  backgroundColor: selected
                      ? tacticsYellow
                      : Colors.white.withValues(alpha: .055),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              icon: Icon(icon, size: 20),
              label: Text(label)));

  Widget _tools(bool sidebar) {
    final children = <Widget>[
      for (final tool in const [
        ('move', 'Verschieben', Icons.pan_tool_outlined),
        ('pen', 'Stift', Icons.edit_outlined),
        ('arrow', 'Passpfeil', Icons.arrow_forward_rounded),
        ('run', 'Laufweg', Icons.trending_up_rounded),
        ('zone', 'Raum', Icons.crop_square_rounded),
        ('erase', 'Radierer', Icons.auto_fix_normal_rounded),
        ('zoom', 'Zoom', Icons.zoom_in_rounded),
      ])
        _button(tool.$2, tool.$3, _editable ? () => _toolSelect(tool.$1) : null,
            selected: _tool == tool.$1),
      _button('Spieler', Icons.person_add_alt,
          _editable ? () => _add('own') : null),
      _button('Gegner', Icons.person_add_outlined,
          _editable ? () => _add('opponent') : null),
      _button(
          'Ball', Icons.sports_soccer, _editable ? () => _add('ball') : null),
      _button('Text', Icons.title, _editable ? () => _add('text') : null),
    ];
    final colors = Row(mainAxisSize: MainAxisSize.min, children: [
      for (final entry in tacticsColors.entries)
        Tooltip(
            message: 'Farbe ${{
              'yellow': 'Gelb',
              'cyan': 'Türkis',
              'white': 'Weiß',
              'red': 'Rot'
            }[entry.key]}',
            child: IconButton(
              key: ValueKey('tactics-color-${entry.key}'),
              onPressed:
                  _editable ? () => setState(() => _color = entry.key) : null,
              icon: Icon(
                  _color == entry.key ? Icons.check_circle : Icons.circle,
                  color: entry.value),
            )),
    ]);
    if (sidebar) {
      return SizedBox(
          width: 208,
          child: ListView(padding: const EdgeInsets.all(8), children: [
            const Text('WERKZEUGE',
                style: TextStyle(
                    fontSize: 11, color: Colors.white60, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 4), child: child),
            colors,
            _button('Zentrieren', Icons.center_focus_strong,
                () => _transform.value = Matrix4.identity()),
          ]));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            for (final child in children)
              Padding(padding: const EdgeInsets.only(right: 4), child: child)
          ])),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            colors,
            _button('Ansicht zentrieren', Icons.center_focus_strong,
                () => _transform.value = Matrix4.identity()),
          ])),
    ]);
  }

  TacticsToken? _hitToken(Offset point, Size size, bool landscape) {
    for (final token in _editor!.scene.tokens.reversed) {
      final center = tacticsToScreen(token.position, size, landscape);
      final markerRect = Rect.fromLTWH(
          (center.dx - 40).clamp(0, math.max(0, size.width - 80)),
          (center.dy - 17).clamp(0, math.max(0, size.height - 62)),
          80,
          62);
      if (markerRect.contains(point)) {
        return token;
      }
    }
    return null;
  }

  void _erase(Offset point, Size size, bool landscape) {
    final editor = _editor!;
    final token = _hitToken(point, size, landscape);
    if (token != null) {
      editor.updateScene(editor.scene.copyWith(
          tokens: editor.scene.tokens.where((t) => t.id != token.id).toList()));
      return;
    }
    for (final stroke in editor.scene.strokes.reversed) {
      final pts = stroke.points
          .map((p) => tacticsToScreen(p, size, landscape))
          .toList();
      final hit = stroke.kind == 'zone'
          ? Rect.fromPoints(pts.first, pts.last).inflate(10).contains(point)
          : List.generate(pts.length - 1,
                  (i) => tacticsSegmentDistance(point, pts[i], pts[i + 1]))
              .any((d) => d < 12);
      if (hit) {
        editor.updateScene(editor.scene.copyWith(
            strokes:
                editor.scene.strokes.where((s) => s.id != stroke.id).toList()));
        return;
      }
    }
  }

  Widget _pitch() => LayoutBuilder(builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final ratio = landscape ? 1.5 : 2 / 3;
        final width =
            math.min(constraints.maxWidth, constraints.maxHeight * ratio);
        final size = Size(math.max(1, width), math.max(1, width / ratio));
        if (_lastSize != size) {
          _lastSize = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _transform.value = Matrix4.identity();
          });
          // A fold/rotation cancels the current gesture, never the saved positions.
          _points = [];
          _dragId = null;
        }
        final scene = _editor!.scene;
        final preview = _points.length >= 2
            ? TacticsStroke(
                id: 'preview', kind: _tool, color: _color, points: _points)
            : null;
        return Center(
            child: SizedBox.fromSize(
                size: size,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    transformationController: _transform,
                    minScale: 1,
                    maxScale: 3,
                    panEnabled: _tool == 'zoom',
                    scaleEnabled: _tool == 'zoom',
                    child: GestureDetector(
                      key: const ValueKey('tactics-pitch'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: !_editable || _tool == 'zoom'
                          ? null
                          : (event) {
                              if (_tool == 'erase') {
                                _erase(event.localPosition, size, landscape);
                                return;
                              }
                              if (_tool == 'move') {
                                final token = _hitToken(
                                    event.localPosition, size, landscape);
                                if (token != null) _editToken(token);
                              }
                            },
                      onPanDown: (event) => _pointerDown = event.localPosition,
                      onPanStart: !_editable || _tool == 'zoom'
                          ? null
                          : (event) {
                              final p = tacticsFromScreen(
                                  _pointerDown ?? event.localPosition,
                                  size,
                                  landscape);
                              final current = tacticsFromScreen(
                                  event.localPosition, size, landscape);
                              if (_tool == 'move') {
                                final token = _hitToken(
                                    _pointerDown ?? event.localPosition,
                                    size,
                                    landscape);
                                setState(() {
                                  _dragId = token?.id;
                                  final moved = token == null
                                      ? null
                                      : token.position + current - p;
                                  _dragPosition = moved == null
                                      ? null
                                      : Offset(moved.dx.clamp(0, 1),
                                          moved.dy.clamp(0, 1));
                                  _dragStart = p;
                                });
                              } else if (_tool != 'erase') {
                                setState(() => _points = [p, current]);
                              }
                            },
                      onPanUpdate: !_editable || _tool == 'zoom'
                          ? null
                          : (event) {
                              final p = tacticsFromScreen(
                                  event.localPosition, size, landscape);
                              setState(() {
                                if (_dragId != null) {
                                  final original = scene.tokens
                                      .firstWhere((t) => t.id == _dragId)
                                      .position;
                                  final next = original + p - _dragStart!;
                                  _dragPosition = Offset(
                                      next.dx.clamp(0, 1), next.dy.clamp(0, 1));
                                } else if (_points.isNotEmpty) {
                                  if (_tool == 'pen') {
                                    if ((_points.last - p).distance < .003) {
                                      return;
                                    }
                                    if (_points.length >= 160) {
                                      _points = [
                                        for (var i = 0;
                                            i < _points.length;
                                            i += 2)
                                          _points[i]
                                      ];
                                    }
                                    _points = [..._points, p];
                                  } else {
                                    _points = [_points.first, p];
                                  }
                                }
                              });
                            },
                      onPanEnd: !_editable || _tool == 'zoom'
                          ? null
                          : (_) {
                              if (_dragId != null) {
                                _editor!.updateScene(scene.copyWith(tokens: [
                                  for (final t in scene.tokens)
                                    t.id == _dragId
                                        ? t.copyWith(position: _dragPosition)
                                        : t
                                ]));
                              } else if (_points.length >= 2 &&
                                  (_tool == 'pen' && _points.length > 2 ||
                                      (_points.first - _points.last).distance >
                                          .005)) {
                                final total = _editor!.document.scenes
                                    .expand((s) => s.strokes)
                                    .fold(0, (int n, s) => n + s.points.length);
                                if (scene.strokes.length >= 80 ||
                                    total + _points.length > 8000) {
                                  _message(
                                      'Zeichenlimit erreicht. Bitte nicht benötigte Zeichnungen entfernen.');
                                } else {
                                  _editor!.updateScene(scene.copyWith(strokes: [
                                    ...scene.strokes,
                                    TacticsStroke(
                                        id: tacticsId(),
                                        kind: _tool,
                                        color: _color,
                                        points: _points)
                                  ]));
                                }
                              }
                              setState(() {
                                _points = [];
                                _dragId = null;
                              });
                            },
                      onPanCancel: () => setState(() {
                        _points = [];
                        _dragId = null;
                      }),
                      child: CustomPaint(
                        painter: TacticsPitchPainter(strokes: [
                          ...scene.strokes,
                          if (preview != null) preview
                        ], landscape: landscape),
                        child: Stack(children: [
                          for (final token in scene.tokens)
                            Builder(builder: (_) {
                              final current = token.id == _dragId
                                  ? token.copyWith(position: _dragPosition)
                                  : token;
                              final point = tacticsToScreen(
                                  current.position, size, landscape);
                              return Positioned(
                                  left: (point.dx - 40)
                                      .clamp(0, math.max(0, size.width - 80)),
                                  top: (point.dy - 17)
                                      .clamp(0, math.max(0, size.height - 62)),
                                  width: 80,
                                  child: TacticsMarker(
                                      token: current,
                                      onTap: _editable
                                          ? () => _editToken(current)
                                          : null));
                            })
                        ]),
                      ),
                    ),
                  ),
                )));
      });

  @override
  Widget build(BuildContext context) {
    final boardTheme = ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: tacticsYellow,
            brightness: Brightness.dark,
            primary: tacticsYellow,
            onPrimary: tacticsInk,
            surface: tacticsInk),
        scaffoldBackgroundColor: tacticsInk);
    return PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: Theme(
            data: boardTheme,
            child: ColoredBox(
                color: tacticsInk,
                child: AdaptiveHingePane(
                    child: Scaffold(
                  body: SafeArea(
                      child: Column(children: [
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(children: [
                          IconButton(
                              tooltip: 'Taktikboard schließen',
                              onPressed: _saving ? null : _close,
                              icon: const Icon(Icons.close)),
                          Expanded(
                              child: Text(
                                  _presentation ? 'Besprechung' : 'Taktikboard',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800))),
                          if (_editor != null && !_loading) ...[
                            IconButton(
                                tooltip: _presentation
                                    ? 'Werkzeuge anzeigen'
                                    : 'Präsentieren',
                                onPressed: _saving
                                    ? null
                                    : () => setState(() {
                                          _presentation = !_presentation;
                                          _points = [];
                                          _dragId = null;
                                        }),
                                icon: Icon(_presentation
                                    ? Icons.edit_outlined
                                    : Icons.slideshow_rounded)),
                            if (!_presentation)
                              IconButton(
                                  tooltip: _saving
                                      ? 'Wird gespeichert'
                                      : 'Taktik speichern',
                                  onPressed: _saving ? null : _save,
                                  icon: _saving
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : Icon(Icons.save_outlined,
                                          color: _dirty
                                              ? tacticsYellow
                                              : Colors.white)),
                            if (!_presentation)
                              PopupMenuButton<String>(
                                  tooltip: 'Taktikoptionen',
                                  enabled: !_saving,
                                  onSelected: _menu,
                                  itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'new',
                                            child: Text('Neuer Spielzug')),
                                        PopupMenuItem(
                                            value: 'copy',
                                            child:
                                                Text('Spielzug duplizieren')),
                                        PopupMenuItem(
                                            value: 'rename',
                                            child: Text('Spielzug umbenennen')),
                                        PopupMenuItem(
                                            value: 'lineup',
                                            child: Text(
                                                'Ausgangsaufstellung übernehmen')),
                                        PopupMenuItem(
                                            value: 'clear',
                                            child:
                                                Text('Zeichnungen entfernen')),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Spielzug löschen')),
                                        PopupMenuItem(
                                            value: 'reload',
                                            child: Text(
                                                'Gespeicherten Stand laden')),
                                      ]),
                          ],
                        ])),
                    if (_loading)
                      const Expanded(
                          child: Center(child: CircularProgressIndicator()))
                    else if (_error != null)
                      Expanded(
                          child: Center(
                              child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_error!),
                                        TextButton(
                                            onPressed: _load,
                                            child: const Text('Erneut laden'))
                                      ]))))
                    else ...[
                      if (!_presentation)
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                    '${widget.title}\nTrainerintern · ${_dirty ? 'Ungespeichert' : _revision == 0 ? 'Neuer Entwurf' : 'Gespeichert'}',
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 12)))),
                      Row(children: [
                        Expanded(
                            child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(children: [
                                  for (var i = 0;
                                      i < _editor!.document.scenes.length;
                                      i++)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: ChoiceChip(
                                          label: Text(
                                              _editor!.document.scenes[i].name),
                                          selected: _editor!.index == i,
                                          onSelected: _saving
                                              ? null
                                              : (_) {
                                                  _editor!.select(i);
                                                  _toolSelect(_tool);
                                                },
                                        )),
                                ]))),
                        if (!_presentation) ...[
                          IconButton(
                              tooltip: 'Rückgängig',
                              onPressed: !_saving && _editor!.canUndo
                                  ? _editor!.undo
                                  : null,
                              icon: const Icon(Icons.undo)),
                          IconButton(
                              tooltip: 'Wiederholen',
                              onPressed: !_saving && _editor!.canRedo
                                  ? _editor!.redo
                                  : null,
                              icon: const Icon(Icons.redo)),
                        ],
                      ]),
                      Expanded(
                          child: LayoutBuilder(builder: (context, constraints) {
                        final sidebar =
                            !_presentation && constraints.maxWidth >= 600;
                        return Column(children: [
                          Expanded(
                              child: Row(children: [
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: _pitch())),
                            if (sidebar) _tools(true),
                          ])),
                          if (!_presentation && !sidebar) _tools(false),
                        ]);
                      })),
                      if (_presentation)
                        Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 16,
                                runSpacing: 4,
                                children: [
                                  Text('● ${widget.ownTeam}',
                                      style: const TextStyle(
                                          color: tacticsYellow)),
                                  Text('● ${widget.opponent}',
                                      style: const TextStyle(
                                          color: Color(0xFF65D9ED))),
                                ])),
                    ],
                  ])),
                )))));
  }
}
