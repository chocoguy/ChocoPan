import QuartzCore
import UIKit

//MPV Render Target
//MoltenVK momentarily sets `drawableSize` to 1x1 to forcefully complete a presentation, which
//causes flicker and can leave the layer stuck at 1x1. Swallowing those assignments is the
//workaround used upstream. See https://github.com/mpv-player/mpv/pull/13651
nonisolated final class MetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1, Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}
