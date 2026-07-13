import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int kSessionThreshold = 5; // matches "sessionCount >= 5" in the doc

void main() => runApp(const ReviewFlowTesterApp());

class ReviewFlowTesterApp extends StatelessWidget {
  const ReviewFlowTesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rating Prompt Flow Tester',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const FlowTesterPage(),
    );
  }
}

/// Mirrors the functions named in the reference document:
/// requestiOSRating(), requestAndroidRating(), openAppStorePage(),
/// openPlayStorePage() — plus persisted sessionCount / hasReviewed /
/// hasRated so the "already reviewed" behavior survives app restarts,
/// same as it would in production.
class RatingService {
  static const _keySessionCount = 'sessionCount';
  static const _keyHasReviewed = 'hasReviewed'; // iOS
  static const _keyHasRated = 'hasRated'; // Android

  final InAppReview _inAppReview = InAppReview.instance;

  Future<int> getSessionCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keySessionCount) ?? 0;
  }

  Future<int> incrementSessionCount() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_keySessionCount) ?? 0) + 1;
    await prefs.setInt(_keySessionCount, next);
    return next;
  }

  Future<bool> getHasReviewed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasReviewed) ?? false;
  }

  Future<bool> getHasRated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasRated) ?? false;
  }

  Future<void> _setHasReviewed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasReviewed, value);
  }

  Future<void> _setHasRated(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasRated, value);
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySessionCount, 0);
    await prefs.setBool(_keyHasReviewed, false);
    await prefs.setBool(_keyHasRated, false);
  }

  /// iOS: sessionCount >= 5 && !hasReviewed → requestiOSRating()
  Future<void> requestiOSRating(void Function(String) log) async {
    final available = await _inAppReview.isAvailable();
    log('in_app_review.isAvailable() = $available');
    if (!available) {
      log('Not available on this device → falling back to openAppStorePage()');
      await openAppStorePage(log);
      return;
    }
    await _inAppReview.requestReview();
    await _setHasReviewed(true);
    log('requestiOSRating() called requestReview(). hasReviewed set to true. '
        'Apple decides silently whether the dialog actually appears — no '
        'callback confirms it either way.');
  }

  /// Android: sessionCount >= 5 && !hasRated → requestAndroidRating()
  Future<void> requestAndroidRating(void Function(String) log) async {
    final available = await _inAppReview.isAvailable();
    log('in_app_review.isAvailable() = $available');
    if (!available) {
      log('Not available on this device → falling back to openPlayStorePage()');
      await openPlayStorePage(log);
      return;
    }
    await _inAppReview.requestReview();
    await _setHasRated(true);
    log('requestAndroidRating() called requestReview(). hasRated set to true. '
        'Google decides silently whether the bottom sheet actually appears — '
        'no callback confirms it either way.');
  }

  Future<void> openAppStorePage(void Function(String) log,
      {String appStoreId = '123456789'}) async {
    await _inAppReview.openStoreListing(appStoreId: appStoreId);
    log('openAppStorePage() called with appStoreId=$appStoreId (fallback)');
  }

  Future<void> openPlayStorePage(void Function(String) log) async {
    await _inAppReview.openStoreListing();
    log('openPlayStorePage() called (fallback)');
  }
}

class FlowTesterPage extends StatefulWidget {
  const FlowTesterPage({super.key});

  @override
  State<FlowTesterPage> createState() => _FlowTesterPageState();
}

class _FlowTesterPageState extends State<FlowTesterPage> {
  final RatingService _service = RatingService();
  final List<String> _log = [];

  int _sessionCount = 0;
  bool _hasReviewed = false;
  bool _hasRated = false;
  bool _loading = true;

