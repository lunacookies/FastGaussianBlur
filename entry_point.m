@import AppKit;
@import Metal;
@import MetalPerformanceShaders;
@import QuartzCore;
@import simd;

#include "renderer.m"
#include "live_render_view_controller.m"
#include "benchmarks_view_controller.m"
#include "main_view_controller.m"
#include "app_delegate.m"

int
main(void)
{
	setenv("MTL_HUD_ENABLED", "1", 1);
	setenv("MTL_SHADER_VALIDATION", "1", 1);
	setenv("MTL_DEBUG_LAYER", "1", 1);
	setenv("MTL_DEBUG_LAYER_WARNING_MODE", "nslog", 1);

	@autoreleasepool
	{
		[NSApplication sharedApplication];
		NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
		AppDelegate *appDelegate = [[AppDelegate alloc] init];
		NSApp.delegate = appDelegate;
		[NSApp run];
	}
}
