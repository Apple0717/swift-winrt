import DotNetMD
import CodeWriters

enum SwiftProjection {
    static func toVisibility(_ visibility: DotNetMD.Visibility) -> SwiftVisibility {
        switch visibility {
            case .compilerControlled: return .fileprivate
            case .private: return .private
            case .assembly: return .internal
            case .familyAndAssembly: return .internal
            case .familyOrAssembly: return .public
            case .family: return .public
            case .public: return .public
        }
    }

    static func toType(mscorlibType: BoundType, allowImplicitUnwrap: Bool = false) -> SwiftType? {
        guard mscorlibType.definition.namespace == "System" else { return nil }
        if mscorlibType.fullGenericArgs.isEmpty {
            switch mscorlibType.definition.name {
                case "Int16", "UInt16", "Int32", "UInt32", "Int64", "UInt64", "Double", "String", "Void":
                    return .identifier(name: mscorlibType.definition.name)

                case "Boolean": return .bool
                case "SByte": return .int(bits: 8, signed: true)
                case "Byte": return .int(bits: 8, signed: false)
                case "IntPtr": return .int
                case "UIntPtr": return .uint
                case "Single": return .float
                case "Char": return .identifierChain("UTF16", "CodeUnit")
                case "Guid": return .identifierChain("Foundation", "UUID")
                case "Object": return .optional(wrapped: .any, implicitUnwrap: allowImplicitUnwrap)

                default: return nil
            }
        }
        else {
            return nil
        }
    }

    static func toType(_ type: TypeNode, allowImplicitUnwrap: Bool = false) -> SwiftType {
        switch type {
            case let .bound(type):
                // Remap primitive types
                if type.definition.assembly is Mscorlib,
                    let result = toType(mscorlibType: type, allowImplicitUnwrap: allowImplicitUnwrap) {
                    return result
                }

                else if type.definition.assembly.name == "Windows",
                    type.definition.assembly.version == .all255,
                    type.definition.namespace == "Windows.Foundation",
                    type.definition.name == "IReference`1"
                    && type.fullGenericArgs.count == 1 {
                    return .optional(wrapped: toType(type.fullGenericArgs[0]), implicitUnwrap: allowImplicitUnwrap)
                }

                let namePrefix = type.definition is InterfaceDefinition ? "Any" : ""
                let name = namePrefix + toTypeName(type.definition)

                let genericArgs = type.fullGenericArgs.map { toType($0) }
                var result: SwiftType = .identifier(name: name, genericArgs: genericArgs)
                if type.definition is InterfaceDefinition || type.definition is ClassDefinition
                    && type.definition.fullName != "System.String" {
                    result = .optional(wrapped: result, implicitUnwrap: allowImplicitUnwrap)
                }

                return result

            case let .array(element):
                return .optional(
                    wrapped: .array(element: toType(element)),
                    implicitUnwrap: allowImplicitUnwrap)

            case let .genericArg(param):
                return .identifier(name: param.name)

            default:
                fatalError()
        }
    }

    static func toReturnType(_ type: TypeNode) -> SwiftType? {
        if case let .bound(type) = type,
            let mscorlib = type.definition.assembly as? Mscorlib,
            type.definition === mscorlib.specialTypes.void {
            return nil
        }
        return toType(type, allowImplicitUnwrap: true)
    }

    static func toBaseType(_ type: BoundType?) -> SwiftType? {
        guard let type else { return nil }
        if let mscorlib = type.definition.assembly as? Mscorlib {
            guard type.definition !== mscorlib.specialTypes.object else { return nil }
        }

        guard type.definition.visibility == .public else { return nil }
        // Generic arguments do not appear on base types in Swift, but as separate typealiases
        return .identifier(name: toTypeName(type.definition))
    }

    static func toTypeName(_ type: TypeDefinition) -> String {
        var fullName = type.fullName
        fullName.replace(".", with: "_")
        fullName.replace("/", with: "_")
        if let genericSuffixStartIndex = fullName.firstIndex(of: TypeDefinition.genericParamCountSeparator) {
            fullName.removeSubrange(genericSuffixStartIndex...)
        }
        return fullName
    }

    static func toParameter(_ param: Param) -> SwiftParameter {
        .init(label: "_", name: param.name!, `inout`: param.isByRef, type: toType(param.type))
    }

    static func toConstant(_ constant: Constant) -> String {
        switch constant {
            case let .boolean(value): return value ? "true" : "false"
            case let .int8(value): return String(value)
            case let .int16(value): return String(value)
            case let .int32(value): return String(value)
            case let .int64(value): return String(value)
            case let .uint8(value): return String(value)
            case let .uint16(value): return String(value)
            case let .uint32(value): return String(value)
            case let .uint64(value): return String(value)
            case .null: return "nil"
            default: fatalError("Not implemented")
        }
    }
}