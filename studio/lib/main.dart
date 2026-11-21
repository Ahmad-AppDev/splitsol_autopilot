import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'github_api.dart';

const terracotta = Color(0xFFC8553D);
const cream = Color(0xFFF6EEE0);
const ink = Color(0xFF16130F);
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
  Episode? selected; // null = Today
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
    final repo = prefs!.getString('repo') ?? defaultRepo;
    if (token.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSettings(firstRun: true));
    }
    api = GithubApi(repo: repo, token: token);
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
      List<WorkflowRun> r = runs;
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
    if (s.pending != null) {
      final key = 'd${s.pending!.day}v${s.pending!.attempt}';
      if (p.getString('notified_pending') != key) {
        await p.setString('notified_pending', key);
        await _notify('Day ${s.pending!.day} is ready 🎬', 'Your SplitSol reel is waiting for review.');
      }
    }
    if (s.history.isNotEmpty) {
      final key = 'posted${s.history.first.day}';
      if (p.getString('notified_posted') != key) {
        final first = p.getString('notified_posted') == null;
        await p.setString('notified_posted', key);
        if (!first) await _notify('Day ${s.history.first.day} done ✅', s.history.first.results.join(' · '));
      }
    }
    final err = s.lastError;
    if (err != null) {
      final key = '${err['at']}';
      if (p.getString('notified_error') != key) {
        await p.setString('notified_error', key);
        await _notify('Autopilot ${err['command']} failed ❌', '${err['message']}');
      }
    }
  }

  Future<void> _notify(String title, String body) => notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
        title,
        body,
        const NotificationDetails(macOS: DarwinNotificationDetails(presentSound: true)),
      );

  Future<void> _run(String command, {String feedback = '', required String doneMsg}) async {
    setState(() => busy = true);
    try {
      await api!.dispatch(command, feedback: feedback);
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

  Future<void> _openSettings({bool firstRun = false}) async {
    final repoCtl = TextEditingController(text: prefs?.getString('repo') ?? defaultRepo);
    final tokenCtl = TextEditingController(text: prefs?.getString('token') ?? '');
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !firstRun,
      builder: (c) => AlertDialog(
        title: const Text('Connect to GitHub'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: repoCtl, decoration: const InputDecoration(labelText: 'Repo (owner/name)')),
            const SizedBox(height: 12),
            TextField(
              controller: tokenCtl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'GitHub token (fine-grained)'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Create at github.com/settings/personal-access-tokens → only this repo → '
              'permissions: Actions = Read and write, Contents = Read-only.',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ]),
        ),
        actions: [
          if (!firstRun) TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      await prefs!.setString('repo', repoCtl.text.trim());
      await prefs!.setString('token', tokenCtl.text.trim());
      api = GithubApi(repo: repoCtl.text.trim(), token: tokenCtl.text.trim());
      await refresh();
    }
  }

  WorkflowRun? get activeRun => runs.where((r) => r.running).firstOrNull;

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
      color: const Color(0xFF1E1A16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 36),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Text('split', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cream)),
            Container(
              margin: const EdgeInsets.only(left: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(color: cream, borderRadius: BorderRadius.circular(6)),
              child: const Text('sol', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: terracotta)),
            ),
            const SizedBox(width: 8),
            const Text('Studio', style: TextStyle(fontSize: 14, color: Colors.white54)),
          ]),
        ),
        const SizedBox(height: 22),
        _navTile(
          title: 'Today',
          subtitle: pending != null
              ? 'Day ${pending.day} · waiting for you'
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
            for (final e in s?.history ?? <Episode>[])
              _navTile(
                title: 'Day ${e.day}',
                subtitle: _shortDate(e.postedAt),
                selected: selected?.day == e.day && selected?.isPosted == true,
                onTap: () => setState(() => selected = e),
              ),
            if ((s?.history ?? []).isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Posted days show up here.', style: TextStyle(color: Colors.white38)),
              ),
          ]),
        ),
        _runStatus(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Row(children: [
            IconButton(tooltip: 'Refresh', onPressed: refresh, icon: const Icon(Icons.refresh)),
            IconButton(tooltip: 'Settings', onPressed: () => _openSettings(), icon: const Icon(Icons.settings)),
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
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: badge ? const Icon(Icons.circle, size: 10, color: terracotta) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _main() {
    if (loadError != null && state == null) {
      return _centerMsg('Can\'t reach GitHub', loadError!, action: ('Settings', () => _openSettings()));
    }
    final s = state;
    if (s == null) return const Center(child: CircularProgressIndicator());

    if (selected != null) {
      return EpisodeView(key: ValueKey('h${selected!.day}'), episode: selected!);
    }

    final err = s.lastError;
    final banner = err == null
        ? null
        : MaterialBanner(
            backgroundColor: const Color(0xFF4A1D16),
            content: Text('Last ${err['command']} failed: ${err['message']}'),
            actions: [
              TextButton(
                onPressed: busy ? null : () => _run('generate', doneMsg: 'Retrying…'),
                child: const Text('Retry'),
              ),
            ],
          );

    Widget body;
    if (s.pending != null) {
      final p = s.pending!;
      body = EpisodeView(
        key: ValueKey('p${p.day}v${p.attempt}'),
        episode: p,
        busy: busy || activeRun != null,
        onApprove: () => _confirmApprove(p),
        onRedo: () => _redo(p),
      );
    } else if (activeRun != null) {
      body = _centerMsg('Making Day ${s.day}…', 'Writing, drawing, voicing and checking. Usually 5–10 minutes.',
          spinner: true);
    } else {
      body = _centerMsg(
        'Nothing waiting',
        'Day ${s.day} is made automatically every day at about 4:47 PM.\nYou\'ll get a notification when it\'s ready.',
        action: ('Make Day ${s.day} now', () => _run('generate', doneMsg: 'Started making Day ${s.day}')),
      );
    }
    return Column(children: [if (banner != null) banner, Expanded(child: body)]);
  }

  Future<void> _confirmApprove(Episode p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Post Day ${p.day}?'),
        content: const Text(
            'This posts the reel to Instagram + TikTok (where connected) and moves the story to the next day.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Approve & Post')),
        ],
      ),
    );
    if (ok == true) await _run('approve', doneMsg: 'Posting Day ${p.day}…');
  }

  Future<void> _redo(Episode p) async {
    final ctl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Redo Day ${p.day}'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: ctl,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'What should change? (optional) e.g. make Bilal funnier'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Make new version')),
        ],
      ),
    );
    if (note != null) await _run('redo', feedback: note, doneMsg: 'Making a new version of Day ${p.day}…');
  }

  Widget _centerMsg(String title, String body, {(String, VoidCallback)? action, bool spinner = false}) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (spinner) const Padding(padding: EdgeInsets.only(bottom: 20), child: CircularProgressIndicator()),
        Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: cream)),
        const SizedBox(height: 10),
        Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, height: 1.5)),
        if (action != null) ...[
          const SizedBox(height: 22),
          FilledButton(onPressed: busy ? null : action.$2, child: Text(action.$1)),
        ],
      ]),
    );
  }
}

