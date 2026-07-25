import Darwin
import Foundation

@main
struct MX3Lite {
    static func main() {
        do {
            try CLI().run()
        } catch let result as CLIExit {
            exit(result.exitCode)
        } catch let error as CLIError {
            FileHandle.standardError.writeLine("mx3-lite: \(error.message)")
            exit(Int32(error.exitCode))
        } catch {
            FileHandle.standardError.writeLine("mx3-lite: \(error)")
            exit(1)
        }
    }
}
