import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/tools/aiActionSheets.dart';
import 'package:budget/struct/aiActions.dart';
import 'package:budget/struct/aiAttachments.dart';
import 'package:budget/struct/aiChat.dart';
import 'package:budget/struct/chatgptSignIn.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/helpGuide.dart';
import 'package:budget/widgets/radioItems.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  AiProvider provider = selectedAiProvider();
  bool hasKey = false;
  bool signedIn = false;
  String? planEmail;
  List<AiModelInfo> models = [];
  // Goes with the next message
  AiAttachment? attachment;
  List<ChatMessage> conversation = [];
  // Answers of the month summary action, shown as a card
  final Set<ChatMessage> summaries = {};
  bool sending = false;
  bool shareData = appStateSettings["aiShareData"] ?? true;
  String? error;
  bool errorManagesUsage = false;
  final TextEditingController keyController = TextEditingController();
  final TextEditingController messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadProvider();
  }

  @override
  void dispose() {
    keyController.dispose();
    messageController.dispose();
    super.dispose();
  }

  bool get ready => provider == AiProvider.chatgpt
      ? signedIn
      : (aiNeedsApiKey(provider) ? hasKey : true);

  Future<void> loadProvider() async {
    bool key =
        aiNeedsApiKey(provider) ? await readApiKey(provider) != null : false;
    bool session = await ChatGptSession.isSignedIn();
    String? email = await ChatGptSession.email();
    setState(() {
      hasKey = key;
      signedIn = session;
      planEmail = email;
      models = [];
      error = null;
    });
    if (ready) loadModels();
  }

  Future<void> loadModels() async {
    try {
      List<AiModelInfo> list = await listModels(provider);
      setState(() {
        models = list;
        dropUnsupportedAttachment();
      });
    } catch (e) {
      showError(e);
    }
  }

  void showError(Object e) {
    setState(() {
      error = aiErrorText(e);
      errorManagesUsage = e is AiError && e.manageUsage;
    });
  }

  // What the selected model reads, from its list once loaded
  AiModelInfo get model => selectedModelInfo(provider);

  bool get readsPdf => model.readsPdf && provider != AiProvider.chatgpt;

  // After a change of service or model
  void dropUnsupportedAttachment() {
    AiAttachment? file = attachment;
    if (file == null) return;
    if ((file.kind == AiAttachmentKind.image && !model.readsImages) ||
        (file.kind == AiAttachmentKind.pdf && !readsPdf)) {
      attachment = null;
    }
  }

  void runAction(AiAction action) {
    // Say so before any camera opens
    if (aiPhotoActions.contains(action) && model.readsImages == false) {
      openAiNoPhotosSheet(context, action,
          onChooseModel: ready && models.length > 1 ? chooseModel : null);
      return;
    }
    if (action == AiAction.summary && ready) {
      runSummary();
    } else {
      openAiAction(context, action, ready: ready);
    }
  }

  // Month summary with tips, added to the conversation as a card
  Future<void> runSummary() async {
    if (sending) return;
    if (shareData == false) {
      await openBottomSheet(
        context,
        PopupFramework(
          title: "📊 " + "ai-action-summary".tr(),
          child: Builder(
            builder: (sheetContext) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                note("ai-summary-needs-data".tr()),
                SizedBox(height: 10),
                Button(
                  label: "ai-summary-share-and-run".tr(),
                  expandedLayout: true,
                  onTap: () {
                    popRoute(sheetContext);
                    updateSettings("aiShareData", true,
                        updateGlobalState: false);
                    setState(() => shareData = true);
                    runSummary();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
    String languageCode = context.locale.languageCode;
    setState(() {
      conversation.add(ChatMessage(true, "ai-summary-request".tr()));
      sending = true;
      error = null;
    });
    try {
      String summary = await monthlySummary(
        await buildFinanceContext(allWallets),
        languageCode: languageCode,
      );
      ChatMessage answer = ChatMessage(false, summary);
      setState(() {
        summaries.add(answer);
        conversation.add(answer);
      });
    } catch (e) {
      showError(e);
    }
    setState(() => sending = false);
  }

  Future<void> chooseProvider(AiProvider value) async {
    await updateSettings("aiProvider", value.name, updateGlobalState: false);
    setState(() => provider = value);
    await loadProvider();
    setState(dropUnsupportedAttachment);
  }

  String modelTags(AiModelInfo info) => [
        if (info.free) "ai-tag-free".tr(),
        if (info.readsImages) "📷 " + "ai-tag-reads-photos".tr(),
        if (info.readsPdf && provider != AiProvider.chatgpt)
          "📄 " + "ai-tag-reads-pdf".tr(),
        if (info.fast) "⚡ " + "ai-tag-fast".tr(),
      ].join("  ·  ");

  Future<void> chooseModel() async {
    if (models.isEmpty) return;
    await openBottomSheet(
      context,
      PopupFramework(
        title: "ai-choose-model".tr(),
        child: Builder(
          builder: (sheetContext) => RadioItems<String>(
            initial: model.id,
            items: [for (AiModelInfo m in models) m.id],
            displayFilter: (id) => modelInfo(provider, id).label,
            getDescription: (id) => modelTags(modelInfo(provider, id)),
            onChanged: (id) async {
              popRoute(sheetContext);
              await setSelectedModel(provider, id);
              setState(dropUnsupportedAttachment);
            },
          ),
        ),
      ),
    );
  }

  // The attach sheet: photos and PDFs when the model reads them, data files
  // always (they go as text)
  Future<void> openAttachSheet() async {
    await openBottomSheet(
      context,
      PopupFramework(
        title: "📎 " + "ai-attach-title".tr(),
        subtitle: "ai-attach-subtitle".tr(),
        child: Builder(builder: (sheetContext) {
          Future<void> pick(Future<AiAttachment?> Function() picker) async {
            popRoute(sheetContext);
            try {
              AiAttachment? file = await picker();
              if (file != null) {
                setState(() {
                  attachment = file;
                  error = null;
                });
              }
            } catch (e) {
              showError(e);
            }
          }

          Future<AiAttachment?> photo(ImageSource source) async {
            AiImage? image = await pickAiImage(source);
            return image == null
                ? null
                : AiAttachment.image("ai-attachment-photo".tr(), image);
          }

          List<String> missing = [
            if (model.readsImages == false) "ai-model-no-photos-short".tr(),
            if (readsPdf == false) "ai-model-no-pdf-short".tr(),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (model.readsImages) ...[
                SettingsContainer(
                  title: "ai-take-photo".tr(),
                  icon: Icons.photo_camera_rounded,
                  onTap: () => pick(() => photo(ImageSource.camera)),
                ),
                SettingsContainer(
                  title: "ai-choose-photo".tr(),
                  icon: Icons.photo_library_rounded,
                  onTap: () => pick(() => photo(ImageSource.gallery)),
                ),
              ],
              if (readsPdf)
                SettingsContainer(
                  title: "ai-attach-pdf".tr(),
                  description: "ai-attach-pdf-description".tr(),
                  icon: Icons.picture_as_pdf_rounded,
                  onTap: () => pick(() => pickAiFile(allowPdf: true)),
                ),
              SettingsContainer(
                title: "ai-attach-data".tr(),
                description: "ai-attach-data-description".tr(),
                icon: Icons.table_chart_rounded,
                onTap: () => pick(() => pickAiFile(allowPdf: false)),
              ),
              if (missing.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                      start: 18, end: 18, top: 8),
                  child: note([...missing, "ai-attach-choose-other-model".tr()]
                      .join(" ")),
                ),
            ],
          );
        }),
      ),
    );
  }

  IconData attachmentIcon(AiAttachment file) => switch (file.kind) {
        AiAttachmentKind.image => Icons.image_rounded,
        AiAttachmentKind.pdf => Icons.picture_as_pdf_rounded,
        AiAttachmentKind.text => Icons.table_chart_rounded,
      };

  Future<void> saveKey() async {
    await saveApiKey(provider, keyController.text);
    keyController.clear();
    await loadProvider();
  }

  Future<void> signInWithChatGpt() async {
    try {
      await ChatGptSession.signIn();
    } catch (e) {
      showError(e);
    }
    await loadProvider();
  }

  Future<void> send() async {
    String text = messageController.text.trim();
    if ((text == "" && attachment == null) || sending) return;
    AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
    ChatMessage answer = ChatMessage(false, "");
    setState(() {
      conversation.add(ChatMessage(true, text, attachment: attachment));
      attachment = null;
      sending = true;
      error = null;
      messageController.clear();
    });
    try {
      String? context =
          shareData ? await buildFinanceContext(allWallets) : null;
      String reply = await sendChat(
        conversation,
        financeContext: context,
        onDelta: (soFar) => setState(() {
          answer.text = soFar;
          if (conversation.contains(answer) == false) conversation.add(answer);
        }),
      );
      setState(() {
        answer.text = reply;
        if (conversation.contains(answer) == false) conversation.add(answer);
      });
    } catch (e) {
      conversation.remove(answer);
      showError(e);
    }
    setState(() => sending = false);
  }

  String providerLabel(AiProvider p) => switch (p) {
        AiProvider.gemini => "Gemini",
        AiProvider.openai => "OpenAI",
        AiProvider.chatgpt => "ai-provider-chatgpt-plan".tr(),
        AiProvider.finza => "ai-provider-finza".tr(),
        AiProvider.openrouter => "OpenRouter",
        AiProvider.claude => "Claude",
        AiProvider.deepseek => "DeepSeek",
      };

  Widget setupSection() {
    if (provider == AiProvider.finza) {
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
        child: note("ai-finza-description".tr()),
      );
    }
    if (provider == AiProvider.chatgpt) {
      if (chatGptSignInSupported == false) {
        return note("ai-plan-not-on-web".tr());
      }
      if (signedIn) {
        return Column(children: [
          SettingsContainer(
            title: "ai-using-chatgpt-plan".tr(),
            description: planEmail,
            icon: Icons.verified_rounded,
          ),
          SettingsContainer(
            title: "ai-manage-usage".tr(),
            icon: Icons.data_usage_rounded,
            onTap: () => openUrl(chatGptUsageUrl),
          ),
          SettingsContainer(
            title: "logout".tr(),
            icon: Icons.logout_rounded,
            onTap: () async {
              await ChatGptSession.signOut();
              await loadProvider();
            },
          ),
        ]);
      }
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
        child: Column(children: [
          note("ai-plan-description".tr()),
          SizedBox(height: 10),
          Button(
            label: "ai-continue-with-chatgpt".tr(),
            onTap: signInWithChatGpt,
            expandedLayout: true,
          ),
        ]),
      );
    }
    if (aiNeedsApiKey(provider) == false) return SizedBox.shrink();
    if (hasKey) {
      return SettingsContainer(
        title: "ai-key-saved".tr(),
        icon: Icons.key_rounded,
        afterWidget: TextButton(
          onPressed: () async {
            await saveApiKey(provider, null);
            await loadProvider();
          },
          child: TextFont(text: "delete".tr()),
        ),
      );
    }
    HelpGuide guide = HelpGuides.aiChat();
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
      child: Column(children: [
        if (provider == AiProvider.gemini) ...[
          // The same steps as the help guide, right where the key goes
          SizedBox(height: 6),
          for (int i = 0; i < guide.steps.length; i++)
            HelpStepRow(number: i + 1, text: guide.steps[i]),
          Button(
            label: guide.action!.label,
            icon: guide.action!.icon,
            onTap: guide.action!.onTap,
            expandedLayout: true,
          ),
          SizedBox(height: 6),
          note("ai-gemini-key-description".tr()),
        ] else ...[
          note(("ai-key-help-" + provider.name).tr()),
          if (aiKeyUrl(provider) != null)
            Button(
              label: "ai-get-my-key".tr(),
              onTap: () => openUrl(aiKeyUrl(provider)!),
              expandedLayout: true,
            ),
        ],
        SizedBox(height: 10),
        TextInput(
          labelText: "ux-ai-paste-key".tr(),
          controller: keyController,
          obscureText: true,
          padding: EdgeInsetsDirectional.zero,
        ),
        SizedBox(height: 10),
        Button(
          label: "ai-save-key".tr(),
          onTap: saveKey,
          expandedLayout: true,
        ),
      ]),
    );
  }

  Widget note(String text) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
        child: TextFont(
          text: text,
          fontSize: 14,
          maxLines: 10,
          textColor: getColor(context, "black").withOpacity(0.6),
        ),
      );

  Widget summaryCard(ChatMessage message) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxWidth: 560),
      margin:
          const EdgeInsetsDirectional.symmetric(horizontal: 15, vertical: 6),
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text("📊", style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Expanded(
              child: TextFont(
                text: "ai-summary-title".tr(),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ]),
          SizedBox(height: 10),
          SelectableText(message.text,
              style: TextStyle(
                  fontSize: 15, height: 1.35, color: colors.onSurface)),
          SizedBox(height: 12),
          TextFont(
            text: "ai-summary-note".tr(),
            fontSize: 13,
            maxLines: 4,
            textColor: getColor(context, "black").withOpacity(0.6),
          ),
        ],
      ),
    );
  }

  Widget bubble(ChatMessage message) {
    if (summaries.contains(message)) return summaryCard(message);
    ColorScheme colors = Theme.of(context).colorScheme;
    return Align(
      alignment: message.fromUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: 520),
        margin:
            const EdgeInsetsDirectional.symmetric(horizontal: 15, vertical: 5),
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: message.fromUser
              ? colors.primaryContainer
              : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.attachment != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(attachmentIcon(message.attachment!),
                    size: 18, color: colors.onSurface),
                SizedBox(width: 6),
                Flexible(
                  child: TextFont(
                    text: message.attachment!.name,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    maxLines: 2,
                  ),
                ),
              ]),
            if (message.attachment != null && message.text != "")
              SizedBox(height: 6),
            if (message.text != "")
              SelectableText(message.text,
                  style: TextStyle(fontSize: 15, color: colors.onSurface)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "ai-chat".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      actions: [HelpGuideButton(guide: HelpGuides.aiChat())],
      listWidgets: [
        if (ready == false)
          Padding(
            padding:
                const EdgeInsetsDirectional.only(start: 18, end: 18, bottom: 8),
            child: note("ux-ai-intro".tr()),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 15),
          child: Wrap(
            spacing: 8,
            children: [
              for (AiProvider p in offeredAiProviders)
                ChoiceChip(
                  label: TextFont(
                      text: p == AiProvider.chatgpt && !chatGptSignInSupported
                          ? providerLabel(p) + " · " + "ai-app-only".tr()
                          : providerLabel(p),
                      fontSize: 15),
                  selected: provider == p,
                  onSelected: (_) => chooseProvider(p),
                ),
            ],
          ),
        ),
        SizedBox(height: 8),
        setupSection(),
        if (ready && models.isNotEmpty)
          SettingsContainer(
            title: "ai-model".tr(),
            description: model.label +
                (modelTags(model) == "" ? "" : "\n" + modelTags(model)),
            icon: Icons.memory_rounded,
            afterWidget: Icon(Icons.unfold_more_rounded),
            onTap: chooseModel,
          ),
        if (ready)
          SettingsContainerSwitch(
            title: "ai-share-data".tr(),
            description: "ai-share-data-description"
                .tr(namedArgs: {"provider": providerLabel(provider)}),
            initialValue: shareData,
            icon: Icons.privacy_tip_rounded,
            onSwitched: (value) {
              updateSettings("aiShareData", value, updateGlobalState: false);
              setState(() => shareData = value);
            },
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
            child: Column(children: [
              TextFont(
                text: error!,
                fontSize: 14,
                maxLines: 6,
                textColor: getColor(context, "expenseAmount"),
              ),
              if (errorManagesUsage)
                TextButton(
                  onPressed: () => openUrl(chatGptUsageUrl),
                  child: TextFont(text: "ai-manage-usage".tr()),
                ),
            ]),
          ),
        SizedBox(height: 10),
        AiActionsGrid(
          onTap: runAction,
          providerName: providerLabel(provider),
          readsImages: model.readsImages,
        ),
        SizedBox(height: 6),
        if (ready && conversation.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (String key in [
                  "ai-example-1",
                  "ai-example-2",
                  "ai-example-3",
                ])
                  ActionChip(
                    label: Text(key.tr()),
                    onPressed: () {
                      messageController.text = key.tr();
                      send();
                    },
                  ),
              ],
            ),
          ),
        for (ChatMessage message in conversation) bubble(message),
        if (sending && (conversation.lastOrNull?.fromUser ?? false))
          Padding(
            padding: const EdgeInsetsDirectional.all(15),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        if (ready)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 15, vertical: 10),
            child: Column(children: [
              if (attachment != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 8),
                    child: InputChip(
                      avatar: Icon(attachmentIcon(attachment!), size: 18),
                      label: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 240),
                        child: Text(attachment!.name,
                            overflow: TextOverflow.ellipsis),
                      ),
                      onDeleted: () => setState(() => attachment = null),
                      deleteButtonTooltipMessage: "ai-attach-remove".tr(),
                    ),
                  ),
                ),
              Row(children: [
                IconButton(
                  onPressed: sending ? null : openAttachSheet,
                  tooltip: "ai-attach".tr(),
                  icon: Icon(Icons.attach_file_rounded),
                ),
                Expanded(
                  child: TextInput(
                    labelText: attachment == null
                        ? "ai-ask-placeholder".tr()
                        : "ai-ask-about-file".tr(),
                    controller: messageController,
                    padding: EdgeInsetsDirectional.zero,
                    onSubmitted: (_) => send(),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sending ? null : send,
                  icon: Icon(Icons.send_rounded),
                ),
              ]),
            ]),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: note("ai-disclaimer".tr()),
        ),
        SizedBox(height: 60),
      ],
    );
  }
}
