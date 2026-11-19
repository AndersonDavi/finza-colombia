import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/tools/loanSimulatorPage.dart';
import 'package:budget/pages/tools/rateMath.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/struct/aiActions.dart';
import 'package:budget/struct/aiChat.dart';
import 'package:budget/struct/colombia.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

// The assistant actions shown above the AI chat: big buttons that open a
// short sheet, ask the model and land on a screen to review before saving.

enum AiAction { receipt, text, voice, bankMessage, loanOffer, summary }

// Vector icons, never emoji: emoji fonts look different on every phone
class AiActionInfo {
  const AiActionInfo(this.icon, this.color, this.labelKey, this.helpKey);
  final IconData icon;
  final Color color;
  final String labelKey;
  final String helpKey;
}

const Map<AiAction, AiActionInfo> aiActionInfo = {
  AiAction.receipt: AiActionInfo(Icons.photo_camera_rounded,
      Color(0xFFEF6C00), "ai-action-receipt", "ai-action-receipt-help"),
  AiAction.text: AiActionInfo(Icons.edit_note_rounded, Color(0xFF1E88E5),
      "ai-action-text", "ai-action-text-help"),
  AiAction.voice: AiActionInfo(Icons.mic_rounded, Color(0xFFE53935),
      "ai-action-voice", "ai-action-voice-help"),
  AiAction.bankMessage: AiActionInfo(Icons.sms_rounded, Color(0xFF43A047),
      "ai-action-bank-message", "ai-action-bank-message-help"),
  AiAction.loanOffer: AiActionInfo(Icons.request_quote_rounded,
      Color(0xFF8E24AA), "ai-action-loan", "ai-action-loan-help"),
  AiAction.summary: AiActionInfo(Icons.insights_rounded, Color(0xFF00897B),
      "ai-action-summary", "ai-action-summary-help"),
};

// The action's icon on a soft square of its color
class AiActionIcon extends StatelessWidget {
  const AiActionIcon(this.info, {this.size = 40, super.key});
  final AiActionInfo info;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: info.color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(info.icon, color: info.color, size: size * 0.6),
    );
  }
}

// Actions that start with a photo
const Set<AiAction> aiPhotoActions = {AiAction.receipt, AiAction.loanOffer};

// Translation key (or the provider's own text) for an error
String aiErrorMessage(Object e) {
  String message = e.toString();
  // No connection: the browser or the phone could not reach the provider
  if (e is! AiError &&
      (message.contains("SocketException") ||
          message.contains("ClientException") ||
          message.contains("Failed host lookup") ||
          message.contains("XMLHttpRequest"))) {
    return "ai-no-internet";
  }
  return message;
}

String aiErrorText(Object e) {
  String message = aiErrorMessage(e);
  return message.startsWith("ai-") ? message.tr() : message;
}

// The grid of actions with a help line under each title
class AiActionsGrid extends StatelessWidget {
  const AiActionsGrid({
    required this.onTap,
    required this.providerName,
    this.readsImages = true,
    super.key,
  });
  final void Function(AiAction action) onTap;
  final String providerName;
  // When false the photo actions look disabled; tapping them explains why
  final bool readsImages;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 3, bottom: 8),
            child: TextFont(
              text: "ai-actions-title".tr(),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          LayoutBuilder(builder: (context, constraints) {
            int columns = constraints.maxWidth >= 600 ? 3 : 2;
            List<AiAction> actions = AiAction.values;
            return Column(children: [
              for (int start = 0; start < actions.length; start += columns)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 10),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = start; i < start + columns; i++) ...[
                          if (i > start) SizedBox(width: 10),
                          Expanded(
                            child: i < actions.length
                                ? AiActionTile(
                                    action: actions[i],
                                    onTap: () => onTap(actions[i]),
                                    disabledNote: readsImages ||
                                            !aiPhotoActions.contains(actions[i])
                                        ? null
                                        : "ai-model-no-photos-short".tr(),
                                  )
                                : SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ]);
          }),
          ToolNote(
            text:
                "ai-actions-privacy".tr(namedArgs: {"provider": providerName}),
          ),
        ],
      ),
    );
  }
}

