// The Emoji widget: a searchable picker that copies the chosen emoji through
// the system clipboard (so it also lands in the in-shell Clipboard history).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n.dart';
import '../../ui/glass.dart';

const List<(String, String, String)> _emojis = [
  ('😀', 'smileys', 'grin happy smile'),
  ('😁', 'smileys', 'grin happy'),
  ('😂', 'smileys', 'laugh tears joy'),
  ('🤣', 'smileys', 'laugh rolling'),
  ('😊', 'smileys', 'blush smile'),
  ('😍', 'smileys', 'love heart eyes'),
  ('😘', 'smileys', 'kiss'),
  ('😎', 'smileys', 'cool sunglasses'),
  ('🤔', 'smileys', 'think'),
  ('😴', 'smileys', 'sleep'),
  ('😭', 'smileys', 'cry sad'),
  ('😡', 'smileys', 'angry'),
  ('🥳', 'smileys', 'party'),
  ('🤯', 'smileys', 'mind blown'),
  ('👋', 'hands', 'wave hello'),
  ('👍', 'hands', 'thumbs up like'),
  ('👎', 'hands', 'thumbs down'),
  ('👏', 'hands', 'clap'),
  ('🙏', 'hands', 'please thanks pray'),
  ('💪', 'hands', 'strong muscle'),
  ('🤝', 'hands', 'handshake'),
  ('✌️', 'hands', 'peace'),
  ('❤️', 'symbols', 'heart love red'),
  ('🧡', 'symbols', 'heart orange'),
  ('💚', 'symbols', 'heart green'),
  ('💙', 'symbols', 'heart blue'),
  ('💜', 'symbols', 'heart purple'),
  ('🖤', 'symbols', 'heart black'),
  ('💔', 'symbols', 'broken heart'),
  ('💯', 'symbols', 'hundred'),
  ('🔥', 'symbols', 'fire hot'),
  ('✨', 'symbols', 'sparkles'),
  ('💫', 'symbols', 'dizzy star'),
  ('💥', 'symbols', 'boom'),
  ('⭐', 'symbols', 'star'),
  ('✅', 'symbols', 'check done'),
  ('❌', 'symbols', 'cross no'),
  ('⚠️', 'symbols', 'warning'),
  ('🚀', 'objects', 'rocket launch'),
  ('💻', 'objects', 'laptop computer'),
  ('🖥️', 'objects', 'desktop screen'),
  ('⌨️', 'objects', 'keyboard'),
  ('🖱️', 'objects', 'mouse'),
  ('🎧', 'objects', 'headphones music'),
  ('🎵', 'objects', 'music note'),
  ('📁', 'objects', 'folder'),
  ('📝', 'objects', 'note write'),
  ('📅', 'objects', 'calendar date'),
  ('🔒', 'objects', 'lock'),
  ('🔑', 'objects', 'key'),
  ('💡', 'objects', 'idea light'),
  ('⚙️', 'objects', 'settings gear'),
  ('🛠️', 'objects', 'tools'),
  ('🐱', 'nature', 'cat'),
  ('🐶', 'nature', 'dog'),
  ('🦊', 'nature', 'fox'),
  ('🐻', 'nature', 'bear'),
  ('🌙', 'nature', 'moon night'),
  ('☀️', 'nature', 'sun'),
  ('🌈', 'nature', 'rainbow'),
  ('🌸', 'nature', 'flower'),
  ('🌊', 'nature', 'wave water'),
  ('🍕', 'food', 'pizza'),
  ('🍔', 'food', 'burger'),
  ('🍟', 'food', 'fries'),
  ('🍣', 'food', 'sushi'),
  ('🍎', 'food', 'apple'),
  ('🍩', 'food', 'donut'),
  ('☕', 'food', 'coffee'),
  ('🍺', 'food', 'beer'),
  ('🎉', 'symbols', 'party tada'),
  ('🎁', 'objects', 'gift'),
  ('🤖', 'symbols', 'robot'),
  ('👀', 'smileys', 'eyes look'),
];

class EmojiApp extends StatefulWidget {
  final Future<void> Function(String text)? copy;
  const EmojiApp({super.key, this.copy});

  @override
  State<EmojiApp> createState() => _EmojiAppState();
}

class _EmojiAppState extends State<EmojiApp> {
  String _query = '';
  String _category = 'all';
  String _status = '';

  Future<void> _pick(String emoji) async {
    final copy = widget.copy;
    if (copy != null) {
      await copy(emoji);
    } else {
      await Clipboard.setData(ClipboardData(text: emoji));
    }
    if (!mounted) return;
    setState(() => _status = '${Loc.t('Copied', 'Скопировано')} $emoji');
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final visible = [
      for (final emoji in _emojis)
        if ((_category == 'all' || emoji.$2 == _category) &&
            (q.isEmpty ||
                emoji.$1.contains(q) ||
                emoji.$3.contains(q)))
          emoji,
    ];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_emotions_outlined,
                  size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                Loc.t('Emoji', 'Эмодзи'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: _status.isEmpty
                    ? const SizedBox.shrink()
                    : Caption(_status, key: ValueKey(_status)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: Loc.t('Search emoji', 'Поиск эмодзи'),
              hintStyle:
                  const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded,
                  size: 16, color: Colors.white54),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final category in const [
                  'all',
                  'smileys',
                  'hands',
                  'nature',
                  'food',
                  'objects',
                  'symbols',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      key: ValueKey('emoji-category-$category'),
                      onTap: () => setState(() => _category = category),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: _category == category ? 0.18 : 0.05,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          category == 'all'
                              ? Loc.t('All', 'Все')
                              : category,
                          style: TextStyle(
                            color: _category == category
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Caption(Loc.t(
                      'Nothing matches that search',
                      'По этому запросу ничего нет',
                    )),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final emoji = visible[index];
                      return GestureDetector(
                        key: ValueKey('emoji-${emoji.$1}'),
                        onTap: () => _pick(emoji.$1),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            emoji.$1,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}