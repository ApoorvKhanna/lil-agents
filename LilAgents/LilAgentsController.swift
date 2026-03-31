import AppKit

// MARK: - Character config pool
// To add a new character:
//   1. Drop a walk-<name>.mov into LilAgents/ and add it to the Xcode target
//   2. Add an entry below with its timing params tuned to the video

struct CharacterConfig {
    let videoName: String
    let accelStart: CFTimeInterval
    let fullSpeedStart: CFTimeInterval
    let decelStart: CFTimeInterval
    let walkStop: CFTimeInterval
    let walkAmountRange: ClosedRange<CGFloat>
    let yOffset: CGFloat
    let flipXOffset: CGFloat
    let color: NSColor
}

private let characterPool: [CharacterConfig] = [
    CharacterConfig(
        videoName: "walk-bruce-01",
        accelStart: 3.0, fullSpeedStart: 3.75, decelStart: 8.0, walkStop: 8.5,
        walkAmountRange: 0.4...0.65,
        yOffset: -3, flipXOffset: 0,
        color: NSColor(red: 0.4, green: 0.72, blue: 0.55, alpha: 1.0)
    ),
    CharacterConfig(
        videoName: "walk-jazz-01",
        accelStart: 3.9, fullSpeedStart: 4.5, decelStart: 8.0, walkStop: 8.75,
        walkAmountRange: 0.35...0.6,
        yOffset: -7, flipXOffset: -9,
        color: NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0)
    ),
    // Add more characters here as you create their videos, e.g.:
    // CharacterConfig(
    //     videoName: "walk-dog-01",
    //     accelStart: 2.5, fullSpeedStart: 3.2, decelStart: 7.8, walkStop: 8.4,
    //     walkAmountRange: 0.3...0.55,
    //     yOffset: -5, flipXOffset: 0,
    //     color: NSColor(red: 0.7, green: 0.5, blue: 0.3, alpha: 1.0)
    // ),
]

class LilAgentsController {
    var characters: [WalkerCharacter] = []
    private var displayLink: CVDisplayLink?
    var debugWindow: NSWindow?
    var pinnedScreenIndex: Int = -1
    private static let onboardingKey = "hasCompletedOnboarding"
    private var isHiddenForEnvironment = false

    func start() {
        // Pick 2 random configs (without repetition) from the pool
        var pool = characterPool.filter {
            Bundle.main.url(forResource: $0.videoName, withExtension: "mov") != nil
        }
        pool.shuffle()
        let configs = Array(pool.prefix(2))

        let startPositions: [CGFloat] = [0.3, 0.7]
        let startDelays: [ClosedRange<Double>] = [0.5...2.0, 8.0...14.0]

        let chars: [WalkerCharacter] = configs.enumerated().map { i, cfg in
            let c = WalkerCharacter(videoName: cfg.videoName)
            c.accelStart = cfg.accelStart
            c.fullSpeedStart = cfg.fullSpeedStart
            c.decelStart = cfg.decelStart
            c.walkStop = cfg.walkStop
            c.walkAmountRange = cfg.walkAmountRange
            c.yOffset = cfg.yOffset
            c.flipXOffset = cfg.flipXOffset
            c.characterColor = cfg.color
            c.positionProgress = startPositions[i]
            c.pauseEndTime = CACurrentMediaTime() + Double.random(in: startDelays[i])
            c.setup()
            return c
        }

        characters = chars
        characters.forEach { $0.controller = self }

        setupDebugLine()
        startDisplayLink()

        if !UserDefaults.standard.bool(forKey: Self.onboardingKey) {
            triggerOnboarding()
        }
    }

    private func triggerOnboarding() {
        guard let bruce = characters.first else { return }
        bruce.isOnboarding = true
        // Show "hi!" bubble after a short delay so the character is visible first
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            bruce.currentPhrase = "hi!"
            bruce.showingCompletion = true
            bruce.completionBubbleExpiry = CACurrentMediaTime() + 600 // stays until clicked
            bruce.showBubble(text: "hi!", isCompletion: true)
            bruce.playCompletionSound()
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        characters.forEach { $0.isOnboarding = false }
    }

    // MARK: - Debug

