import DotNetMD

extension CAbi {
    struct CType: ExpressibleByStringLiteral {
        public static let hresult = CType(name: "HRESULT")

        public static func pointer(to name: String) -> CType {
            .init(name: name, pointerIndirections: 1)
        }

        var name: String
        var pointerIndirections: Int = 0

        init(stringLiteral name: String) {
            self.name = name
        }

        init(name: String, pointerIndirections: Int = 0) {
            self.name = name
            self.pointerIndirections = pointerIndirections
        }

        public var pointerIndirected: CType { .init(name: name, pointerIndirections: pointerIndirections + 1) }
    }

    public static func toCType(_ type: BoundType) -> CType {
        if case let .definition(definition) = type {
            return CType(
                name: mangleName(typeDefinition: definition.definition, genericArgs: definition.genericArgs),
                pointerIndirections: definition.definition is EnumDefinition || definition.definition is StructDefinition ? 0 : 1)
        }
        else {
            fatalError("Not implemented")
        }
    }
}