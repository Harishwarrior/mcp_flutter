// Copyright 2020 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

// ignore_for_file: avoid-explicit-type-declaration, forked code from Flutter framework.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [ScrollView] that uses a single child layout model and allows for custom
/// handling of [PointerSignalEvent]s.
///
/// This class is copied from the Flutter framework [BoxScrollView] and
/// overrides [ScrollView.build] to use [CustomPointerScrollable] in place of
/// [Scrollable].
abstract class CustomPointerScrollView extends BoxScrollView {
  /// Creates a [ScrollView] uses a single child layout model.
  ///
  /// If the [primary] argument is true, the [controller] must be null.
  const CustomPointerScrollView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding,
    super.cacheExtent,
    super.semanticChildCount,
    super.dragStartBehavior,
    this.customPointerSignalHandler,
  }) : _primary =
           primary ??
           controller == null && identical(scrollDirection, Axis.vertical);

  final void Function(PointerSignalEvent event)? customPointerSignalHandler;

  // TODO(Piinks): Restore once PSC changes have landed, or keep to maintain
  // original primary behavior.
  final bool _primary;

  @override
  Widget build(final BuildContext context) {
    final List<Widget> slivers = buildSlivers(context);
    final AxisDirection axisDirection = getDirection(context);

    final ScrollController? scrollController =
        _primary ? PrimaryScrollController.of(context) : controller;

    assert(
      scrollController != null,
      'No ScrollController has been provided to the CustomPointerScrollView. '
      'Either provide a controller or set primary to true to use the PrimaryScrollController.',
    );

    final scrollable = CustomPointerScrollable(
      dragStartBehavior: dragStartBehavior,
      axisDirection: axisDirection,
      controller: scrollController,
      physics: physics,
      semanticChildCount: semanticChildCount,
      viewportBuilder:
          (final context, final offset) =>
              buildViewport(context, offset, axisDirection, slivers),
      customPointerSignalHandler: customPointerSignalHandler,
    );
    return _primary
        ? PrimaryScrollController.none(child: scrollable)
        : scrollable;
  }
}

/// A widget that scrolls and allows custom pointer signal event handling.
///
/// This widget is a copy of [Scrollable] with additional support for custom
/// pointer signal event handling via [customPointerSignalHandler].
class CustomPointerScrollable extends StatefulWidget {
  const CustomPointerScrollable({
    required this.viewportBuilder,
    super.key,
    this.axisDirection = AxisDirection.down,
    this.controller,
    this.physics,
    this.incrementCalculator,
    this.excludeFromSemantics = false,
    this.semanticChildCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.customPointerSignalHandler,
  }) : assert(
         semanticChildCount == null || semanticChildCount >= 0,
         'semanticChildCount must be null or greater than or equal to 0',
       );

  /// The direction in which this widget scrolls.
  ///
  /// For example, if the [axisDirection] is [AxisDirection.down], increasing
  /// the scroll position will cause content below the bottom of the viewport to
  /// become visible through the viewport. Similarly, if [axisDirection] is
  /// [AxisDirection.right], increasing the scroll position will cause content
  /// beyond the right edge of the viewport to become visible through the
  /// viewport.
  ///
  /// Defaults to [AxisDirection.down].
  final AxisDirection axisDirection;

  /// An object that can be used to control the position to which this widget is
  /// scrolled.
  ///
  /// A [ScrollController] serves several purposes. It can be used to control
  /// the initial scroll position (see [ScrollController.initialScrollOffset]).
  /// It can be used to control whether the scroll view should automatically
  /// save and restore its scroll position in the [PageStorage] (see
  /// [ScrollController.keepScrollOffset]). It can be used to read the current
  /// scroll position (see [ScrollController.offset]), or change it (see
  /// [ScrollController.animateTo]).
  ///
  /// See also:
  ///
  ///  * [ensureVisible], which animates the scroll position to reveal a given
  ///    [BuildContext].
  final ScrollController? controller;

