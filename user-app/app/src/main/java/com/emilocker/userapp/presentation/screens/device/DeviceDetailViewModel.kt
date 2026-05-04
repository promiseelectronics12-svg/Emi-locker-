package com.emilocker.userapp.presentation.screens.device

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.emilocker.userapp.data.remote.api.DeviceDto
import com.emilocker.userapp.data.repository.DeviceRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DeviceDetailUiState(
    val device: DeviceDto? = null,
    val isLoading: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class DeviceDetailViewModel @Inject constructor(
    private val deviceRepository: DeviceRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(DeviceDetailUiState())
    val uiState: StateFlow<DeviceDetailUiState> = _uiState.asStateFlow()

    fun loadDevice(deviceId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            val result = deviceRepository.getDevice(deviceId)

            result.fold(
                onSuccess = { device ->
                    _uiState.update { it.copy(isLoading = false, device = device) }
                },
                onFailure = { exception ->
                    _uiState.update { 
                        it.copy(isLoading = false, error = exception.message ?: "Failed to load device") 
                    }
                }
            )
        }
    }
}