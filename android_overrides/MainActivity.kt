package com.jizhang.jizhang

import android.content.ContentUris
import android.content.ContentValues
import android.database.Cursor
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.jizhang.app/backup"
    private val PREFIX = "极简记账_"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "backupSave" -> {
                            val name = call.argument<String>("name") ?: throw Exception("缺少文件名")
                            val content = call.argument<String>("content") ?: throw Exception("缺少内容")
                            saveToDownloads(name, content)
                            result.success(name)
                        }
                        "backupList" -> {
                            result.success(listBackups())
                        }
                        "backupRead" -> {
                            val name = call.argument<String>("name") ?: throw Exception("缺少文件名")
                            result.success(readFromDownloads(name))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("BACKUP_ERR", e.message ?: "未知错误", null)
                }
            }
    }

    private fun saveToDownloads(name: String, content: String) {
        val resolver = applicationContext.contentResolver
        val values = ContentValues()
        values.put(MediaStore.Downloads.DISPLAY_NAME, name)
        values.put(MediaStore.Downloads.MIME_TYPE, "application/json")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.put(MediaStore.Downloads.RELATIVE_PATH, "Download/极简记账备份")
            values.put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw Exception("无法写入下载目录（存储权限不足）")
        resolver.openOutputStream(uri)?.use { os ->
            os.write(content.toByteArray(Charsets.UTF_8))
        } ?: throw Exception("无法打开输出流")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
    }

    private fun listBackups(): List<String> {
        val resolver = applicationContext.contentResolver
        val out = mutableListOf<String>()
        val cursor: Cursor? = resolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads.DISPLAY_NAME),
            "${MediaStore.Downloads.DISPLAY_NAME} LIKE ?",
            arrayOf("$PREFIX%"),
            null
        )
        cursor?.use {
            val idx = it.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
            while (it.moveToNext()) {
                val n = it.getString(idx)
                if (n != null && n.endsWith(".json")) out.add(n)
            }
        }
        return out
    }

    private fun readFromDownloads(name: String): String {
        val resolver = applicationContext.contentResolver
        val cursor: Cursor? = resolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME} = ?",
            arrayOf(name),
            null
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val id = it.getLong(it.getColumnIndexOrThrow(MediaStore.Downloads._ID))
                val uri = ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id)
                resolver.openInputStream(uri)?.use { input ->
                    return input.bufferedReader(Charsets.UTF_8).readText()
                } ?: throw Exception("无法读取备份文件")
            }
        }
        throw Exception("找不到备份：$name")
    }
}