  /// How the widgets should respond to user input.
  ///
  /// For example, determines how the widget continues to animate after the
  /// user stops dragging the scroll view.
  ///
  /// Defaults to matching platform conventions via the physics provided from
  /// the ambient [ScrollConfiguration].
  ///
  /// The physics can be changed dynamically, but new physics will only take
  /// effect if the _class_ of the provided object changes. Merely constructing
  /// a new instance with a different configuration is insufficient to cause the
  /// physics to be reapplied. (This is because the final object used is
  /// generated dynamically, which can be relatively expensive, and it would be
  /// inefficient to speculatively create this object each frame to see if the
  /// physics should be updated.)
  ///
  /// See also:
  ///
  ///  * [AlwaysScrollableScrollPhysics], which can be used to indicate that the
  ///    scrollable should react to scroll requests (and possible overscroll)
  ///    even if the scrollable's contents fit without scrolling being necessary.
  final ScrollPhysics? physics;

  /// Builds the viewport through which the scrollable content is displayed.
  ///
  /// A typical viewport uses the given [ViewportOffset] to determine which part
  /// of its content is actually visible through the viewport.
  ///
  /// See also:
  ///
  ///  * [Viewport], which is a viewport that displays a list of slivers.
  ///  * [ShrinkWrappingViewport], which is a viewport that displays a list of
  ///    slivers and sizes itself based on the size of the slivers.
  final ViewportBuilder viewportBuilder;

  /// An optional function that will be called to calculate the distance to
  /// scroll when the scrollable is asked to scroll via the keyboard using a
  /// [ScrollAction].
  ///
  /// If not supplied, the [Scrollable] will scroll a default amount when a
  /// keyboard navigation key is pressed (e.g. pageUp/pageDown, control-upArrow,
  /// etc.), or otherwise invoked by a [ScrollAction].
  ///
  /// If [incrementCalculator] is null, the default for
  /// [ScrollIncrementType.page] is 80% of the size of the scroll window, and
  /// for [ScrollIncrementType.line], 50 logical pixels.
  final ScrollIncrementCalculator? incrementCalculator;

  /// Whether the scroll actions introduced by this [Scrollable] are exposed
  /// in the semantics tree.
  ///
  /// Text fields with an overflow are usually scrollable to make sure that the
  /// user can get to the beginning/end of the entered text. However, these
  /// scrolling actions are generally not exposed to the semantics layer.
  ///
  /// See also:
  ///
  ///  * [GestureDetector.excludeFromSemantics], which is used to accomplish the
  ///    exclusion.
  final bool excludeFromSemantics;

  /// The number of children that will contribute semantic information.
  ///
  /// The value will be null if the number of children is unknown or unbounded.
  ///
  /// Some subtypes of [ScrollView] can infer this value automatically. For
  /// example [ListView] will use the number of widgets in the child list,
  /// while the [ListView.separated] constructor will use half that amount.
  ///
  /// For [CustomScrollView] and other types which do not receive a builder
  /// or list of widgets, the child count must be explicitly provided.
  ///
  /// See also:
  ///
  ///  * [CustomScrollView], for an explanation of scroll semantics.
  ///  * [SemanticsConfiguration.scrollChildCount], the corresponding semantics property.
  final int? semanticChildCount;

  /// {@macro flutter.widgets.scrollable.dragStartBehavior}
  final DragStartBehavior dragStartBehavior;

  /// Optional handler for pointer signal events.
  ///
  /// If not provided, pointer signal events will be handled by the default
  /// implementation.
  final void Function(PointerSignalEvent event)? customPointerSignalHandler;

  /// The axis along which the scroll view scrolls.
  ///
  /// Determined by the [axisDirection].
  Axis get axis => axisDirectionToAxis(axisDirection);

