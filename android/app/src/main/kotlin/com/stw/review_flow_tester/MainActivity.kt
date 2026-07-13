package com.stw.review_flow_tester

import androidx.annotation.NonNull
import com.google.android.play.core.review.ReviewManagerFactory
import com.google.android.play.core.review.testing.FakeReviewManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.review_flow_tester/fake_review"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "requestFakeReview") {
                    val manager = FakeReviewManager(this)
                    val request = manager.requestReviewFlow()
                    request.addOnCompleteListener { task ->
                        if (task.isSuccessful) {
                            val reviewInfo = task.result
                            val flow = manager.launchReviewFlow(this, reviewInfo)
                            flow.addOnCompleteListener {
                                result.success("Fake review flow completed")
                            }
                        } else {
                            result.success("Fake review flow failed to start: ${task.exception}")
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}