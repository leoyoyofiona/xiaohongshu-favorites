import Foundation

public struct XHSConnectorStatus: Sendable {
    public var isConnected: Bool
    public var lastSyncDescription: String

    public init(isConnected: Bool = false, lastSyncDescription: String = "尚未连接小红书") {
        self.isConnected = isConnected
        self.lastSyncDescription = lastSyncDescription
    }
}

public struct XHSConnector: Sendable {
    public init() {}

    public func currentStatus() -> XHSConnectorStatus {
        XHSConnectorStatus(
            isConnected: false,
            lastSyncDescription: "V2 预留：后续通过登录态授权后同步收藏夹"
        )
    }
}
