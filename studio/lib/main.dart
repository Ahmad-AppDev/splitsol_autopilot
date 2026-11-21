import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'github_api.dart';

const terracotta = Color(0xFFC8553D);
const cream = Color(0xFFF6EEE0);
const ink = Color(0xFF16130F);
const panel = Color(0xFF1E1A16);
const defaultRepo = 'Ahmad-AppDev/splitsol_autopilot';

final notifications = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await notifications.initialize(const InitializationSettings(
    macOS: DarwinInitializationSettings(requestAlertPermission: true, requestSoundPermission: true),
  ));
  runApp(const StudioApp());
}

class StudioApp extends StatelessWidget {
  const StudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SplitSol Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: terracotta, brightness: Brightness.dark, primary: terracotta),
        scaffoldBackgroundColor: ink,
      ),
      home: const StudioHome(),
    );
  }
}

class StudioHome extends StatefulWidget {
  const StudioHome({super.key});
  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  SharedPreferences? prefs;
  GithubApi? api;
  AutopilotState? state;
  List<WorkflowRun> runs = [];
  String? loadError;
  Item? selected; // null = Today
  bool busy = false;
  Timer? slowTimer, fastTimer;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    prefs = await SharedPreferences.getInstance();
    final token = prefs!.getString('token') ?? '';
    api = GithubApi(repo: prefs!.getString('repo') ?? defaultRepo, token: token);
    if (token.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSettings(firstRun: true));
    }
    await refresh();
    slowTimer = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
  }

  @override
  void dispose() {
    slowTimer?.cancel();
    fastTimer?.cancel();
    super.dispose();
  }

  /// After an action, check every 20s for 15 minutes so the app updates quickly.
  void _pollFast() {
    fastTimer?.cancel();
    var ticks = 0;
    fastTimer = Timer.periodic(const Duration(seconds: 20), (t) {
      if (++ticks > 45) t.cancel();
      refresh();
    });
  }

  Future<void> refresh() async {
    if (api == null) return;
    try {
      final s = await api!.fetchState();
      var r = runs;
      try {
        r = await api!.fetchRuns();
      } catch (_) {}
      await _notifyChanges(s);
      if (!mounted) return;
      setState(() {
        state = s;
        runs = r;
        loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => loadError = '$e');
    }
  }

  Future<void> _notifyChanges(AutopilotState s) async {
    final p = prefs!;
    final pend = s.pending;
    if (pend != null) {
      final key = '${pend.id}v${pend.attempt}';
      if (p.getString('notified_pending') != key) {
        await p.setString('notified_pending', key);
        await _notify('${pend.label} is ready 🎬', pend.isCarousel ? pend.title : 'Your SplitSol reel is waiting for review.');
      }
    }
    if (s.history.isNotEmpty) {
      final key = s.history.first.id;
      final before = p.getString('notified_posted');
      if (before != key) {
        await p.setString('notified_posted', key);
        if (before != null) await _notify('${s.history.first.label} done ✅', s.history.first.results.join(' · '));
      }
    }
    final err = s.lastError;
    if (err != null && p.getString('notified_error') != '${err['at']}') {
      await p.setString('notified_error', '${err['at']}');
      await _notify('Autopilot ${err['command']} failed ❌', '${err['message']}');
    }
  }

  Future<void> _notify(String title, String body) => notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
        title,
        body,
        const NotificationDetails(macOS: DarwinNotificationDetails(presentSound: true)),
      );

  Future<void> _run(String command, {String feedback = '', String kind = 'carousel', required String doneMsg}) async {
    setState(() => busy = true);
    try {
      await api!.dispatch(command, feedback: feedback, kind: kind);
      _toast(doneMsg);
      _pollFast();
      Future.delayed(const Duration(seconds: 4), refresh);
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ---------------- settings ----------------

  Future<void> _openSettings({bool firstRun = false}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !firstRun,
      builder: (c) => SettingsDialog(
        prefs: prefs!,
        firstRun: firstRun,
        onSaved: (newApi) async {
          api = newApi;
          await refresh();
        },
      ),
    );
  }

  WorkflowRun? get activeRun => runs.where((r) => r.running).firstOrNull;

  // ---------------- layout ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        _sidebar(),
        const VerticalDivider(width: 1, color: Colors.white12),
        Expanded(child: _main()),
      ]),
    );
  }

  Widget _sidebar() {
    final s = state;
    final pending = s?.pending;
    return Container(
      width: 270,
      color: panel,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 36),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Wordmark(size: 26, suffix: 'Studio')),
        const SizedBox(height: 22),
        _navTile(
          icon: Icons.today,
          title: 'Today',
          subtitle: pending != null
              ? '${pending.label} · waiting for you'
              : activeRun != null
                  ? 'Working…'
                  : 'Nothing waiting',
          selected: selected == null,
          badge: pending != null,
          onTap: () => setState(() => selected = null),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Text('HISTORY', style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: Colors.white38)),
        ),
        Expanded(
          child: ListView(children: [
            for (final e in s?.history ?? <Item>[])
              _navTile(
                icon: e.isCarousel ? Icons.view_carousel_outlined : Icons.movie_outlined,
                title: e.isCarousel ? e.title : e.label,
                subtitle: '${e.label} · ${_shortDate(e.postedAt)}',
                selected: selected?.id == e.id,
                onTap: () => setState(() => selected = e),
              ),
            if ((s?.history ?? []).isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Posted carousels and reels show up here.', style: TextStyle(color: Colors.white38)),
              ),
          ]),
        ),
        _runStatus(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Row(children: [
            IconButton(tooltip: 'Refresh', onPressed: refresh, icon: const Icon(Icons.refresh)),
            IconButton(tooltip: 'Settings & keys', onPressed: () => _openSettings(), icon: const Icon(Icons.settings)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse('https://github.com/${api?.repo ?? defaultRepo}/actions')),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Runs'),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _runStatus() {
    final r = runs.isNotEmpty ? runs.first : null;
    if (r == null) return const SizedBox.shrink();
    final color = r.running ? Colors.amber : (r.failed ? Colors.redAccent : Colors.greenAccent);
    final label = r.running ? 'Running' : (r.failed ? 'Failed' : 'OK');
    return InkWell(
      onTap: () => launchUrl(Uri.parse(r.url)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$label · ${r.title}',
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ),
        ]),
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    bool badge = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: selected,
        selectedTileColor: terracotta.withOpacity(0.22),
        leading: Icon(icon, size: 20),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        trailing: badge ? const Icon(Icons.circle, size: 10, color: terracotta) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _main() {
    if (loadError != null && state == null) {
      return _centerMsg('Can\'t reach GitHub', loadError!, actions: [('Settings', () => _openSettings())]);
    }
    final s = state;
    if (s == null) return const Center(child: CircularProgressIndicator());
    if (selected != null) return ItemView(key: ValueKey('h${selected!.id}'), item: selected!);

    final err = s.lastError;
    final banner = err == null
        ? null
        : MaterialBanner(
            backgroundColor: const Color(0xFF4A1D16),
            content: Text('Last ${err['command']} failed: ${err['message']}'),
            actions: [TextButton(onPressed: () => launchUrl(Uri.parse('https://github.com/${api!.repo}/actions')), child: const Text('See log'))],
          );

    Widget body;
    final p = s.pending;
    if (p != null) {
      body = ItemView(
        key: ValueKey('p${p.id}v${p.attempt}'),
        item: p,
        busy: busy || activeRun != null,
        onApprove: () => _confirmApprove(p),
        onRedo: () => _redo(p),
        onSkip: () => _skip(p),
      );
    } else if (activeRun != null) {
      body = _centerMsg('Making it…', 'Writing, drawing and checking. Usually 3–10 minutes.\nYou\'ll get a notification when it\'s ready.',
          spinner: true);
    } else {
      body = _centerMsg(
        'Nothing waiting',
        'A new post is made automatically every day at about 4:47 PM.\nYou\'ll get a notification when it\'s ready.',
        actions: [
          ('Make a carousel now', () => _run('generate', kind: 'carousel', doneMsg: 'Making a carousel…')),
          ('Make story Day ${s.day} now', () => _run('generate', kind: 'story', doneMsg: 'Making Day ${s.day}…')),
        ],
      );
    }
    return Column(children: [if (banner != null) banner, Expanded(child: body)]);
  }

  Future<void> _confirmApprove(Item p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Post ${p.label}?'),
        content: const Text('This posts it to Instagram (when connected) and moves it to History.\n'
            'Until Instagram is connected, it\'s just marked as posted — copy the caption and post it yourself.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Approve & Post')),
        ],
      ),
    );
    if (ok == true) await _run('approve', doneMsg: 'Posting ${p.label}…');
  }

  Future<void> _redo(Item p) async {
    final ctl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Redo ${p.label}'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: ctl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
                hintText: p.isCarousel
                    ? 'What should change? e.g. "topic about flatmates", "funnier"'
                    : 'What should change? e.g. "make Bilal funnier"'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Make new version')),
        ],
      ),
    );
    if (note != null) await _run('redo', feedback: note, doneMsg: 'Making a new version of ${p.label}…');
  }

  Future<void> _skip(Item p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Skip ${p.label}?'),
        content: const Text('It won\'t be posted. You can then make a new carousel or story.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Skip it')),
        ],
      ),
    );
    if (ok == true) await _run('discard', doneMsg: 'Skipped ${p.label}');
  }

  Widget _centerMsg(String title, String body, {List<(String, VoidCallback)> actions = const [], bool spinner = false}) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (spinner) const Padding(padding: EdgeInsets.only(bottom: 20), child: CircularProgressIndicator()),
        Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: cream)),
        const SizedBox(height: 10),
        Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, height: 1.5)),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Wrap(spacing: 12, children: [
            for (final (i, a) in actions.indexed)
              i == 0
                  ? FilledButton(onPressed: busy ? null : a.$2, child: Text(a.$1))
                  : OutlinedButton(onPressed: busy ? null : a.$2, child: Text(a.$1)),
          ]),
        ],
      ]),
    );
  }
}

