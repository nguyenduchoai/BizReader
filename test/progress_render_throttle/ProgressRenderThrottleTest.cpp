#include <gtest/gtest.h>

#include "src/util/ProgressRenderThrottle.h"

TEST(ProgressRenderThrottle, LimitsUpdatesByTimeOrPercentage) {
  ProgressRenderThrottle throttle;
  throttle.reset(100);

  EXPECT_FALSE(throttle.shouldRender(4, 100, 999));
  EXPECT_FALSE(throttle.shouldRender(5, 100, 999));
  EXPECT_TRUE(throttle.shouldRender(5, 100, 1100));
  EXPECT_FALSE(throttle.shouldRender(9, 100, 2200));
  EXPECT_TRUE(throttle.shouldRender(10, 100, 2200));
}

TEST(ProgressRenderThrottle, AlwaysAllowsFirstAndCompletion) {
  ProgressRenderThrottle throttle;

  EXPECT_TRUE(throttle.shouldRender(0, 100, 50));
  EXPECT_FALSE(throttle.shouldRender(0, 100, 51));
  EXPECT_TRUE(throttle.shouldRender(100, 100, 52));
  EXPECT_FALSE(throttle.shouldRender(100, 100, 53));
}

TEST(ProgressRenderThrottle, ResetRestartsThresholdsForEachTransfer) {
  ProgressRenderThrottle throttle;
  throttle.reset(100);
  EXPECT_FALSE(throttle.shouldRender(50, 100, 101));
  EXPECT_TRUE(throttle.shouldRender(50, 100, 1100));

  throttle.reset(1200);
  EXPECT_FALSE(throttle.shouldRender(0, 100, 1201));
  EXPECT_FALSE(throttle.shouldRender(4, 100, 2200));
  EXPECT_TRUE(throttle.shouldRender(5, 100, 2200));
}

TEST(ProgressRenderThrottle, HandlesUnknownTotalsAndClockWraparound) {
  ProgressRenderThrottle throttle;
  throttle.reset(UINT32_MAX - 500);

  EXPECT_FALSE(throttle.shouldRender(100, 0, 200));
  EXPECT_TRUE(throttle.shouldRender(200, 0, 500));
}

TEST(ProgressRenderThrottle, BoundsKnownSizeTransferRefreshes) {
  ProgressRenderThrottle throttle;
  throttle.reset(0);

  int renders = 0;
  for (size_t completed = 1; completed <= 100; ++completed) {
    if (throttle.shouldRender(completed, 100, static_cast<uint32_t>(completed * 200))) ++renders;
  }

  EXPECT_LE(renders, 20);
  EXPECT_EQ(renders, 20);
}
