import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/presentation/board_flow_page.dart';

void main() {
  test('flow cards can travel all the way to the playfield edges', () {
    const playfieldSize = Size(390, 620);
    const cardSize = Size(220, 146);
    const itemKey = 'board-1::edge-check';

    var minLeft = double.infinity;
    var minTop = double.infinity;
    var maxRight = double.negativeInfinity;
    var maxBottom = double.negativeInfinity;

    for (var step = 0; step < 500; step++) {
      final timeSeconds = step * 0.1;
      final state = resolveFlowCardDebugStatesForTesting(
        playfieldSize: playfieldSize,
        cardSizes: const [cardSize],
        itemKeys: const [itemKey],
        timeSeconds: timeSeconds,
      ).single;
      minLeft = math.min(minLeft, state.rect.left);
      minTop = math.min(minTop, state.rect.top);
      maxRight = math.max(maxRight, state.rect.right);
      maxBottom = math.max(maxBottom, state.rect.bottom);
    }

    expect(minLeft <= 6, isTrue);
    expect(minTop <= 6, isTrue);
    expect(maxRight >= playfieldSize.width - 6, isTrue);
    expect(maxBottom >= playfieldSize.height - 6, isTrue);
  });

  test('flow cards dodge same-direction heavy overlap smoothly', () {
    const playfieldSize = Size(390, 620);
    final cardSizes = List<Size>.filled(4, const Size(220, 146));
    const itemKeys = [
      'board-1::a',
      'board-1::b',
      'board-1::c',
      'board-1::d',
    ];

    for (final timeSeconds in [1.5, 4.0, 7.5, 11.0, 15.0]) {
      final states = resolveFlowCardDebugStatesForTesting(
        playfieldSize: playfieldSize,
        cardSizes: cardSizes,
        itemKeys: itemKeys,
        timeSeconds: timeSeconds,
      );

      for (var index = 0; index < states.length; index++) {
        for (var otherIndex = index + 1;
            otherIndex < states.length;
            otherIndex++) {
          final firstRect = states[index].rect;
          final secondRect = states[otherIndex].rect;
          final overlapX = math.max(
            0,
            math.min(firstRect.right, secondRect.right) -
                math.max(firstRect.left, secondRect.left),
          );
          final overlapY = math.max(
            0,
            math.min(firstRect.bottom, secondRect.bottom) -
                math.max(firstRect.top, secondRect.top),
          );
          final widthRatio =
              overlapX / math.min(firstRect.width, secondRect.width);
          final heightRatio =
              overlapY / math.min(firstRect.height, secondRect.height);
          final firstVelocity = states[index].velocity;
          final secondVelocity = states[otherIndex].velocity;
          final similarity = ((firstVelocity.dx * secondVelocity.dx) +
                  (firstVelocity.dy * secondVelocity.dy)) /
              (firstVelocity.distance * secondVelocity.distance);

          if (similarity < 0.72) {
            continue;
          }

          expect(
            widthRatio < 0.60 || heightRatio < 0.60,
            isTrue,
            reason:
                'Same-direction cards should dodge before they cover most of each other.',
          );
        }
      }
    }
  });

  test('flow mallet swipe gives a nearby card a puck-like impulse', () {
    final state = resolveFlowCardDebugStateAfterMalletForTesting(
      playfieldSize: const Size(390, 620),
      cardSize: const Size(220, 146),
      itemKey: 'board-1::mallet-hit',
      initialPosition: const Offset(120, 220),
      initialVelocity: const Offset(90, 0),
      previousMalletPosition: const Offset(30, 280),
      malletPosition: const Offset(190, 280),
      malletVelocity: const Offset(820, 0),
    );

    expect(state.velocity.dx, greaterThan(90));
    expect(state.rect.left, greaterThan(120));
  });

  test('flow mallet swipe does not affect a distant card', () {
    final state = resolveFlowCardDebugStateAfterMalletForTesting(
      playfieldSize: const Size(390, 620),
      cardSize: const Size(220, 146),
      itemKey: 'board-1::mallet-miss',
      initialPosition: const Offset(120, 220),
      initialVelocity: const Offset(90, 0),
      previousMalletPosition: const Offset(20, 40),
      malletPosition: const Offset(110, 40),
      malletVelocity: const Offset(760, 0),
    );

    expect(state.velocity.dx, closeTo(90, 0.001));
    expect(state.rect.left, closeTo(120, 0.001));
  });

  test('flow create puck floats around the playfield over time', () {
    const playfieldSize = Size(390, 620);

    final initial = resolveFlowCreatePuckDebugStateForTesting(
      playfieldSize: playfieldSize,
      timeSeconds: 0,
    );
    final later = resolveFlowCreatePuckDebugStateForTesting(
      playfieldSize: playfieldSize,
      timeSeconds: 4.0,
    );

    expect(later.rect.left, isNot(closeTo(initial.rect.left, 0.001)));
    expect(later.rect.top, isNot(closeTo(initial.rect.top, 0.001)));
    expect(later.rect.left, inInclusiveRange(0, playfieldSize.width));
    expect(later.rect.top, inInclusiveRange(0, playfieldSize.height));
    expect(later.rect.right, lessThanOrEqualTo(playfieldSize.width));
    expect(later.rect.bottom, lessThanOrEqualTo(playfieldSize.height));
  });
}