// ---------------- settings dialog ----------------

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.prefs, required this.firstRun, required this.onSaved});
  final SharedPreferences prefs;
  final bool firstRun;
  final Future<void> Function(GithubApi) onSaved;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final repo = TextEditingController(text: widget.prefs.getString('repo') ?? defaultRepo);
  late final ghToken = TextEditingController(text: widget.prefs.getString('token') ?? '');
  final gemini = TextEditingController();
  final pollinations = TextEditingController();
  final model = TextEditingController(text: 'flux');
  String dailyKind = 'carousel';
  Set<String> saved = {};
  String? status;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _loadRemote();
  }

  GithubApi get _api => GithubApi(repo: repo.text.trim(), token: ghToken.text.trim());

  Future<void> _loadRemote() async {
    if (ghToken.text.trim().isEmpty) return;
    try {
      final names = await _api.secretNames();
      final vars = await _api.variables();
      if (!mounted) return;
      setState(() {
        saved = names;
        model.text = vars['POLLINATIONS_MODEL'] ?? 'flux';
        dailyKind = vars['DAILY_KIND'] ?? 'carousel';
        status = null;
      });
    } catch (e) {
      if (mounted) setState(() => status = 'Couldn\'t read keys from GitHub — check the token permissions.\n$e');
    }
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      status = 'Saving…';
    });
    try {
      await widget.prefs.setString('repo', repo.text.trim());
      await widget.prefs.setString('token', ghToken.text.trim());
      final api = _api;
      if (gemini.text.trim().isNotEmpty) await api.setSecret('GEMINI_API_KEY', gemini.text.trim());
      if (pollinations.text.trim().isNotEmpty) await api.setSecret('POLLINATIONS_TOKEN', pollinations.text.trim());
      await api.setVariable('POLLINATIONS_MODEL', model.text.trim().isEmpty ? 'flux' : model.text.trim());
      await api.setVariable('DAILY_KIND', dailyKind);
      await widget.onSaved(api);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          status = 'Save failed: $e';
        });
      }
    }
  }

  Widget _secretField(TextEditingController c, String name, String label, String help) {
    final has = saved.contains(name);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: c,
        obscureText: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          hintText: has ? '•••••••• saved — leave empty to keep' : 'paste key',
          suffixIcon: has ? const Icon(Icons.check_circle, color: Colors.greenAccent) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings & keys'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GITHUB', style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: Colors.white54)),
            TextField(controller: repo, decoration: const InputDecoration(labelText: 'Repo (owner/name)')),
            const SizedBox(height: 8),
            TextField(
              controller: ghToken,
              obscureText: true,
              onSubmitted: (_) => _loadRemote(),
              decoration: const InputDecoration(
                labelText: 'GitHub token (fine-grained)',
                helperText: 'github.com/settings/personal-access-tokens → only this repo →\n'
                    'Actions, Secrets, Variables: Read and write · Contents: Read-only',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 22),
            const Text('AI KEYS (saved encrypted in GitHub)',
                style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: Colors.white54)),
            _secretField(gemini, 'GEMINI_API_KEY', 'Gemini API key', 'aistudio.google.com → Get API key (free). Writes the posts.'),
            _secretField(pollinations, 'POLLINATIONS_TOKEN', 'Pollinations key',
                'enter.pollinations.ai → API key. Draws the pictures.'),
            const SizedBox(height: 12),
            TextField(
              controller: model,
              decoration: const InputDecoration(
                labelText: 'Image model',
                helperText: 'flux, or one listed at gen.pollinations.ai/image/models (e.g. gptimage, seedream)',
              ),
            ),
            const SizedBox(height: 18),
            const Text('DAILY POST', style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: Colors.white54)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'carousel', label: Text('Carousel'), icon: Icon(Icons.view_carousel_outlined)),
                ButtonSegment(value: 'story', label: Text('Story reel'), icon: Icon(Icons.movie_outlined)),
              ],
              selected: {dailyKind},
              onSelectionChanged: (v) => setState(() => dailyKind = v.first),
            ),
            if (status != null) ...[
              const SizedBox(height: 14),
              Text(status!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ]),
        ),
      ),
      actions: [
        if (!widget.firstRun) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

// ---------------- shared bits ----------------

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 26, this.suffix});
  final double size;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text('split', style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: cream)),
      Container(
        margin: const EdgeInsets.only(left: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: cream, borderRadius: BorderRadius.circular(6)),
        child: Text('sol', style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: terracotta)),
      ),
      if (suffix != null) ...[
        const SizedBox(width: 8),
        Text(suffix!, style: const TextStyle(fontSize: 14, color: Colors.white54)),
      ],
    ]);
  }
}

