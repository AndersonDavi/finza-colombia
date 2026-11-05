import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/aiChat.dart';
import 'package:budget/struct/chatgptSignIn.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
  List<String> models = [];
  List<ChatMessage> conversation = [];
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

  bool get ready => provider == AiProvider.chatgpt ? signedIn : hasKey;

  Future<void> loadProvider() async {
    bool key = provider == AiProvider.chatgpt
        ? false
        : await readApiKey(provider) != null;
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
      List<String> list = await listModels(provider);
      setState(() => models = list);
    } catch (e) {
      showError(e);
    }
  }

  void showError(Object e) {
    setState(() {
      String message = e.toString();
      error = message.startsWith("ai-") ? message.tr() : message;
      errorManagesUsage = e is AiError && e.manageUsage;
    });
  }

  Future<void> chooseProvider(AiProvider value) async {
    await updateSettings("aiProvider", value.name, updateGlobalState: false);
    setState(() => provider = value);
    await loadProvider();
  }

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
    if (text == "" || sending) return;
    AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
    ChatMessage answer = ChatMessage(false, "");
    setState(() {
      conversation.add(ChatMessage(true, text));
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
      };

  Widget setupSection() {
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
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
      child: Column(children: [
        note((provider == AiProvider.gemini
                ? "ai-gemini-key-description"
                : "ai-openai-key-description")
            .tr()),
        SizedBox(height: 10),
        TextInput(
          labelText: "ai-api-key".tr(),
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

  Widget bubble(ChatMessage message) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Align(
      alignment: message.fromUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: 520),
        margin: const EdgeInsetsDirectional.symmetric(
            horizontal: 15, vertical: 5),
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: message.fromUser
              ? colors.primaryContainer
              : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(message.text,
            style: TextStyle(fontSize: 15, color: colors.onSurface)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "ai-chat".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      listWidgets: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 15),
          child: Wrap(
            spacing: 8,
            children: [
              for (AiProvider p in AiProvider.values)
                ChoiceChip(
                  label: TextFont(text: providerLabel(p), fontSize: 15),
                  selected: provider == p,
                  onSelected: (_) => chooseProvider(p),
                ),
            ],
          ),
        ),
        SizedBox(height: 8),
        setupSection(),
        if (ready && models.isNotEmpty)
          SettingsContainerDropdown(
            title: "ai-model".tr(),
            icon: Icons.memory_rounded,
            initial: models.contains(selectedModel(provider))
                ? selectedModel(provider)!
                : models.first,
            items: models,
            getLabel: (m) => m.replaceFirst("models/", ""),
            onChanged: (m) => setSelectedModel(provider, m),
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
            child: Row(children: [
              Expanded(
                child: TextInput(
                  labelText: "ai-ask-placeholder".tr(),
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
