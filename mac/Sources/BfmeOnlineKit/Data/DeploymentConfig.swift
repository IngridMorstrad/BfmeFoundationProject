import Foundation

/// Port of `DeploymentConfig.cs`. Runtime-mutable host endpoints for the
/// arena backend. Left as `var` so integration tests can swing the hosts
/// at a local fixture server.
public enum DeploymentConfig {
    public static var arenaServerHost = "https://bfmeladder.com"
    public static var arenaFilesHost = "https://arena-files.bfmeladder.com"
}
