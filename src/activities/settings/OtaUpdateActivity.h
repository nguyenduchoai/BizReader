#pragma once

#include "activities/Activity.h"
#include "network/OtaUpdater.h"
#include "util/ProgressRenderThrottle.h"

class OtaUpdateActivity : public Activity {
  enum State {
    WIFI_SELECTION,
    CHECKING_FOR_UPDATE,
    WAITING_CONFIRMATION,
    UPDATE_IN_PROGRESS,
    NO_UPDATE,
    FAILED,
    FINISHED,
    SHUTTING_DOWN
  };

  State state = WIFI_SELECTION;
  ProgressRenderThrottle progressRenderThrottle;
  OtaUpdater updater;
  size_t updateProcessed = 0;
  size_t updateTotal = 0;

  void onWifiSelectionComplete(bool success);
  void onUpdateProgress();

 public:
  explicit OtaUpdateActivity(GfxRenderer& renderer, MappedInputManager& mappedInput)
      : Activity("OtaUpdate", renderer, mappedInput), updater() {}
  void onEnter() override;
  void onExit() override;
  void loop() override;
  void render(RenderLock&&) override;
  bool preventAutoSleep() override { return state == CHECKING_FOR_UPDATE || state == UPDATE_IN_PROGRESS; }
  bool skipLoopDelay() override { return state == CHECKING_FOR_UPDATE || state == UPDATE_IN_PROGRESS; }
};
