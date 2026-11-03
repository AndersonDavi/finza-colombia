import 'package:flutter/material.dart';

// Centers a page's content with a maximum width, so it keeps the same shape on
// any window size (the padding helpers grow with the screen width)
class CenteredPageContent extends StatelessWidget {
  const CenteredPageContent({
    required this.child,
    this.maxWidth = 520,
    this.horizontalPadding = 20,
    super.key,
  });
  final Widget child;
  final double maxWidth;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding:
              EdgeInsetsDirectional.symmetric(horizontal: horizontalPadding),
          child: child,
        ),
      ),
    );
  }
}
