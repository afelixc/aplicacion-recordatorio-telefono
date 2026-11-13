import 'package:flutter/material.dart';

/// Hoja de abajo que nunca queda tapada por la barra del teléfono
/// (|||  ◯  ‹): sus botones quedan siempre enteros (pedido del usuario).
/// Usar siempre esta en vez de `showModalBottomSheet`.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  showDragHandle: showDragHandle,
  useSafeArea: true,
  builder: (context) => SafeArea(top: false, child: builder(context)),
);
