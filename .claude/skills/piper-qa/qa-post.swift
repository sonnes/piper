// Posts the distributed notification com.piper.qa.eval with a script as its object.
// Usage: qa-post <script>
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: qa-post <script>\n".utf8))
    exit(1)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.piper.qa.eval"),
    object: CommandLine.arguments[1],
    userInfo: nil,
    deliverImmediately: true
)
