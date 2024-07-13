package com.example.liveness

import android.graphics.BitmapFactory
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.benamorn.liveness"
    private var job: Job? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkLiveness" -> checkLiveness(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun checkLiveness(data: Any?, result: MethodChannel.Result) {
        if (job?.isActive == true) {
            job?.cancel()
        }

        job = CoroutineScope(Dispatchers.Main).launch {
            try {
                val imageBytes = withContext(Dispatchers.Default) {
                    val key = data as? Map<String, Any> ?: throw IllegalArgumentException("Invalid data format")
                    val bytesList = key["platforms"] as? List<ByteArray> ?: throw IllegalArgumentException("Invalid platforms data")
                    val strides = (key["strides"] as? List<Int>)?.toIntArray() ?: throw IllegalArgumentException("Invalid strides data")
                    val width = key["width"] as? Int ?: throw IllegalArgumentException("Invalid width")
                    val height = key["height"] as? Int ?: throw IllegalArgumentException("Invalid height")

                    Log.i("checkLiveness", "Processing image: ${width}x${height}, strides: ${strides.joinToString()}")
                    Log.i("checkLiveness", "Planes sizes: ${bytesList.map { it.size }.joinToString()}")

                    val nv21 = YuvConverter.YUVtoNV21(bytesList, strides, width, height)
                    Log.i("checkLiveness", "NV21 conversion complete, size: ${nv21.size}")

                    YuvConverter.NV21toJPEG(nv21, width, height, 80)
                }

                Log.i("checkLiveness", "Image processed, size: ${imageBytes.size}")

                // Return the processed image bytes
                result.success(imageBytes)

            } catch (e: Exception) {
                Log.e("checkLiveness", "Error processing image", e)
                result.error("ERROR", "Failed to process image: ${e.message}", e.stackTraceToString())
            }
        }
    }
}