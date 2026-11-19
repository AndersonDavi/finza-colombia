import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Amount fields show thousands as they are typed: 3500000 -> 3.500.000.
// A comma starts the decimals, the Colombian way. The parsers of the tool
// pages already read this format back.

String groupThousands(String text) {
  String cleaned = text.replaceAll(RegExp(r"[^0-9,]"), "");
  int comma = cleaned.indexOf(",");
  String whole = comma == -1 ? cleaned : cleaned.substring(0, comma);
  String decimals =
      comma == -1 ? "" : "," + cleaned.substring(comma + 1).replaceAll(",", "");
  whole = whole.replaceFirst(RegExp(r"^0+(?=\d)"), "");
  StringBuffer grouped = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(".");
    grouped.write(whole[i]);
  }
  return grouped.toString() + decimals;
}

class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String formatted = groupThousands(newValue.text);
    if (formatted == newValue.text) return newValue;
    // Keeps the cursor after the same number of digits it had before
    int cursor = newValue.selection.end.clamp(0, newValue.text.length);
    int digitsBefore = newValue.text
        .substring(0, cursor)
        .replaceAll(RegExp(r"[^0-9,]"), "")
        .length;
    int position = 0;
    int seen = 0;
    while (position < formatted.length && seen < digitsBefore) {
      if (RegExp(r"[0-9,]").hasMatch(formatted[position])) seen++;
      position++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: position),
    );
  }
}

// Also groups text put in the field by code, like the "try an example"
// buttons. Returns the listener so it can be removed
VoidCallback groupThousandsOnChange(TextEditingController controller) {
  void listener() {
    String formatted = groupThousands(controller.text);
    if (formatted != controller.text) {
      controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  controller.addListener(listener);
  listener();
  return listener;
}
