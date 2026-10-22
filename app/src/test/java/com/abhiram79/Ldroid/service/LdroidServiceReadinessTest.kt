package com.abhiram79.Ldroid.service

import com.abhiram79.Ldroid.engine.VmState
import java.io.IOException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class LdroidServiceReadinessTest {
    @Test
    fun awaitAssetsReadyForVm_reportsErrorBeforeRethrowing() = runBlocking {
        val failure = IOException("disk full")
        var state: VmState = VmState.Idle

        val thrown = try {
            awaitAssetsReadyForVm(
                awaitReady = { throw failure },
                failureMessage = "localized extraction failure",
                reportFailure = { state = VmState.Error(it) },
            )
            null
        } catch (e: Exception) {
            e
        }

        assertSame(failure, thrown)
        assertEquals(VmState.Error("localized extraction failure"), state)
    }
}
