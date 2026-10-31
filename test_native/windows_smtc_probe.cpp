// Manual/native integration probe. Run against an isolated portable test app
// with a generated track restored paused. Never targets another media app.
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Control.h>
#include <chrono>
#include <iostream>
#include <thread>

int main() {
  using namespace winrt;
  using namespace Windows::Media::Control;
  init_apartment(apartment_type::multi_threaded);
  try {
    const auto manager = GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
    for (const auto& session : manager.GetSessions()) {
      const std::wstring id(session.SourceAppUserModelId());
      if (id.find(L"electrowave") == std::wstring::npos && id.find(L"Electrowave") == std::wstring::npos) continue;
      const auto initial = session.TryGetMediaPropertiesAsync().get().Title();
      if (initial.empty()) { std::cerr << "Electrowave has no restored test track\n"; return 1; }
      if (!session.TryPlayAsync().get()) { std::cerr << "SMTC Play was rejected\n"; return 1; }
      bool playing = false;
      for (int i = 0; i < 30; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (session.GetPlaybackInfo().PlaybackStatus() == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing) { playing = true; break; }
      }
      if (!playing) { std::cerr << "SMTC Play did not reach the player\n"; return 1; }
      if (!session.TrySkipNextAsync().get()) { std::cerr << "SMTC Next was rejected\n"; return 1; }
      bool advanced = false;
      for (int i = 0; i < 30; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (session.TryGetMediaPropertiesAsync().get().Title() != initial) { advanced = true; break; }
      }
      session.TryPauseAsync().get();
      if (!advanced) { std::cerr << "SMTC Next did not update metadata\n"; return 1; }
      std::cout << "SMTC metadata, Play, Next and Pause verified\n";
      return 0;
    }
    std::cerr << "No Electrowave SMTC session found\n";
    return 1;
  } catch (const hresult_error& error) {
    std::cerr << to_string(error.message()) << '\n';
    return 1;
  }
}
