Susurro — local TTS for macOS via text selection. MVP in progress.

## Resetting Accessibility for testing

Susurro is registered with TCC under bundle ID `com.benatespina.susurro`. To force the
permission flow again for testing:

    tccutil reset Accessibility com.benatespina.susurro

Then relaunch Susurro.