  @override
  State<CustomPointerScrollable> createState() =>
      CustomPointerScrollableState();

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<AxisDirection>('axisDirection', axisDirection));
    properties.add(DiagnosticsProperty<ScrollPhysics>('physics', physics));
  }

  /// The state from the closest instance of this class that encloses the given context.
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// _CustomPointerScrollableState scrollable = Scrollable.of(context);
  /// ```
  ///
  /// Calling this method will create a dependency on the closest [Scrollable]
  /// in the [context], if there is one.
  static CustomPointerScrollableState? of(final BuildContext context) {
    final _ScrollableScope? widget =
        context.dependOnInheritedWidgetOfExactType<_ScrollableScope>();
    return widget?.scrollable;
  }

  /// Scrolls the scrollables that enclose the given context so as to make the
  /// given context visible.
  static Future<void> ensureVisible(
    BuildContext context, {
    final double alignment = 0.0,
    final Duration duration = Duration.zero,
    final Curve curve = Curves.ease,
    final ScrollPositionAlignmentPolicy alignmentPolicy =
        ScrollPositionAlignmentPolicy.explicit,
  }) {
    final List<Future<void>> futures = <Future<void>>[];

    CustomPointerScrollableState? scrollable = CustomPointerScrollable.of(
      context,
    );
    while (scrollable != null) {
      futures.add(
        scrollable.position.ensureVisible(
          context.findRenderObject()!,
          alignment: alignment,
          duration: duration,
          curve: curve,
          alignmentPolicy: alignmentPolicy,
        ),
      );
      context = scrollable.context;
      scrollable = CustomPointerScrollable.of(context);
    }

    if (futures.isEmpty || duration == Duration.zero) {
      return Future<void>.value();
    }
    if (futures.length == 1) return futures.single;
    return futures.wait.then<void>((_) => null);
  }
}

