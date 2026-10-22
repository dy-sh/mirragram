import 'package:flutter/cupertino.dart';

/// Navigation shared by both layouts: on mobile [open] pushes a page, on
/// desktop it shows the page in the right pane and highlights [selectedId].
class TgNav extends InheritedWidget {
  const TgNav({
    super.key,
    required this.isDesktop,
    required this.selectedId,
    required this.onOpen,
    required super.child,
  });

  final bool isDesktop;
  final String? selectedId;
  final void Function(BuildContext context, String id, WidgetBuilder builder)
  onOpen;

  static TgNav of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TgNav>()!;

  static TgNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TgNav>();

  void open(BuildContext context, String id, WidgetBuilder builder) =>
      onOpen(context, id, builder);

  static String chatId(int id) => 'chat:$id';

  @override
  bool updateShouldNotify(TgNav old) =>
      old.isDesktop != isDesktop || old.selectedId != selectedId;
}

void pushPage(BuildContext context, String id, WidgetBuilder builder) {
  Navigator.of(context).push(CupertinoPageRoute<void>(builder: builder));
}
