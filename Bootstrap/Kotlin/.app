

```kotlin
package com.example.aqarions

import android.content.Context
import android.os.Build
import ai.koog.agents.AIAgent
import ai.koog.agents.core.tools.Tool
import ai.koog.agents.core.tools.ToolRegistry
import ai.koog.agents.features.persistence.FilePersistenceStorageProvider
import ai.koog.agents.features.persistence.Persistence
import ai.koog.prompt.executor.simpleOpenAIExecutor
import ai.koog.prompt.models.openai.OpenAIModels
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

// ----------------------
// Local tools
// ----------------------

class DeviceStatusTool(private val context: Context) : Tool {
    override val name: String = "device_status"
    override val description: String =
        "Returns information about the Android device (manufacturer, model, SDK)."

    override suspend fun invoke(arguments: Map<String, Any?>): Any {
        val model = Build.MODEL
        val manu = Build.MANUFACTURER
        val sdk = Build.VERSION.SDK_INT
        return "Device: $manu $model, SDK $sdk"
    }
}

class NotesTool(private val context: Context) : Tool {
    override val name: String = "notes"
    override val description: String =
        "Save and list short notes on device. Use action='add' or 'list'."

    private val file: File
        get() = File(context.filesDir, "notes.txt")

    override suspend fun invoke(arguments: Map<String, Any?>): Any =
        withContext(Dispatchers.IO) {
            when (arguments["action"]) {
                "add" -> {
                    val text = (arguments["text"] as? String)?.trim().orEmpty()
                    if (text.isNotEmpty()) {
                        file.appendText(text + "\n")
                        "Note saved."
                    } else {
                        "No text provided."
                    }
                }
                "list" -> {
                    if (!file.exists()) {
                        "No notes yet."
                    } else {
                        file.readLines().joinToString(separator = "; ")
                    }
                }
                else -> "Unknown action. Use action='add' or 'list'."
            }
        }
}

// ----------------------
// Python tool (Chaquopy)
// ----------------------

class PythonHeavyComputeTool(private val context: Context) : Tool {
    override val name: String = "python_heavy_compute"
    override val description: String =
        "Runs a Python function heavy_compute(values=[...]) and returns a summary."

    override suspend fun invoke(arguments: Map<String, Any?>): Any =
        withContext(Dispatchers.Default) {
            if (!Python.isStarted()) {
                Python.start(AndroidPlatform(context))
            }
            val py = Python.getInstance()
            val module = py.getModule("aqarions_tools")

            val values = arguments["values"] as? List<Number> ?: emptyList()
            val json = JSONObject().apply {
                put("values", values.map { it.toDouble() })
            }.toString()

            module.callAttr("heavy_compute", json).toString()
        }
}

// ----------------------
// AQARIONS Koog agent
// ----------------------

fun createAqaAgent(context: Context, apiKey: String): AIAgent {
    val tools = ToolRegistry().apply {
        register(DeviceStatusTool(context))
        register(NotesTool(context))
        register(PythonHeavyComputeTool(context))
    }

    val checkpointDir = File(context.filesDir, "koog-checkpoints").apply { mkdirs() }

    return AIAgent(
        promptExecutor = simpleOpenAIExecutor(apiKey, temperature = 0.2),
        systemPrompt = """
            You are AQARIONS, an on-device assistant running on this Android phone.
            You can:
            - Inspect the device via the 'device_status' tool.
            - Save and list notes via the 'notes' tool.
            - Analyze numeric arrays via the 'python_heavy_compute' tool.
            Rules:
            - Keep answers under three sentences.
            - Clearly summarize what you did and what you found.
        """.trimIndent(),
        llmModel = OpenAIModels.Chat.GPT4o,
        toolRegistry = tools
    ) {
        install(Persistence) {
            storage = FilePersistenceStorageProvider(checkpointDir)
            enableAutomaticPersistence = true
        }
    }
}
```

This single file is the “AQARION Kotlin” core:

- Defines three tools (device, notes, Python).  
- Creates a Koog `AIAgent` with continuous file-based persistence on Android.[1][2]

Citations:
[1] Agent Persistence - Koog https://docs.koog.ai/agent-persistence/
[2] JetBrains/koog: Koog is the official Kotlin framework for ... - GitHub https://github.com/JetBrains/koog
