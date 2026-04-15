import '../../core/theme/app_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';

class ChatScreen extends StatefulWidget {
  final String tripId;
  const ChatScreen({super.key, required this.tripId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Timer? _pollTimer;
  bool _sending = false;
  String? _myUserId; // our own DB user ID, fetched once on init

  @override
  void initState() {
    super.initState();
    _loadMyId();
    _loadMessages();
    // Poll every 5 seconds for new messages.
    // When Supabase Realtime is wired up this polling can be removed.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMyId() async {
    try {
      final res = await createApiClient().get('/users/me');
      setState(() => _myUserId = res.data['id'] as String);
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    try {
      final res = await createApiClient().get('/trips/${widget.tripId}/messages');
      final msgs = List<Map<String, dynamic>>.from(res.data as List);
      setState(() => _messages = msgs);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      await createApiClient().post('/trips/${widget.tripId}/messages', data: {'content': text});
      await _loadMessages();
    } catch (_) {}
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat groupe'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Les messages disparaissent après 72h',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Aucun message.', style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _MessageBubble(
                      msg: _messages[i],
                      isMine: (_messages[i]['sender'] as Map)['id'] == _myUserId,
                    ),
                  ),
          ),
          _InputBar(controller: _controller, onSend: _send, sending: _sending),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMine;
  const _MessageBubble({required this.msg, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final sender = msg['sender'] as Map<String, dynamic>;
    final ts = DateTime.parse(msg['created_at'] as String).toLocal();
    final timeFmt = DateFormat('HH:mm');

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? kPrimary : kSurface,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMine ? const Radius.circular(4) : null,
            bottomLeft: isMine ? null : const Radius.circular(4),
          ),
          border: isMine ? null : Border.all(color: kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Text(sender['display_name'] as String,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kAccent)),
            Text(msg['content'] as String, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 2),
            Text(timeFmt.format(ts),
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5))),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;
  const _InputBar({required this.controller, required this.onSend, required this.sending});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Message…',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
          ),
        ]),
      ),
    );
  }
}
