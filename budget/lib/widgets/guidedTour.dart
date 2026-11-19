import 'dart:async';

import 'package:budget/colors.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/helpGuide.dart';
import 'package:budget/main.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Spotlight tour: dims the screen, highlights one real widget at a time and
// shows a bubble with a short text, Back / Next / Skip and a step counter.
// Steps whose widget is not on screen (e.g. the bottom bar on desktop) are
// skipped

class GuidedTourStep {
  const GuidedTourStep({required this.targets, required this.text});
  // The first target that is laid out and on screen is highlighted
  final List<GlobalKey> targets;
  final String text;
}

OverlayEntry? _currentTourEntry;

bool isGuidedTourOpen() => _currentTourEntry != null;

Future<void> showGuidedTour(
    BuildContext context, List<GuidedTourStep> steps) async {
  if (_currentTourEntry != null) return;
  OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  List<GuidedTourStep> available = steps
      .where((step) => _findTarget(step, overlay.context) != null)
      .toList();
  if (available.isEmpty) return;
  Completer<void> completer = Completer();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _GuidedTourOverlay(
      steps: available,
      onClose: () {
        entry.remove();
        _currentTourEntry = null;
        if (!completer.isCompleted) completer.complete();
      },
    ),
  );
  _currentTourEntry = entry;
  overlay.insert(entry);
  return completer.future;
}

// Target context and its rect in the overlay, or null when not visible
(BuildContext, Rect)? _findTarget(GuidedTourStep step, BuildContext overlay) {
  RenderObject? overlayBox = overlay.findRenderObject();
  if (overlayBox is! RenderBox || !overlayBox.hasSize) return null;
  Size screen = overlayBox.size;
  for (GlobalKey key in step.targets) {
    BuildContext? targetContext = key.currentContext;
    RenderObject? box = targetContext?.findRenderObject();
    if (targetContext == null ||
        box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.width < 2 ||
        box.size.height < 2) continue;
    // Through global coordinates: the overlay box is not always an ancestor
    Offset topLeft = overlayBox.globalToLocal(box.localToGlobal(Offset.zero));
    Rect rect = topLeft & box.size;
    bool inScrollable = Scrollable.maybeOf(targetContext) != null;
    // A scrolled away target can be brought back, a hidden one cannot
    if (!inScrollable && !rect.overlaps(Offset.zero & screen)) continue;
    return (targetContext, rect);
  }
  return null;
}

class _GuidedTourOverlay extends StatefulWidget {
  const _GuidedTourOverlay({required this.steps, required this.onClose});
  final List<GuidedTourStep> steps;
  final VoidCallback onClose;

  @override
  State<_GuidedTourOverlay> createState() => _GuidedTourOverlayState();
}

