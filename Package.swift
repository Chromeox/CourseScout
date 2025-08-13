// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CourseScout",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "CourseScout",
            targets: ["CourseScout"]
        ),
        .library(
            name: "CourseScoutWatch",
            targets: ["CourseScoutWatch"]
        ),
    ],
    dependencies: [
        // Appwrite backend integration (migrating from Supabase)
        .package(url: "https://github.com/appwrite/sdk-for-swift.git", from: "5.0.0"),
        
        // Payment processing
        .package(url: "https://github.com/stripe/stripe-ios", exact: "24.15.1"),
        
        // Social authentication
        .package(url: "https://github.com/google/GoogleSignIn-iOS", exact: "8.0.0"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", exact: "18.0.0"),
        
        // Golf-specific APIs and weather services
        .package(url: "https://github.com/WeatherKit/WeatherKit-Swift", from: "1.0.0"),
        
        // Enhanced networking and image caching
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.0.0"),
        
        // Analytics and crash reporting
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.0.0"),
    ],
    targets: [
        .target(
            name: "CourseScout",
            dependencies: [
                .product(name: "Appwrite", package: "sdk-for-swift"),
                .product(name: "StripePaymentSheet", package: "stripe-ios"),
                .product(name: "StripeApplePay", package: "stripe-ios"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "FacebookLogin", package: "facebook-ios-sdk"),
                .product(name: "WeatherKit", package: "WeatherKit-Swift"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
            ],
            path: "CourseScoutApp"
        ),
        .target(
            name: "CourseScoutWatch",
            dependencies: [
                .product(name: "Appwrite", package: "sdk-for-swift"),
            ],
            path: "CourseScoutWatch"
        ),
        .testTarget(
            name: "CourseScoutTests",
            dependencies: ["CourseScout"],
            path: "CourseScoutAppTests"
        ),
    ]
)