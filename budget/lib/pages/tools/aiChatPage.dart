import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/tools/aiActionSheets.dart';
import 'package:budget/struct/aiActions.dart';
import 'package:budget/struct/aiAttachmentStore.dart';
import 'package:budget/struct/aiAttachments.dart';
import 'package:budget/struct/aiChanges.dart';
import 'package:budget/struct/aiQueries.dart';
import 'package:budget/struct/aiChat.dart';
import 'package:budget/struct/aiConversations.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/chatgptSignIn.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/aiMarkdown.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/helpGuide.dart';
import 'package:budget/widgets/openPopup.dart';
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
  // Waiting for the browser to come back from the ChatGPT sign-in
  bool signingIn = false;
  bool shareData = appStateSettings["aiShareData"] ?? true;
  String? error;
  bool errorManagesUsage = false;
  final TextEditingController keyController = TextEditingController();
  final TextEditingController messageController = TextEditingController();
  final ScrollController chatScroll = ScrollController();
  // The chat being shown; it is saved on the device after every answer
  String conversationId = uuid.v4();
  // The service and model settings, opened from the gear once set up
  bool showSettings = false;
  // The changes proposed in each answer, checked against the data once
  final Map<ChatMessage, Future<List<AiChangePlan>>> changePlans = {};
  // While the AI is reading more data from the app
  bool lookingUp = false;

  @override
  void initState() {
    super.initState();
    // Coming back to the page opens the last chat where it was left
    AiConversation? last = loadAiConversations().firstOrNull;
    if (last != null) openConversation(last, scroll: false);
    loadProvider();
  }

  @override
  void dispose() {
    keyController.dispose();
    messageController.dispose();
    chatScroll.dispose();
    super.dispose();
  }

  Future<void> openConversation(AiConversation saved,
      {bool scroll = true}) async {
    // The chat's latest file, kept so it can still be asked about
    (int, AiAttachment)? file = await loadChatAttachment(saved.id);
    if (!mounted) return;
    List<ChatMessage> messages = [];
    Set<ChatMessage> savedSummaries = {};
    for (int i = 0; i < saved.messages.length; i++) {
      SavedMessage m = saved.messages[i];
      ChatMessage message = ChatMessage(m.fromUser, m.text,
          attachment: file != null && file.$1 == i ? file.$2 : null,
          attachmentName: m.attachmentName,
          hidden: m.hidden);
      message.changeStatus.addAll(m.changeStatus);
      messages.add(message);
      if (m.summary) savedSummaries.add(message);
    }
    setState(() {
      conversationId = saved.id;
      conversation = messages;
      summaries
        ..clear()
        ..addAll(savedSummaries);
      attachment = null;
      error = null;
    });
    if (scroll) scrollToBottom();
  }

  void newConversation() {
    setState(() {
      conversationId = uuid.v4();
      conversation = [];
      summaries.clear();
      attachment = null;
      error = null;
      messageController.clear();
    });
  }

  Future<void> persist() async {
    await saveAiConversation(conversationId, conversation,
        summaries: summaries);
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!chatScroll.hasClients) return;
      chatScroll.animateTo(
        chatScroll.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // The saved chats, newest first: tap to open, the bin deletes one
  Future<void> openHistory() async {
    await openBottomSheet(
      context,
      PopupFramework(
        title: "ai-history".tr(),
        subtitle: "ai-history-subtitle".tr(),
        child: StatefulBuilder(builder: (sheetContext, setSheetState) {
          List<AiConversation> saved = loadAiConversations();
          if (saved.isEmpty) return note("ai-history-empty".tr());
          return Column(children: [
            for (AiConversation c in saved)
              SettingsContainer(
                title: c.title == "" ? "ai-chat".tr() : c.title,
                description:
                    getWordedDateShortMore(c.updated, includeTime: true),
                icon: c.id == conversationId
                    ? Icons.chat_rounded
                    : Icons.chat_bubble_outline_rounded,
                onTap: () {
                  popRoute(sheetContext);
                  openConversation(c);
                },
                afterWidget: IconButton(
                  tooltip: "delete".tr(),
                  icon: Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    await deleteAiConversation(c.id);
                    await deleteChatAttachment(c.id);
                    if (c.id == conversationId) newConversation();
                    setSheetState(() {});
                  },
                ),
              ),
          ]);
        }),
      ),
    );
  }

  // All the actions in a sheet, from the chat bar
  Future<void> openActionsSheet() async {
    await openBottomSheet(
      context,
      PopupFramework(
        child: Builder(
          builder: (sheetContext) => AiActionsGrid(
            onTap: (action) {
              popRoute(sheetContext);
              runAction(action);
            },
            providerName: providerLabel(provider),
            readsImages: model.readsImages,
          ),
        ),
      ),
    );
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
    if (aiChatActions.contains(action) && ready) {
      if (action == AiAction.summary) {
        runSummary();
      } else {
        askWithData(action);
      }
    } else {
      openAiAction(context, action, ready: ready, onSaved: addSavedNote);
    }
  }

  // A line in the chat once a transaction is saved from the add screen, so
  // it is clear it was done (the model also sees it in the history)
  Future<void> addSavedNote(Transaction saved) async {
    AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
    TransactionCategory? category =
        await database.getCategoryInstanceOrNull(saved.categoryFk);
    TransactionWallet? wallet = allWallets.indexedByPk[saved.walletFk];
    String? account = wallet?.walletGroupFk == null
        ? null
        : walletGroupNamesCache[wallet!.walletGroupFk];
    String what = [
      if (saved.name.trim().isNotEmpty) "**" + saved.name.trim() + "**",
      (saved.income ? "+ " : "- ") +
          convertToMoney(allWallets, saved.amount.abs(),
              currencyKey: wallet?.currency),
      if (category != null) category.name,
      if (wallet != null)
        account == null ? wallet.name : account + " / " + wallet.name,
    ].join(" · ");
    if (!mounted) return;
    setState(() => conversation.add(ChatMessage(
        false, "ai-saved-transaction".tr(namedArgs: {"what": what}))));
    scrollToBottom();
    await persist();
  }

  // The words go to the input and are sent like a typed question
  void askByVoice() {
    openAiVoiceSheet(
      context,
      title: "ai-voice-chat-title".tr(),
      subtitle: "ai-voice-chat-help".tr(),
      submitLabel: "ai-send".tr(),
      submitIcon: Icons.send_rounded,
      onText: (text) {
        messageController.text = text;
        send();
      },
    );
  }

  // Asks to share the data first when it is off; true when it can go on
  Future<bool> ensureShareData(AiAction action) async {
    if (shareData) return true;
    bool turnedOn = false;
    await openBottomSheet(
      context,
      PopupFramework(
        title: aiActionInfo[action]!.labelKey.tr(),
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
                  updateSettings("aiShareData", true, updateGlobalState: false);
                  setState(() => shareData = true);
                  turnedOn = true;
                },
              ),
            ],
          ),
        ),
      ),
    );
    return turnedOn;
  }

  // Debts and duplicates are questions to the chat: the AI reads the data,
  // asks the app for more when needed and proposes changes to confirm
  Future<void> askWithData(AiAction action) async {
    if (sending || !await ensureShareData(action)) return;
    messageController.text = switch (action) {
      AiAction.debts => "ai-debts-request".tr(),
      _ => "ai-duplicates-request".tr(),
    };
    await send();
  }

  // Month summary with tips, added to the conversation as a card
  Future<void> runSummary() async {
    if (sending || !await ensureShareData(AiAction.summary)) return;
    AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
    String languageCode = context.locale.languageCode;
    setState(() {
      conversation.add(ChatMessage(true, "ai-summary-request".tr()));
      sending = true;
      error = null;
    });
    scrollToBottom();
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
      await persist();
    } catch (e) {
      showError(e);
    }
    setState(() => sending = false);
    scrollToBottom();
  }

  Future<void> chooseProvider(AiProvider value) async {
    await updateSettings("aiProvider", value.name, updateGlobalState: false);
    setState(() => provider = value);
    await loadProvider();
    setState(dropUnsupportedAttachment);
  }

  String modelTags(AiModelInfo info) => [
        if (info.free) "ai-tag-free".tr(),
        if (info.readsImages) "ai-tag-reads-photos".tr(),
        if (info.readsPdf && provider != AiProvider.chatgpt)
          "ai-tag-reads-pdf".tr(),
        if (info.fast) "ai-tag-fast".tr(),
      ].join("  ·  ");

  // The first model of each list is the one the app picks by default
  String get recommendedModelId => models.first.id;

  String modelDescription(AiModelInfo info) => [
        if (info.id == recommendedModelId) "ai-model-recommended".tr(),
        if (modelTags(info) != "") modelTags(info),
      ].join("  ·  ");

  Future<void> chooseModel() async {
    if (models.isEmpty) return;
    await openBottomSheet(
      context,
      PopupFramework(
        title: "ai-choose-model".tr(),
        subtitle: "ai-choose-model-help".tr(),
        child: Builder(
          builder: (sheetContext) => RadioItems<String>(
            initial: model.id,
            // The recommended one, then the fast ones, then the rest
            items: [
              models.first.id,
              for (AiModelInfo m in models.skip(1))
                if (m.fast) m.id,
              for (AiModelInfo m in models.skip(1))
                if (!m.fast) m.id,
            ],
            displayFilter: (id) => modelInfo(provider, id).label,
            getDescription: (id) => modelDescription(modelInfo(provider, id)),
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
        title: "ai-attach-title".tr(),
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
    if (signingIn) return;
    setState(() {
      signingIn = true;
      error = null;
    });
    try {
      await ChatGptSession.signIn();
    } catch (e) {
      print("ChatGPT sign-in failed: " + e.toString());
      // Stays on the page, so it is seen when coming back from the browser
      if (mounted) showError(e);
    }
    if (!mounted) return;
    setState(() => signingIn = false);
    await loadProvider();
  }

  Future<void> send() async {
    String text = messageController.text.trim();
    if ((text == "" && attachment == null) || sending) return;
    AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
    ChatMessage answer = ChatMessage(false, "");
    AiAttachment? sentFile = attachment;
    setState(() {
      conversation.add(ChatMessage(true, text, attachment: attachment));
      attachment = null;
      sending = true;
      error = null;
      messageController.clear();
    });
    scrollToBottom();
    if (sentFile != null) {
      saveChatAttachment(conversationId, conversation.length - 1, sentFile);
    }
    try {
      // The AI may ask the app for more data first: the results go back to
      // it as a hidden message and it answers again, a few rounds at most
      for (int round = 0;; round++) {
        String? context =
            shareData ? await buildFinanceContext(allWallets) : null;
        ChatMessage current = answer;
        String reply = await sendChat(
          conversation,
          financeContext: context,
          onDelta: (soFar) => setState(() {
            current.text = soFar;
            if (conversation.contains(current) == false) {
              conversation.add(current);
            }
          }),
        );
        setState(() {
          current.text = reply;
          if (conversation.contains(current) == false) {
            conversation.add(current);
          }
        });
        List<Map<String, dynamic>> queries = extractAiQueries(reply);
        if (queries.isEmpty || round >= maxAiQueryRounds) break;
        setState(() => lookingUp = true);
        // Data turned off: the app says so instead of reading anything
        String results = shareData
            ? await runAiQueries(queries, allWallets)
            : "The user chose not to share their data with you; answer without it.";
        answer = ChatMessage(false, "");
        setState(() {
          conversation.add(ChatMessage(true, results, hidden: true));
          lookingUp = false;
        });
      }
      await persist();
    } catch (e) {
      if (answer.text.trim() == "") conversation.remove(answer);
      showError(e);
    }
    setState(() {
      sending = false;
      lookingUp = false;
    });
    scrollToBottom();
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
          if (signingIn)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextFont(
                      text: "ai-plan-waiting".tr(),
                      fontSize: 15,
                      maxLines: 4,
                    ),
                  ),
                ],
              ),
            )
          else
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
            AiActionIcon(aiActionInfo[AiAction.summary]!, size: 32),
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
          AiMarkdownText(message.text, color: colors.onSurface),
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

  Future<List<AiChangePlan>> plansFor(ChatMessage message) {
    return changePlans.putIfAbsent(message, () async {
      AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
      List<AiChangePlan> plans = [];
      for (Map<String, dynamic> json in extractAiChanges(message.text)) {
        try {
          plans.add(await planAiChange(json, allWallets));
        } catch (e) {
          print("AI change could not be checked: " + e.toString());
          AiChangeKind kind = aiChangeKindOf(json["action"])!;
          plans.add(AiChangePlan(
              kind: kind,
              title: ("ai-change-" + kind.name).tr(),
              error: "ai-change-failed".tr()));
        }
      }
      return plans;
    });
  }

  Future<bool> confirmDelete(AiChangePlan plan) async {
    bool confirmed = false;
    await openPopup(
      context,
      icon: Icons.delete_rounded,
      title: "ai-change-delete-title".tr(),
      description: ([...plan.details, "ai-change-cannot-undo".tr()]).join("\n"),
      onCancel: () => popRoute(context),
      onCancelLabel: "cancel".tr(),
      onSubmit: () {
        confirmed = true;
        popRoute(context);
      },
      onSubmitLabel: "delete".tr(),
    );
    return confirmed;
  }

  // Checks the change again with the data as it is now, then applies it
  Future<void> applyChange(ChatMessage message, int index) async {
    AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
    List<Map<String, dynamic>> changes = extractAiChanges(message.text);
    if (index >= changes.length) return;
    AiChangePlan plan;
    try {
      plan = await planAiChange(changes[index], allWallets);
    } catch (e) {
      setState(() => message.changeStatus[index] = "failed");
      await persist();
      return;
    }
    if (!plan.canApply) {
      setState(() => changePlans.remove(message));
      return;
    }
    if (plan.destructive && !await confirmDelete(plan)) return;
    try {
      String status = await plan.apply!(context);
      setState(() => message.changeStatus[index] = status);
    } catch (e) {
      print("AI change failed: " + e.toString());
      setState(() => message.changeStatus[index] = "failed");
    }
    changePlans.remove(message);
    await persist();
  }

  Widget changeCard(ChatMessage message, int index, AiChangePlan plan) {
    ColorScheme colors = Theme.of(context).colorScheme;
    String? status = message.changeStatus[index];
    Widget statusLine(IconData icon, String text, Color color) =>
        Row(children: [
          Icon(icon, size: 18, color: color),
          SizedBox(width: 6),
          Expanded(
            child: TextFont(
                text: text, fontSize: 14, maxLines: 3, textColor: color),
          ),
        ]);
    return Container(
      constraints: BoxConstraints(maxWidth: 520),
      margin:
          const EdgeInsetsDirectional.symmetric(horizontal: 15, vertical: 4),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: plan.destructive
              ? colors.error.withOpacity(0.6)
              : colors.primary.withOpacity(0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (plan.destructive ? colors.error : colors.primary)
                    .withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(aiChangeIcon(plan.kind),
                  size: 20,
                  color: plan.destructive ? colors.error : colors.primary),
            ),
            SizedBox(width: 10),
            Expanded(
              child: TextFont(
                text: plan.title,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                maxLines: 2,
              ),
            ),
          ]),
          SizedBox(height: 8),
          for (String line in plan.details)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 2),
              child: TextFont(text: line, fontSize: 14, maxLines: 4),
            ),
          SizedBox(height: 8),
          if (status == "done")
            statusLine(Icons.check_circle_rounded, "ai-change-done".tr(),
                getColor(context, "incomeAmount"))
          else if (status == "opened")
            statusLine(Icons.open_in_new_rounded, "ai-change-opened".tr(),
                colors.primary)
          else if (status == "cancelled")
            statusLine(Icons.block_rounded, "ai-change-cancelled".tr(),
                getColor(context, "black").withOpacity(0.6))
          else if (status == "failed")
            statusLine(Icons.error_rounded, "ai-change-failed".tr(),
                getColor(context, "expenseAmount"))
          else if (plan.error != null)
            statusLine(Icons.error_outline_rounded, plan.error!,
                getColor(context, "expenseAmount"))
          else
            Row(children: [
              Expanded(
                child: Button(
                  label: "cancel".tr(),
                  color: colors.surfaceContainerHighest,
                  textColor: colors.onSurface,
                  onTap: () async {
                    setState(() => message.changeStatus[index] = "cancelled");
                    await persist();
                  },
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Button(
                  label: plan.kind == AiChangeKind.addTransaction
                      ? "ai-change-review".tr()
                      : plan.destructive
                          ? "delete".tr()
                          : "ai-change-confirm".tr(),
                  color: plan.destructive ? colors.error : colors.primary,
                  textColor:
                      plan.destructive ? colors.onError : colors.onPrimary,
                  onTap: () => applyChange(message, index),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  Widget changeCards(ChatMessage message) {
    return FutureBuilder<List<AiChangePlan>>(
      future: plansFor(message),
      builder: (context, snapshot) {
        List<AiChangePlan> plans = snapshot.data ?? [];
        return Column(children: [
          for (int i = 0; i < plans.length; i++)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: changeCard(message, i, plans[i]),
            ),
        ]);
      },
    );
  }

  // What the bubble shows: the answer without the change and query blocks
  String shownText(ChatMessage message) => message.fromUser
      ? message.text
      : stripAiQueries(stripAiChanges(message.text));

  Widget messageWidget(ChatMessage message) {
    if (message.hidden) return SizedBox.shrink();
    bool streaming = sending && message == conversation.lastOrNull;
    bool hasChanges = message.fromUser == false &&
        streaming == false &&
        message.text.contains("```" + aiChangeFence);
    bool hasText = shownText(message) != "" ||
        message.attachment != null ||
        message.attachmentName != null;
    return Column(children: [
      if (hasText) bubble(message),
      if (hasChanges) changeCards(message),
    ]);
  }

  Widget bubble(ChatMessage message) {
    if (summaries.contains(message)) return summaryCard(message);
    ColorScheme colors = Theme.of(context).colorScheme;
    String? fileName = message.attachment?.name ?? message.attachmentName;
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
            if (fileName != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    message.attachment == null
                        ? Icons.attach_file_rounded
                        : attachmentIcon(message.attachment!),
                    size: 18,
                    color: colors.onSurface),
                SizedBox(width: 6),
                Flexible(
                  child: TextFont(
                    text: fileName,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    maxLines: 2,
                  ),
                ),
              ]),
            if (fileName != null && shownText(message) != "")
              SizedBox(height: 6),
            if (shownText(message) != "")
              message.fromUser
                  ? SelectableText(message.text,
                      style: TextStyle(fontSize: 15, color: colors.onSurface))
                  : AiMarkdownText(shownText(message), color: colors.onSurface),
          ],
        ),
      ),
    );
  }

  Widget errorLine() => Padding(
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
      );

  @override
  Widget build(BuildContext context) {
    // Once a service works the page is a chat; its settings move to the gear
    if (ready && showSettings == false) return chatPage();
    return settingsPage();
  }

  Widget settingsPage() {
    return PageFramework(
      title: ready ? "ai-settings".tr() : "ai-chat".tr(),
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
                (modelDescription(model) == ""
                    ? ""
                    : "\n" + modelDescription(model)),
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
        if (error != null) errorLine(),
        SizedBox(height: 10),
        if (ready)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 15),
            child: Button(
              label: "ai-back-to-chat".tr(),
              icon: Icons.chat_rounded,
              expandedLayout: true,
              onTap: () => setState(() {
                showSettings = false;
                error = null;
              }),
            ),
          )
        else
          // Shown before setting up, so it is clear what the chat can do
          AiActionsGrid(
            onTap: runAction,
            providerName: providerLabel(provider),
            readsImages: model.readsImages,
          ),
        SizedBox(height: 60),
      ],
    );
  }

  Widget chatPage() {
    ColorScheme colors = Theme.of(context).colorScheme;
    List<Widget> body = conversation.isEmpty
        ? [
            Padding(
              padding: const EdgeInsetsDirectional.only(
                  start: 18, end: 18, top: 4, bottom: 4),
              child: TextFont(
                text: "ai-chat-empty-title".tr(),
                fontSize: 22,
                fontWeight: FontWeight.bold,
                maxLines: 3,
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
              child: note("ai-chat-empty-subtitle"
                  .tr(namedArgs: {"provider": providerLabel(provider)})),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                  start: 18, end: 18, top: 4, bottom: 16),
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
            AiActionsGrid(
              onTap: runAction,
              providerName: providerLabel(provider),
              readsImages: model.readsImages,
            ),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
              child: note("ai-disclaimer".tr()),
            ),
          ]
        : [
            for (ChatMessage message in conversation) messageWidget(message),
            if (sending &&
                (conversation.lastOrNull == null ||
                    conversation.last.fromUser ||
                    shownText(conversation.last) == ""))
              Padding(
                padding: const EdgeInsetsDirectional.all(15),
                child: Row(children: [
                  SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  if (lookingUp) ...[
                    SizedBox(width: 10),
                    Expanded(
                      child: TextFont(
                        text: "ai-looking-up".tr(),
                        fontSize: 14,
                        maxLines: 2,
                        textColor: getColor(context, "black").withOpacity(0.6),
                      ),
                    ),
                  ],
                ]),
              ),
          ];

    Widget inputBar = Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: EdgeInsetsDirectional.only(
        start: 8,
        end: 12,
        top: 6,
        // Above the phone's gesture bar when the keyboard is closed
        bottom: 8 +
            (MediaQuery.viewInsetsOf(context).bottom > 0
                ? 0
                : MediaQuery.viewPaddingOf(context).bottom),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 760),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 6),
                child: errorLine(),
              ),
            if (attachment != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding:
                      const EdgeInsetsDirectional.only(start: 8, bottom: 6),
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
                onPressed: sending ? null : openActionsSheet,
                tooltip: "ai-actions-title".tr(),
                icon: Icon(Icons.auto_awesome_rounded, color: colors.primary),
              ),
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
                  maxLines: 5,
                ),
              ),
              SizedBox(width: 8),
              // Microphone while there is nothing to send, like in chat apps
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: messageController,
                builder: (context, value, _) {
                  bool empty = value.text.trim().isEmpty && attachment == null;
                  return AnimatedSwitcher(
                    duration: Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: empty
                        ? IconButton.filled(
                            key: ValueKey("mic"),
                            onPressed: sending ? null : askByVoice,
                            tooltip: "ai-voice-chat".tr(),
                            icon: Icon(Icons.mic_rounded),
                          )
                        : IconButton.filled(
                            key: ValueKey("send"),
                            onPressed: sending ? null : send,
                            tooltip: "ai-send".tr(),
                            icon: Icon(Icons.send_rounded),
                          ),
                  );
                },
              ),
            ]),
          ]),
        ),
      ),
    );

    return PageFramework(
      title: "ai-chat".tr(),
      dragDownToDismiss: true,
      resizeToAvoidBottomInset: true,
      scrollController: chatScroll,
      actions: [
        IconButton(
          tooltip: "ai-new-chat".tr(),
          onPressed: sending ? null : newConversation,
          icon: Icon(Icons.add_comment_rounded),
        ),
        IconButton(
          tooltip: "ai-history".tr(),
          onPressed: openHistory,
          icon: Icon(Icons.history_rounded),
        ),
        IconButton(
          tooltip: "ai-settings".tr(),
          onPressed: () => setState(() => showSettings = true),
          icon: Icon(Icons.settings_rounded),
        ),
      ],
      bodyBuilder: (scrollController, scrollPhysics, sliverAppBar) => Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: scrollController,
              physics: scrollPhysics,
              slivers: [
                sliverAppBar,
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [...body, SizedBox(height: 12)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          inputBar,
        ],
      ),
    );
  }
}