String _shortDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}';
}

String _rs(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return 'Rs $b';
}

String _releasePage(String assetUrl) {
  // .../releases/download/<tag>/<file>  →  .../releases/tag/<tag>
  final m = RegExp(r'^(.*)/releases/download/([^/]+)/').firstMatch(assetUrl);
  return m == null ? assetUrl : '${m.group(1)}/releases/tag/${m.group(2)}';
}

// ---------------- item view (reel or carousel) ----------------

class ItemView extends StatelessWidget {
  const ItemView({super.key, required this.item, this.onApprove, this.onRedo, this.onSkip, this.busy = false});
  final Item item;
  final VoidCallback? onApprove, onRedo, onSkip;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final e = item;
    final btnPad = const EdgeInsets.symmetric(horizontal: 22, vertical: 18);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        e.isCarousel ? CarouselPane(slides: e.slides) : VideoPane(item: e),
        const SizedBox(width: 32),
        Expanded(
          child: ListView(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: terracotta, borderRadius: BorderRadius.circular(8)),
                child: Text(e.label.toUpperCase(),
                    style: const TextStyle(color: cream, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
              const SizedBox(width: 12),
              Text(e.isPosted ? 'Posted ${_shortDate(e.postedAt)}' : 'Waiting for review${e.attempt > 1 ? ' · version ${e.attempt}' : ''}',
                  style: const TextStyle(color: Colors.white60)),
            ]),
            const SizedBox(height: 14),
            Text(e.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cream)),
            if (e.hud != null) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _stat('PAID', _rs(e.hud!.paid)),
                _stat('YOUR SHARE', _rs(e.hud!.share)),
                _stat('FRIENDSHIP', '${e.hud!.friendship}%'),
                if (e.options.isNotEmpty) _stat('VOTE', e.options.join(' / ')),
              ]),
            ],
            if (e.voteResult != null) ...[
              const SizedBox(height: 14),
              Text('🗳  ${e.voteResult}', style: const TextStyle(color: Colors.white70)),
            ],
            for (final q in e.qa) Padding(padding: const EdgeInsets.only(top: 8), child: Text(q)),
            const SizedBox(height: 20),
            Row(children: [
              const Text('Caption', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: e.caption));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caption copied')));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ]),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(e.caption, style: const TextStyle(height: 1.45)),
            ),
            if (e.script.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(e.isCarousel ? 'Slides' : 'Script', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              for (final (i, line) in e.script.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${i + 1}. $line', style: const TextStyle(color: Colors.white70)),
                ),
            ],
            if (e.results.isNotEmpty) ...[const SizedBox(height: 18), for (final r in e.results) Text(r)],
            const SizedBox(height: 26),
            Wrap(spacing: 12, runSpacing: 12, children: [
              if (onApprove != null)
                FilledButton.icon(
                  onPressed: busy ? null : onApprove,
                  icon: const Icon(Icons.check),
                  label: const Text('Approve & Post'),
                  style: FilledButton.styleFrom(padding: btnPad),
                ),
              if (onRedo != null)
                OutlinedButton.icon(
                  onPressed: busy ? null : onRedo,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Redo'),
                  style: OutlinedButton.styleFrom(padding: btnPad),
                ),
              if (e.isCarousel && e.slides.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(_releasePage(e.slides.first))),
                  icon: const Icon(Icons.download),
                  label: const Text('Download slides'),
                  style: OutlinedButton.styleFrom(padding: btnPad),
                ),
              if (!e.isCarousel && e.videoUrl.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(e.videoUrl)),
                  icon: const Icon(Icons.download),
                  label: const Text('Download video'),
                  style: OutlinedButton.styleFrom(padding: btnPad),
                ),
              if (onSkip != null)
                TextButton.icon(
                  onPressed: busy ? null : onSkip,
                  icon: const Icon(Icons.close),
                  label: const Text('Skip'),
                ),
            ]),
            if (busy && onApprove != null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('A run is in progress…', style: TextStyle(color: Colors.white54)),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: Colors.white54)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Swipeable 4:5 slides with arrows and a counter.
