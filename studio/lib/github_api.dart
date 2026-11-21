import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pinenacl/x25519.dart' show PublicKey;
import 'package:pinenacl/public.dart' show SealedBox;

/// Talks to the splitsol_autopilot repo: reads story/state.json, lists workflow runs,
/// triggers the workflow, and saves your API keys as encrypted GitHub secrets.
class GithubApi {
  GithubApi({required this.repo, required this.token});

  final String repo; // e.g. Ahmad-AppDev/splitsol_autopilot
  final String token; // fine-grained PAT (see README for permissions)
  static const workflow = 'autopilot.yml';

  String get _base => 'https://api.github.com/repos/$repo';

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<AutopilotState> fetchState() async {
    final r = await http.get(Uri.parse('$_base/contents/story/state.json?ref=main'),
        headers: {..._headers, 'Accept': 'application/vnd.github.raw+json'});
    _check(r);
    return AutopilotState.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<WorkflowRun>> fetchRuns() async {
    final r = await http.get(Uri.parse('$_base/actions/workflows/$workflow/runs?per_page=6'), headers: _headers);
    _check(r);
    final runs = (jsonDecode(r.body)['workflow_runs'] as List).cast<Map<String, dynamic>>();
    return runs.map(WorkflowRun.fromJson).toList();
  }

  Future<void> dispatch(String command, {String feedback = '', String kind = 'carousel'}) async {
    final r = await http.post(
      Uri.parse('$_base/actions/workflows/$workflow/dispatches'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'ref': 'main',
        'inputs': {'command': command, 'feedback': feedback, 'kind': kind},
      }),
    );
    _check(r);
  }

  /// Names of the secrets already saved in the repo (values are never readable).
  Future<Set<String>> secretNames() async {
    final r = await http.get(Uri.parse('$_base/actions/secrets?per_page=100'), headers: _headers);
    _check(r);
    return ((jsonDecode(r.body)['secrets'] as List).map((s) => s['name'] as String)).toSet();
  }

  /// Encrypts [value] with the repo's public key (libsodium sealed box) and saves it as a secret.
  Future<void> setSecret(String name, String value) async {
    final k = await http.get(Uri.parse('$_base/actions/secrets/public-key'), headers: _headers);
    _check(k);
    final j = jsonDecode(k.body) as Map<String, dynamic>;
    final box = SealedBox(PublicKey(Uint8List.fromList(base64Decode(j['key'] as String))));
    final encrypted = box.encrypt(Uint8List.fromList(utf8.encode(value)));
    final r = await http.put(
      Uri.parse('$_base/actions/secrets/$name'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'encrypted_value': base64Encode(List<int>.from(encrypted)), 'key_id': j['key_id']}),
    );
    _check(r);
  }

  Future<Map<String, String>> variables() async {
    final r = await http.get(Uri.parse('$_base/actions/variables?per_page=30'), headers: _headers);
    _check(r);
    return {
      for (final v in (jsonDecode(r.body)['variables'] as List)) v['name'] as String: v['value'] as String,
    };
  }

  Future<void> setVariable(String name, String value) async {
    final body = jsonEncode({'name': name, 'value': value});
    final h = {..._headers, 'Content-Type': 'application/json'};
    final p = await http.patch(Uri.parse('$_base/actions/variables/$name'), headers: h, body: body);
    if (p.statusCode == 404) {
      _check(await http.post(Uri.parse('$_base/actions/variables'), headers: h, body: body));
    } else {
      _check(p);
    }
  }

  void _check(http.Response r) {
    if (r.statusCode >= 300) {
      throw Exception('GitHub ${r.statusCode}: ${r.body.length > 300 ? r.body.substring(0, 300) : r.body}');
    }
  }
}

class Hud {
  Hud(this.paid, this.share, this.friendship);
  final int paid, share, friendship;
  factory Hud.fromJson(Map<String, dynamic>? j) =>
      Hud((j?['paid'] ?? 0) as int, (j?['share'] ?? 0) as int, (j?['friendship'] ?? 100) as int);
}

/// One piece of content: a story reel (kind=story) or a carousel (kind=carousel),
/// either waiting for review or already posted.
class Item {
  Item({
    required this.kind,
    required this.number,
    required this.title,
    required this.caption,
    this.videoUrl = '',
    this.slides = const [],
    this.options = const [],
    this.hud,
    this.attempt = 1,
    this.qa = const [],
    this.voteResult,
    this.postedAt,
    this.results = const [],
    this.script = const [],
  });