String _shortDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'Posted ${d.day} ${m[d.month - 1]}';
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

/// Video + details for one day.
class EpisodeView extends StatefulWidget {
  const EpisodeView({super.key, required this.episode, this.onApprove, this.onRedo, this.busy = false});
  final Episode episode;
  final VoidCallback? onApprove, onRedo;
  final bool busy;

  @override
  State<EpisodeView> createState() => _EpisodeViewState();
}

class _EpisodeViewState extends State<EpisodeView> {
  VideoPlayerController? ctl;
  String? videoError;

  @override
  void initState() {
    super.initState();
    if (widget.episode.videoUrl.isNotEmpty) {
      ctl = VideoPlayerController.networkUrl(Uri.parse(widget.episode.videoUrl))
        ..initialize().then((_) {
          if (mounted) setState(() {});
        }).catchError((e) {
          if (mounted) setState(() => videoError = '$e');
        })
        ..addListener(() {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.episode;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _video(),
        const SizedBox(width: 32),
        Expanded(
          child: ListView(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: terracotta, borderRadius: BorderRadius.circular(8)),
                child: Text('DAY ${e.day}',
                    style: const TextStyle(color: cream, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
              const SizedBox(width: 12),
              Text(e.isPosted ? 'Posted' : 'Waiting for review${e.attempt > 1 ? ' · version ${e.attempt}' : ''}',
                  style: const TextStyle(color: Colors.white60)),
            ]),
            const SizedBox(height: 18),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _stat('PAID', _rs(e.hud.paid)),
              _stat('YOUR SHARE', _rs(e.hud.share)),
              _stat('FRIENDSHIP', '${e.hud.friendship}%'),
              if (e.options.isNotEmpty) _stat('VOTE', e.options.join(' / ')),
            ]),
            if (e.voteResult != null) ...[
              const SizedBox(height: 14),
              Text('🗳  ${e.voteResult}', style: const TextStyle(color: Colors.white70)),
            ],
            for (final q in e.qa) Padding(padding: const EdgeInsets.only(top: 8), child: Text(q)),
            const SizedBox(height: 22),
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
            if (e.narration.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('Script', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              for (final (i, line) in e.narration.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${i + 1}. $line', style: const TextStyle(color: Colors.white70)),
                ),
            ],
            if (e.results.isNotEmpty) ...[
              const SizedBox(height: 18),
              for (final r in e.results) Text(r),
            ],
            const SizedBox(height: 26),
            Wrap(spacing: 12, runSpacing: 12, children: [
              if (widget.onApprove != null)
                FilledButton.icon(
                  onPressed: widget.busy ? null : widget.onApprove,
                  icon: const Icon(Icons.check),
                  label: const Text('Approve & Post'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
                ),
              if (widget.onRedo != null)
                OutlinedButton.icon(
                  onPressed: widget.busy ? null : widget.onRedo,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Redo'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
                ),
              if (e.videoUrl.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(e.videoUrl)),
                  icon: const Icon(Icons.download),
                  label: const Text('Download video'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
                ),
            ]),
            if (widget.busy && widget.onApprove != null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('A run is in progress…', style: TextStyle(color: Colors.white54)),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _video() {
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
            if (!c.value.isPlaying)
              const Center(child: Icon(Icons.play_circle_fill, size: 84, color: Colors.white70)),
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
