import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Google Mobile Ads 初期化
  await MobileAds.instance.initialize();
  runApp(const StickyMemoApp());
}

/// 4色のメモ種別
enum MemoColor { blue, orange, green, pink }

extension MemoColorX on MemoColor {
  Color get bg {
    switch (this) {
      case MemoColor.blue:
        return const Color(0xFFBBD7FF);
      case MemoColor.orange:
        return const Color(0xFFFFC5A6);
      case MemoColor.green:
        return const Color(0xFFE2FFB4);
      case MemoColor.pink:
        return const Color(0xFFFFC6EB);
    }
  }

  String get nameJp {
    switch (this) {
      case MemoColor.blue:
        return 'ブルー';
      case MemoColor.orange:
        return 'オレンジ';
      case MemoColor.green:
        return 'グリーン';
      case MemoColor.pink:
        return 'ピンク';
    }
  }

  static MemoColor fromIndex(int i) => MemoColor.values[i.clamp(0, 3)];
}

class Memo {
  Memo({
    required this.id,
    required this.color,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final MemoColor color;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  Memo copyWith({
    String? id,
    MemoColor? color,
    String? title,
    String? body,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Memo(
      id: id ?? this.id,
      color: color ?? this.color,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'color': color.index,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Memo fromJson(Map<String, dynamic> json) => Memo(
        id: json['id'] as String,
        color: MemoColorX.fromIndex(json['color'] as int),
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

/// ローカル保存（SharedPreferences）
class MemoRepository {
  static const _key = 'memos_v1';

  Future<List<Memo>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(Memo.fromJson)
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // 新しい順
    return list;
  }

  Future<void> save(List<Memo> memos) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(memos.map((e) => e.toJson()).toList());
    await prefs.setString(_key, raw);
  }
}

/// アプリ全体の状態
class MemoStore extends ChangeNotifier {
  MemoStore(this._repo);
  final MemoRepository _repo;

  final _uuid = const Uuid();
  List<Memo> _items = [];
  List<Memo> get items => List.unmodifiable(_items);

  /// UI用：展開中のID
  final Set<String> _expanded = {};
  bool isExpanded(String id) => _expanded.contains(id);
  void toggleExpanded(String id) {
    if (!_expanded.add(id)) _expanded.remove(id);
    notifyListeners();
  }

  bool _initialized = false;
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _items = await _repo.load();
    notifyListeners();
  }

  Future<void> add(MemoColor color, String title, String body) async {
    final now = DateTime.now();
    final memo = Memo(
      id: _uuid.v4(),
      color: color,
      title: title.trim().isEmpty ? _firstLineOrEmpty(body) : title.trim(),
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    _items = [memo, ..._items];
    await _repo.save(_items);
    notifyListeners();
  }

  Future<void> update(Memo updated) async {
    _items = _items.map((m) => m.id == updated.id ? updated : m).toList();
    await _repo.save(_items);
    notifyListeners();
  }

  Future<Memo?> removeById(String id) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx == -1) return null;
    final removed = _items.removeAt(idx);
    await _repo.save(_items);
    notifyListeners();
    return removed;
  }

  static String _firstLineOrEmpty(String text) {
    final t = text.trimLeft();
    if (t.isEmpty) return '';
    return t.split('\n').first.trim();
  }
}

const String kBackgroundAsset = 'assets/backgrounds/app_bg_02.png';

class StickyMemoApp extends StatelessWidget {
  const StickyMemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MemoStore(MemoRepository())..init(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Sticky Memo',
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF7BA7FF),
          useMaterial3: true,
          fontFamily: 'NotoSansJP', // フォントで問題があればこの行をコメントアウト
        ),
        home: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _trashHover = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MemoStore>();
    final items = store.items;

    return Scaffold(
      // 画面下固定のバナー広告
      bottomNavigationBar: const _AdBanner(),
      backgroundColor: const Color(0xFFF8F8F8),
      body: Stack(
        children: [
          // 背景画像
          Positioned.fill(
            child: Image.asset(
              kBackgroundAsset,
              fit: BoxFit.cover,
            ),
          ),
          // コンテンツ
          SafeArea(
            child: Column(
              children: [
                // 上段：ゴミ箱／設定
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: DragTarget<Memo>(
                          onWillAccept: (data) {
                            setState(() => _trashHover = true);
                            return true;
                          },
                          onLeave: (_) => setState(() => _trashHover = false),
                          onAccept: (memo) async {
                            setState(() => _trashHover = false);
                            final removed = await store.removeById(memo.id);
                            if (!mounted || removed == null) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('メモを削除しました'),
                                action: SnackBarAction(
                                  label: '元に戻す',
                                  onPressed: () async {
                                    await store.add(
                                        removed.color, removed.title, removed.body);
                                  },
                                ),
                              ),
                            );
                          },
                          builder: (context, cand, rej) {
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              height: 52,
                              decoration: BoxDecoration(
                                color: _trashHover || cand.isNotEmpty
                                    ? Colors.red.shade300
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.delete,
                                      color: _trashHover
                                          ? Colors.white
                                          : Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(
                                    'ゴミ箱にドラッグで削除',
                                    style: TextStyle(
                                      color: _trashHover
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.settings),
                        tooltip: '設定（プレースホルダー）',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => const _SettingsDialog(),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // 中段：新規メモ 4色（ボタン幅は前回より少し小さめ）
                SizedBox(
                  height: 108,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    scrollDirection: Axis.horizontal,
                    itemCount: MemoColor.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final c = MemoColor.values[i];
                      return _NewMemoChip(
                        color: c,
                        onTap: () => _openEditor(context, color: c),
                      );
                    },
                  ),
                ),

                // 下段：メモ一覧
                Expanded(
                  child: items.isEmpty
                      ? const _EmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final memo = items[index];
                            final expanded = store.isExpanded(memo.id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: LongPressDraggable<Memo>(
                                data: memo,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 320),
                                    child: _MemoCard(
                                      memo: memo,
                                      expanded: false,
                                      feedback: true,
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.35,
                                  child: _MemoCard(
                                      memo: memo, expanded: expanded),
                                ),
                                child: _MemoCard(
                                  memo: memo,
                                  expanded: expanded,
                                  onTap: () => store.toggleExpanded(memo.id),
                                  onEdit: () => _openEditor(
                                    context,
                                    color: memo.color,
                                    original: memo,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    required MemoColor color,
    Memo? original,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditorSheet(color: color, original: original),
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// 広告（下部バナー）
/// ─────────────────────────────────────────────────────────────

class _AdBanner extends StatefulWidget {
  const _AdBanner({super.key});

  @override
  State<_AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<_AdBanner> {
  BannerAd? _banner;
  bool _isLoaded = false;

  // 本番ID（リリースビルド）／テストID（デバッグビルド）を自動切替
  String get _adUnitId {
    if (kIsWeb) return ''; // Webは未対応
    if (Platform.isAndroid) {
      return kReleaseMode
          // ★ Android 本番（あなたのユニットID）
          ? 'ca-app-pub-3585644693335870/6620456388'
          // 開発時のテストID
          : 'ca-app-pub-3940256099942544/6300978111';
    } else if (Platform.isIOS) {
      return kReleaseMode
          // ★ iOS 本番（あなたのユニットID）
          ? 'ca-app-pub-3585644693335870/9156750697'
          // 開発時のテストID
          : 'ca-app-pub-3940256099942544/2934735716';
    } else {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    if (_adUnitId.isEmpty) return;

    _banner = BannerAd(
      size: AdSize.banner,
      adUnitId: _adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          debugPrint('Banner failed to load: $err');
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _banner == null) {
      // 読み込み中は高さ0でスペースを取らない
      return const SizedBox.shrink();
    }
    final height = _banner!.size.height.toDouble();
    // 端末幅いっぱいに中央寄せで表示
    return SafeArea(
      top: false,
      child: Container(
        alignment: Alignment.center,
        width: double.infinity,
        height: height,
        color: Colors.transparent,
        child: AdWidget(ad: _banner!),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// UI パーツ
/// ─────────────────────────────────────────────────────────────

class _NewMemoChip extends StatelessWidget {
  const _NewMemoChip({required this.color, required this.onTap});
  final MemoColor color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 112, // ちょい小さめ
        decoration: BoxDecoration(
          color: color.bg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.note_add_outlined),
            const Spacer(),
            Text(
              '${color.nameJp}で新規',
              style: const TextStyle(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoCard extends StatelessWidget {
  const _MemoCard({
    required this.memo,
    this.onTap,
    this.onEdit,
    this.expanded = false,
    this.feedback = false,
  });

  final Memo memo;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final bool expanded;
  final bool feedback;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context)
        .textTheme
        .titleLarge!
        .copyWith(fontWeight: FontWeight.w800);
    final textStyle = Theme.of(context).textTheme.bodyLarge;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: memo.color.bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(feedback ? 0.16 : 0.08),
            blurRadius: feedback ? 14 : 10,
            offset: Offset(0, feedback ? 6 : 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      memo.title.isEmpty ? '（無題）' : memo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  if (!feedback)
                    IconButton(
                      tooltip: '編集',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: onEdit,
                    ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: expanded ? 5000 : textStyle!.fontSize! * 1.6,
                  ),
                  child: Text(
                    memo.body.isEmpty ? '（本文なし）' : memo.body,
                    softWrap: true,
                    overflow: TextOverflow.fade,
                    style: textStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorSheet extends StatefulWidget {
  const _EditorSheet({required this.color, this.original});
  final MemoColor color;
  final Memo? original;

  @override
  State<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<_EditorSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.original?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.original?.body ?? '');
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.original != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Material(
        color: widget.color.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      isEdit
                          ? 'メモを編集（${widget.color.nameJp}）'
                          : '新規メモ（${widget.color.nameJp}）',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge!
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'タイトル（空なら本文1行目が使われます）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  maxLines: 10,
                  minLines: 6,
                  decoration: const InputDecoration(
                    labelText: '本文',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            final store = context.read<MemoStore>();
                            if (isEdit) {
                              final updated = widget.original!.copyWith(
                                title: _title.text.trim(),
                                body: _body.text,
                                updatedAt: DateTime.now(),
                              );
                              await store.update(updated);
                            } else {
                              await store.add(
                                  widget.color, _title.text, _body.text);
                            }
                            if (mounted) Navigator.pop(context);
                          },
                    child: Text(
                        _saving ? '保存中…' : (isEdit ? '保存する' : '追加する')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'まだメモがありません。\n上の色つきカードから作成してください！',
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: Colors.grey.shade600),
      ),
    );
  }
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('設定（ダミー）'),
      content: const Text('ここにテーマ・バックアップ・エクスポート等を今後追加できます。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}