/// State object for [CustomPointerScrollable].
///
/// This state object is a copy of [ScrollableState] and replaces the handler
/// [ScrollableState._receivedPointerSignal] with
/// [CustomPointerScrollable.customPointerSignalHandler] when non-null.
class CustomPointerScrollableState extends State<CustomPointerScrollable>
    with TickerProviderStateMixin
    implements ScrollContext {
  /// The manager for this [Scrollable] widget's viewport position.
  ///
  /// To control what kind of [ScrollPosition] is created for a [Scrollable],
  /// provide it with custom [ScrollController] that creates the appropriate
  /// [ScrollPosition] in its [ScrollController.createScrollPosition] method.
  ScrollPosition get position => _position!;
  ScrollPosition? _position;

  @override
  AxisDirection get axisDirection => widget.axisDirection;

  @override
  double get devicePixelRatio =>
      MediaQuery.maybeDevicePixelRatioOf(context) ??
      View.of(context).devicePixelRatio;

  @override
  void saveOffset(final double offset) {
    // TODO(goderbauer): enable state restoration once the framework is stable.
  }

  final Map<Type, GestureRecognizerFactory> _recognizers = {};
  ScrollBehavior? _configuration;
  ScrollPhysics? _physics;

  // Only call this from places that will definitely trigger a rebuild.
  void _updatePosition() {
    _configuration = ScrollConfiguration.of(context);
    _physics = _configuration?.getScrollPhysics(context);
    if (widget.physics != null) {
      _physics = widget.physics!.applyTo(_physics);
    } else if (_configuration != null) {
      _physics = _configuration!.getScrollPhysics(context);
    }
  }

  @override
  void initState() {
    super.initState();
    final controller = widget.controller ?? ScrollController();
    _position =
        controller.position ??
        ScrollPositionWithSingleContext(
          physics: _physics ?? const AlwaysScrollableScrollPhysics(),
          context: this,
        );
  }

  @override
  void didChangeDependencies() {
    _updatePosition();
    if (_position == null) {
      final controller = widget.controller ?? ScrollController();
      _position = ScrollPositionWithSingleContext(
        physics: _physics ?? const AlwaysScrollableScrollPhysics(),
        context: this,
      );
      controller.attach(_position!);
    }
    super.didChangeDependencies();
  }

  bool _shouldUpdatePosition(final CustomPointerScrollable oldWidget) {
    assert(
      _position != null,
      'ScrollController not properly initialized. '
      'Check if _position is created in initState or didChangeDependencies.',
    );
    ScrollPhysics? newPhysics = widget.physics;
    ScrollPhysics? oldPhysics = oldWidget.physics;
    do {
      if (newPhysics?.runtimeType != oldPhysics?.runtimeType) {
        return true;
      }
      newPhysics = newPhysics?.parent;
      oldPhysics = oldPhysics?.parent;
    } while (newPhysics != null || oldPhysics != null);
    return false;
  }

  @override
  void didUpdateWidget(final CustomPointerScrollable oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      assert(
        widget.controller == null || oldWidget.controller == null,
        'Scrollable widget controller changed from ${oldWidget.controller} to '
        '${widget.controller}. This is not supported. Consider using a '
        'StatefulWidget to maintain the ScrollController.',
      );
      if (oldWidget.controller != null) {
        oldWidget.controller!.detach(position);
        _position = null;
      }
      if (widget.controller != null) {
        widget.controller!.attach(position);
      }
    }

    if (_shouldUpdatePosition(oldWidget)) {
      _updatePosition();
    }
  }

  @override
  void dispose() {
    if (widget.controller != null) {
      widget.controller!.detach(position);
    }
    position.dispose();
    super.dispose();
  }

  // SEMANTICS

  final GlobalKey _scrollSemanticsKey = GlobalKey();

  @override
  @protected
  void setSemanticsActions(final Set<SemanticsAction> actions) {
    if (_gestureDetectorKey.currentState != null) {
      _gestureDetectorKey.currentState!.replaceSemanticsActions(actions);
    }
  }

  // GESTURE RECOGNITION AND POINTER IGNORING

  final _gestureDetectorKey = GlobalKey<RawGestureDetectorState>();
  final GlobalKey _ignorePointerKey = GlobalKey();

  // This field is set during layout, and then reused until the next time it is set.
  var _gestureRecognizers = const <Type, GestureRecognizerFactory>{};
  var _shouldIgnorePointer = false;

  bool? _lastCanDrag;
  Axis? _lastAxisDirection;

  @override
  @protected
  void setCanDrag(final bool canDrag) {
    if (canDrag == _lastCanDrag &&
        (!canDrag || widget.axis == _lastAxisDirection)) {
      return;
    }
    if (!canDrag) {
      _gestureRecognizers = const <Type, GestureRecognizerFactory>{};
    } else {
      switch (widget.axis) {
        case Axis.vertical:
          _gestureRecognizers = <Type, GestureRecognizerFactory>{
            VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<
              VerticalDragGestureRecognizer
            >(VerticalDragGestureRecognizer.new, (final instance) {
              instance
                ..onDown = _handleDragDown
                ..onStart = _handleDragStart
                ..onUpdate = _handleDragUpdate
                ..onEnd = _handleDragEnd
                ..onCancel = _handleDragCancel
                ..minFlingDistance = _physics?.minFlingDistance
                ..minFlingVelocity = _physics?.minFlingVelocity
                ..maxFlingVelocity = _physics?.maxFlingVelocity
                ..dragStartBehavior = widget.dragStartBehavior;
            }),
          };
        case Axis.horizontal:
          _gestureRecognizers = <Type, GestureRecognizerFactory>{
            HorizontalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  HorizontalDragGestureRecognizer
                >(HorizontalDragGestureRecognizer.new, (final instance) {
                  instance
                    ..onDown = _handleDragDown
                    ..onStart = _handleDragStart
                    ..onUpdate = _handleDragUpdate
                    ..onEnd = _handleDragEnd
                    ..onCancel = _handleDragCancel
                    ..minFlingDistance = _physics?.minFlingDistance
                    ..minFlingVelocity = _physics?.minFlingVelocity
                    ..maxFlingVelocity = _physics?.maxFlingVelocity
                    ..dragStartBehavior = widget.dragStartBehavior;
                }),
          };
      }
    }
    _lastCanDrag = canDrag;
    _lastAxisDirection = widget.axis;
    if (_gestureDetectorKey.currentState != null) {
      _gestureDetectorKey.currentState!.replaceGestureRecognizers(
        _gestureRecognizers,
      );
    }
  }

  @override
  TickerProvider get vsync => this;

  @override
  @protected
  void setIgnorePointer(final bool value) {
    if (_shouldIgnorePointer == value) return;
    _shouldIgnorePointer = value;
    if (_ignorePointerKey.currentContext != null) {
      final RenderIgnorePointer renderBox =
          _ignorePointerKey.currentContext!.findRenderObject()!
              as RenderIgnorePointer;
      renderBox.ignoring = _shouldIgnorePointer;
    }
  }

  @override
  BuildContext? get notificationContext => _gestureDetectorKey.currentContext;

  @override
  BuildContext get storageContext => context;

  // TOUCH HANDLERS

  Drag? _drag;
  ScrollHoldController? _hold;

  void _handleDragDown(DragDownDetails _) {
    assert(_drag == null);
    assert(_hold == null);
    _hold = position.hold(_disposeHold);
  }

  void _handleDragStart(final DragStartDetails details) {
    // It's possible for _hold to become null between _handleDragDown and
    // _handleDragStart, for example if some user code calls jumpTo or otherwise
    // triggers a new activity to begin.
    assert(_drag == null);
    _drag = position.drag(details, _disposeDrag);
    assert(_drag != null);
    assert(_hold == null);
  }

  void _handleDragUpdate(final DragUpdateDetails details) {
    // _drag might be null if the drag activity ended and called _disposeDrag.
    assert(_hold == null || _drag == null);
    _drag?.update(details);
  }

  void _handleDragEnd(final DragEndDetails details) {
    // _drag might be null if the drag activity ended and called _disposeDrag.
    assert(_hold == null || _drag == null);
    _drag?.end(details);
    assert(_drag == null);
  }

  void _handleDragCancel() {
    // _hold might be null if the drag started.
    // _drag might be null if the drag activity ended and called _disposeDrag.
    assert(_hold == null || _drag == null);
    _hold?.cancel();
    _drag?.cancel();
    assert(_hold == null);
    assert(_drag == null);
  }

  void _disposeHold() {
    _hold = null;
  }

  void _disposeDrag() {
    _drag = null;
  }

  // SCROLL WHEEL

  // Returns the offset that should result from applying [event] to the current
  // position, taking min/max scroll extent into account.
  double _targetScrollOffsetForPointerScroll(final PointerScrollEvent event) {
    double delta =
        widget.axis == Axis.horizontal
            ? event.scrollDelta.dx
            : event.scrollDelta.dy;

    if (axisDirectionIsReversed(widget.axisDirection)) {
      delta *= -1;
    }

    return math.min(
      math.max(position.pixels + delta, position.minScrollExtent),
      position.maxScrollExtent,
    );
  }

  void _receivedPointerSignal(final PointerSignalEvent event) {
    if (widget.customPointerSignalHandler != null) {
      widget.customPointerSignalHandler!(event);
      return;
    }
    if (event is PointerScrollEvent) {
      if (_physics != null && !_physics!.shouldAcceptUserOffset(position)) {
        return;
      }
      final double delta = _pointerSignalEventDelta(event);
      if (delta != 0.0) {
        position.pointerScroll(delta);
      }
    }
  }

  double _pointerSignalEventDelta(final PointerScrollEvent event) {
    double delta =
        widget.axisDirection == AxisDirection.up ||
                widget.axisDirection == AxisDirection.down
            ? event.scrollDelta.dy
            : event.scrollDelta.dx;

    if (widget.axisDirection == AxisDirection.up ||
        widget.axisDirection == AxisDirection.left) {
      delta = -delta;
    }
    return delta;
  }

  // DESCRIPTION

  @override
  Widget build(final BuildContext context) {
    Widget result = _ScrollableScope(
      scrollable: this,
      position: position,
      child: Listener(
        onPointerSignal: _receivedPointerSignal,
        child: RawGestureDetector(
          gestures: _recognizers,
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: widget.excludeFromSemantics,
          child: Semantics(
            explicitChildNodes: !widget.excludeFromSemantics,
            child: widget.viewportBuilder(context, position),
          ),
        ),
      ),
    );

    if (!widget.excludeFromSemantics) {
      result = _ScrollSemantics(
        key: ValueKey<ScrollPosition>(position),
        position: position,
        allowImplicitScrolling: _physics?.allowImplicitScrolling ?? false,
        semanticChildCount: widget.semanticChildCount,
        child: result,
      );
    }

    return result;
  }

  @override
  void debugFillProperties(final DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<ScrollPosition>('position', position));
  }
}