  bool get _isIOS => Platform.isIOS;
  bool get _isAndroid => Platform.isAndroid;
  bool get _alreadyDone => _isIOS ? _hasReviewed : _hasRated;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final count = await _service.getSessionCount();
    final reviewed = await _service.getHasReviewed();
    final rated = await _service.getHasRated();
    setState(() {
      _sessionCount = count;
      _hasReviewed = reviewed;
      _hasRated = rated;
      _loading = false;
    });
    _addLog('State loaded from disk → sessionCount=$count, '
        'hasReviewed=$reviewed, hasRated=$rated');
  }

  void _addLog(String message) {
    final now = TimeOfDay.now().format(context);
    setState(() => _log.insert(0, '[$now] $message'));
  }



  /// Simulates one "successful session" — matches the app-side condition
  /// described in the doc: sessionCount >= 5 && !hasReviewed/!hasRated.
  Future<void> _simulateSession() async {
    final count = await _service.incrementSessionCount();
    setState(() => _sessionCount = count);
    _addLog('Session simulated → sessionCount = $count');

    if (_alreadyDone) {
      _addLog('Condition skipped: user has already '
          '${_isIOS ? "reviewed" : "rated"} (persisted).');
      return;
    }
    if (count < kSessionThreshold) {
      _addLog('Condition not met yet ($count/$kSessionThreshold)');
      return;
    }

    _addLog('Condition met ($count >= $kSessionThreshold) → '
        'calling ${_isIOS ? "requestiOSRating()" : "requestAndroidRating()"}');
    await _requestNow();
  }

  Future<void> _requestNow() async {
    if (_isIOS) {
      await _service.requestiOSRating(_addLog);
      final reviewed = await _service.getHasReviewed();
      setState(() => _hasReviewed = reviewed);
    } else if (_isAndroid) {
      await _service.requestAndroidRating(_addLog);
      final rated = await _service.getHasRated();
      setState(() => _hasRated = rated);
    } else {
      _addLog('Not iOS or Android — nothing to call.');
    }
  }

  Future<void> _openFallback() async {
    if (_isIOS) {
      await _service.openAppStorePage(_addLog);
    } else {
      await _service.openPlayStorePage(_addLog);
    }
  }

  Future<void> _resetState() async {
    await _service.resetAll();
    setState(() {
      _sessionCount = 0;
      _hasReviewed = false;
      _hasRated = false;
    });
    _addLog('Test state reset (sessionCount=0, hasReviewed=false, '
        'hasRated=false) — persisted to disk.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rating Prompt Flow Tester')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 12),
                  _buildTestingGuidanceCard(),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _simulateSession,
                        icon: const Icon(Icons.touch_app),
                        label: const Text('Simulate session (+1)'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _requestNow,
                        icon: const Icon(Icons.star_rate),
                        label: const Text('Force request now'),
                      ),
                      // if (kDebugMode)
                      //   ElevatedButton.icon(
                      //     onPressed: _testWithFakeReviewManager,
                      //     icon: const Icon(Icons.science),
                      //     label: const Text('Test with FakeReviewManager'),
                      //     style: ElevatedButton.styleFrom(
                      //         backgroundColor: Colors.deepOrange),
                      //   ),
                      OutlinedButton.icon(
                        onPressed: _openFallback,
                        icon: const Icon(Icons.storefront),
                        label: const Text('Open store fallback'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _resetState,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset test state'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Log',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: _log.isEmpty
                          ? const Text('No actions yet.',
                              style: TextStyle(color: Colors.white54))
                          : ListView.builder(
                              itemCount: _log.length,
                              itemBuilder: (context, i) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  _log[i],
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final platformLabel =
        _isIOS ? 'iOS' : (_isAndroid ? 'Android' : Platform.operatingSystem);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Platform: $platformLabel',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('sessionCount: $_sessionCount / $kSessionThreshold'),
            if (_isIOS) Text('hasReviewed: $_hasReviewed'),
            if (_isAndroid) Text('hasRated: $_hasRated'),
            const SizedBox(height: 8),
            Text(
              _alreadyDone
                  ? 'Condition will NOT auto-trigger again — already ${_isIOS ? "reviewed" : "rated"} (persisted across restarts).'
                  : (_sessionCount >= kSessionThreshold
                      ? 'Condition met — next "Simulate session" or "Force request" call will fire the native prompt call.'
                      : 'Condition not met yet — need ${kSessionThreshold - _sessionCount} more session(s).'),
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.indigo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestingGuidanceCard() {
    return Card(
      color: Colors.amber.shade50,
      child: ExpansionTile(
        title: const Text('Testing notes (from the document)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (_isIOS) ...const [
            _Bullet('Debug / Simulator (USB, run from Xcode): the dialog '
                'shows every single time, with no quota — this is expected, '
                'not a bug. Submit is not clickable and it does not count '
                'toward the real 3-per-365-day quota.'),
            _Bullet('TestFlight: the native dialog will NEVER appear at '
                'all — Apple blocks it there on purpose.'),
            _Bullet('App Store (production): this is the only build where '
                'the real 3-per-365-days quota is enforced, silently.'),
          ],
          if (_isAndroid) ...const [
            _Bullet('Internal Testing track: bypasses the time-based '
                'quota, so the dialog can reappear repeatedly for testing.'),
            _Bullet('BUT: the Google account must never have reviewed '
                'this app before. If it already has, delete the existing '
                'review from the Play Store app first (search your app → '
                '⋮ → Delete review), then relaunch to see it again.'),
            _Bullet('Sideloaded debug builds may silently no-op even '
                'when requestReview() returns without error.'),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
