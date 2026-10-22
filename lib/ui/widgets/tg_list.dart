import 'package:flutter/cupertino.dart';

import '../tg_theme.dart';

class TgSection extends StatelessWidget {
  const TgSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        final indent =
            children[i] is TgCell && (children[i] as TgCell).leading != null
            ? 60.0
            : 16.0;
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: indent),
            child: Container(height: 0.5, color: c.separator),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 7),
              child: Text(
                header!.toUpperCase(),
                style: TextStyle(fontSize: 13, color: c.secondaryText),
              ),
            )
          else
            const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: c.cell,
              child: Column(children: rows),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
              child: Text(
                footer!,
                style: TextStyle(
                  fontSize: 13,
                  color: c.secondaryText,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TgCell extends StatefulWidget {
  const TgCell({
    super.key,
    required this.title,
    this.leading,
    this.value,
    this.trailing,
    this.chevron = false,
    this.onTap,
    this.titleColor,
    this.selected = false,
  });

  final String title;
  final Widget? leading;
  final String? value;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;
  final Color? titleColor;

  /// Highlighted item in the desktop sidebar.
  final bool selected;

  @override
  State<TgCell> createState() => _TgCellState();
}

class _TgCellState extends State<TgCell> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    final selected = widget.selected;
    final fg = selected ? const Color(0xFFFFFFFF) : null;
    final background = selected
        ? c.selected
        : (_pressed ? c.separator.withValues(alpha: 0.5) : null);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: Container(
        color: background,
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (widget.leading != null) ...[
              widget.leading!,
              const SizedBox(width: 15),
            ],
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                letterSpacing: -0.4,
                color: fg ?? widget.titleColor ?? c.primaryText,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: widget.value == null
                  ? const SizedBox.shrink()
                  : Text(
                      widget.value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 17,
                        letterSpacing: -0.4,
                        color: fg ?? c.secondaryText,
                      ),
                    ),
            ),
            if (widget.trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: widget.trailing!,
              ),
            if (widget.chevron)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 17,
                  color: fg ?? c.secondaryText.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TgIconBox extends StatelessWidget {
  const TgIconBox(this.icon, this.color, {super.key});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 29,
    height: 29,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Icon(icon, color: const Color(0xFFFFFFFF), size: 18),
  );
}

class TgSwitch extends StatelessWidget {
  const TgSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.color,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: color ?? c.accent,
      inactiveTrackColor: c.isDark
          ? const Color(0xFF39393D)
          : const Color(0xFFE9E9EA),
    );
  }
}
