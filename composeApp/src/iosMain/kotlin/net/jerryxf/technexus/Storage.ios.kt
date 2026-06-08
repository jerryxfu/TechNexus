package net.jerryxf.technexus

import com.russhwolf.settings.NSUserDefaultsSettings
import com.russhwolf.settings.Settings
import kotlinx.cinterop.*
import platform.Foundation.*

// dont delete
fun saveString(name: String, data: String) = save(name, data)
fun loadString(name: String) = load<String>(name)

actual fun createSettings(): Settings {
    val userDefaults = NSUserDefaults.standardUserDefaults
    return NSUserDefaultsSettings(userDefaults)
}

@OptIn(BetaInteropApi::class)
actual fun saveInternal(name: String, data: String) {
    val url = fileURL(name) ?: return
    val nsData = NSString.create(string = data)
        .dataUsingEncoding(NSUTF8StringEncoding) ?: return
    val success = nsData.writeToURL(url, atomically = true)
    if (!success) println("Failed to write $name")
}

@OptIn(ExperimentalForeignApi::class)
actual fun loadInternal(name: String): String? {
    val url = fileURL(name) ?: return null
    return NSString.stringWithContentsOfURL(url, NSUTF8StringEncoding, null)
}

actual fun exists(name: String): Boolean {
    val path = fileURL(name)?.path ?: return false
    return NSFileManager.defaultManager.fileExistsAtPath(path)
}

@OptIn(BetaInteropApi::class, ExperimentalForeignApi::class)
actual fun delete(name: String): Boolean {
    val url = fileURL(name) ?: return false
    return memScoped {
        val error = alloc<ObjCObjectVar<NSError?>>()
        val success = NSFileManager.defaultManager.removeItemAtURL(url, error.ptr)
        if (!success) println("Delete failed: ${error.value?.localizedDescription}")
        success
    }
}

@OptIn(BetaInteropApi::class, ExperimentalForeignApi::class)
private fun getAppSupportDir(): NSURL? {
    val fileManager = NSFileManager.defaultManager
    val dir = fileManager
        .URLsForDirectory(NSApplicationSupportDirectory, NSUserDomainMask)
        .lastOrNull() as? NSURL ?: return null

    val path = dir.path ?: return null
    if (fileManager.fileExistsAtPath(path)) return dir

    return memScoped {
        val error = alloc<ObjCObjectVar<NSError?>>()
        if (fileManager.createDirectoryAtURL(
                url = dir,
                withIntermediateDirectories = true,
                attributes = null,
                error = error.ptr
            )
        ) {
            dir
        } else {
            println(
                "Failed to create Application Support directory at path $path: " +
                        (error.value?.localizedDescription ?: "No error details available")
            )
            null
        }
    }
}

private fun fileURL(name: String): NSURL? =
    getAppSupportDir()?.URLByAppendingPathComponent(name)
