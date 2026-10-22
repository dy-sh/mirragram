import 'dart:io';

import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import '../tg_theme.dart';
import 'pick_images.dart';

/// Shows picked photos with a caption field. Returns the caption, or null if
/// sending was cancelled.
Future<String?> showSendPhotosSheet(
  BuildContext context,
  List<PickedImage> images, {
  required bool encryptedChat,
}) {
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (_) =>
        _SendPhotosSheet(images: images, encryptedChat: encryptedChat),
  );
}

class _SendPhotosSheet extends StatefulWidget {
  const _SendPhotosSheet({required this.images, required this.encryptedChat});

  final List<PickedImage> images;
  final bool encryptedChat;

  @override
  State<_SendPhotosSheet> createState() => _SendPhotosSheetState();
}

class _SendPhotosSheetState extends State<_SendPhotosSheet> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _send() => Navigator.of(context).pop(_caption.text.trim());

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    final l = context.l10n;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          decoration: BoxDecoration(
            color: c.cell,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: Text(
                            l.sendPhotos(widget.images.length),
                            style: TgText.navTitle.copyWith(
                              color: c.primaryText,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 4,
                          top: 0,
                          bottom: 0,
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(l.cancel),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: widget.images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, i) {
                        final image = widget.images[i];
                        final width = (180 * image.width / image.height).clamp(
                          90.0,
                          320.0,
                        );
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(image.path),
                            width: width,
                            height: 180,
                            fit: BoxFit.cover,
                            cacheHeight:
                                (180 * MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                          ),
                        );
                      },
                    ),
                  ),
                  if (widget.encryptedChat)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.lock_open_fill,
                            size: 14,
                            color: c.secondaryText,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l.photosNotEncrypted,
                              style: TextStyle(
                                fontSize: 13,
                                color: c.secondaryText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            controller: _caption,
                            autofocus: true,
                            placeholder: l.captionPlaceholder,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            style: TextStyle(
                              fontSize: 17,
                              color: c.primaryText,
                            ),
                            placeholderStyle: TextStyle(
                              fontSize: 17,
                              color: c.placeholder,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: c.inputField,
                              border: Border.all(
                                color: c.inputFieldBorder,
                                width: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
                          minimumSize: const Size(36, 36),
                          onPressed: _send,
                          child: Container(
                            width: 33,
                            height: 33,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              CupertinoIcons.arrow_up,
                              color: Color(0xFFFFFFFF),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
