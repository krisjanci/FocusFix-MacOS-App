import Foundation

@main struct ReleaseConfigurationTests {
    static func main() {
        #if DEBUG
        precondition(UploadConfiguration.researchUploadsAllowed)
        precondition(UploadPolicy.endpoint(UploadConfiguration.serviceURL) != nil)
        print("Debug configuration retains the enrolled test receiver.")
        #else
        precondition(!UploadConfiguration.researchUploadsAllowed)
        precondition(UploadConfiguration.serviceURL.isEmpty)
        precondition(UploadPolicy.endpoint(UploadConfiguration.serviceURL) == nil)
        print("Release configuration has no research upload endpoint.")
        #endif
    }
}