// The following classes were copied from the Flutter framework with minor
// changes to use with [CustomPointerScrollable] instead of [Scrollable]. See
// flutter/lib/src/widgets/scrollable.dart for original classes.

// Enable Scrollable.of() to work as if _CustomPointerScrollableState was an
// inherited widget. _CustomPointerScrollableState.build() always rebuilds its
// _ScrollableScope.
class _ScrollableScope extends InheritedWidget {
  const _ScrollableScope({
    required this.scrollable,
    required this.position,
    required super.child,
  });

  final CustomPointerScrollableState scrollable;
  final ScrollPosition position;

  @override
  bool updateShouldNotify(final _ScrollableScope old) =>
      position != old.position;
}

/// With [_ScrollSemantics] certain child [SemanticsNode]s can be
/// excluded from the scrollable area for semantics purposes.
///
/// Nodes, that are to be excluded, have to be tagged with
/// [RenderViewport.excludeFromScrolling] and the [RenderAbstractViewport] in
/// use has to add the [RenderViewport.useTwoPaneSemantics] tag to its
/// [SemanticsConfiguration] by overriding
/// [RenderObject.describeSemanticsConfiguration].
///
/// If the tag [RenderViewport.useTwoPaneSemantics] is present on the viewport,
/// two semantics nodes will be used to represent the [Scrollable]: The outer
/// node will contain all children, that are excluded from scrolling. The inner
/// node, which is annotated with the scrolling actions, will house the
/// scrollable children.
class _ScrollSemantics extends SingleChildRenderObjectWidget {
  const _ScrollSemantics({
    required this.position,
    required this.allowImplicitScrolling,
    required this.semanticChildCount,
    required super.child,
    super.key,
  });

