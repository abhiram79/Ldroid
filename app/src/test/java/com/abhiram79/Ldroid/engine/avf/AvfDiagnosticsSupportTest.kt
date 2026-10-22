package com.abhiram79.Ldroid.engine.avf

import org.junit.Assert.assertFalse
import org.junit.Test

class AvfDiagnosticsSupportTest {
    @Test fun `customVmConfigSupported is false when AVF classes absent`() {
        // JVM unit test: android.system.virtualmachine.* is not on the classpath.
        assertFalse(AvfDiagnostics.customVmConfigSupported())
    }
}
