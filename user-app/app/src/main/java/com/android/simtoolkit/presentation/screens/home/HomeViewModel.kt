package com.android.simtoolkit.presentation.screens.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.android.simtoolkit.data.repository.AuthRepository
import com.android.simtoolkit.data.repository.DeviceRepository
import com.android.simtoolkit.data.remote.api.DeviceDto
import com.android.simtoolkit.data.remote.api.AgreementDto
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class HomeUiState(
    val devices: List<DeviceDto> = emptyList(),
    val agreements: List<AgreementDto> = emptyList(),
    val isLoading: Boolean = false,
    val isLoggedOut: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val deviceRepository: DeviceRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init {
        loadData()
    }

    private fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            val devicesResult = deviceRepository.getDevices()
            val agreementsResult = deviceRepository.getAgreements()

            _uiState.update { state ->
                state.copy(
                    isLoading = false,
                    devices = devicesResult.getOrDefault(emptyList()),
                    agreements = agreementsResult.getOrDefault(emptyList()),
                    error = devicesResult.exceptionOrNull()?.message
                        ?: agreementsResult.exceptionOrNull()?.message
                )
            }
        }
    }

    fun refresh() {
        loadData()
    }

    fun logout() {
        viewModelScope.launch {
            authRepository.logout()
            _uiState.update { it.copy(isLoggedOut = true) }
        }
    }
}