class _GuidedTourOverlayState extends State<_GuidedTourOverlay>
    with SingleTickerProviderStateMixin {
  int index = 0;
  Rect? fromRect;
  Rect? targetRect;
  bool closing = false;
  Timer? followTimer;
  FocusNode focusNode = FocusNode();
  late AnimationController moveController = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 380),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => goTo(0, 1));
    // Follows the target if the layout moves (window resize, late content)
    followTimer = Timer.periodic(Duration(milliseconds: 250), (_) {
      if (moveController.isAnimating || closing) return;
      Rect? rect = measure(index);
      if (rect != null && rect != targetRect) {
        setState(() => targetRect = rect);
      }
    });
  }

  @override
  void dispose() {
    followTimer?.cancel();
    moveController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  Rect? measure(int stepIndex) {
    if (stepIndex < 0 || stepIndex >= widget.steps.length) return null;
    return _findTarget(widget.steps[stepIndex], context)?.$2;
  }

  // Moves to the first visible step from stepIndex in the given direction
  Future<void> goTo(int stepIndex, int direction) async {
    while (stepIndex >= 0 && stepIndex < widget.steps.length) {
      (BuildContext, Rect)? found =
          _findTarget(widget.steps[stepIndex], context);
      if (found != null) {
        if (Scrollable.maybeOf(found.$1) != null) {
          await Scrollable.ensureVisible(
            found.$1,
            alignment: 0.3,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
          );
          if (!mounted) return;
        }
        Rect? rect = measure(stepIndex);
        if (rect != null) {
          Rect? current = currentRect();
          setState(() {
            index = stepIndex;
            fromRect = current ?? rect;
            targetRect = rect;
          });
          moveController.forward(from: 0);
          focusNode.requestFocus();
          return;
        }
      }
      stepIndex += direction;
    }
    // Nothing left to show going forward ends the tour
    if (direction > 0) close();
  }

  Rect? currentRect() {
    if (targetRect == null) return null;
    double t = Curves.easeInOutCubic.transform(moveController.value);
    return Rect.lerp(fromRect ?? targetRect, targetRect, t);
  }

  void next() {
    if (index + 1 >= widget.steps.length) {
      close();
    } else {
      goTo(index + 1, 1);
    }
  }

  void back() {
    if (index > 0) goTo(index - 1, -1);
  }

  void close() {
    if (closing) return;
    setState(() => closing = true);
    Future.delayed(Duration(milliseconds: 250), widget.onClose);
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      close();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      next();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      back();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: onKey,
      child: AnimatedOpacity(
        opacity: closing || targetRect == null ? 0 : 1,
        duration: Duration(milliseconds: 250),
        child: AnimatedBuilder(
          animation: moveController,
          builder: (context, _) {
            Rect? rect = currentRect();
            if (rect == null) return SizedBox.expand();
            Rect hole = rect.inflate(6);
            return Stack(
              children: [
                // Blocks taps on the app while the tour is open
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: CustomPaint(
                      painter: _SpotlightPainter(
                        hole: hole,
                        dimColor: Colors.black.withOpacity(0.68),
                        ringColor: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomSingleChildLayout(
                    delegate: _BubbleLayout(hole: hole),
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: 200),
                      child: _TourBubble(
                        key: ValueKey(index),
                        text: widget.steps[index].text,
                        current: index + 1,
                        total: widget.steps.length,
                        onNext: next,
                        onBack: index > 0 ? back : null,
                        onSkip: close,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(
      {required this.hole, required this.dimColor, required this.ringColor});
  final Rect hole;
  final Color dimColor;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    RRect holeRRect = RRect.fromRectAndRadius(hole, Radius.circular(16));
    Path dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(holeRRect),
    );
    canvas.drawPath(dim, Paint()..color = dimColor);
    canvas.drawRRect(
      holeRRect,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole ||
      oldDelegate.dimColor != dimColor ||
      oldDelegate.ringColor != ringColor;
}

// Puts the bubble below the highlight, else above, else beside it, else
// over its lower part
class _BubbleLayout extends SingleChildLayoutDelegate {
  _BubbleLayout({required this.hole});
  final Rect hole;
  static const double margin = 16;
  static const double gap = 12;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    double maxWidth = constraints.maxWidth - margin * 2;
    if (maxWidth > 360) maxWidth = 360;
    return BoxConstraints(
      minWidth: maxWidth,
      maxWidth: maxWidth,
      maxHeight: constraints.maxHeight - margin * 2,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double clampX(double x) =>
        x.clamp(margin, size.width - childSize.width - margin).toDouble();
    double clampY(double y) =>
        y.clamp(margin, size.height - childSize.height - margin).toDouble();
    double centeredX = clampX(hole.center.dx - childSize.width / 2);
    if (hole.bottom + gap + childSize.height <= size.height - margin) {
      return Offset(centeredX, hole.bottom + gap);
    }
    if (hole.top - gap - childSize.height >= margin) {
      return Offset(centeredX, hole.top - gap - childSize.height);
    }
    double centeredY = clampY(hole.center.dy - childSize.height / 2);
    if (hole.right + gap + childSize.width <= size.width - margin) {
      return Offset(hole.right + gap, centeredY);
    }
    if (hole.left - gap - childSize.width >= margin) {
      return Offset(hole.left - gap - childSize.width, centeredY);
    }
    return Offset(centeredX, clampY(hole.bottom - childSize.height - gap));
  }

  @override
  bool shouldRelayout(_BubbleLayout oldDelegate) => oldDelegate.hole != hole;
}

class _TourBubble extends StatelessWidget {
  const _TourBubble({
    required this.text,
    required this.current,
    required this.total,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
    super.key,
  });
  final String text;
  final int current;
  final int total;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    bool last = current >= total;
    return Material(
      color: getColor(context, "lightDarkAccentHeavyLight"),
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
            start: 18, end: 8, top: 6, bottom: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFont(
                    text: "tour-step-counter".tr(namedArgs: {
                      "current": current.toString(),
                      "total": total.toString(),
                    }),
                    fontSize: 14,
                    textColor: getColor(context, "textLight"),
                  ),
                ),
                TextButton(
                  onPressed: onSkip,
                  child: TextFont(
                    text: "tour-skip".tr(),
                    fontSize: 15,
                    textColor: colors.primary,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: TextFont(
                text: text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                maxLines: 6,
              ),
            ),
            SizedBox(height: 14),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Row(
                children: [
                  if (onBack != null)
                    Button(
                      label: "tour-back".tr(),
                      onTap: onBack!,
                      color: getColor(context, "lightDarkAccentHeavy"),
                      textColor: getColor(context, "black"),
                    ),
                  Spacer(),
                  Button(
                    label: last ? "tour-done".tr() : "tour-next".tr(),
                    onTap: onNext,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Home tour

class HomeTourKeys {
  final GlobalKey addButton = GlobalKey();
  final GlobalKey accounts = GlobalKey();
  final GlobalKey summary = GlobalKey();
  final GlobalKey aiChat = GlobalKey();
  final GlobalKey drive = GlobalKey();
  final GlobalKey privacy = GlobalKey();
  final GlobalKey navigation = GlobalKey();
  final GlobalKey help = GlobalKey();
}

final HomeTourKeys homeTourKeys = HomeTourKeys();

const String homeTourSeenSetting = "homeTourSeen";

List<GuidedTourStep> getHomeTourSteps() {
  return [
    GuidedTourStep(targets: [homeTourKeys.addButton], text: "tour-add".tr()),
    GuidedTourStep(
        targets: [homeTourKeys.accounts], text: "tour-accounts".tr()),
    GuidedTourStep(targets: [homeTourKeys.summary], text: "tour-summary".tr()),
    GuidedTourStep(targets: [homeTourKeys.aiChat], text: "tour-ai-chat".tr()),
    GuidedTourStep(targets: [homeTourKeys.drive], text: "tour-drive".tr()),
    GuidedTourStep(targets: [homeTourKeys.privacy], text: "tour-privacy".tr()),
    // The sidebar takes the place of the bottom bar on wide screens
    GuidedTourStep(
      targets: [homeTourKeys.navigation, sidebarStateKey],
      text: "tour-navigation".tr(),
    ),
    GuidedTourStep(targets: [homeTourKeys.help], text: "tour-help".tr()),
  ];
}

Future<void> startHomeTour(BuildContext context) async {
  if (isGuidedTourOpen()) return;
  await updateSettings(homeTourSeenSetting, true, updateGlobalState: false);
  // The tour covers what the first-time tip card says; hide it before
  // measuring so the layout does not move under the spotlight
  if (!helpGuideSeen("home")) {
    await markHelpGuideSeen("home");
    await Future.delayed(Duration(milliseconds: 400));
  }
  if (!context.mounted) return;
  await showGuidedTour(context, getHomeTourSteps());
}

// Runs the tour once, the first time Home is on screen with nothing above it
Future<void> maybeStartHomeTour(BuildContext context) async {
  for (int attempt = 0; attempt < 30; attempt++) {
    await Future.delayed(Duration(milliseconds: attempt == 0 ? 1200 : 1000));
    if (!context.mounted) return;
    if (appStateSettings[homeTourSeenSetting] == true) return;
    bool onHome = pageNavigationFrameworkKey.currentState?.currentPage == 0;
    bool nothingAbove = ModalRoute.of(context)?.isCurrent ?? true;
    if (onHome && nothingAbove && !isGuidedTourOpen()) {
      await startHomeTour(context);
      return;
    }
  }
}
