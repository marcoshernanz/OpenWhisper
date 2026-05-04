import Testing
@testable import OpenWhisperCore

@Test func removesWhisperLogsAndNormalizesWhitespace() {
    let raw = """
    whisper_init_from_file_with_params_no_state: loading model
    system_info: n_threads = 8
      Hello   world.
    This is local dictation.
    """

    let cleaned = TranscriptionOutputCleaner().clean(raw)

    #expect(cleaned == "Hello world. This is local dictation.")
}

@Test func removesTimestampPrefixesWhenPresent() {
    let raw = """
    [00:00:00.000 --> 00:00:01.000]  Hello there.
    [00:00:01.000 --> 00:00:02.000]  General Kenobi.
    """

    let cleaned = TranscriptionOutputCleaner().clean(raw)

    #expect(cleaned == "Hello there. General Kenobi.")
}
