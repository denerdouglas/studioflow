import 'package:flutter/material.dart';

abstract final class AppRoutes {
  static Route<T> material<T>({required WidgetBuilder builder}) {
    return MaterialPageRoute<T>(builder: builder);
  }

  static Future<T?> push<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return Navigator.push<T>(context, material<T>(builder: builder));
  }

  static Future<T?> replaceAll<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return Navigator.pushAndRemoveUntil<T>(
      context,
      material<T>(builder: builder),
      (_) => false,
    );
  }

  const AppRoutes._();
}
