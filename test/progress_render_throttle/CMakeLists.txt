add_executable(ProgressRenderThrottleTest
  ProgressRenderThrottleTest.cpp
)

target_link_libraries(ProgressRenderThrottleTest PRIVATE
  crosspoint_test_common
  GTest::gtest_main
)

gtest_discover_tests(ProgressRenderThrottleTest)
