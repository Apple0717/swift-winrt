import Collections
import CodeWriters
import DotNetMetadata

struct SwiftAssemblyModuleFileWriter {
    private let sourceFileWriter: SwiftSourceFileWriter
    private let module: SwiftProjection.Module
    private var projection: SwiftProjection { module.projection }

    init(path: String, module: SwiftProjection.Module) {
        self.sourceFileWriter = SwiftSourceFileWriter(output: FileTextOutputStream(path: path))
        self.module = module

        sourceFileWriter.output.writeLine("// Generated by swift-winrt")
        sourceFileWriter.output.writeLine("// swiftlint:disable all")

        sourceFileWriter.writeImport(module: "WindowsRuntime")

        for reference in module.references {
            sourceFileWriter.writeImport(module: reference.target.name)
        }

        sourceFileWriter.writeImport(module: "Foundation", struct: "UUID")
    }

    public func writeTypeDefinition(_ typeDefinition: TypeDefinition) throws {
        if let interfaceDefinition = typeDefinition as? InterfaceDefinition {
            try writeProtocol(interfaceDefinition)
            try writeProtocolTypeAlias(interfaceDefinition)
        }
        else if let classDefinition = typeDefinition as? ClassDefinition {
            try writeClass(classDefinition)
        }
        else if let structDefinition = typeDefinition as? StructDefinition {
            try writeStruct(structDefinition)
        }
        else if let enumDefinition = typeDefinition as? EnumDefinition {
            try writeEnumStruct(enumDefinition)
        }
    }

    private func writeProtocol(_ interface: InterfaceDefinition) throws {
        try sourceFileWriter.writeProtocol(
            visibility: SwiftProjection.toVisibility(interface.visibility),
            name: try projection.toProtocolName(interface),
            typeParameters: interface.genericParams.map { $0.name }) { writer throws in
            for genericParam in interface.genericParams {
                writer.writeAssociatedType(name: genericParam.name)
            }

            for property in interface.properties {
                if let getter = try property.getter, getter.isPublic {
                    try writer.writeProperty(
                        static: property.isStatic,
                        name: projection.toMemberName(property),
                        type: projection.toType(property.type, referenceNullability: .none),
                        throws: true,
                        set: false)
                }

                if let setter = try property.setter, setter.isPublic {
                    try writer.writeFunc(
                        isPropertySetter: true,
                        static: property.isStatic,
                        name: projection.toMemberName(property),
                        parameters: [.init(label: "_", name: "newValue", type: projection.toType(property.type))],
                        throws: true)
                }
            }

            for method in interface.methods.filter({ $0.visibility == .public }) {
                guard !method.isAccessor else { continue }
                try writer.writeFunc(
                    static: method.isStatic,
                    name: projection.toMemberName(method),
                    typeParameters: method.genericParams.map { $0.name },
                    parameters: method.params.map(projection.toParameter),
                    throws: true,
                    returnType: projection.toReturnType(method.returnType))
            }
        }
    }

    private func writeProtocolTypeAlias(_ interface: InterfaceDefinition) throws {
        // For every "protocol IFoo", we generate a "typealias AnyIFoo = any IFoo"
        // This enables the shorter "AnyIFoo?" syntax instead of "(any IFoo)?" or "Optional<any IFoo>"
        sourceFileWriter.writeTypeAlias(
            visibility: SwiftProjection.toVisibility(interface.visibility),
            name: try projection.toTypeName(interface),
            typeParameters: interface.genericParams.map { $0.name },
            target: .identifier(
                protocolModifier: .existential,
                name: try projection.toProtocolName(interface),
                genericArgs: interface.genericParams.map { .identifier(name: $0.name) }))
    }

    private func writeClass(_ classDefinition: ClassDefinition) throws {
        try sourceFileWriter.writeClass(
            visibility: SwiftProjection.toVisibility(classDefinition.visibility, inheritableClass: !classDefinition.isSealed),
            final: classDefinition.isSealed,
            name: try projection.toTypeName(classDefinition),
            typeParameters: classDefinition.genericParams.map { $0.name },
            base: try projection.toBaseType(classDefinition.base),
            protocolConformances: try classDefinition.baseInterfaces.compactMap { try projection.toBaseType($0.interface) }) {
            writer throws in
            try writeTypeAliasesForBaseGenericArgs(of: classDefinition, to: writer)
            try writeFields(of: classDefinition, defaultInit: false, to: writer)
            try writeMembers(of: classDefinition, to: writer)
        }
    }

