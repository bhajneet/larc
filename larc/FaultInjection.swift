#if LARC_DEV
import Foundation

/// Deliberate failure injection, compiled only into `./build.sh --dev`.
///
/// It exists because the failures worth testing are the ones that can't be
/// staged: a single dropped read out of four leaves a settings screen with one
/// blank control and no error anywhere, and waiting for the hardware to do it
/// spontaneously is not a test. Powering the device off exercises the
/// everything-failed path instead, which is the easy one.
///
/// A compile flag rather than a setting, for the same reason the Dev screen is:
/// a release build cannot ship it by accident — no flag, no code.
///
///     open build/Larc.app --args --fail-reads 0.5
///
enum LarcFaultInjection {
    /// Probability that any single device request throws, 0…1. Nil when the
    /// argument is absent, which is every normal run.
    static let readFailureRate: Double? = {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--fail-reads"),
              args.index(after: flag) < args.endIndex,
              let rate = Double(args[args.index(after: flag)]),
              rate > 0
        else { return nil }
        let clamped = min(rate, 1)
        NSLog("[larc] fault injection: %.0f%% of device reads will fail", clamped * 100)
        return clamped
    }()
}
#endif
