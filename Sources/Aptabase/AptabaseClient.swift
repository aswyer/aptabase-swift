import Foundation

class AptabaseClient {
    private static let sdkVersion = "aptabase-swift@0.3.11"
    // Session expires after 1 hour of inactivity
    private static let sessionTimeout: TimeInterval = 1 * 60 * 60

    private var sessionId = newSessionId()
    private var lastTouched = Date()
    private var flushTimer: Timer?
    private let dispatcher: EventDispatcher
    private let env: EnvironmentInfo
    private let flushInterval: Double
    private var pauseFlushTimer: Bool = false

    init(appKey: String, baseUrl: String, env: EnvironmentInfo, options: InitOptions?) {
        flushInterval = options?.flushInterval ?? (env.isDebug ? 2.0 : 60.0)
        self.env = env

        dispatcher = EventDispatcher(appKey: appKey, baseUrl: baseUrl, env: env)
    }

    /// Begins tracking an event in the asynchronously.
    public func trackEvent(_ eventName: String, with props: [String: AnyCodableValue] = [:]) {
        Task {
            await trackEvent(eventName, with: props)
        }
    }

    public func trackEvent(_ eventName: String, with props: [String: AnyCodableValue] = [:]) async {
        let now = Date()
        if lastTouched.distance(to: now) > AptabaseClient.sessionTimeout {
            sessionId = AptabaseClient.newSessionId()
        }
        lastTouched = now

        let evt = Event(timestamp: Date(),
                        sessionId: sessionId,
                        eventName: eventName,
                        systemProps: Event.SystemProps(
                            isDebug: env.isDebug,
                            locale: env.locale,
                            osName: env.osName,
                            osVersion: env.osVersion,
                            appVersion: env.appVersion,
                            appBuildNumber: env.appBuildNumber,
                            sdkVersion: AptabaseClient.sdkVersion,
                            deviceModel: env.deviceModel
                        ),
                        props: props)

        await dispatcher.enqueue(evt)
    }

    public func startPolling() {
        stopPolling()

        flushTimer = Timer.scheduledTimer(timeInterval: flushInterval, target: self, selector: #selector(timerFlushSync), userInfo: nil, repeats: true)
    }

    public func stopPolling() {
        flushTimer?.invalidate()
        flushTimer = nil
        
        Task {
            await flush()
        }
        
    }

    public func flush() async {
        await dispatcher.flush()
    }
    
    private static func newSessionId() -> String {
        let epochInSeconds = UInt64(Date().timeIntervalSince1970)
        let random = UInt64.random(in: 0...99999999)
        return String(epochInSeconds * 100000000 + random)
    }

    @objc private func timerFlushSync() {
        if !pauseFlushTimer {
            Task {
                self.pauseFlushTimer = true
                await self.flush()
                self.pauseFlushTimer = false
            }
        }
    }
}
