// Copyright 2020 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_mcp_extension/core/devtools_core/shared/primitives/utils.dart';
import 'package:vm_service/vm_service.dart';

class _JsonFields {
  static const file = 'file';
  static const line = 'line';
  static const column = 'column';
}

class InspectorSourceLocation {
  InspectorSourceLocation(this.json, this.parent);

  final Map<String, Object?> json;
  final InspectorSourceLocation? parent;

  String? get path => JsonUtils.getStringMember(json, _JsonFields.file);

  String? getFile() {
    final fileName = path;
    if (fileName == null) {
      return parent?.getFile();
    }

    return fileName;
  }

  int getLine() => JsonUtils.getIntMember(json, _JsonFields.line);

  int getColumn() => JsonUtils.getIntMember(json, _JsonFields.column);
}

class SourcePosition {
  const SourcePosition({
    required this.line,
    required this.column,
    this.tokenPos,
  });

  factory SourcePosition.calculatePosition(
    final Script script,
    final int tokenPos,
  ) => SourcePosition(
    line: script.getLineNumberFromTokenPos(tokenPos),
    column: script.getColumnNumberFromTokenPos(tokenPos),
    tokenPos: tokenPos,
  );

  final int? line;
  final int? column;
  final int? tokenPos;

  @override
  bool operator ==(final Object other) =>
      other is SourcePosition &&
      other.line == line &&
      other.column == column &&
      other.tokenPos == tokenPos;

  @override
  int get hashCode =>
      line != null && column != null ? (line! << 7) ^ column! : super.hashCode;

  @override
  String toString() => '$line:$column';
}