    private func setupDebugLine() {
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 2),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = NSColor.red
        win.hasShadow = false
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.moveToActiveSpace, .stationary]
        win.orderOut(nil)
        debugWindow = win
    }

    private func updateDebugLine(dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat) {
        guard let win = debugWindow, win.isVisible else { return }
        win.setFrame(CGRect(x: dockX, y: dockTopY, width: dockWidth, height: 2), display: true)
    }

    // MARK: - Dock Geometry

    private func getDockIconArea(screenWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        let tileSize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 48)
        // Each dock slot is the icon + padding. The padding scales with tile size.
        // At default 48pt: slot ≈ 58pt. At 37pt: slot ≈ 47pt. Roughly tileSize * 1.25.
        let slotWidth = tileSize * 1.25

        let persistentApps = dockDefaults?.array(forKey: "persistent-apps")?.count ?? 0
        let persistentOthers = dockDefaults?.array(forKey: "persistent-others")?.count ?? 0

        // Only count recent apps if show-recents is enabled
        let showRecents = dockDefaults?.bool(forKey: "show-recents") ?? true
        let recentApps = showRecents ? (dockDefaults?.array(forKey: "recent-apps")?.count ?? 0) : 0
        let totalIcons = persistentApps + persistentOthers + recentApps

        var dividers = 0
        if persistentApps > 0 && (persistentOthers > 0 || recentApps > 0) { dividers += 1 }
        if persistentOthers > 0 && recentApps > 0 { dividers += 1 }
        // show-recents adds its own divider
        if showRecents && recentApps > 0 { dividers += 1 }

        let dividerWidth: CGFloat = 12.0
        var dockWidth = slotWidth * CGFloat(totalIcons) + CGFloat(dividers) * dividerWidth

        let magnificationEnabled = dockDefaults?.bool(forKey: "magnification") ?? false
        if magnificationEnabled,
           let largeSize = dockDefaults?.object(forKey: "largesize") as? CGFloat {
            // Magnification only affects the hovered area; at rest the dock is normal size.
            // Don't inflate the width — characters should stay within the at-rest bounds.
            _ = largeSize
        }

        // Small fudge factor for dock edge padding
        dockWidth *= 1.1

        // Fallback: if dock detection returned nothing useful, span most of the screen
        if dockWidth < 100 {
            dockWidth = screenWidth * 0.85
        }

        let dockX = (screenWidth - dockWidth) / 2.0
        return (dockX, dockWidth)
    }

    private func dockAutohideEnabled() -> Bool {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        return dockDefaults?.bool(forKey: "autohide") ?? false
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            let controller = Unmanaged<LilAgentsController>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.tick()
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback,
                                       Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(displayLink)
    }

    private(set) var isClaudeCodeBusy: Bool = false
    private var lastBusyCheckTime: CFTimeInterval = 0

    var activeScreen: NSScreen? {
        if pinnedScreenIndex >= 0, pinnedScreenIndex < NSScreen.screens.count {
            return NSScreen.screens[pinnedScreenIndex]
        }
        return NSScreen.main
    }

    /// The dock lives on the screen where visibleFrame.origin.y > frame.origin.y (bottom dock)
    /// On screens without the dock, visibleFrame.origin.y == frame.origin.y
    private func screenHasDock(_ screen: NSScreen) -> Bool {
        return screen.visibleFrame.origin.y > screen.frame.origin.y
    }

    private func shouldShowCharacters(on screen: NSScreen) -> Bool {
        if screenHasDock(screen) {
            return true
        }

        // With dock auto-hide enabled on the active desktop, the dock can still be
        // present even though visibleFrame starts at the screen origin. In fullscreen
        // spaces, both the dock and menu bar are absent, so visibleFrame matches frame.
        let menuBarVisible = screen.visibleFrame.maxY < screen.frame.maxY
        return dockAutohideEnabled() && screen == NSScreen.main && menuBarVisible
    }

    @discardableResult
    private func updateEnvironmentVisibility(for screen: NSScreen) -> Bool {
        let shouldShow = shouldShowCharacters(on: screen)
        guard shouldShow != !isHiddenForEnvironment else { return shouldShow }

        isHiddenForEnvironment = !shouldShow

        if shouldShow {
            characters.forEach { $0.showForEnvironmentIfNeeded() }
        } else {
            debugWindow?.orderOut(nil)
            characters.forEach { $0.hideForEnvironment() }
        }

        return shouldShow
    }

    func tick() {
        guard let screen = activeScreen else { return }
        guard updateEnvironmentVisibility(for: screen) else { return }

        let screenWidth = screen.frame.width
        let dockX: CGFloat
        let dockWidth: CGFloat
        let dockTopY: CGFloat

        // Dock is on this screen — constrain to dock area
        (dockX, dockWidth) = getDockIconArea(screenWidth: screenWidth)
        dockTopY = screen.visibleFrame.origin.y

        updateDebugLine(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)

        let now2 = CACurrentMediaTime()
        if now2 - lastBusyCheckTime > 1.0 {
            lastBusyCheckTime = now2
            isClaudeCodeBusy = FileManager.default.fileExists(atPath: "/tmp/.claude-busy")
        }

        let activeChars = characters.filter { $0.window.isVisible && $0.isManuallyVisible }

        let now = CACurrentMediaTime()
        let anyWalking = activeChars.contains { $0.isWalking }
        for char in activeChars {
            if char.isIdleForPopover { continue }
            if char.isPaused && now >= char.pauseEndTime && anyWalking {
                char.pauseEndTime = now + Double.random(in: 5.0...10.0)
            }
        }
        for char in activeChars {
            char.update(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)
        }

        let sorted = activeChars.sorted { $0.positionProgress < $1.positionProgress }
        for (i, char) in sorted.enumerated() {
            char.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + i)
        }
    }

    deinit {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}
