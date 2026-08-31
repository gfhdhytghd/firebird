#import <UIKit/UIKit.h>

static UIEdgeInsets currentSafeAreaInsets()
{
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState != UISceneActivationStateUnattached &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                    if (candidate.isKeyWindow) {
                        window = candidate;
                        break;
                    }
                }
            }
            if (window)
                break;
        }
    }
    if (!window)
        window = [UIApplication sharedApplication].keyWindow;
    return window ? window.safeAreaInsets : UIEdgeInsetsZero;
}

int iosSafeAreaTop() { return (int)currentSafeAreaInsets().top; }
int iosSafeAreaLeft() { return (int)currentSafeAreaInsets().left; }
int iosSafeAreaRight() { return (int)currentSafeAreaInsets().right; }