class CarouselPane extends StatefulWidget {
  const CarouselPane({super.key, required this.slides});
  final List<String> slides;
  @override
  State<CarouselPane> createState() => _CarouselPaneState();
}

class _CarouselPaneState extends State<CarouselPane> {
  final page = PageController();
  int index = 0;

  void _go(int i) {
    if (i < 0 || i >= widget.slides.length) return;
    page.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = (box.maxHeight.isFinite ? box.maxHeight : 760.0) - 40;
      final w = h * 4 / 5;
      return SizedBox(
        width: w,
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(children: [
                PageView.builder(
                  controller: page,
                  itemCount: widget.slides.length,
                  onPageChanged: (i) => setState(() => index = i),
                  itemBuilder: (_, i) => Image.network(
                    widget.slides[i],
                    fit: BoxFit.cover,
                    loadingBuilder: (c, child, p) => p == null ? child : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (c, e, s) => Center(child: Text('Can\'t load slide\n$e', textAlign: TextAlign.center)),
                  ),
                ),
                if (index > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton.filledTonal(onPressed: () => _go(index - 1), icon: const Icon(Icons.chevron_left)),
                  ),
                if (index < widget.slides.length - 1)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton.filledTonal(onPressed: () => _go(index + 1), icon: const Icon(Icons.chevron_right)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text('${index + 1} / ${widget.slides.length}', style: const TextStyle(color: Colors.white60)),
        ]),
      );
    });
  }
}