    private func writeStruct(_ structDefinition: StructDefinition) throws {
        try sourceFileWriter.writeStruct(
            visibility: SwiftProjection.toVisibility(structDefinition.visibility),
            name: try projection.toTypeName(structDefinition),
            typeParameters: structDefinition.genericParams.map { $0.name },
            protocolConformances: [ .identifier(name: "Hashable"), .identifier(name: "Codable") ]) { writer throws in

            try writeFields(of: structDefinition, defaultInit: true, to: writer)
            writer.writeInit(visibility: .public, parameters: []) { _ in } // Default initializer
            try writeFieldwiseInitializer(of: structDefinition, to: writer)
        }
    }

    private func writeEnumStruct(_ enumDefinition: EnumDefinition) throws {
        // Enums are syntactic sugar for integers in .NET,
        // so we cannot guarantee that the enumerants are exhaustive,
        // therefore we cannot project them to Swift enums
        // since they would be unable to represent unknown values.
        try sourceFileWriter.writeStruct(
            visibility: SwiftProjection.toVisibility(enumDefinition.visibility),
            name: try projection.toTypeName(enumDefinition),
            protocolConformances: [
                .identifier(name: enumDefinition.isFlags ? "OptionSet" : "RawRepresentable"),
                .identifier(name: "Hashable"),
                .identifier(name: "Codable") ]) { writer throws in

            let rawValueType = try projection.toType(enumDefinition.underlyingType.bindNode())
            writer.writeTypeAlias(visibility: .public, name: "RawValue", target: rawValueType)
            writer.writeStoredProperty(visibility: .public, name: "rawValue", type: rawValueType, initializer: "0")
            writer.writeInit(visibility: .public, parameters: []) { _ in } // Default initializer
            writer.writeInit(
                visibility: .public,
                parameters: [ .init(name: "rawValue", type:rawValueType) ]) {
                $0.output.write("self.rawValue = rawValue")
            }

            for field in enumDefinition.fields.filter({ $0.visibility == .public && $0.isStatic }) {
                let value = SwiftProjection.toConstant(try field.literalValue!)
                writer.writeStoredProperty(
                    visibility: .public,
                    static: true,
                    let: true,
                    name: projection.toMemberName(field),
                    type: .identifier(name: "Self", allowKeyword: true),
                    initializer: "Self(rawValue: \(value))")
            }
        }
    }

    private func writeFunctionTypeAlias(_ delegateDefinition: DelegateDefinition) throws {
        try sourceFileWriter.writeTypeAlias(
            visibility: SwiftProjection.toVisibility(delegateDefinition.visibility),
            name: try projection.toTypeName(delegateDefinition),
            typeParameters: delegateDefinition.genericParams.map { $0.name },
            target: .function(
                params: delegateDefinition.invokeMethod.params.map { try projection.toType($0.type) },
                throws: true,
                returnType: projection.toReturnType(delegateDefinition.invokeMethod.returnType) ?? SwiftType.void
            )
        )
    }

    fileprivate func writeTypeAliasesForBaseGenericArgs(of typeDefinition: TypeDefinition, to writer: SwiftRecordBodyWriter) throws {
        var baseTypes = try typeDefinition.baseInterfaces.map { try $0.interface }
        if let base = try typeDefinition.base {
            baseTypes.insert(base, at: 0)
        }

        var typeAliases: Collections.OrderedDictionary<String, SwiftType> = .init()
        for baseType in baseTypes {
            for (i, genericArg) in baseType.genericArgs.enumerated() {
                typeAliases[baseType.definition.genericParams[i].name] = try projection.toType(genericArg)
            }
        }

        for entry in typeAliases {
            writer.writeTypeAlias(visibility: .public, name: entry.key, typeParameters: [], target: entry.value)
        }
    }

