import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gives confirmation dialogs a consistent keyboard affordance.
///
/// Plain Enter accepts the dialog, while multiline editors retain Enter for
/// adding a new line. Escape remains owned by Flutter's modal route.
class NineSoftEnterConfirmScope extends StatelessWidget {
  const NineSoftEnterConfirmScope({
    required this.onConfirm,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final VoidCallback onConfirm;
  final Widget child;
  final bool enabled;

  bool _isEditingMultilineText() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;

    EditableText? editor;
    if (focusContext.widget case final EditableText editableText) {
      editor = editableText;
    } else {
      focusContext.visitAncestorElements((element) {
        if (element.widget case final EditableText editableText) {
          editor = editableText;
          return false;
        }
        return true;
      });
    }

    return editor != null && editor!.maxLines != 1;
  }

  void _confirmFromKeyboard() {
    if (!enabled || _isEditingMultilineText()) return;
    onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _confirmFromKeyboard,
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            _confirmFromKeyboard,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
