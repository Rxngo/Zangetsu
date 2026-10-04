package com.spyou.watch_app

import java.util.concurrent.CancellationException
import com.google.android.gms.tasks.TaskCompletionSource
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertSame
import org.junit.Assert.assertNull
import org.junit.Test

class MangaTranslationBridgeTest {
    @Test
    fun `maps Japanese to Japanese recognizer`() {
        assertEquals(MangaOcrScript.JAPANESE, MangaOcrScriptMapping.forLanguage("ja"))
    }

    @Test
    fun `maps Chinese to Chinese recognizer`() {
        assertEquals(MangaOcrScript.CHINESE, MangaOcrScriptMapping.forLanguage("zh"))
    }

    @Test
    fun `maps Korean to Korean recognizer`() {
        assertEquals(MangaOcrScript.KOREAN, MangaOcrScriptMapping.forLanguage("ko"))
    }

    @Test
    fun `maps Hindi to Devanagari recognizer`() {
        assertEquals(MangaOcrScript.DEVANAGARI, MangaOcrScriptMapping.forLanguage("hi"))
    }

    @Test
    fun `maps Latin source languages to Latin recognizer`() {
        assertEquals(MangaOcrScript.LATIN, MangaOcrScriptMapping.forLanguage("en"))
        assertEquals(MangaOcrScript.LATIN, MangaOcrScriptMapping.forLanguage("es"))
    }

    @Test
    fun `rejects unsupported scripts with stable error code`() {
        val error = assertThrows(MangaTranslationBridgeException::class.java) {
            MangaOcrScriptMapping.forLanguage("ar")
        }

        assertEquals("unsupported_source_language", error.code)
    }

    @Test
    fun `maps only the OCR module polling deadline to a stable download error`() {
        val error = assertThrows(MangaTranslationBridgeException::class.java) {
            runBlocking {
                awaitOcrModuleReady(timeoutMillis = 5, pollIntervalMillis = 1) { false }
            }
        }

        assertEquals("model_download_failed", error.code)
    }

    @Test
    fun `nested timeout remains the same cancellation instead of becoming a model error`() {
        var nestedTimeout: TimeoutCancellationException? = null
        val thrown = assertThrows(TimeoutCancellationException::class.java) {
            runBlocking {
                awaitOcrModuleReady(timeoutMillis = 500, pollIntervalMillis = 1) {
                    try {
                        withTimeout(1) {
                            delay(1_000)
                            true
                        }
                    } catch (error: TimeoutCancellationException) {
                        nestedTimeout = error
                        throw error
                    }
                }
            }
        }

        // Coroutines may copy TimeoutCancellationException while recovering
        // its stack trace; the cancellation type and diagnostic stay intact.
        assertEquals(nestedTimeout?.message, thrown.message)
    }

    @Test
    fun `generic failure mapping rethrows the original coroutine cancellation`() {
        val cancellation = CancellationException("cancelled by caller")
        val thrown = assertThrows(CancellationException::class.java) {
            rethrowIfCancellation(cancellation)
        }

        assertSame(cancellation, thrown)
    }

    @Test
    fun `preserves a bridge error found in a wrapped cause chain`() {
        val expected = MangaTranslationBridgeException(
            code = "image_read_failed",
            message = "Could not read image.",
            cause = IllegalStateException("decoder failure"),
        )
        val wrapper = IllegalStateException("task wrapper", expected)

        assertSame(expected, wrapper.asBridgeError("platform_error"))
    }

    @Test
    fun `maps canceled platform task while the request coroutine is active`() {
        val task = TaskCompletionSource<String>().apply {
            setException(CancellationException("Google task canceled"))
        }.task
        val canceledTaskError = googleTaskFailure(isCanceled = true, failure = null)

        val error = assertThrows(MangaTranslationBridgeException::class.java) {
            runBlocking { awaitGoogleTask(task) }
        }

        assertEquals("platform_task_cancelled", error.code)
        assertEquals("platform_task_cancelled", (canceledTaskError as MangaTranslationBridgeException).code)
    }

    @Test
    fun `request job cancellation propagates while awaiting a platform task`() {
        val taskSource = TaskCompletionSource<String>()
        val requestJob = Job()
        val request = CoroutineScope(requestJob + Dispatchers.Unconfined).async {
            awaitGoogleTask(taskSource.task)
        }
        requestJob.cancel(CancellationException("request cancelled"))

        val thrown = assertThrows(CancellationException::class.java) {
            runBlocking { request.await() }
        }
        taskSource.setException(CancellationException("late task cancellation"))

        assertEquals("request cancelled", thrown.message)
    }

    @Test
    fun `translation model download owned deadline maps to model download failure`() {
        val error = assertThrows(MangaTranslationBridgeException::class.java) {
            runBlocking {
                awaitTranslationModelDownloads(timeoutMillis = 5) { awaitCancellation() }
            }
        }

        assertEquals("model_download_failed", error.code)
    }

    @Test
    fun `translation model download nested timeout remains cancellation`() {
        var nestedTimeout: TimeoutCancellationException? = null
        val thrown = assertThrows(TimeoutCancellationException::class.java) {
            runBlocking {
                awaitTranslationModelDownloads(timeoutMillis = 500) {
                    try {
                        withTimeout(20) { delay(1_000) }
                    } catch (error: TimeoutCancellationException) {
                        nestedTimeout = error
                        throw error
                    }
                }
            }
        }

        assertEquals(nestedTimeout?.message, thrown.message)
    }

    @Test
    fun `mapped OCR timeout is delivered as one method result`() {
        val bridgeError = assertThrows(MangaTranslationBridgeException::class.java) {
            runBlocking {
                awaitOcrModuleReady(timeoutMillis = 5, pollIntervalMillis = 1) { false }
            }
        }
        val result = RecordingMethodResult()
        val reply = MangaTranslationOnceResult(result) { action -> action() }

        reply.error(bridgeError.code, bridgeError.message.orEmpty(), bridgeError.details)
        reply.error(bridgeError.code, bridgeError.message.orEmpty(), bridgeError.details)

        assertEquals(1, result.errorCount)
        assertEquals("model_download_failed", result.errorCode)
    }

    @Test
    fun `normalizes Kotlin Unit to null before returning success`() {
        val result = RecordingMethodResult()
        val reply = MangaTranslationOnceResult(result) { action -> action() }

        reply.success(Unit)

        assertEquals(1, result.successCount)
        assertNull(result.successValue)
    }

    private class RecordingMethodResult : MethodChannel.Result {
        var successCount = 0
            private set
        var successValue: Any? = Unit
            private set
        var errorCount = 0
            private set
        var errorCode: String? = null
            private set

        override fun success(result: Any?) {
            successCount++
            successValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            this.errorCount++
            this.errorCode = errorCode
        }

        override fun notImplemented() = Unit
    }
}
