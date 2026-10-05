package pk.ussdpay.ussd_pay

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Walks a multi-step USSD menu: the first code is dialed by MainActivity, then every
 * time the system USSD dialog shows an input box we type the next queued step and
 * press Send. When the queue is empty (or the network shows a final message) we
 * report the text back to Flutter and dismiss the dialog.
 */
class UssdService : AccessibilityService() {
    companion object {
        @Volatile var active = false
        private var queue = ArrayDeque<String>()
        private var lastText = ""
        var onEvent: ((String, String) -> Unit)? = null

        fun start(steps: List<String>) {
            queue = ArrayDeque(steps)
            lastText = ""
            active = true
        }

        fun cancel() { active = false; queue.clear() }

        private val transient = Regex("running|loading|please wait|in progress", RegexOption.IGNORE_CASE)
        private val sendBtn = Regex("^(send|ok|reply|submit|yes|continue)$", RegexOption.IGNORE_CASE)
        private val closeBtn = Regex("^(cancel|dismiss|ok|close|done)$", RegexOption.IGNORE_CASE)
    }

    private val handler = Handler(Looper.getMainLooper())

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!active || event == null) return
        val pkg = event.packageName?.toString() ?: return
        if (!(pkg.contains("phone") || pkg.contains("dialer") || pkg.contains("telecom"))) return
        handler.postDelayed({ process() }, 350)
    }

    private fun process() {
        if (!active) return
        val root = rootInActiveWindow ?: return
        val texts = mutableListOf<String>()
        var input: AccessibilityNodeInfo? = null
        val buttons = mutableListOf<AccessibilityNodeInfo>()
        walk(root, texts, buttons) { if (input == null) input = it }
        val msg = texts.joinToString("\n").trim()
        if (msg.isEmpty() || transient.containsMatchIn(msg) || msg == lastText) return
        lastText = msg

        val box = input
        if (box != null && queue.isNotEmpty()) {
            val next = queue.removeFirst()
            onEvent?.invoke("progress", msg)
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, next)
            }
            box.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            buttons.firstOrNull { sendBtn.matches(it.text?.toString()?.trim() ?: "") }
                ?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        } else {
            active = false
            queue.clear()
            onEvent?.invoke("result", msg)
            buttons.firstOrNull { closeBtn.matches(it.text?.toString()?.trim() ?: "") }
                ?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                ?: performGlobalAction(GLOBAL_ACTION_BACK)
        }
    }

    private fun walk(
        n: AccessibilityNodeInfo,
        texts: MutableList<String>,
        buttons: MutableList<AccessibilityNodeInfo>,
        onInput: (AccessibilityNodeInfo) -> Unit
    ) {
        val cls = n.className?.toString() ?: ""
        when {
            cls.endsWith("EditText") -> onInput(n)
            cls.endsWith("Button") -> buttons.add(n)
            !n.text.isNullOrBlank() && n.childCount == 0 -> texts.add(n.text.toString())
        }
        for (i in 0 until n.childCount) n.getChild(i)?.let { walk(it, texts, buttons, onInput) }
    }

    override fun onInterrupt() {}
}
