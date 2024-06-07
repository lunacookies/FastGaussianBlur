@import AppKit;
@import Metal;
@import QuartzCore;
@import simd;

#include "renderer.m"
#include "metal_view_controller.m"
#include "app_delegate.m"

int
main(void)
{
	setenv("MTL_HUD_ENABLED", "1", 1);
	setenv("MTL_SHADER_VALIDATION", "1", 1);
	setenv("MTL_DEBUG_LAYER", "1", 1);
	setenv("MTL_DEBUG_LAYER_WARNING_MODE", "assert", 1);

	@autoreleasepool
	{
		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		AppDelegate *appDelegate = [[AppDelegate alloc] init];
		NSApp.delegate = appDelegate;
		[NSApp run];
	}
}
