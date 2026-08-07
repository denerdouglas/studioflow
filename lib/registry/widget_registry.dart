import 'package:flutter/material.dart';

typedef WidgetBuilderFn =
    Widget Function(BuildContext context, Map<String, dynamic> data);

class WidgetRegistry {
  static final WidgetRegistry _instance = WidgetRegistry._internal();
  factory WidgetRegistry() => _instance;
  WidgetRegistry._internal();

  final Map<String, WidgetBuilderFn> _builders = {};

  void register(String type, WidgetBuilderFn builder) {
    _builders[type] = builder;
  }

  Widget buildWidget(
    BuildContext context,
    String type, {
    Map<String, dynamic> data = const {},
  }) {
    final builder = _builders[type];
    if (builder != null) {
      return builder(context, data);
    }
    return const SizedBox.shrink();
  }
}
