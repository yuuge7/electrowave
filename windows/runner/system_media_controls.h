#pragma once
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Foundation.h>
#include <memory>

class SystemMediaControls {
 public:
  static constexpr UINT kButtonMessage = WM_APP + 77;
  SystemMediaControls(HWND window, flutter::BinaryMessenger* messenger);
  ~SystemMediaControls();
  void HandleButton(WPARAM button);
 private:
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::Windows::Media::SystemMediaTransportControls controls_{nullptr};
  winrt::event_token button_token_{};
  void Initialize();
};