  final String kind; // story | carousel
  final int number, attempt; // story day / carousel number
  final String title, caption, videoUrl;
  final List<String> slides, options, qa, results, script;
  final Hud? hud;
  final String? voteResult, postedAt;

  bool get isPosted => postedAt != null;
  bool get isCarousel => kind == 'carousel';
  String get label => isCarousel ? 'Carousel $number' : 'Day $number';
  String get id => '$kind$number';

  factory Item.fromPending(Map<String, dynamic> p) {
    if (p['kind'] == 'carousel') {
      final c = p['carousel'] as Map<String, dynamic>;
      return Item(
        kind: 'carousel',
        number: (p['number'] ?? 1) as int,
        attempt: (p['attempt'] ?? 1) as int,
        title: (c['title'] ?? '') as String,
        caption: (c['caption'] ?? '') as String,
        slides: ((p['slides'] ?? []) as List).cast<String>(),
        qa: ((p['qa'] ?? []) as List).cast<String>(),
        script: ((c['points'] ?? []) as List).map((x) => '${(x as Map)['headline']} — ${x['body']}').toList(),
      );
    }
    final ep = p['episode'] as Map<String, dynamic>;
    return Item(
      kind: 'story',
      number: (p['day'] ?? 1) as int,
      attempt: (p['attempt'] ?? 1) as int,
      title: 'THE TRIP · Day ${p['day']}',
      videoUrl: (p['video_url'] ?? '') as String,
      caption: (ep['caption'] ?? '') as String,
      options: ((ep['vote']?['options'] ?? []) as List).cast<String>(),
      hud: Hud.fromJson(ep['hud_after'] as Map<String, dynamic>?),
      qa: ((p['qa'] ?? []) as List).cast<String>(),
      voteResult: p['vote_result'] as String?,
      script: ((ep['scenes'] ?? []) as List).map((s) => (s as Map)['narration'].toString()).toList(),
    );
  }

  factory Item.fromStoryHistory(Map<String, dynamic> h) => Item(
        kind: 'story',
        number: h['day'] as int,
        title: 'THE TRIP · Day ${h['day']}',
        videoUrl: (h['video_url'] ?? '') as String,
        caption: (h['caption'] ?? h['summary'] ?? '') as String,
        options: ((h['options'] ?? []) as List).cast<String>(),
        hud: Hud.fromJson(h['hud_after'] as Map<String, dynamic>?),
        postedAt: (h['posted_at'] ?? '') as String,
        results: ((h['results'] ?? []) as List).cast<String>(),
        voteResult: h['chosen'] != null ? '${h['chosen']} won ${h['votes'] ?? ''}' : null,
      );

  factory Item.fromCarouselHistory(Map<String, dynamic> h) => Item(
        kind: 'carousel',
        number: (h['number'] ?? 0) as int,
        title: (h['title'] ?? '') as String,
        caption: (h['caption'] ?? '') as String,
        slides: ((h['slides'] ?? []) as List).cast<String>(),
        postedAt: (h['posted_at'] ?? '') as String,
        results: ((h['results'] ?? []) as List).cast<String>(),
      );
}

class AutopilotState {
  AutopilotState({required this.day, required this.pending, required this.history, this.lastError});
  final int day;
  final Item? pending;
  final List<Item> history; // stories + carousels, newest first
  final Map<String, dynamic>? lastError;

  factory AutopilotState.fromJson(Map<String, dynamic> j) {
    final items = <Item>[
      ...((j['history'] ?? []) as List).cast<Map<String, dynamic>>().map(Item.fromStoryHistory),
      ...((j['carousels'] ?? []) as List).cast<Map<String, dynamic>>().map(Item.fromCarouselHistory),
    ]..sort((a, b) => (b.postedAt ?? '').compareTo(a.postedAt ?? ''));
    return AutopilotState(
      day: (j['day'] ?? 1) as int,
      pending: j['pending'] == null ? null : Item.fromPending(j['pending'] as Map<String, dynamic>),
      history: items,
      lastError: j['last_error'] as Map<String, dynamic>?,
    );
  }
}

class WorkflowRun {
  WorkflowRun({required this.title, required this.status, required this.conclusion, required this.url, required this.createdAt});
  final String title, status, url, createdAt;
  final String? conclusion;

  bool get running => status != 'completed';
  bool get failed => conclusion == 'failure';

  factory WorkflowRun.fromJson(Map<String, dynamic> j) => WorkflowRun(
        title: (j['display_title'] ?? j['name'] ?? '') as String,
        status: j['status'] as String,
        conclusion: j['conclusion'] as String?,
        url: j['html_url'] as String,
        createdAt: j['created_at'] as String,
      );
}
