#pragma once

#include "BizContentStore.h"
#include "activities/Activity.h"
#include "util/ButtonNavigator.h"

class BizHubActivity final : public Activity {
 public:
  explicit BizHubActivity(GfxRenderer& renderer, MappedInputManager& mappedInput)
      : Activity("BizHub", renderer, mappedInput) {}

  void onEnter() override;
  void loop() override;
  void render(RenderLock&&) override;

 private:
  ButtonNavigator buttonNavigator;
  BizContentData content;
  int module = -1;
  int selectorIndex = 0;
  bool showingDetail = false;

  int itemCount() const;
  std::string itemTitle(int index) const;
  std::string itemSubtitle(int index) const;
  void renderDetail(int contentTop, int contentHeight) const;
};
