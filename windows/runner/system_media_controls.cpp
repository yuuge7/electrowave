#include "system_media_controls.h"
#include <SystemMediaTransportControlsInterop.h>

using namespace winrt;
using namespace Windows::Media;
using flutter::EncodableMap;
using flutter::EncodableValue;
namespace {
std::string Text(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return {};
  const auto* value = std::get_if<std::string>(&it->second);
  return value ? *value : "";
}
}
SystemMediaControls::SystemMediaControls(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "electrowave/media", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    try {
      if (call.method_name() == "initialize") {
        Initialize();
      } else if (call.method_name() == "update") {
        if (!controls_) Initialize();
        const auto* data = std::get_if<EncodableMap>(call.arguments());
        if (!data) { result->Error("arguments", "Expected metadata map"); return; }
        auto updater = controls_.DisplayUpdater();
        updater.Type(MediaPlaybackType::Music);
        updater.MusicProperties().Title(to_hstring(Text(*data, "title")));
        updater.MusicProperties().Artist(to_hstring(Text(*data, "artist")));
        updater.MusicProperties().AlbumTitle(to_hstring(Text(*data, "album")));
        const auto cover = Text(*data, "cover");
        if (!cover.empty()) {
          // A local file URI; no networking or artwork downloads.
          auto path = to_hstring(cover);
          std::wstring uri = L"file:///" + std::wstring(path);
          for (auto& character : uri) if (character == L'\\') character = L'/';
          updater.Thumbnail(Windows::Storage::Streams::RandomAccessStreamReference::CreateFromUri(Windows::Foundation::Uri(uri)));
        } else { updater.Thumbnail(nullptr); }
        updater.Update();
        const auto playing = data->find(EncodableValue("playing"));
        const bool is_playing = playing != data->end() && std::get_if<bool>(&playing->second) && std::get<bool>(playing->second);
        controls_.PlaybackStatus(is_playing ? MediaPlaybackStatus::Playing : MediaPlaybackStatus::Paused);
      } else if (call.method_name() == "dispose") {
        if (controls_) controls_.IsEnabled(false);
      } else { result->NotImplemented(); return; }
      result->Success();
    } catch (const hresult_error& error) {
      result->Error("media_controls", to_string(error.message()));
    } catch (...) { result->Error("media_controls", "System media controls unavailable"); }
  });
}
void SystemMediaControls::Initialize() {
  if (controls_) return;
  auto factory = get_activation_factory<SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
  check_hresult(factory->GetForWindow(window_, guid_of<SystemMediaTransportControls>(), put_abi(controls_)));
  controls_.IsEnabled(true);
  controls_.IsPlayEnabled(true);
  controls_.IsPauseEnabled(true);
  controls_.IsStopEnabled(true);
  controls_.IsNextEnabled(true);
  controls_.IsPreviousEnabled(true);
  const HWND window = window_;
  button_token_ = controls_.ButtonPressed([window](auto const&, auto const& args) {
    PostMessage(window, kButtonMessage, static_cast<WPARAM>(args.Button()), 0);
  });
}
void SystemMediaControls::HandleButton(WPARAM button) {
  const char* command = nullptr;
  switch (static_cast<SystemMediaTransportControlsButton>(button)) {
    case SystemMediaTransportControlsButton::Play: command = "Play"; break;
    case SystemMediaTransportControlsButton::Pause: command = "Pause"; break;
    case SystemMediaTransportControlsButton::Stop: command = "Stop"; break;
    case SystemMediaTransportControlsButton::Next: command = "Next"; break;
    case SystemMediaTransportControlsButton::Previous: command = "Previous"; break;
    default: break;
  }
  if (command) channel_->InvokeMethod(command, nullptr);
}
SystemMediaControls::~SystemMediaControls() {
  if (controls_) {
    controls_.ButtonPressed(button_token_);
    controls_.IsEnabled(false);
  }
}
