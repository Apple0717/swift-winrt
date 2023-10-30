import CodeWriters
import DotNetMetadata

extension SwiftAssemblyModuleFileWriter {
    internal func writeDelegate(_ delegateDefinition: DelegateDefinition) throws {
        try sourceFileWriter.writeTypeAlias(
            visibility: SwiftProjection.toVisibility(delegateDefinition.visibility),
            name: try projection.toTypeName(delegateDefinition),
            typeParameters: delegateDefinition.genericParams.map { $0.name },
            target: .function(
                params: delegateDefinition.invokeMethod.params.map { try projection.toType($0.type) },
                throws: true,
                returnType: projection.toReturnType(delegateDefinition.invokeMethod.returnType)
            )
        )
    }

    internal func writeDelegateProjection(_ delegateDefinition: DelegateDefinition, genericArgs: [TypeNode]?) throws {
        if delegateDefinition.genericArity == 0 {
            // class AsyncActionCompletedHandlerProjection: WinRTProjection... {}
            try writeDelegateProjection(delegateDefinition.bind(),
                projectionName: projection.toProjectionTypeName(delegateDefinition),
                to: sourceFileWriter)
        }
        else if let genericArgs {
            // extension AsyncOperationCompletedHandlerProjection {
            //     internal final class Boolean: WinRTProjection... {}
            // }
            try sourceFileWriter.writeExtension(
                    name: projection.toProjectionTypeName(delegateDefinition)) { writer in
                try writeDelegateProjection(delegateDefinition.bind(genericArgs: genericArgs),
                    projectionName: try projection.toProjectionInstanciationTypeName(genericArgs: genericArgs),
                    to: sourceFileWriter)
            }
        }
        else {
            // public enum AsyncOperationCompletedHandlerProjection {}
            try sourceFileWriter.writeEnum(
                visibility: SwiftProjection.toVisibility(delegateDefinition.visibility),
                name: projection.toProjectionTypeName(delegateDefinition)) { _ in }
        }
    }

    fileprivate func writeDelegateProjection(
            _ delegate: BoundDelegate, projectionName: String,
            to writer: some SwiftDeclarationWriter) throws {
        try writer.writeClass(
                visibility: SwiftProjection.toVisibility(delegate.definition.visibility),
                final: true, name: projectionName,
                base: .identifier("WinRTDelegateProjectionBase", genericArgs: [.identifier(projectionName)]),
                protocolConformances: [.identifier("COMTwoWayProjection")]) { writer throws in 

            try writeWinRTProjectionConformance(interfaceOrDelegate: delegate.asBoundType, to: writer)

            // public var swiftObject: Projection.SwiftObject { invoke }
            writer.writeComputedProperty(
                visibility: .public, override: true, name: "swiftObject",
                type: .identifier("SwiftObject"),
                get: { $0.writeStatement("invoke") })

            // The only member should be an "invoke()" method
            try writeMemberImplementations(
                interfaceOrDelegate: delegate.asBoundType,
                thisPointer: .name("comPointer"), to: writer)

            // public static var virtualTablePointer: COMVirtualTablePointer { withUnsafePointer(to: &virtualTable) { $0 } }
            // TODO: Actually generate a virtual table struct
            writer.writeComputedProperty(visibility: .public, static: true, name: "virtualTablePointer",
                type: .identifier("COMVirtualTablePointer"), throws: false,
                get: { $0.writeNotImplemented() })
        }
    }
}