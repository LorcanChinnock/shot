import Testing
@testable import ShotCore

@Test func rmsOfASquareWaveIsItsAmplitude() {
    #expect(AudioLevel.rms([0.5, -0.5, 0.5, -0.5]) == 0.5)
    #expect(AudioLevel.rms([Float]()) == 0)
}

@Test func meterIsLinearInDecibelsBetweenTheFloorAndFullScale() {
    #expect(AudioLevel.meter(rms: 1) == 1)
    #expect(AudioLevel.meter(rms: 2) == 1)
    #expect(AudioLevel.meter(rms: 0) == 0)
    #expect(AudioLevel.meter(rms: 0.001) == 0)
    // -25 dBFS is halfway up a -50 dB meter.
    #expect(abs(AudioLevel.meter(rms: 0.056234) - 0.5) < 0.001)
}
