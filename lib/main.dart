import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_checker/store_checker.dart';

const int kSessionThreshold = 5;

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

class RatingService {
  static const _keySessionCount = 'sessionCount';
  static const _keyHasReviewed = 'hasReviewed';
  static const _keyHasRated = 'hasRated';

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

  Future<Source> getInstallSource() async {
    try {
      return await StoreChecker.getSource;
    } catch (_) {
      return Source.UNKNOWN;
    }
  }

  Future<void> requestiOSRating(void Function(String) log) async {
    final available = await _inAppReview.isAvailable();
    log('in_app_review.isAvailable() = $available');
    if (!available) {
      log('Not available → falling back to openAppStorePage()');
      await openAppStorePage(log);
      return;
    }
    await _inAppReview.requestReview();
    await _setHasReviewed(true);
    log('requestiOSRating() called requestReview(). hasReviewed set to true.');
  }

  Future<void> requestAndroidRating(void Function(String) log) async {
    final available = await _inAppReview.isAvailable();
    log('in_app_review.isAvailable() = $available');
    if (!available) {
      log('Not available → falling back to openPlayStorePage()');
      await openPlayStorePage(log);
      return;
    }
    await _inAppReview.requestReview();
    await _setHasRated(true);
    log('requestAndroidRating() called requestReview() (Play Core). hasRated set to true.');
  }

  Future<void> requestHuaweiRating(void Function(String) log) async {
    log('No native Huawei review popup API exists — opening AppGallery page instead.');
    await openAppGalleryPage(log);
    await _setHasRated(true);
  }

  Future<void> openAppStorePage(void Function(String) log,
      {String appStoreId = '123456789'}) async {
    await _inAppReview.openStoreListing(appStoreId: appStoreId);
    log('openAppStorePage() called (fallback)');
  }

  Future<void> openPlayStorePage(void Function(String) log) async {
    await _inAppReview.openStoreListing();
    log('openPlayStorePage() called (fallback)');
  }

  Future<void> openAppGalleryPage(void Function(String) log) async {
    log('openAppGalleryPage() called (fallback) — package: com.stw.review_flow_tester');
    // Actual URL launching can be wired in later with url_launcher if needed;
    // logged here so the routing decision itself is verifiable first.
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
  Source _installSource = Source.UNKNOWN;
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
    final source = await _service.getInstallSource();
    setState(() {
      _sessionCount = count;
      _hasReviewed = reviewed;
      _hasRated = rated;
      _installSource = source;
      _loading = false;
    });
    _addLog('State loaded → sessionCount=$count, hasReviewed=$reviewed, '
        'hasRated=$rated, installSource=$source');
  }

  void _addLog(String message) {
    final now = TimeOfDay.now().format(context);
    setState(() => _log.insert(0, '[$now] $message'));
  }

  Future<void> _simulateSession() async {
    final count = await _service.incrementSessionCount();
    setState(() => _sessionCount = count);
    _addLog('Session simulated → sessionCount = $count');

    if (_alreadyDone) {
      _addLog('Condition skipped: already ${_isIOS ? "reviewed" : "rated"}.');
      return;
    }
    if (count < kSessionThreshold) {
      _addLog('Condition not met yet ($count/$kSessionThreshold)');
      return;
    }
    _addLog('Condition met ($count >= $kSessionThreshold)');
    await _requestNow();
  }

  Future<void> _requestNow() async {
    if (_isIOS) {
      await _service.requestiOSRating(_addLog);
    } else if (_isAndroid) {
      switch (_installSource) {
        case Source.IS_INSTALLED_FROM_HUAWEI_APP_GALLERY:
          _addLog('Install source: Huawei AppGallery → routing to Huawei path');
          await _service.requestHuaweiRating(_addLog);
          break;
        case Source.IS_INSTALLED_FROM_PLAY_STORE:
          _addLog('Install source: Play Store → routing to Play Core');
          await _service.requestAndroidRating(_addLog);
          break;
        default:
          _addLog('Install source: $_installSource (not Play Store or '
              'AppGallery — likely local/debug build) → attempting Play '
              'Core anyway for local testing');
          await _service.requestAndroidRating(_addLog);
      }
    }
    final reviewed = await _service.getHasReviewed();
    final rated = await _service.getHasRated();
    setState(() {
      _hasReviewed = reviewed;
      _hasRated = rated;
    });
  }

  Future<void> _openFallback() async {
    if (_isIOS) {
      await _service.openAppStorePage(_addLog);
    } else if (_installSource == Source.IS_INSTALLED_FROM_HUAWEI_APP_GALLERY) {
      await _service.openAppGalleryPage(_addLog);
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
    _addLog('Test state reset.');
  }

  Future<void> _recheckInstallSource() async {
    final source = await _service.getInstallSource();
    setState(() => _installSource = source);
    _addLog('Install source re-checked → $source');
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
                      if (_isAndroid)
                        OutlinedButton.icon(
                          onPressed: _recheckInstallSource,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Re-check install source'),
                        ),
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
                  const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                padding: const EdgeInsets.symmetric(vertical: 2),
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
    final platformLabel = _isIOS ? 'iOS' : (_isAndroid ? 'Android' : Platform.operatingSystem);
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
            if (_isAndroid) ...[
              Text('hasRated: $_hasRated'),
              const SizedBox(height: 8),
              Text('Install source: ${_installSource.toString().split('.').last}'),
            ],
          ],
        ),
      ),
    );
  }
}