    fileprivate func writeFields(of typeDefinition: TypeDefinition, defaultInit: Bool, to writer: SwiftRecordBodyWriter) throws {
        // FIXME: Rather switch on TypeDefinition to properly handle enum cases
        func getDefaultValue(_ type: SwiftType) -> String? {
            if case .optional = type { return "nil" }
            guard case .identifierChain(let chain) = type,
                chain.identifiers.count == 1 else { return nil }
            switch chain.identifiers[0].name {
                case "Bool": return "false"
                case "Int", "UInt", "Int8", "UInt8", "Int16", "UInt16", "Int32", "UInt32", "Int64", "UInt64": return "0"
                case "Float", "Double": return "0.0"
                case "String": return "\"\""
                default: return ".init()"
            }
        }

        for field in typeDefinition.fields {
            guard field.visibility == .public else { continue }

            // We can't generate non-const static fields
            let literalValue = try field.literalValue
            guard field.isInstance || literalValue != nil else { continue }

            let type = try projection.toType(field.type)
            writer.writeStoredProperty(
                visibility: SwiftProjection.toVisibility(field.visibility),
                static: field.isStatic,
                let: literalValue != nil,
                name: projection.toMemberName(field),
                type: type,
                initializer: literalValue.flatMap(SwiftProjection.toConstant) ?? (field.isInstance && defaultInit ? getDefaultValue(type) : nil))
        }
    }

    fileprivate func writeFieldwiseInitializer(of structDefinition: StructDefinition, to writer: SwiftRecordBodyWriter) throws {
        let params = try structDefinition.fields
            .filter { $0.visibility == .public && $0.isInstance }
            .map { SwiftParameter(name: projection.toMemberName($0), type: try projection.toType($0.type)) }
        guard !params.isEmpty else { return }

        writer.writeInit(visibility: .public, parameters: params) {
            for param in params {
                var lineWriter = $0.output
                lineWriter.write("self.")
                SwiftIdentifiers.write(param.name, to: &lineWriter)
                lineWriter.write(" = ")
                SwiftIdentifiers.write(param.name, to: &lineWriter)
                lineWriter.endLine()
            }
        }
    }

    fileprivate func writeMembers(of classDefinition: ClassDefinition, to writer: SwiftRecordBodyWriter) throws {
        for property in classDefinition.properties {
            if let getter = try property.getter, getter.isPublic {
                try writer.writeComputedProperty(
                    visibility: .public,
                    static: property.isStatic,
                    override: getter.isOverride,
                    name: projection.toMemberName(property),
                    type: projection.toType(property.type, referenceNullability: .none),
                    throws: true,
                    get: { $0.writeFatalError("Not implemented") },
                    set: nil)
            }

            if let setter = try property.setter, setter.isPublic {
                // Swift does not support throwing setters, so generate a method
                try writer.writeFunc(
                    visibility: .public,
                    static: property.isStatic,
                    override: setter.isOverride,
                    name: projection.toMemberName(property),
                    parameters: [.init(label: "_", name: "newValue", type: projection.toType(property.type, referenceNullability: .none))],
                    throws: true) {
                        $0.writeFatalError("Not implemented")
                    }
            }
        }

        for method in classDefinition.methods {
            guard SwiftProjection.toVisibility(method.visibility) == .public else { continue }
            guard !method.isAccessor else { continue }
            if let constructor = method as? Constructor {
                try writer.writeInit(
                    visibility: .public,
                    override: try projection.isOverriding(constructor),
                    parameters: method.params.map(projection.toParameter),
                    throws: true) { $0.writeFatalError("Not implemented") }
            }
            else {
                try writer.writeFunc(
                    visibility: .public,
                    static: method.isStatic,
                    override: method.isOverride,
                    name: projection.toMemberName(method),
                    typeParameters: method.genericParams.map { $0.name },
                    parameters: method.params.map(projection.toParameter),
                    throws: true,
                    returnType: projection.toReturnType(method.returnType)) { $0.writeFatalError("Not implemented") }
            }
        }
    }
}