import CABI
import COM

internal protocol IUnknown2Protocol: IUnknownProtocol {}
internal typealias IUnknown2 = any IUnknown2Protocol

internal final class IUnknown2Projection: COMProjectionBase<IUnknown2Projection>, COMTwoWayProjection,
        IUnknown2Protocol {
    public typealias SwiftObject = IUnknown2
    public typealias COMInterface = CABI.IUnknown
    public typealias VirtualTable = CABI.IUnknownVtbl

    public static let iid = IID(0x5CF9DEB3, 0xD7C6, 0x42A9, 0x85B3, 0x61D8B68A7B2A)
    public static var vtable: VirtualTablePointer { withUnsafePointer(to: &vtableStruct) { $0 } }
    private static var vtableStruct: VirtualTable = .init(
        QueryInterface: { this, iid, ppvObject in _queryInterface(this, iid, ppvObject) },
        AddRef: { this in _addRef(this) },
        Release: { this in _release(this) })
}