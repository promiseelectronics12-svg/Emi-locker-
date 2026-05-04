package com.emilocker.userapp.presentation.navigation

import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.emilocker.userapp.presentation.screens.auth.LoginScreen
import com.emilocker.userapp.presentation.screens.auth.RegisterScreen
import com.emilocker.userapp.presentation.screens.home.HomeScreen
import com.emilocker.userapp.presentation.screens.device.DeviceDetailScreen
import com.emilocker.userapp.presentation.screens.agreement.AgreementDetailScreen
import com.emilocker.userapp.presentation.screens.dashboard.DashboardScreen
import com.emilocker.userapp.ui.dealer.DealerContactActivity

sealed class Screen(val route: String) {
    object Login : Screen("login")
    object Register : Screen("register")
    object Home : Screen("home")
    object Dashboard : Screen("dashboard")
    object DeviceDetail : Screen("device/{deviceId}") {
        fun createRoute(deviceId: String) = "device/$deviceId"
    }
    object AgreementDetail : Screen("agreement/{agreementId}") {
        fun createRoute(agreementId: String) = "agreement/$agreementId"
    }
}

@Composable
fun EMILockerNavHost(
    navController: NavHostController = rememberNavController(),
    onAuthSuccess: () -> Unit = {}
) {
    NavHost(
        navController = navController,
        startDestination = Screen.Login.route
    ) {
        composable(Screen.Login.route) {
            LoginScreen(
                onNavigateToRegister = {
                    navController.navigate(Screen.Register.route)
                },
                onLoginSuccess = {
                    onAuthSuccess()
                }
            )
        }

        composable(Screen.Register.route) {
            RegisterScreen(
                onNavigateToLogin = {
                    navController.popBackStack()
                },
                onRegisterSuccess = {
                    onAuthSuccess()
                }
            )
        }

        composable(Screen.Home.route) {
            HomeScreen(
                onDeviceClick = { deviceId ->
                    navController.navigate(Screen.DeviceDetail.createRoute(deviceId))
                },
                onAgreementClick = { agreementId ->
                    navController.navigate(Screen.AgreementDetail.createRoute(agreementId))
                },
                onLogout = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.Home.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.Dashboard.route) {
            DashboardScreen(
                onNavigateToAgreement = { agreementId ->
                    navController.navigate(Screen.AgreementDetail.createRoute(agreementId))
                },
                onNavigateToDealerContact = {
                    navController.navigate("dealer_contact")
                }
            )
        }

        composable(
            route = Screen.DeviceDetail.route,
            arguments = listOf(navArgument("deviceId") { type = NavType.StringType })
        ) { backStackEntry ->
            val deviceId = backStackEntry.arguments?.getString("deviceId") ?: ""
            DeviceDetailScreen(
                deviceId = deviceId,
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable(
            route = Screen.AgreementDetail.route,
            arguments = listOf(navArgument("agreementId") { type = NavType.StringType })
        ) { backStackEntry ->
            val agreementId = backStackEntry.arguments?.getString("agreementId") ?: ""
            AgreementDetailScreen(
                agreementId = agreementId,
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable("dealer_contact") {
            val context = navController.context as? android.content.Context ?: return@composable
            val intent = Intent(context, DealerContactActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }
}