/// Plays a reel. macOS's player can't open GitHub release links directly, so it downloads first.
class VideoPane extends StatefulWidget {
  const VideoPane({super.key, required this.item});
  final Item item;
  @override
  State<VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends State<VideoPane> {
  VideoPlayerController? ctl;
  String? videoError;

  @override
  void initState() {
    super.initState();
    if (widget.item.videoUrl.isNotEmpty) _load();
  }

  Future<void> _load() async {
    try {
      final e = widget.item;
      final file = File('${Directory.systemTemp.path}/splitsol_${e.id}_v${e.attempt}_${e.videoUrl.hashCode}.mp4');
      if (!await file.exists() || await file.length() == 0) {
        final r = await http.get(Uri.parse(e.videoUrl));
        if (r.statusCode != 200) throw Exception('download failed (${r.statusCode})');
        await file.writeAsBytes(r.bodyBytes);
      }
      final c = VideoPlayerController.file(file);
      await c.initialize();
      c.addListener(() {
        if (mounted) setState(() {});
      });
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => ctl = c);
    } catch (err) {
      if (mounted) setState(() => videoError = '$err');
    }
  }

  @override
  void dispose() {
    ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ctl;
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight.isFinite ? box.maxHeight : 720.0;
      final w = h * 9 / 16;
      Widget inner;
      if (videoError != null) {
        inner = Center(child: Text('Can\'t play video\n$videoError', textAlign: TextAlign.center));
      } else if (c == null || !c.value.isInitialized) {
        inner = const Center(child: CircularProgressIndicator());
      } else {
        inner = GestureDetector(
          onTap: () => c.value.isPlaying ? c.pause() : c.play(),
          child: Stack(fit: StackFit.expand, children: [
            VideoPlayer(c),
            if (!c.value.isPlaying) const Center(child: Icon(Icons.play_circle_fill, size: 84, color: Colors.white70)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: terracotta)),
            ),
          ]),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(width: w, height: h, color: Colors.black, child: inner),
      );
    });
  }
}
