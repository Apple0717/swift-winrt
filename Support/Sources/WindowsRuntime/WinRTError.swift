import COM
import CWinRTCore

public struct WinRTError: COMError, CustomStringConvertible {
    public let hresult: HResult
    public let errorInfo: IRestrictedErrorInfo?

    public init?(hresult: HResult, captureErrorInfo: Bool) {
        if hresult.isSuccess { return nil }
        self.hresult = hresult
        self.errorInfo = captureErrorInfo ? try? Self.getRestrictedErrorInfo(matching: hresult) : nil
    }

    public var description: String {
        let details = (try? errorInfo?.details) ?? RestrictedErrorInfoDetails()
        // RestrictedDescription contains the value reported in RoOriginateError
        return details.restrictedDescription ?? details.description ?? hresult.description
    }

    public static func throwIfFailed(_ hresult: CWinRTCore.SWRT_HResult) throws {
        let hresult = HResultProjection.toSwift(hresult)
        guard let error = WinRTError(hresult: hresult, captureErrorInfo: true) else { return }
        throw error
    }

    public static func getRestrictedErrorInfo() throws -> IRestrictedErrorInfo? {
        var restrictedErrorInfo: UnsafeMutablePointer<SWRT_IRestrictedErrorInfo>?
        defer { IRestrictedErrorInfoProjection.release(&restrictedErrorInfo) }

        // Don't throw a WinRTError, that would be recursive
        let hresult = CWinRTCore.SWRT_GetRestrictedErrorInfo(&restrictedErrorInfo)
        if let error = WinRTError(hresult: HResult(hresult), captureErrorInfo: false) { throw error }

        return IRestrictedErrorInfoProjection.toSwift(consuming: &restrictedErrorInfo)
    }

    public static func getRestrictedErrorInfo(matching expectedHResult: HResult) throws -> IRestrictedErrorInfo? {
        var restrictedErrorInfo: UnsafeMutablePointer<SWRT_IRestrictedErrorInfo>?
        defer { IRestrictedErrorInfoProjection.release(&restrictedErrorInfo) }

        let hresult = CWinRTCore.SWRT_RoGetMatchingRestrictedErrorInfo(expectedHResult.value, &restrictedErrorInfo)
        if let error = WinRTError(hresult: HResult(hresult), captureErrorInfo: false) { throw error }

        return IRestrictedErrorInfoProjection.toSwift(consuming: &restrictedErrorInfo)
    }
}