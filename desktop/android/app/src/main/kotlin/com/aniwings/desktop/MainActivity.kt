package com.aniwings.desktop

import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

/** Android host for previewing the desktop Flutter interface in an emulator. */
class MainActivity : FlutterActivity() {
    private var systemBarsVisible: Boolean? = null
    private val barsHandler = Handler(Looper.getMainLooper())
    private val hideBars = Runnable { setSystemBarsVisible(false) }

    private fun setSystemBarsVisible(visible: Boolean) {
        // Insets changes can resize the Flutter/video surfaces. Only issue a
        // native change when the desired visibility actually changes.
        if (systemBarsVisible == visible) return
        systemBarsVisible = visible
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                if (visible) show(WindowInsets.Type.systemBars())
                else hide(WindowInsets.Type.systemBars())
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = if (visible) View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                else View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_HOVER_MOVE ||
            event.actionMasked == MotionEvent.ACTION_HOVER_ENTER) {
            val edge = 12f * resources.displayMetrics.density
            val top = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                window.decorView.rootWindowInsets?.getInsets(WindowInsets.Type.systemBars())?.top ?: 0
                else 0
            barsHandler.removeCallbacks(hideBars)
            if (event.y <= edge + top) setSystemBarsVisible(true)
            else setSystemBarsVisible(false)
        } else if (event.actionMasked == MotionEvent.ACTION_HOVER_EXIT) {
            barsHandler.removeCallbacks(hideBars)
            barsHandler.postDelayed(hideBars, 700)
        }
        return super.dispatchGenericMotionEvent(event)
    }

    override fun onDestroy() {
        barsHandler.removeCallbacks(hideBars)
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        barsHandler.removeCallbacks(hideBars)
        if (hasFocus) {
            // System UI may have changed while another activity had focus.
            systemBarsVisible = null
            setSystemBarsVisible(false)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Remove the system splash immediately instead of fading an extra
            // launch screen over the first intro frames.
            splashScreen.setOnExitAnimationListener { splashView -> splashView.remove() }
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setSystemBarsVisible(false)
    }
}
