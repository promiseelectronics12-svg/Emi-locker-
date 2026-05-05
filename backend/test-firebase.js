const admin = require('firebase-admin');
require('dotenv').config();

async function testFirebaseConnection() {
    try {
        console.log("Initializing Firebase Admin SDK...");
        
        // Ensure private key handles newlines correctly
        let privateKey = process.env.FIREBASE_PRIVATE_KEY;
        if (privateKey) {
            privateKey = privateKey.replace(/\\n/g, '\n').replace(/"/g, '');
        }

        admin.initializeApp({
            credential: admin.credential.cert({
                projectId: process.env.FIREBASE_PROJECT_ID,
                clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
                privateKey: privateKey,
            }),
            databaseURL: process.env.FIREBASE_DATABASE_URL
        });

        // Test the connection by trying to access the RTDB
        console.log("Connecting to Firebase Database URL:", process.env.FIREBASE_DATABASE_URL);
        const db = admin.database();
        const ref = db.ref('.info/connected');
        
        console.log("Firebase connection established successfully! ✅");
        console.log(`- Authenticated as: ${process.env.FIREBASE_CLIENT_EMAIL}`);
        console.log(`- Project ID: ${process.env.FIREBASE_PROJECT_ID}`);
        
        process.exit(0);
    } catch (error) {
        console.error("❌ FIREBASE CONNECTION FAILED:");
        console.error(error.message);
        process.exit(1);
    }
}

testFirebaseConnection();
