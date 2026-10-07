#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  device_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.aniwings/device",
      &flutter::StandardMethodCodec::GetInstance());
  device_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "setScreenAwake") {
      const auto* args = call.arguments();
      const auto* map = args ? std::get_if<flutter::EncodableMap>(args) : nullptr;
      bool enabled = false;
      if (map) {
        auto entry = map->find(flutter::EncodableValue("enabled"));
        if (entry != map->end()) {
          const auto* value = std::get_if<bool>(&entry->second);
          enabled = value && *value;
        }
      }
      SetThreadExecutionState(enabled ? ES_CONTINUOUS | ES_DISPLAY_REQUIRED : ES_CONTINUOUS);
      result->Success();
      return;
    }
    if (call.method_name() == "setFullscreen") {
      const auto* value = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!value) {
        result->Error("invalid_argument", "Expected a fullscreen boolean");
        return;
      }
      if (*value != fullscreen_) {
        const HWND window = GetHandle();
        if (*value) {
          window_style_ = GetWindowLongPtr(window, GWL_STYLE);
          GetWindowPlacement(window, &window_placement_);
          MONITORINFO monitor = {sizeof(MONITORINFO)};
          GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor);
          SetWindowLongPtr(window, GWL_STYLE, window_style_ & ~WS_OVERLAPPEDWINDOW);
          SetWindowPos(window, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
              monitor.rcMonitor.right - monitor.rcMonitor.left,
              monitor.rcMonitor.bottom - monitor.rcMonitor.top, SWP_FRAMECHANGED);
        } else {
          SetWindowLongPtr(window, GWL_STYLE, window_style_);
          SetWindowPlacement(window, &window_placement_);
          SetWindowPos(window, nullptr, 0, 0, 0, 0,
              SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
        }
        fullscreen_ = *value;
        if (!fullscreen_) {
          caption_visible_ = true;
          SetCaptionVisible(false);
        }
      }
      result->Success();
      return;
    }
    result->NotImplemented();
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  SetCaptionVisible(false);
  SetTimer(GetHandle(), 0xA117, 100, nullptr);

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  KillTimer(GetHandle(), 0xA117);
  SetThreadExecutionState(ES_CONTINUOUS);
  device_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetCaptionVisible(bool visible) {
  if (fullscreen_ || caption_visible_ == visible) return;
  caption_visible_ = visible;
  const HWND window = GetHandle();
  const LONG_PTR style = GetWindowLongPtr(window, GWL_STYLE);
  SetWindowLongPtr(window, GWL_STYLE,
      visible ? style | WS_CAPTION : style & ~WS_CAPTION);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Poll the native cursor because child Flutter surfaces receive mouse events.
  if (message == WM_TIMER && wparam == 0xA117) {
    GUITHREADINFO gui = {sizeof(GUITHREADINFO)};
    if (GetGUIThreadInfo(GetCurrentThreadId(), &gui) &&
        (gui.flags & (GUI_INMENUMODE | GUI_INMOVESIZE))) return 0;
    if (!fullscreen_ && (IsIconic(hwnd) || GetForegroundWindow() != hwnd)) {
      SetCaptionVisible(false);
      return 0;
    }
    if (!fullscreen_ && !IsIconic(hwnd) && GetForegroundWindow() == hwnd) {
      POINT cursor;
      RECT bounds;
      if (GetCursorPos(&cursor) && GetWindowRect(hwnd, &bounds)) {
        const int edge = MulDiv(12, GetDpiForWindow(hwnd), 96);
        const int caption = GetSystemMetricsForDpi(SM_CYCAPTION, GetDpiForWindow(hwnd));
        const bool inside = cursor.x >= bounds.left && cursor.x < bounds.right &&
            cursor.y >= bounds.top && cursor.y < bounds.bottom;
        const ULONGLONG now = GetTickCount64();
        if (inside && cursor.y < bounds.top + edge + (caption_visible_ ? caption : 0)) {
          caption_last_hover_ = now;
          SetCaptionVisible(true);
        } else if (now - caption_last_hover_ > 700) {
          SetCaptionVisible(false);
        }
      }
    }
    return 0;
  }
  // Alt opens the standard window menu, including with the caption hidden.
  if (message == WM_SYSKEYDOWN && wparam == VK_SPACE) {
    caption_last_hover_ = GetTickCount64();
    SetCaptionVisible(true);
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
