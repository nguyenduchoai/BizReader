/**
 * XtcReaderActivity.h
 *
 * XTC ebook reader activity for CrossPoint Reader
 * Displays pre-rendered XTC pages on e-ink display
 */

#pragma once

#include <Xtc.h>

#include <atomic>
#include <string>
#include <utility>

#include "ReaderUtils.h"
#include "activities/Activity.h"

class XtcReaderActivity final : public Activity {
  std::shared_ptr<Xtc> xtc;

  uint32_t currentPage = 0;
  int pagesUntilFullRefresh = 0;
  // Debounced progress.bin persistence; see ReaderUtils::ProgressDebouncer.
  ReaderUtils::ProgressDebouncer progressDeb;
  // Set at the end of onEnter() once the saved position has been loaded. render()
  // no-ops until then, so a stale render-task notification surviving the activity
  // swap cannot render (and save progress for) page 0 before loadProgress() ran.
  std::atomic<bool> ready{false};

  enum class StatusBarOverlayPosition { Bottom, Top };
  struct StatusBarInfo {
    int currentPage;
    int pageCount;
    std::string title;
  };

  void renderPage();
  void renderStatusBarOverlay(StatusBarOverlayPosition position) const;
  StatusBarInfo getStatusBarInfo() const;
  bool saveProgress(uint32_t page) const;
  void loadProgress();

 public:
  explicit XtcReaderActivity(GfxRenderer& renderer, MappedInputManager& mappedInput, std::unique_ptr<Xtc> xtc)
      : Activity("XtcReader", renderer, mappedInput), xtc(std::move(xtc)) {}
  void onEnter() override;
  void onExit() override;
  void loop() override;
  void render(RenderLock&&) override;
  bool isReaderActivity() const override { return true; }
  ScreenshotInfo getScreenshotInfo() const override;
};
