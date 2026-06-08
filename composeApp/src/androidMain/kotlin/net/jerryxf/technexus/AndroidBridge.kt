package net.jerryxf.technexus

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import java.io.File

@SuppressLint("StaticFieldLeak")
object AndroidBridge {
    lateinit var activity: Activity
    lateinit var context: Context
    lateinit var filesDir: File
    var appIcon: Int = -1

    fun setup(activity: Activity, icon: Int) {
        this.activity = activity
        context = activity.applicationContext
        filesDir = context.filesDir
        appIcon = icon
    }
}
