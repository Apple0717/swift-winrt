import CodeWriters
import DotNetMetadata
import DotNetMetadataFormat
import Foundation
import ArgumentParser

@main
struct EntryPoint: ParsableCommand {
    @Option(name: .customLong("reference"), help: "A path to a .winmd file with the APIs to project.")
    var references: [String] = []

    @Option(help: "A Windows SDK version with the APIs to project.")
    var sdk: String? = nil

    @Option(name: .customLong("module-map"), help: "A path to a module map json file to use.")
    var moduleMap: String? = nil

    @Option(help: "A path to the output directory.")
    var out: String

    mutating func run() throws {
        var allReferences = Set(references)
        if let sdk {
            allReferences.insert("C:\\Program Files (x86)\\Windows Kits\\10\\UnionMetadata\\\(sdk)\\Windows.winmd")
        }

        let moduleMap: ModuleMapFile?
        if let moduleMapPath = self.moduleMap {
            moduleMap = try JSONDecoder().decode(ModuleMapFile.self, from: Data(contentsOf: URL(fileURLWithPath: moduleMapPath)))
        }
        else {
            moduleMap = nil
        }

        // Resolve the mscorlib dependency from the .NET Framework 4 machine installation
        struct AssemblyLoadError: Error {}
        let context = AssemblyLoadContext(resolver: {
            guard $0.name == "mscorlib", let mscorlibPath = SystemAssemblies.DotNetFramework4.mscorlibPath else { throw AssemblyLoadError() }
            return try ModuleFile(path: mscorlibPath)
        })

        let swiftProjection = SwiftProjection()
        var typeGraphWalker = TypeGraphWalker(
            filter: {
                $0.namespace?.starts(with: "System.") != true && (try? $0.base?.definition.fullName) != "System.Attribute"
            },
            publicMembersOnly: true)

        // Gather types from all referenced assemblies
        for reference in allReferences {
            let assembly = try context.load(path: reference)

            let (moduleName, moduleMapping) = Self.getModule(assemblyName: assembly.name, moduleMapFile: moduleMap)
            let module = swiftProjection.modulesByName[moduleName] ?? swiftProjection.addModule(moduleName)
            module.addAssembly(assembly)

            print("Gathering types from \(assembly.name)...")
            for typeDefinition in assembly.definedTypes {
                if typeDefinition.visibility == .public && Self.isIncluded(fullName: typeDefinition.fullName, filters: moduleMapping?.includeFilters) {
                    try typeGraphWalker.walk(typeDefinition)
                }
            }
        }

        // Classify types into modules
        print("Classifying types into modules...")
        for typeDefinition in typeGraphWalker.definitions {
            guard !(typeDefinition.assembly is Mscorlib) else { continue }

            let module: SwiftProjection.Module
            if let existingModule = swiftProjection.assembliesToModules[typeDefinition.assembly] {
                module = existingModule
            }
            else {
                let (moduleName, _) = Self.getModule(assemblyName: typeDefinition.assembly.name, moduleMapFile: moduleMap)
                module = swiftProjection.addModule(moduleName)
                module.addAssembly(typeDefinition.assembly)
            }

            module.addType(typeDefinition)
        }

        // Establish references between modules
        for assembly in context.loadedAssembliesByName.values {
            guard !(assembly is Mscorlib) else { continue }

            if let sourceModule = swiftProjection.assembliesToModules[assembly] {
                for reference in assembly.references {
                    if let targetModule = swiftProjection.assembliesToModules[try reference.resolve()] {
                        sourceModule.addReference(targetModule)
                    }
                }
            }
        }

        for module in swiftProjection.modulesByName.values {
            let moduleRootPath = "\(out)\\\(module.name)"
            let assemblyModuleDirectoryPath = "\(moduleRootPath)\\Assembly"
            try FileManager.default.createDirectory(atPath: assemblyModuleDirectoryPath, withIntermediateDirectories: true)

            // For each namespace
            for (namespace, types) in module.typesByNamespace {
                let compactNamespace = namespace == "" ? "global" : SwiftProjection.toCompactNamespace(namespace)
                print("Writing \(module.name)/\(compactNamespace).swift...")

                let definitionsPath = "\(assemblyModuleDirectoryPath)\\\(compactNamespace).swift"
                let projectionsPath = "\(assemblyModuleDirectoryPath)\\\(compactNamespace)+Projections.swift"
                let namespaceModuleDirectoryPath = "\(moduleRootPath)\\Namespaces\\\(compactNamespace)"
                let namespaceAliasesPath = "\(namespaceModuleDirectoryPath)\\Aliases.swift"
                try FileManager.default.createDirectory(atPath: namespaceModuleDirectoryPath, withIntermediateDirectories: true)

                let definitionsWriter = SwiftAssemblyModuleFileWriter(path: definitionsPath, module: module)
                let _ = SwiftAssemblyModuleFileWriter(path: projectionsPath, module: module)
                let aliasesWriter = SwiftNamespaceModuleFileWriter(path: namespaceAliasesPath, module: module)
                for typeDefinition in types.sorted(by: { $0.fullName < $1.fullName }) {
                    try definitionsWriter.writeTypeDefinition(typeDefinition)
                    try aliasesWriter.writeAlias(typeDefinition)
                }
            }
        }
    }

    static func getModule(assemblyName: String, moduleMapFile: ModuleMapFile?) -> (name: String, mapping: ModuleMapFile.Module?) {
        if let moduleMapFile {
            for (moduleName, module) in moduleMapFile.modules {
                if module.assemblies.contains(assemblyName) {
                    return (moduleName, module)
                }
            }
        }

        return (assemblyName, nil)
    }

    static func isIncluded(fullName: String, filters: [String]?) -> Bool {
        guard let filters else { return true }

        for filter in filters {
            if filter.last == "*" {
                if fullName.starts(with: filter.dropLast()) {
                    return true
                }
            }
            else if fullName == filter {
                return true
            }
        }

        return false
    }
}

// let cabiWriter = CAbi.SourceFileWriter(output: StdoutOutputStream())

// for typeDefinition in assembly.definedTypes {
//     guard typeDefinition.namespace == namespace,
//         typeDefinition.visibility == .public,
//         typeDefinition.genericParams.isEmpty else { continue }

//     if let structDefinition = typeDefinition as? StructDefinition {
//         try? cabiWriter.writeStruct(structDefinition)
//     }
//     else if let enumDefinition = typeDefinition as? EnumDefinition {
//         try? cabiWriter.writeEnum(enumDefinition)
//     }
//     else if let interfaceDefinition = typeDefinition as? InterfaceDefinition {
//         try? cabiWriter.writeInterface(interfaceDefinition, genericArgs: [])
//     }
// }