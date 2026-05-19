-- Migration 130: Add FCM push token to dealers table
-- Stores the dealer app's Firebase Cloud Messaging token for push alerts.
-- Token is registered by the dealer app on login and refreshed when Firebase rotates it.

ALTER TABLE dealers
  ADD COLUMN IF NOT EXISTS fcm_token TEXT;
