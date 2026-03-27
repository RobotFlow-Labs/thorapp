import Foundation
import THORShared

/// THORCore — Background helper service.
///
/// In the full implementation, this will be registered via SMAppService
/// and communicate with THORApp via NSXPCConnection.
///
/// For M0, it runs as a standalone process that can be used for
/// SSH session management and agent bootstrap testing.

print("[THORCore] Starting background service...")

// Initialize database
let db = try DatabaseManager(path: DatabaseManager.defaultPath)
print("[THORCore] Database initialized at: \(DatabaseManager.defaultPath)")

// Initialize SSH session manager
let sshManager = SSHSessionManager()
print("[THORCore] SSH session manager ready")

// Keep alive — in production this would be an XPC service listener
print("[THORCore] Service running. Press Ctrl+C to stop.")

// Simple run loop to keep the process alive
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
sigintSource.setEventHandler {
    print("\n[THORCore] Shutting down...")
    Task {
        await sshManager.disconnectAll()
    }
    exit(0)
}
sigintSource.resume()

dispatchMain()
