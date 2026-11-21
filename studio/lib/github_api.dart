import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the splitsol_autopilot repo: reads story/state.json, lists workflow
/// runs, and triggers the workflow (generate / approve / redo).
class GithubApi {
  GithubApi({required this.repo, required this.token});

  final String repo; // e.g. Ahmad-AppDev/splitsol_autopilot
  final String token; // fine-grained PAT: Actions read/write + Contents read
  static const workflow = 'autopilot.yml';

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<AutopilotState> fetchState() async {
    final r = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/contents/story/state.json?ref=main'),
      headers: {..._headers, 'Accept': 'application/vnd.github.raw+json'},
    );
    _check(r);
    return AutopilotState.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<WorkflowRun>> fetchRuns() async {
    final r = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/actions/workflows/$workflow/runs?per_page=6'),
      headers: _headers,
    );
    _check(r);
    final runs = (jsonDecode(r.body)['workflow_runs'] as List).cast<Map<String, dynamic>>();
    return runs.map(WorkflowRun.fromJson).toList();
  }

  Future<void> dispatch(String command, {String feedback = ''}) async {
    final r = await http.post(
      Uri.parse('https://api.github.com/repos/$repo/actions/workflows/$workflow/dispatches'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'ref': 'main',
        'inputs': {'command': command, 'feedback': feedback},
      }),
    );
    _check(r);
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

/// One reel: either today's pending one or a posted day from history.
class Episode {
  Episode({
    required this.day,
    required this.videoUrl,
    required this.caption,
    required this.options,
    required this.hud,
    this.attempt = 1,
    this.qa = const [],
    this.voteResult,
    this.createdAt,
    this.postedAt,
    this.results = const [],
    this.narration = const [],
  });

  final int day, attempt;
  final String videoUrl, caption;
  final List<String> options, qa, results, narration;
  final Hud hud;
  final String? voteResult, createdAt, postedAt;

  bool get isPosted => postedAt != null;

  factory Episode.fromPending(Map<String, dynamic> p) {
    final ep = p['episode'] as Map<String, dynamic>;
    return Episode(
      day: p['day'] as int,
      attempt: (p['attempt'] ?? 1) as int,
      videoUrl: p['video_url'] as String,
      caption: ep['caption'] as String? ?? '',
      options: ((ep['vote']?['options'] ?? []) as List).cast<String>(),
      hud: Hud.fromJson(ep['hud_after'] as Map<String, dynamic>?),
      qa: ((p['qa'] ?? []) as List).cast<String>(),
      voteResult: p['vote_result'] as String?,
      createdAt: p['created_at'] as String?,
      narration: ((ep['scenes'] ?? []) as List).map((s) => (s as Map)['narration'].toString()).toList(),
    );
  }

  factory Episode.fromHistory(Map<String, dynamic> h) => Episode(
        day: h['day'] as int,
        videoUrl: (h['video_url'] ?? '') as String,
        caption: (h['caption'] ?? h['summary'] ?? '') as String,
        options: ((h['options'] ?? []) as List).cast<String>(),
        hud: Hud.fromJson(h['hud_after'] as Map<String, dynamic>?),
        postedAt: (h['posted_at'] ?? '') as String,
        results: ((h['results'] ?? []) as List).cast<String>(),
        voteResult: h['chosen'] != null ? '${h['chosen']} won ${h['votes'] ?? ''}' : null,
      );
}

class AutopilotState {
  AutopilotState({required this.day, required this.pending, required this.history, this.lastError});
  final int day;
  final Episode? pending;
  final List<Episode> history; // newest first
  final Map<String, dynamic>? lastError;

  factory AutopilotState.fromJson(Map<String, dynamic> j) => AutopilotState(
        day: (j['day'] ?? 1) as int,
        pending: j['pending'] == null ? null : Episode.fromPending(j['pending'] as Map<String, dynamic>),
        history: ((j['history'] ?? []) as List)
            .cast<Map<String, dynamic>>()
            .map(Episode.fromHistory)
            .toList()
            .reversed
            .toList(),
        lastError: j['last_error'] as Map<String, dynamic>?,
      );
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
