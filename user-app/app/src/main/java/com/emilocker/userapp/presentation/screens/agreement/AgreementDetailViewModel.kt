package com.emilocker.userapp.presentation.screens.agreement

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.emilocker.userapp.data.remote.api.AgreementDto
import com.emilocker.userapp.data.remote.api.PaymentDto
import com.emilocker.userapp.data.repository.DeviceRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AgreementDetailUiState(
    val agreement: AgreementDto? = null,
    val payments: List<PaymentDto> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class AgreementDetailViewModel @Inject constructor(
    private val deviceRepository: DeviceRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(AgreementDetailUiState())
    val uiState: StateFlow<AgreementDetailUiState> = _uiState.asStateFlow()

    fun loadAgreement(agreementId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            val result = deviceRepository.getAgreement(agreementId)

            result.fold(
                onSuccess = { detail ->
                    _uiState.update { 
                        it.copy(
                            isLoading = false, 
                            agreement = detail.agreement,
                            payments = detail.payments
                        ) 
                    }
                },
                onFailure = { exception ->
                    _uiState.update { 
                        it.copy(isLoading = false, error = exception.message ?: "Failed to load agreement") 
                    }
                }
            )
        }
    }
}