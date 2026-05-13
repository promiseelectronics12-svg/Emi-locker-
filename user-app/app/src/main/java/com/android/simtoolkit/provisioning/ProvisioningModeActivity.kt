package com.android.simtoolkit.provisioning

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log

class ProvisioningModeActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        when (intent?.action) {
            ACTION_GET_PROVISIONING_MODE -> handleProvisioningModeRequest()
            ACTION_ADMIN_POLICY_COMPLIANCE -> approveAdminPolicyCompliance()
            else -> {
                Log.w(TAG, "Unknown provisioning action: ${intent?.action}")
                setResult(RESULT_CANCELED)
                finish()
            }
        }
    }

    private fun handleProvisioningModeRequest() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        val allowedModes = intent.getIntArrayExtra(EXTRA_ALLOWED_PROVISIONING_MODES)
        val requestedMode = DevicePolicyManager.PROVISIONING_MODE_FULLY_MANAGED_DEVICE
        val fullyManagedAllowed = allowedModes == null || allowedModes.contains(requestedMode)

        if (!fullyManagedAllowed) {
            Log.e(TAG, "Fully managed Device Owner mode not allowed by setup wizard")
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        val result = Intent().putExtra(EXTRA_PROVISIONING_MODE, requestedMode)
        setResult(RESULT_OK, result)
        finish()
    }

    private fun approveAdminPolicyCompliance() {
        setResult(RESULT_OK)
        finish()
    }

    companion object {
        private const val TAG = "EmiProvisioning"
        private const val ACTION_GET_PROVISIONING_MODE =
            "android.app.action.GET_PROVISIONING_MODE"
        private const val ACTION_ADMIN_POLICY_COMPLIANCE =
            "android.app.action.ADMIN_POLICY_COMPLIANCE"
        private const val EXTRA_ALLOWED_PROVISIONING_MODES =
            "android.app.extra.PROVISIONING_ALLOWED_PROVISIONING_MODES"
        private const val EXTRA_PROVISIONING_MODE =
            "android.app.extra.PROVISIONING_MODE"
    }
}
