/*
 * Ldroid - Rootless Podman for Android
 * Copyright (C) 2024-2026 Ldroid contributors
 *
 * Exposes the shared server-mode state to MainActivity so it can draw the black
 * overlay and drop window brightness, and lets the overlay turn it off.
 */
package com.abhiram79.Ldroid.ui

import androidx.lifecycle.ViewModel
import com.abhiram79.Ldroid.engine.hostbridge.HeadlessModeManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject

@HiltViewModel
class HeadlessViewModel @Inject constructor(
    private val headlessModeManager: HeadlessModeManager,
) : ViewModel() {
    val active: StateFlow<Boolean> = headlessModeManager.active
    fun disable() = headlessModeManager.setActive(false)
}