class AiActionTile extends StatelessWidget {
  const AiActionTile({
    required this.action,
    required this.onTap,
    this.disabledNote,
    super.key,
  });
  final AiAction action;
  final VoidCallback onTap;
  // Shown instead of the help line when the action can't run
  final String? disabledNote;

  @override
  Widget build(BuildContext context) {
    AiActionInfo info = aiActionInfo[action]!;
    bool disabled = disabledNote != null;
    return Tappable(
      onTap: onTap,
      borderRadius: 18,
      color: disabled
          ? getColor(context, "lightDarkAccent")
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Opacity(
        opacity: disabled ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AiActionIcon(info),
              SizedBox(height: 8),
              TextFont(
                text: info.labelKey.tr(),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                maxLines: 3,
              ),
              SizedBox(height: 3),
              if (disabled)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 1, end: 4),
                      child: Icon(Icons.no_photography_rounded, size: 15),
                    ),
                    Expanded(
                      child: TextFont(
                        text: disabledNote!,
                        fontSize: 13,
                        maxLines: 5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              else
                TextFont(
                  text: info.helpKey.tr(),
                  fontSize: 13,
                  maxLines: 5,
                  textColor: getColor(context, "black").withOpacity(0.65),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Shown instead of the camera when the selected model can't read photos
Future<void> openAiNoPhotosSheet(
  BuildContext context,
  AiAction action, {
  VoidCallback? onChooseModel,
}) {
  return openBottomSheet(
    context,
    _AiSheet(
      action: action,
      child: Builder(
        builder: (sheetContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NoticeBox(
              icon: Icons.no_photography_rounded,
              text: "ai-model-no-photos".tr(),
            ),
            SizedBox(height: 14),
            if (onChooseModel != null) ...[
              Button(
                label: "ai-choose-another-model".tr(),
                icon: Icons.memory_rounded,
                expandedLayout: true,
                onTap: () {
                  popRoute(sheetContext);
                  onChooseModel();
                },
              ),
              SizedBox(height: 10),
            ],
            Button(
              label: "ai-action-text".tr(),
              icon: Icons.edit_rounded,
              expandedLayout: true,
              color: getColor(context, "lightDarkAccentHeavy"),
              textColor: getColor(context, "black"),
              onTap: () {
                popRoute(sheetContext);
                openAiTextSheet(context);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

// Opens the sheet of an action. Without a provider ready it explains what
// to set up first. The summary is run by the chat page itself
Future<void> openAiAction(
  BuildContext context,
  AiAction action, {
  required bool ready,
}) async {
  if (ready == false) return openAiNotReadySheet(context, action);
  switch (action) {
    case AiAction.receipt:
      return _openPhotoSheet(context, action, (image) async {
        List<TransactionCategory> categories = await _categories();
        AiTransactionDraft? draft = await _withLoading(
          context,
          () => readReceipt(
            image,
            categories: [
              for (TransactionCategory c in categories)
                if (c.income == false) c.name
            ],
          ),
          retry: () => openAiAction(context, action, ready: true),
          byHand: true,
        );
        if (draft != null) await openAiDraft(context, draft, receipt: true);
      });
    case AiAction.loanOffer:
      return _openPhotoSheet(context, action, (image) async {
        AiLoanOffer? offer = await _withLoading(
          context,
          () => readLoanOffer(image),
          retry: () => openAiAction(context, action, ready: true),
        );
        if (offer != null) await openLoanOfferResult(context, offer);
      });
    case AiAction.text:
    case AiAction.bankMessage:
      return openAiTextSheet(context,
          bankMessage: action == AiAction.bankMessage);
    case AiAction.voice:
      return openBottomSheet(
        context,
        _AiSheet(
          action: action,
          child: _VoiceInput(
            onText: (text) => readAiText(context, text),
            onUseTyping: () => openAiTextSheet(context),
          ),
        ),
      );
    case AiAction.summary:
      return;
  }
}

Future<void> openAiNotReadySheet(BuildContext context, AiAction action) {
  return openBottomSheet(
    context,
    _AiSheet(
      action: action,
      child: Builder(
        builder: (sheetContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NoticeBox(
              icon: Icons.key_rounded,
              text: "ai-actions-need-key".tr(),
            ),
            SizedBox(height: 14),
            Button(
              label: "help-got-it".tr(),
              expandedLayout: true,
              onTap: () => popRoute(sheetContext),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> openAiTextSheet(BuildContext context, {bool bankMessage = false}) {
  return openBottomSheet(
    context,
    popupWithKeyboard: true,
    _AiSheet(
      action: bankMessage ? AiAction.bankMessage : AiAction.text,
      child: _TextInputSheet(
        bankMessage: bankMessage,
        onText: (text) => readAiText(context, text, bankMessage: bankMessage),
      ),
    ),
  );
}

// Reads a sentence, a voice note or a bank message into a transaction
Future<void> readAiText(BuildContext context, String text,
    {bool bankMessage = false}) async {
  AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
  List<TransactionCategory> categories = await _categories();
  List<AiPocketOption> pockets = await aiPocketOptions(allWallets);
  AiTransactionDraft? draft = await _withLoading(
    context,
    () => readTransactionText(
      text,
      categories: categories.map((c) => c.name).toList(),
      pockets: pockets.map((p) => p.label).toList(),
      bankMessage: bankMessage,
    ),
    retry: () => openAiTextSheet(context, bankMessage: bankMessage),
    byHand: true,
  );
  if (draft != null) await openAiDraft(context, draft);
}

Future<List<TransactionCategory>> _categories() async {
  try {
    return (await database.getAllCategories())
        .where((c) => c.archived == false)
        .toList();
  } catch (e) {
    return [];
  }
}

// Opens the add transaction screen filled with what was read; nothing is
// saved until the user taps save there
Future<void> openAiDraft(BuildContext context, AiTransactionDraft draft,
    {bool receipt = false}) async {
  AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
  TransactionCategory? category =
      matchCategory(draft.category, await _categories());
  TransactionWallet? wallet =
      matchPocket(draft.pocket, await aiPocketOptions(allWallets));
  bool income = receipt ? false : (draft.income ?? category?.income ?? false);
  List<String> tagPks = [];
  String? note = draft.note;
  if (draft.electronicInvoice) {
    String? tagPk = await electronicInvoiceTagPk();
    if (tagPk != null) {
      tagPks.add(tagPk);
    } else {
      note = [if (note != null) note, "ai-electronic-invoice-note".tr()]
          .join("\n");
    }
  }
  await pushRoute(
    context,
    AddTransactionPage(
      routesToPopAfterDelete: RoutesToPopAfterDelete.None,
      startInitialAddTransactionSequence: false,
      selectedAmount: draft.amount,
      selectedTitle: draft.title,
      selectedCategory: category,
      selectedWallet: wallet,
      selectedDate: draft.date,
      selectedIncome: income,
      selectedNotes: note,
      selectedTagPks: tagPks,
    ),
  );
}

// Runs a request behind the loading popup. On failure shows a friendly
// sheet with "try again" and, for transactions, "enter by hand"
Future<T?> _withLoading<T>(
  BuildContext context,
  Future<T> Function() request, {
  required VoidCallback retry,
  bool byHand = false,
}) async {
  openLoadingPopup(context);
  try {
    T result = await request();
    popRoute(context);
    return result;
  } catch (e) {
    print("AI action failed: " + e.toString());
    popRoute(context);
    await openBottomSheet(
      context,
      PopupFramework(
        title: "ai-read-failed-title".tr(),
        child: Builder(
          builder: (sheetContext) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NoticeBox(
                icon: Icons.sentiment_dissatisfied_rounded,
                text: aiErrorText(e),
                color: getColor(context, "expenseAmount"),
              ),
              SizedBox(height: 14),
              Button(
                label: "ai-try-again".tr(),
                icon: Icons.refresh_rounded,
                expandedLayout: true,
                onTap: () {
                  popRoute(sheetContext);
                  retry();
                },
              ),
              if (byHand) ...[
                SizedBox(height: 10),
                Button(
                  label: "ai-enter-by-hand".tr(),
                  icon: Icons.edit_rounded,
                  expandedLayout: true,
                  color: getColor(context, "lightDarkAccentHeavy"),
                  textColor: getColor(context, "black"),
                  onTap: () {
                    popRoute(sheetContext);
                    pushRoute(
                      context,
                      AddTransactionPage(
                        routesToPopAfterDelete: RoutesToPopAfterDelete.None,
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return null;
  }
}

// Sheet frame: the action's title with its help line as subtitle
class _AiSheet extends StatelessWidget {
  const _AiSheet({required this.action, required this.child});
  final AiAction action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    AiActionInfo info = aiActionInfo[action]!;
    return PopupFramework(
      title: info.labelKey.tr(),
      subtitle: info.helpKey.tr(),
      child: child,
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: getColor(context, "lightDarkAccentHeavy"),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color ?? getColor(context, "black"), size: 22),
          SizedBox(width: 10),
          Expanded(
            child: TextFont(
              text: text,
              fontSize: 15,
              maxLines: 12,
              textColor: color,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openPhotoSheet(BuildContext context, AiAction action,
    Future<void> Function(AiImage image) onImage) {
  return openBottomSheet(
    context,
    _AiSheet(
      action: action,
      child: Builder(builder: (sheetContext) {
        Future<void> pick(ImageSource source) async {
          popRoute(sheetContext);
          AiImage? image;
          try {
            image = await pickAiImage(source);
          } catch (e) {
            print("No photo: " + e.toString());
          }
          if (image != null) await onImage(image);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Button(
              label: "ai-take-photo".tr(),
              icon: Icons.photo_camera_rounded,
              expandedLayout: true,
              onTap: () => pick(ImageSource.camera),
            ),
            SizedBox(height: 10),
            Button(
              label: "ai-choose-photo".tr(),
              icon: Icons.photo_library_rounded,
              expandedLayout: true,
              color: getColor(context, "lightDarkAccentHeavy"),
              textColor: getColor(context, "black"),
              onTap: () => pick(ImageSource.gallery),
            ),
            SizedBox(height: 12),
            ToolNote(text: "ai-photo-tip".tr()),
          ],
        );
      }),
    ),
  );
}

class _TextInputSheet extends StatefulWidget {
  const _TextInputSheet({required this.bankMessage, required this.onText});
  final bool bankMessage;
  final void Function(String text) onText;

  @override
  State<_TextInputSheet> createState() => _TextInputSheetState();
}

class _TextInputSheetState extends State<_TextInputSheet> {
  final TextEditingController controller = TextEditingController();
  String? notice;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> paste() async {
    ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (e) {}
    String text = data?.text?.trim() ?? "";
    setState(() {
      if (text.isEmpty) {
        notice = "ai-clipboard-empty".tr();
      } else {
        controller.text = text;
        notice = null;
      }
    });
  }

  void submit() {
    String text = controller.text.trim();
    if (text.isEmpty) {
      setState(() => notice = widget.bankMessage
          ? "ai-bank-message-empty".tr()
          : "ai-text-empty".tr());
      return;
    }
    popRoute(context);
    widget.onText(text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.bankMessage) ...[
          Button(
            label: "ai-paste".tr(),
            icon: Icons.content_paste_rounded,
            expandedLayout: true,
            color: getColor(context, "lightDarkAccentHeavy"),
            textColor: getColor(context, "black"),
            onTap: paste,
          ),
          SizedBox(height: 10),
        ],
        TextInput(
          labelText: widget.bankMessage
              ? "ai-bank-message-label".tr()
              : "ai-text-label".tr(),
          controller: controller,
          padding: EdgeInsetsDirectional.zero,
          autoFocus: widget.bankMessage == false,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) {
            if (notice != null) setState(() => notice = null);
          },
        ),
        SizedBox(height: 8),
        if (notice != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 8, start: 5),
            child: TextFont(
              text: notice!,
              fontSize: 14,
              maxLines: 4,
              textColor: getColor(context, "expenseAmount"),
            ),
          ),
        ToolNote(
          text: widget.bankMessage
              ? "ai-bank-message-example".tr()
              : "ai-text-example".tr(),
        ),
        Button(
          label: "continue".tr(),
          icon: Icons.arrow_forward_rounded,
          expandedLayout: true,
          onTap: submit,
        ),
      ],
    );
  }
}

// Speech to text on the device (Android, Chrome and Edge on the web). Where
// it is missing, points to typing instead
class _VoiceInput extends StatefulWidget {
  const _VoiceInput({required this.onText, required this.onUseTyping});
  final void Function(String text) onText;
  final VoidCallback onUseTyping;

  @override
  State<_VoiceInput> createState() => _VoiceInputState();
}

class _VoiceInputState extends State<_VoiceInput> {
  final SpeechToText speech = SpeechToText();
  final TextEditingController controller = TextEditingController();
  bool? available;
  bool listening = false;
  String? notice;

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    if (listening) speech.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> init() async {
    bool ok = false;
    try {
      ok = await speech.initialize(
        onError: onError,
        onStatus: (status) {
          if (!mounted) return;
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            setState(() => listening = false);
          }
        },
      );
    } catch (e) {
      print("No speech to text: " + e.toString());
    }
    if (mounted) setState(() => available = ok);
  }

  void onError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      listening = false;
      if (error.errorMsg.contains("permission") ||
          error.errorMsg.contains("not-allowed") ||
          error.errorMsg.contains("not supported")) {
        available = false;
      } else if (controller.text.trim().isEmpty) {
        notice = "ai-voice-heard-nothing".tr();
      }
    });
  }

  Future<void> toggle() async {
    if (listening) {
      await speech.stop();
      setState(() => listening = false);
      return;
    }
    setState(() {
      notice = null;
      listening = true;
    });
    try {
      await speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() => controller.text = result.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          localeId: kIsWeb ? "es-CO" : "es_CO",
          partialResults: true,
          listenFor: Duration(seconds: 30),
          pauseFor: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      print("Listening failed: " + e.toString());
      if (mounted) setState(() => available = false);
    }
  }

  void submit() {
    String text = controller.text.trim();
    if (text.isEmpty) {
      setState(() => notice = "ai-voice-heard-nothing".tr());
      return;
    }
    popRoute(context);
    widget.onText(text);
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    if (available == null) {
      return Padding(
        padding: const EdgeInsetsDirectional.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (available == false) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NoticeBox(
            icon: Icons.mic_off_rounded,
            text: "ai-voice-unavailable".tr(),
          ),
          SizedBox(height: 14),
          Button(
            label: "ai-action-text".tr(),
            icon: Icons.edit_rounded,
            expandedLayout: true,
            onTap: () {
              popRoute(context);
              widget.onUseTyping();
            },
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Tappable(
            onTap: toggle,
            borderRadius: 60,
            color: listening ? colors.error : colors.primary,
            child: SizedBox(
              width: 96,
              height: 96,
              child: Icon(
                listening ? Icons.stop_rounded : Icons.mic_rounded,
                size: 48,
                color: listening ? colors.onError : colors.onPrimary,
              ),
            ),
          ),
        ),
        SizedBox(height: 10),
        Center(
          child: TextFont(
            text: listening
                ? "ai-voice-listening".tr()
                : "ai-voice-tap-to-talk".tr(),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 14),
        TextInput(
          labelText: "ai-voice-text-label".tr(),
          controller: controller,
          padding: EdgeInsetsDirectional.zero,
          minLines: 2,
          maxLines: 5,
        ),
        SizedBox(height: 8),
        if (notice != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 8, start: 5),
            child: TextFont(
              text: notice!,
              fontSize: 14,
              maxLines: 4,
              textColor: getColor(context, "expenseAmount"),
            ),
          ),
        Button(
          label: "ai-voice-use-text".tr(),
          icon: Icons.arrow_forward_rounded,
          expandedLayout: true,
          onTap: submit,
        ),
      ],
    );
  }
}

// What a loan offer says, its effective annual rate against the usury rate
// and a way into the simulator with the same figures
Future<void> openLoanOfferResult(BuildContext context, AiLoanOffer offer) {
  return openBottomSheet(
    context,
    PopupFramework(
      title: "ai-loan-result-title".tr(),
      subtitle: offer.bank,
      child: Builder(builder: (sheetContext) {
        String money(double? value) => value == null
            ? "ai-not-found".tr()
            : formatToolMoney(context, value);
        double? ea = offer.effectiveAnnualPercent;
        bool aboveUsury = ea != null && ea > usuryRateEA;
        Map<String, String> usuryArgs = {
          "usury": formatToolPercent(usuryRateEA / 100),
          "period": usuryRatePeriod,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ToolResultRow(
              label: "ai-loan-amount".tr(),
              value: money(offer.amount),
            ),
            ToolResultRow(
              label: "ai-loan-rate".tr(),
              value: offer.ratePercent == null
                  ? "ai-not-found".tr()
                  : formatToolPercent(offer.ratePercent! / 100) +
                      (offer.rateKind == null
                          ? ""
                          : " " + loanRateKindShort(offer.rateKind!)),
            ),
            if (ea != null && offer.rateKind != LoanRateKind.ea)
              ToolResultRow(
                label: "ai-loan-ea".tr(),
                value: formatToolPercent(ea / 100),
                highlight: true,
              ),
            ToolResultRow(
              label: "ai-loan-months".tr(),
              value: offer.months == null
                  ? "ai-not-found".tr()
                  : "ai-loan-months-value"
                      .tr(namedArgs: {"months": offer.months.toString()}),
            ),
            ToolResultRow(
              label: "ai-loan-installment".tr(),
              value: money(offer.installment),
            ),
            if (offer.monthlyFees != null || offer.otherCosts != null)
              ToolResultRow(
                label: "ai-loan-fees".tr(),
                value: offer.monthlyFees == null
                    ? ""
                    : "ai-loan-fees-monthly"
                        .tr(namedArgs: {"amount": money(offer.monthlyFees)}),
                description: offer.otherCosts,
              ),
            SizedBox(height: 4),
            if (ea != null)
              _NoticeBox(
                icon: aboveUsury
                    ? Icons.warning_rounded
                    : Icons.check_circle_rounded,
                color: aboveUsury
                    ? getColor(context, "expenseAmount")
                    : getColor(context, "incomeAmount"),
                text: aboveUsury
                    ? "ai-loan-above-usury".tr(namedArgs: usuryArgs)
                    : "ai-loan-below-usury".tr(namedArgs: usuryArgs),
              ),
            SizedBox(height: 12),
            ToolNote(text: "ai-loan-check-values".tr()),
            Button(
              label: "ai-loan-open-simulator".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.calculate_outlined
                  : Icons.calculate_rounded,
              expandedLayout: true,
              onTap: () {
                popRoute(sheetContext);
                pushRoute(
                  context,
                  LoanSimulatorPage(
                    initialAmount: offer.amount,
                    initialRatePercent: offer.ratePercent,
                    initialRateKind: offer.rateKind,
                    initialMonths: offer.months,
                    initialMonthlyFee: offer.monthlyFees,
                  ),
                );
              },
            ),
          ],
        );
      }),
    ),
  );
}
