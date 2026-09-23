import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/chat/domain/chat_message.dart';
import 'package:tow_truck_frontend/features/chat/presentation/chat_controller.dart';
import 'chat_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen(
      {super.key,
      required this.orderId,
      required this.title,
      this.driverTheme = false,
      this.readOnly = false,
      this.auditDemo = false,
      this.testState,
      this.onTestSend,
      this.onTestRetry,
      this.onTestLoadMore});
  final String orderId;
  final String title;
  final bool driverTheme;
  final bool readOnly;
  final bool auditDemo;
  final ChatState? testState;
  final ValueChanged<String>? onTestSend;
  final ValueChanged<ChatMessage>? onTestRetry;
  final VoidCallback? onTestLoadMore;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final ChatControllerArgs _args;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _args = ChatControllerArgs(widget.orderId, readOnly: widget.readOnly);
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients ||
        _scroll.position.extentAfter > 80 ||
        widget.auditDemo) {
      return;
    }
    final state = widget.testState ?? ref.read(chatControllerProvider(_args));
    if (state == null || state.loadingMore || state.nextBeforeId == null) {
      return;
    }
    if (widget.onTestLoadMore != null) {
      widget.onTestLoadMore!();
    } else {
      ref.read(chatControllerProvider(_args).notifier).loadMore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.auditDemo) {
      ref.invalidate(chatControllerProvider(_args));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.driverTheme
        ? (AvroDriverColors.surface, AvroDriverColors.accent)
        : (AvroClientColors.background, AvroClientColors.accent);
    final chat = widget.testState ??
        (widget.auditDemo ? null : ref.watch(chatControllerProvider(_args)));
    final messages = widget.auditDemo
        ? <ChatMessage>[
            ChatMessage(
                id: 'audit',
                orderId: widget.orderId,
                senderId: 'driver',
                clientMessageId: 'audit',
                text: 'Буду у машины через несколько минут.',
                createdAt: DateTime.now())
          ]
        : chat!.messages;
    final canSend = !widget.readOnly && !widget.auditDemo;
    return Scaffold(
        backgroundColor: colors.$1,
        appBar: AppBar(title: Text(widget.title), backgroundColor: colors.$1),
        body: Column(children: [
          Expanded(
              child: chat?.loading == true && messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : messages.isEmpty
                      ? const Center(child: Text('Сообщений пока нет'))
                      : ListView.builder(
                          controller: _scroll,
                          reverse: false,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final m = messages[i];
                            return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Align(
                                    alignment: m.senderId == 'me'
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: m.senderId == 'me'
                                                ? colors.$2
                                                    .withValues(alpha: .2)
                                                : colors.$2
                                                    .withValues(alpha: .08),
                                            borderRadius:
                                                BorderRadius.circular(18)),
                                        child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(m.text,
                                                      style: EvikTypography
                                                          .bodyLarge),
                                                  if (m.status ==
                                                      ChatMessageStatus.pending)
                                                    const Text('Отправляется…'),
                                                  if (m.status ==
                                                      ChatMessageStatus.failed)
                                                    TextButton(
                                                        onPressed: () {
                                                          if (widget
                                                                  .onTestRetry !=
                                                              null) {
                                                            widget.onTestRetry!(
                                                                m);
                                                          } else {
                                                            ref
                                                                .read(chatControllerProvider(
                                                                        _args)
                                                                    .notifier)
                                                                .retry(m);
                                                          }
                                                        },
                                                        child: const Text(
                                                            'Повторить'))
                                                ])))));
                          })),
          if (chat?.loading == true && messages.isNotEmpty)
            const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Восстанавливаем соединение…')),
          if (chat?.loadingMore == true)
            const Padding(
                padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
          if (chat?.error != null)
            Padding(
                padding: const EdgeInsets.all(8),
                child: Text(chat!.error!,
                    style: const TextStyle(color: Colors.red))),
          if (canSend)
            SafeArea(
                top: false,
                child: Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _text,
                          enabled: canSend,
                          maxLines: 4,
                          decoration: const InputDecoration(
                              hintText: 'Напишите сообщение'))),
                  IconButton(
                      onPressed: () {
                        final value = _text.text.trim();
                        if (value.isEmpty) return;
                        if (widget.onTestSend != null) {
                          widget.onTestSend!(value);
                        } else {
                          ref
                              .read(chatControllerProvider(_args).notifier)
                              .send(value);
                        }
                        _text.clear();
                      },
                      icon: const Icon(Icons.send))
                ]))
          else if (widget.readOnly)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Чат закрыт для отправки новых сообщений'))
        ]));
  }
}