  final ScrollPosition position;
  final bool allowImplicitScrolling;
  final int? semanticChildCount;

  @override
  RenderObject createRenderObject(final BuildContext context) =>
      _RenderScrollSemantics(
        position: position,
        allowImplicitScrolling: allowImplicitScrolling,
        semanticChildCount: semanticChildCount,
      );

  @override
  void updateRenderObject(
    final BuildContext context,
    final _RenderScrollSemantics renderObject,
  ) {
    renderObject
      ..position = position
      ..allowImplicitScrolling = allowImplicitScrolling
      ..semanticChildCount = semanticChildCount;
  }
}

class _RenderScrollSemantics extends RenderProxyBox {
  _RenderScrollSemantics({
    required final ScrollPosition position,
    required final bool allowImplicitScrolling,
    required final int? semanticChildCount,
  }) : _position = position,
       _allowImplicitScrolling = allowImplicitScrolling,
       _semanticChildCount = semanticChildCount;

  ScrollPosition get position => _position;
  ScrollPosition _position;
  set position(final ScrollPosition value) {
    if (value == _position) {
      return;
    }
    _position = value;
    markNeedsLayout();
  }

  bool get allowImplicitScrolling => _allowImplicitScrolling;
  bool _allowImplicitScrolling;
  set allowImplicitScrolling(final bool value) {
    if (value == _allowImplicitScrolling) {
      return;
    }
    _allowImplicitScrolling = value;
    markNeedsLayout();
  }

  int? get semanticChildCount => _semanticChildCount;
  int? _semanticChildCount;
  set semanticChildCount(final int? value) {
    if (value == _semanticChildCount) {
      return;
    }
    _semanticChildCount = value;
    markNeedsLayout();
  }

  @override
  void describeSemanticsConfiguration(final SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;

    if (position.haveDimensions) {
      config
        ..hasImplicitScrolling = _allowImplicitScrolling
        ..scrollPosition = position.pixels
        ..scrollExtentMax = position.maxScrollExtent
        ..scrollExtentMin = position.minScrollExtent;

      if (_semanticChildCount != null) {
        config.scrollChildCount = _semanticChildCount;
      }
    }
  }
}
