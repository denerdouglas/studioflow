import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

class ContextMenuAction {
  final String id;
  final String label;
  final IconData icon;
  final Future<void> Function() onSelected;
  final bool destructive;
  final bool enabled;

  const ContextMenuAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
    this.enabled = true,
  });
}

class ContextActionMenu extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final List<ContextMenuAction> actions;
  final String semanticLabel;
  final bool enabled;

  const ContextActionMenu({
    super.key,
    required this.child,
    required this.actions,
    required this.semanticLabel,
    this.onTap,
    this.enabled = true,
  });

  @override
  State<ContextActionMenu> createState() => _ContextActionMenuState();
}

class _ContextActionMenuState extends State<ContextActionMenu> {
  Offset? _pointerPosition;

  Future<void> _show([Offset? position]) async {
    final actions = widget.actions.where((action) => action.enabled).toList();
    if (!widget.enabled || actions.isEmpty || !mounted) return;
    HapticFeedback.lightImpact();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final render = context.findRenderObject() as RenderBox;
    final origin =
        position ?? render.localToGlobal(render.size.center(Offset.zero));
    final selected = await showMenu<String>(
      context: context,
      semanticLabel: 'Ações de ${widget.semanticLabel}',
      position: RelativeRect.fromRect(
        Rect.fromPoints(origin, origin),
        Offset.zero & overlay.size,
      ),
      items: actions
          .map(
            (action) => PopupMenuItem<String>(
              value: action.id,
              child: Row(
                children: [
                  Icon(
                    action.icon,
                    color: action.destructive
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      action.label,
                      style: action.destructive
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
    if (selected == null) return;
    final action = actions.firstWhere((item) => item.id == selected);
    await action.onSelected();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticLabel,
    button: widget.onTap != null,
    customSemanticsActions: {
      if (widget.actions.any((action) => action.enabled))
        CustomSemanticsAction(label: 'Abrir ações'): () => _show(),
    },
    child: FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.contextMenu): _OpenMenuIntent(),
        SingleActivator(LogicalKeyboardKey.f10, shift: true): _OpenMenuIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
        _OpenMenuIntent: CallbackAction<_OpenMenuIntent>(
          onInvoke: (_) {
            _show(_pointerPosition);
            return null;
          },
        ),
      },
      child: Listener(
        onPointerDown: (event) => _pointerPosition = event.position,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: () => _show(_pointerPosition),
          onSecondaryTapDown: (details) => _show(details.globalPosition),
          child: widget.child,
        ),
      ),
    ),
  );
}

class ContextActionTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final VoidCallback? onTap;
  final List<ContextMenuAction> actions;
  final String semanticLabel;
  final bool isThreeLine;

  const ContextActionTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.onTap,
    required this.actions,
    required this.semanticLabel,
    this.isThreeLine = false,
  });

  @override
  Widget build(BuildContext context) => ContextActionMenu(
    actions: actions,
    semanticLabel: semanticLabel,
    onTap: onTap,
    child: ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      isThreeLine: isThreeLine,
      onTap: null,
      trailing: actions.any((action) => action.enabled)
          ? Builder(
              builder: (buttonContext) => IconButton(
                tooltip: 'Mais ações',
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  final state = buttonContext
                      .findAncestorStateOfType<_ContextActionMenuState>();
                  state?._show();
                },
              ),
            )
          : null,
    ),
  );
}

class _OpenMenuIntent extends Intent {
  const _OpenMenuIntent();
}
