import DotNetMetadata
import CodeWriters
import Collections

extension SwiftProjection {
    func writeModule(_ module: Module, outputDirectoryPath: String) {
        for (namespace, types) in module.typesByNamespace {
            let compactNamespace = namespace == "" ? "global" : SwiftProjection.toCompactNamespace(namespace)
            print("Writing \(module.name)/compactNamespace.swift...")

            let path = "\(outputDirectoryPath)\\\(compactNamespace).swift"
            let sourceFileWriter = SwiftSourceFileWriter(output: FileTextOutputStream(path: path))

            sourceFileWriter.output.writeLine("// Generated by swift-winrt")
            sourceFileWriter.output.writeLine("// swiftlint:disable all")

            for reference in module.references {
                sourceFileWriter.writeImport(module: reference.target.name)
            }

            sourceFileWriter.writeImport(module: "Foundation", struct: "UUID")

            for typeDefinition in types.sorted(by: { $0.fullName < $1.fullName }) {
                guard typeDefinition.visibility == .public else { continue }
                if let interfaceDefinition = typeDefinition as? InterfaceDefinition {
                    writeProtocol(interfaceDefinition, to: sourceFileWriter)
                }
                else {
                    writeTypeDefinition(typeDefinition, to: sourceFileWriter)
                }
            }
        }
    }

    fileprivate func writeTypeDefinition(_ typeDefinition: TypeDefinition, to writer: some SwiftTypeDeclarationWriter) {
        let visibility = Self.toVisibility(typeDefinition.visibility)
        if let classDefinition = typeDefinition as? ClassDefinition {
            // Do not generate Attribute classes since they are compile-time constructs
            if classDefinition.base?.definition.fullName == "System.Attribute" {
                return
            }

            writer.writeClass(
                visibility: visibility == .public && !typeDefinition.isSealed ? .open : .public,
                final: typeDefinition.isSealed,
                name: toTypeName(typeDefinition),
                typeParameters: typeDefinition.genericParams.map { $0.name },
                base: toBaseType(typeDefinition.base),
                protocolConformances: typeDefinition.baseInterfaces.compactMap { toBaseType($0.interface) }) { writer in

                writeTypeAliasesForBaseGenericArgs(of: classDefinition, to: writer)
                writeFields(of: classDefinition, defaultInit: false, to: writer)
                writeMembers(of: classDefinition, to: writer)
            }
        }
        else if let structDefinition = typeDefinition as? StructDefinition {
            // WinRT structs are PODs and cannot implement interfaces
            writer.writeStruct(
                visibility: visibility,
                name: toTypeName(structDefinition),
                typeParameters: structDefinition.genericParams.map { $0.name },
                protocolConformances: [ .identifier(name: "Hashable"), .identifier(name: "Codable") ]) { writer in

                writeFields(of: structDefinition, defaultInit: true, to: writer)
                writer.writeInit(visibility: .public, parameters: []) { _ in } // Default initializer
                writeFieldwiseInitializer(of: structDefinition, to: writer)
            }
        }
        else if let enumDefinition = typeDefinition as? EnumDefinition {
            // Enums are syntactic sugar for integers in .NET,
            // so we cannot guarantee that the enumerants are exhaustive,
            // therefore we cannot project them to Swift enums
            // since they would be unable to represent unknown values.
            writer.writeStruct(
                visibility: visibility,
                name: toTypeName(enumDefinition),
                protocolConformances: [
                    .identifier(name: enumDefinition.isFlags ? "OptionSet" : "RawRepresentable"),
                    .identifier(name: "Hashable"),
                    .identifier(name: "Codable") ]) { writer in

                let rawValueType = try! toType(enumDefinition.underlyingType.bindNode())
                writer.writeTypeAlias(visibility: .public, name: "RawValue", target: rawValueType)
                writer.writeStoredProperty(visibility: .public, name: "rawValue", type: rawValueType, initializer: "0")
                writer.writeInit(visibility: .public, parameters: []) { _ in } // Default initializer
                writer.writeInit(
                    visibility: .public,
                    parameters: [ .init(name: "rawValue", type:rawValueType) ]) {
                    $0.output.write("self.rawValue = rawValue")
                }

                for field in enumDefinition.fields.filter({ $0.visibility == .public && $0.isStatic }) {
                    let value = Self.toConstant(try! field.literalValue!)
                    writer.writeStoredProperty(
                        visibility: .public,
                        static: true,
                        let: true,
                        name: toMemberName(field),
                        type: .identifier(name: "Self", allowKeyword: true),
                        initializer: "Self(rawValue: \(value))")
                }
            }
        }
        else if let delegateDefinition = typeDefinition as? DelegateDefinition {
            try? writer.writeTypeAlias(
                visibility: visibility,
                name: toTypeName(typeDefinition),
                typeParameters: delegateDefinition.genericParams.map { $0.name },
                target: .function(
                    params: delegateDefinition.invokeMethod.params.map { toType($0.type) },
                    throws: true,
                    returnType: toType(delegateDefinition.invokeMethod.returnType)
                )
            )
        }
    }

