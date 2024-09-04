import COM

public typealias IRestrictedErrorInfo = any IRestrictedErrorInfoProtocol
public protocol IRestrictedErrorInfoProtocol: IUnknownProtocol {
    func getErrorDetails(
        description: inout String?,
        error: inout HResult,
        restrictedDescription: inout String?,
        capabilitySid: inout String?) throws
    var reference: String? { get throws }
}

import WindowsRuntime_ABI

public enum IRestrictedErrorInfoProjection: COMProjection {
    public typealias SwiftObject = IRestrictedErrorInfo
    public typealias ABIStruct = WindowsRuntime_ABI.SWRT_IRestrictedErrorInfo

    public static var interfaceID: COMInterfaceID { uuidof(ABIStruct.self) }

    public static func _wrap(_ reference: consuming ABIReference) -> SwiftObject {
        Import(_wrapping: reference)
    }

    public static func toCOM(_ object: SwiftObject) throws -> ABIReference {
        try Import.toCOM(object)
    }

    private final class Import: COMImport<IRestrictedErrorInfoProjection>, IRestrictedErrorInfoProtocol {
        func getErrorDetails(
                description: inout String?,
                error: inout HResult,
                restrictedDescription: inout String?,
                capabilitySid: inout String?) throws {
            try _interop.getErrorDetails(&description, &error, &restrictedDescription, &capabilitySid)
        }

        public var reference: String? { get throws { try _interop.getReference() } }
    }
}

public func uuidof(_: WindowsRuntime_ABI.SWRT_IRestrictedErrorInfo.Type) -> COMInterfaceID {
    .init(0x82BA7092, 0x4C88, 0x427D, 0xA7BC, 0x16DD93FEB67E)
}

extension COMInterop where ABIStruct == WindowsRuntime_ABI.SWRT_IRestrictedErrorInfo {
    public func getErrorDetails(
            _ description: inout String?,
            _ error: inout HResult,
            _ restrictedDescription: inout String?,
            _ capabilitySid: inout String?) throws {
        var description_: WindowsRuntime_ABI.SWRT_BStr? = nil
        defer { BStrProjection.release(&description_) }
        var error_: WindowsRuntime_ABI.SWRT_HResult = 0
        var restrictedDescription_: WindowsRuntime_ABI.SWRT_BStr? = nil
        defer { BStrProjection.release(&restrictedDescription_) }
        var capabilitySid_: WindowsRuntime_ABI.SWRT_BStr? = nil
        defer { BStrProjection.release(&capabilitySid_) }
        try COMError.fromABI(this.pointee.VirtualTable.pointee.GetErrorDetails(this, &description_, &error_, &restrictedDescription_, &capabilitySid_))
        description = BStrProjection.toSwift(consuming: &description_)
        error = HResultProjection.toSwift(error_)
        restrictedDescription = BStrProjection.toSwift(consuming: &restrictedDescription_)
        capabilitySid = BStrProjection.toSwift(consuming: &capabilitySid_)
    }

    public func getReference() throws -> String? {
        var value = BStrProjection.abiDefaultValue
        try COMError.fromABI(this.pointee.VirtualTable.pointee.GetReference(this, &value))
        return BStrProjection.toSwift(consuming: &value)
    }
}