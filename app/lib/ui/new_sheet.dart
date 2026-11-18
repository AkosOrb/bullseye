// Új lap: fotózás segédkerettel vagy kép választása, majd kiértékelés.
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../services/analysis.dart';
import 'sheet_screen.dart';

enum SheetSource { camera, gallery }

/// Új lap felvétele. Ha [session] nincs megadva, a mai edzéshez kerül.
Future<void> startNewSheet(BuildContext context, {Session? session, SheetSource? source}) async {
  source ??= await showModalBottomSheet<SheetSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Lap fotózása'),
            subtitle: const Text('Segédkerettel a merőleges, teljes képhez'),
            onTap: () => Navigator.pop(ctx, SheetSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Kép választása a galériából'),
            onTap: () => Navigator.pop(ctx, SheetSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;
  Uint8List? bytes;
  if (source == SheetSource.camera && kIsWeb) {
    // Böngészőben a telefon saját kamerája nyílik meg.
    final f = await ImagePicker().pickImage(source: ImageSource.camera);
    bytes = await f?.readAsBytes();
  } else if (source == SheetSource.camera) {
    bytes = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(builder: (_) => const CaptureScreen()));
  } else {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    bytes = await f?.readAsBytes();
  }
  if (bytes == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProcessingScreen(bytes: bytes!, session: session)));
}

/// Kamera nézet segédkerettel: a fekete korongnak a körbe kell esnie.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  CameraController? _ctrl;
  String? _error;
  bool _busy = false;
  FlashMode _flash = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'Nem található kamera ezen az eszközön.');
        return;
      }
      final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(cam, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await c.setFlashMode(_flash);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _ctrl = c);
    } on CameraException catch (e) {
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'A kamera használata nincs engedélyezve. Engedélyezd a telefon beállításaiban, vagy válassz képet a galériából.'
          : 'A kamera nem indítható el (${e.code}). Válassz képet a galériából.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _ctrl = null;
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _ctrl;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      final f = await c.takePicture();
      final b = await f.readAsBytes();
      if (mounted) Navigator.of(context).pop(b);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A fotó nem készült el. Próbáld újra.')));
      }
    }
  }

  Future<void> _gallery() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    final b = await f?.readAsBytes();
    if (b != null && mounted) Navigator.of(context).pop(b);
  }

  Future<void> _toggleFlash() async {
    final next = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await _ctrl?.setFlashMode(next);
      setState(() => _flash = next);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Lap fotózása'),
        actions: [
          if (c != null)
            IconButton(
              tooltip: _flash == FlashMode.off ? 'Lámpa bekapcsolása' : 'Lámpa kikapcsolása',
              icon: Icon(_flash == FlashMode.off ? Icons.flashlight_off_outlined : Icons.flashlight_on),
              onPressed: _toggleFlash,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                    ),
                  )
                : c == null
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(builder: (context, box) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(child: CameraPreview(c)),
                            const IgnorePointer(child: CustomPaint(painter: _GuidePainter())),
                            const Positioned(
                              left: 16,
                              right: 16,
                              top: 12,
                              child: Text(
                                'Tartsd a telefont a lappal párhuzamosan. A fekete korong essen a körbe, a lap legyen teljesen a képen.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white, fontSize: 14, height: 1.3, shadows: [Shadow(blurRadius: 4)]),
                              ),
                            ),
                          ],
                        );
                      }),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Kép választása a galériából',
                    iconSize: 28,
                    color: Colors.white,
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: _gallery,
                  ),
                  Semantics(
                    button: true,
                    label: 'Fotó készítése',
                    child: GestureDetector(
                      onTap: c == null ? null : _shoot,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                        padding: const EdgeInsets.all(5),
                        child: Container(
                          decoration: BoxDecoration(shape: BoxShape.circle, color: _busy ? Colors.white54 : Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.92;
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dim);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.9);
    // sarokjelek
    const l = 28.0;
    for (final (o, dx, dy) in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(o, o + Offset(l * dx, 0), line..strokeWidth = 4);
      canvas.drawLine(o, o + Offset(0, l * dy), line);
    }
    // a fekete korong várható helye
    canvas.drawCircle(rect.center, side * 0.33, line..strokeWidth = 2);
    canvas.drawLine(rect.center - const Offset(10, 0), rect.center + const Offset(10, 0), line);
    canvas.drawLine(rect.center - const Offset(0, 10), rect.center + const Offset(0, 10), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Kiértékelés folyamatban; siker esetén a lap képernyőjére vált.
class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key, required this.bytes, this.session});
  final Uint8List bytes;
  final Session? session;
  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() => _error = null);
    final store = StoreScope.of(context);
    final expected = store.settings.defaultShots;
    try {
      final out = await analyzeInBackground(widget.bytes, store.settings.spec, expected);
      if (!mounted) return;
      if (out.error != null) {
        setState(() => _error = out.error);
        return;
      }
      final session = widget.session ?? store.todaySession();
      final sheet = await store.addSheet(session, out.jpeg, out.width, out.height, out.geometry, out.shots, expected);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SheetScreen(sheet: sheet, fresh: true)));
    } catch (e) {
      if (mounted) setState(() => _error = 'A kép feldolgozása nem sikerült: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kiértékelés')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _error == null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text('Találatok keresése…', style: t.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text('Kalibrálás, gyűrűk és lyukak felismerése. Ez néhány másodpercig tart.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ])
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 40, color: t.colorScheme.error),
                  const SizedBox(height: 16),
                  Text('Nem sikerült felismerni a lőlapot', style: t.textTheme.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    '$_error\n\nTipp: fotózz merőlegesen, egyenletes fényben, és a teljes fekete korong legyen a képen.',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      startNewSheet(nav.context, session: widget.session, source: SheetSource.camera);
                    },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Lap újrafotózása'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vissza')),
                ]),
        ),
      ),
    );
  }
}