    fileprivate func writeTypeAliasesForBaseGenericArgs(of typeDefinition: TypeDefinition, to writer: SwiftRecordBodyWriter) {
        var baseTypes = typeDefinition.baseInterfaces.map { $0.interface }
        if let base = typeDefinition.base {
            baseTypes.insert(base, at: 0)
        }

        var typeAliases: Collections.OrderedDictionary<String, SwiftType> = .init()
        for baseType in baseTypes {
            for (i, genericArg) in baseType.genericArgs.enumerated() {
                typeAliases[baseType.definition.genericParams[i].name] = toType(genericArg)
            }
        }

        for entry in typeAliases {
            writer.writeTypeAlias(visibility: .public, name: entry.key, typeParameters: [], target: entry.value)
        }
    }

    fileprivate func writeFields(of typeDefinition: TypeDefinition, defaultInit: Bool, to writer: SwiftRecordBodyWriter) {
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
            let literalValue = try? field.literalValue
            guard field.isInstance || literalValue != nil else { continue }

            let type = try! toType(field.type)
            writer.writeStoredProperty(
                visibility: Self.toVisibility(field.visibility),
                static: field.isStatic,
                let: literalValue != nil,
                name: toMemberName(field),
                type: type,
                initializer: literalValue.flatMap(Self.toConstant) ?? (field.isInstance && defaultInit ? getDefaultValue(type) : nil))
        }
    }

    fileprivate func writeFieldwiseInitializer(of structDefinition: StructDefinition, to writer: SwiftRecordBodyWriter) {
        let params = try! structDefinition.fields
            .filter { $0.visibility == .public && $0.isInstance }
            .map { SwiftParameter(name: toMemberName($0), type: toType(try $0.type)) }
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

    fileprivate func writeMembers(of classDefinition: ClassDefinition, to writer: SwiftRecordBodyWriter) {
        for property in classDefinition.properties {
            guard Self.toVisibility(property.visibility) == .public else { continue }
            let setter = try? property.setter
            try? writer.writeComputedProperty(
                visibility: .public,
                static: property.isStatic,
                override: (try? property.getter)?.isOverride ?? false,
                name: toMemberName(property),
                type: toType(property.type, allowImplicitUnwrap: true),
                throws: setter == nil, // Swift has no syntax for get + set with throws
                get: { $0.writeFatalError("Not implemented") },
                set: setter == nil ? nil : { $0.writeFatalError("Not implemented") })
        }

        for method in classDefinition.methods {
            guard Self.toVisibility(method.visibility) == .public else { continue }
            guard !method.isAccessor else { continue }
            if let constructor = method as? Constructor {
                try? writer.writeInit(
                    visibility: .public,
                    override: (try? isOverriding(constructor)) ?? false,
                    parameters: method.params.map(toParameter),
                    throws: true) { $0.writeFatalError("Not implemented") }
            }
            else {
                try? writer.writeFunc(
                    visibility: .public,
                    static: method.isStatic,
                    override: method.isOverride,
                    name: toMemberName(method),
                    typeParameters: method.genericParams.map { $0.name },
                    parameters: method.params.map(toParameter),
                    throws: true,
                    returnType: toReturnType(method.returnType)) { $0.writeFatalError("Not implemented") }
            }
        }
    }

    fileprivate func writeProtocol(_ interface: InterfaceDefinition, to writer: SwiftSourceFileWriter) {
        writer.writeProtocol(
            visibility: Self.toVisibility(interface.visibility),
            name: toTypeName(interface),
            typeParameters: interface.genericParams.map { $0.name }) { writer in
            for genericParam in interface.genericParams {
                writer.writeAssociatedType(name: genericParam.name)
            }

            for property in interface.properties.filter({ $0.visibility == .public }) {
                try? writer.writeProperty(
                    static: property.isStatic,
                    name: toMemberName(property),
                    type: toType(property.type, allowImplicitUnwrap: true),
                    throws: property.setter == nil,
                    set: property.setter != nil)
            }

            for method in interface.methods.filter({ $0.visibility == .public }) {
                guard !method.isAccessor else { continue }
                try? writer.writeFunc(
                    static: method.isStatic,
                    name: toMemberName(method),
                    typeParameters: method.genericParams.map { $0.name },
                    parameters: method.params.map(toParameter),
                    throws: true,
                    returnType: toReturnType(method.returnType))
            }
        }

        // For every "protocol IFoo", we generate a "typealias AnyIFoo = any IFoo"
        // This enables the shorter "AnyIFoo?" syntax instead of "(any IFoo)?" or "Optional<any IFoo>"
        writer.writeTypeAlias(
            visibility: Self.toVisibility(interface.visibility),
            name: toTypeName(interface, any: true),
            typeParameters: interface.genericParams.map { $0.name },
            target: .identifier(
                protocolModifier: .existential,
                name: toTypeName(interface),
                genericArgs: interface.genericParams.map { .identifier(name: $0.name) }))
    }
}

extension Method {
    var isAccessor: Bool {
        let prefixes = [ "get_", "set_", "put_", "add_", "remove_"]
        return prefixes.contains(where: { name.starts(with: $0) })
    }
}