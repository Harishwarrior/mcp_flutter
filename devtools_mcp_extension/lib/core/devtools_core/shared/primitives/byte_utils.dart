// Copyright 2024 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:devtools_mcp_extension/core/devtools_core/development_helpers.dart';
import 'package:meta/meta.dart';

String? prettyPrintBytes(
  final num? bytes, {
  final int kbFractionDigits = 1,
  final int mbFractionDigits = 1,
  final int gbFractionDigits = 1,
  final bool includeUnit = false,
  final num roundingPoint = 1.0,
  final int maxBytes = 52,
}) {
  if (bytes == null) {
    return null;
  }
  // TODO(kenz): Generalize to handle different kbFractionDigits.
  // Ensure a small number of bytes does not print as 0 KB.
  // If bytes >= maxBytes and kbFractionDigits == 1, it will start rounding to
  // 0.1 KB.
  if (bytes.abs() < maxBytes && kbFractionDigits == 1) {
    var output = bytes.toString();
    if (includeUnit) {
      output += ' B';
    }
    return output;
  }
  final sizeInMB = convertBytes(bytes.abs(), to: ByteUnit.mb);
  final sizeInGB = convertBytes(bytes.abs(), to: ByteUnit.gb);

  ByteUnit printUnit;
  if (sizeInGB >= roundingPoint) {
    printUnit = ByteUnit.gb;
  } else if (sizeInMB >= roundingPoint) {
    printUnit = ByteUnit.mb;
  } else {
    printUnit = ByteUnit.kb;
  }

  final fractionDigits = switch (printUnit) {
    ByteUnit.kb => kbFractionDigits,
    ByteUnit.mb => mbFractionDigits,
    ByteUnit.gb || _ => gbFractionDigits,
  };

  return printBytes(
    bytes,
    unit: printUnit,
    fractionDigits: fractionDigits,
    includeUnit: includeUnit,
  );
}

String printBytes(
  num bytes, {
  final ByteUnit unit = ByteUnit.byte,
  final int fractionDigits = 1,
  final bool includeUnit = false,
}) {
  if (unit == ByteUnit.kb) {
    // We add ((1024/2)-1) to the value before formatting so that a non-zero
    // byte value doesn't round down to 0. If showing decimal points, let it
    // round normally.
    // TODO(peterdjlee): Round up to the respective digit when fractionDigits > 0.
    bytes = fractionDigits == 0 ? bytes + 511 : bytes;
  }
  final bytesDisplay = convertBytes(
    bytes,
    to: unit,
  ).toStringAsFixed(fractionDigits);
  final unitSuffix = includeUnit ? ' ${unit.display}' : '';
  return '$bytesDisplay$unitSuffix';
}

num convertBytes(
  final num value, {
  required final ByteUnit to,
  final ByteUnit from = ByteUnit.byte,
}) {
  final multiplier = to.multiplierCount - from.multiplierCount;
  final multiplierValue = pow(ByteUnit.unitMultiplier, multiplier.abs());

  if (multiplier > 0) {
    // A positive multiplier indicates that we are going from a smaller unit to
    // a larger unit (e.g. from bytes to GB).
    return value / multiplierValue;
  } else if (multiplier < 0) {
    // A positive multiplier indicates that we are going from a larger unit to
    // a smaller unit (e.g. from GB to bytes).
    return value * multiplierValue;
  } else {
    return value;
  }
}

enum ByteUnit {
  byte(multiplierCount: 0, display: 'bytes'),
  kb(multiplierCount: 1),
  mb(multiplierCount: 2),
  gb(multiplierCount: 3);

  const ByteUnit({required this.multiplierCount, final String? display})
    : _display = display;

  static const unitMultiplier = 1024.0;

  /// The number of times this unit should be multiplied or divided by
  /// [unitMultiplier] to convert between units.
  ///
  /// [ByteUnit.byte] is the baseline, with zero multipliers. All other units
  /// have a value for [multiplierCount] that is relative to [ByteUnit.byte].
  final int multiplierCount;

  final String? _display;

  String get display => _display ?? name.toUpperCase();
}

/// Stores a list of Uint8List objects in a ring buffer, keeping the total size
/// at or below [maxSizeBytes].
class Uint8ListRingBuffer {
  Uint8ListRingBuffer({required this.maxSizeBytes});

  /// The maximum size in bytes that [data] will contain.
  final int maxSizeBytes;

  /// Returns the size of the ring buffer in bytes.
  ///
  /// Since each element in [data] is a Uint8List, the size of each element in
  /// bytes is the length of the Uint8List.
  int get size => data.fold(0, (final sum, final e) => sum + e.length);

  /// Returns the number of chunks of data contained in this ring buffer.
  int get chunksLength => data.length;

  @visibleForTesting
  final data = ListQueue<Uint8List>();

  /// Stores [binaryData] in [data] and removes as many early elements as
  /// necessary to keep the size of [data] smaller than [maxSizeBytes].
  void addData(final Uint8List binaryData) {
    data.add(binaryData);

    final exceeded = size - maxSizeBytes;
    if (exceeded < 0) return;

    var bytesRemoved = 0;
    while (bytesRemoved < exceeded && data.length > 1) {
      final removed = data.removeFirst();
      bytesRemoved += removed.length;
    }
  }

  /// Merges all the data in this ring buffer into a single [Uint8List] and
  /// returns it.
  Uint8List get merged {
    final allBytes = BytesBuilder();
    debugTimeSync(
      () => data.forEach(allBytes.add),
      debugName: 'Uint8ListRingBuffer.mergeAllData',
    );
    return allBytes.takeBytes();
  }

  void clear() {
    data.clear();
  }

  void trimToSublist(final int start, [final int? end]) {
    for (var i = data.length; i > (end ?? data.length); i--) {
      data.removeLast();
    }
    for (var i = 0; i < start; i++) {
      data.removeFirst();
    }
  }
}
