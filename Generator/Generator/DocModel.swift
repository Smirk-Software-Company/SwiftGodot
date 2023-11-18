//
//  DocModel.swift
//  Generator
//
//  Created by Miguel de Icaza on 4/5/23.
//

import Foundation
import ExtensionApi
import XMLCoder

struct DocClass: Codable {
    @Attribute var name: String
    @Attribute var inherits: String?
    @Attribute var version: String?
    var brief_description: String
    var description: String
    var tutorials: [DocTutorial]
    // TODO: theme_items see HSplitContaienr
    var methods: DocMethods?
    var members: DocMembers?
    var signals: DocSignals?
    var constants: DocConstants?
}

struct DocBuiltinClass: Codable {
    @Attribute var name: String
    @Attribute var version: String?
    var brief_description: String
    var description: String
    var tutorials: [DocTutorial]
    var constructors: DocConstructors?
    var methods: DocMethods?
    var members: DocMembers?
    var constants: DocConstants?
    var operators: DocOperators?
}

struct DocConstructors: Codable {
    var constructor: [DocConstructor]
}

struct DocConstructor: Codable {
    @Attribute var name: String
    var `return`: [DocReturn]
    var description: String
    var param: [DocParam]
}

struct DocOperators: Codable {
    var `operator`: [DocOperator]
}

struct DocOperator: Codable {
    @Attribute var name: String
    var `return`: [DocReturn]
    var description: String
    var param: [DocParam]
}
struct DocTutorial: Codable {
    var link: [DocLink]
}

struct DocLink: Codable, Equatable {
    @Attribute var title: String
    let value: String
    
    enum CodingKeys: String, CodingKey {
        case title
        case value = ""
    }
}

struct DocMethods: Codable {
    var method: [DocMethod]
}

struct DocMethod: Codable {
    @Attribute var name: String
    @Attribute var qualifiers: String?
    var `return`: DocReturn?
    var description: String
    var params: [DocParam]
    
    enum CodingKeys: String, CodingKey {
        case name
        case qualifiers
        case `return`
        case description
        case params
    }
}

struct DocSignals: Codable {
    var signal: [DocSignal]
}

struct DocSignal: Codable {
    @Attribute var name: String
    var params: [DocParam]?
    var description: String
}

struct DocParam: Codable {
    @Attribute var index: Int
    @Attribute var name: String
    @Attribute var type: String
}

struct DocReturn: Codable {
    @Attribute var type: String
}

struct DocMembers: Codable {
    var member: [DocMember]
}

struct DocMember: Codable {
    @Attribute var name: String
    @Attribute var type: String
    @Attribute var setter: String
    @Attribute var getter: String
    @Attribute var `enum`: String?
    @Attribute var `default`: String?
    var value: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case type
        case setter
        case getter
        case `enum`
        case `default`
        case value = ""
    }
}

struct DocConstants: Codable {
    var constant: [DocConstant]
}

struct DocConstant: Codable {
    @Attribute var name: String
    @Attribute var value: String
    @Attribute var `enum`: String?
    let rest: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case value
        case `enum`
        case rest = ""
    }
}

func loadClassDoc (base: String, name: String) -> DocClass? {
    guard let d = try? Data(contentsOf: URL (fileURLWithPath: "\(base)/classes/\(name).xml")) else {
        return nil
    }
    let decoder = XMLDecoder()
    do {
        let v = try decoder.decode(DocClass.self, from: d)
        return v
    } catch (let e){
        print ("Failed to load docs for \(name), details: \(e)")
        return nil
    }
}

func loadBuiltinDoc (base: String, name: String) -> DocBuiltinClass? {
    guard let d = try? Data(contentsOf: URL (fileURLWithPath: "\(base)/classes/\(name).xml")) else {
        return nil
    }
    let decoder = XMLDecoder()
    do {
        let v = try decoder.decode(DocBuiltinClass.self, from: d)
        return v
    } catch (let e){
        print ("Failed to load docs for \(name), details: \(e)")
        return nil
    }
}

let rxConstantParam = try! NSRegularExpression(pattern: "\\[(constant|param) ([\\w\\._@]+)\\]")
let rxEnumMethodMember = try! NSRegularExpression(pattern: "\\[(enum|method|member) ([\\w\\.@_/]+)\\]")
let rxTypeName = try! NSRegularExpression(pattern: "\\[([A-Z]\\w+)\\]")
let rxEmptyLeading = try! NSRegularExpression(pattern: "\\s+")

// If the string contains a ".", it will return a pair
// with the first element containing all the text up until the last dot
// and the second with the rest.   If it does not contain it,
// the first value is an empty string

func splitAtLastDot (str: String.SubSequence) -> (String, String) {
    if let p = str.lastIndex(of: ".") {
        let first = String (str [str.startIndex..<p])
        let last = String (str [str.index(p, offsetBy: 1)...])
        return (String (first), String (last))
    } else {
        return ("", String (str))
    }
}

// Attributes to handle:
// [NAME] is a type reference
// [b]..[/b] bold
// [method name] is a method reference, should apply the remapping we do
// 
func doc (_ p: Printer, _ cdef: JClassInfo?, _ text: String?) {
    guard let text else { return }
//    guard ProcessInfo.processInfo.environment ["GENERATE_DOCS"] != nil else {
//        return
//    }
    
    func lookupConstant (_ txt: String.SubSequence) -> String {
        func lookInDef (def: JClassInfo, match: String, local: Bool) -> String? {
            // TODO: for builtins, we wont have a cdef
            for ed in def.enums ?? [] {
                for vp in ed.values {
                    if vp.name == match {
                        let name = dropMatchingPrefix(ed.name, vp.name)
                        if local {
                            return ".\(escapeSwift (name))"
                        } else {
                            return getGodotType(SimpleType (type: "enum::" + ed.name)) + "/" + escapeSwift (name)
                        }
                    }
                }
            }
            
            if let cdef = def as? JGodotExtensionAPIClass {
                for x in cdef.constants ?? [] {
                    if match == x.name {
                        return "``\(snakeToCamel (x.name))``"
                    }
                }
            }
            return nil
        }
        
        if let cdef {
            if let result = lookInDef(def: cdef, match: String(txt), local: true) {
                return result
            }
        }
        for ed in jsonApi.globalEnums {
            for ev in ed.values {
                if ev.name == txt {
                    var type = ""
                    var lookup = ed.name
                    if let dot = ed.name.lastIndex(of: ".") {
                        let containerType = String (ed.name [ed.name.startIndex..<dot])
                        type = getGodotType (SimpleType (type: containerType)) + "."
                        lookup = String (ed.name [ed.name.index(dot, offsetBy: 1)...])
                    }
                    let name = dropMatchingPrefix(lookup, ev.name)
                    
                    return "``\(type)\(getGodotType (SimpleType (type: lookup)))/\(escapeSwift(String (name)))``"
                }
            }
        }
        let (type, name) = splitAtLastDot(str: txt)
        if type != "", let ldef = classMap [type] {
            if let r = lookInDef(def: ldef, match: name, local: false) {
                return "``\(getGodotType(SimpleType (type: type)) + "/" + r)``"
            }
        }
        
        return "``\(txt)``"
    }
    
    // If this is a Type.Name returns "Type", "Name"
    // If this is Type it returns (nil, "Name")
    func typeSplit (txt: String.SubSequence) -> (String?, String) {
        if let dot = txt.firstIndex(of: ".") {
            let rest = String (txt [text.index(dot, offsetBy: 1)...])
            return (String (txt [txt.startIndex..<dot]), rest)
        }
        
        return (nil, String (txt))
    }

    func assembleArgs (_ optMethod: JGodotClassMethod?, _ arguments: [JGodotArgument]?) -> String {
        var args = ""
        
        // Assemble argument names
        var i = 0
        for arg in arguments ?? [] {
            if optMethod != nil && i == 0 && optMethod!.name.hasSuffix(arg.name) {
                args.append ("_")
            } else {
                args.append(godotArgumentToSwift(arg.name))
            }
            args.append(":")
            i += 1
        }
        return args
    }
    
    func convertMethod (_ txt: String.SubSequence) -> String {
        if txt.starts(with: "@") {
            // TODO, examples:
            // @GlobalScope.remap
            // @GDScript.load

            return String (txt)
        }
        
        func findMethod (name: String, on: JGodotExtensionAPIClass) -> JGodotClassMethod? {
            on.methods?.first(where: { x in x.name == name })
        }
        func findMethod (name: String, on: JGodotBuiltinClass) -> JGodotBuiltinClassMethod? {
            on.methods?.first(where: { x in x.name == name })
        }
        
        let (type, member) = typeSplit(txt: txt)
        
        var args = ""
        if let type {
            if let m = classMap [type] {
                if let method = findMethod (name: member, on: m) {
                    args = assembleArgs (method, method.arguments)
                }
            } else if let m = builtinMap [type] {
                if let method = findMethod (name: member, on: m) {
                    args = assembleArgs(nil, method.arguments)
                }
            }
            return "\(type)/\(godotMethodToSwift(member))(\(args))"
        } else {
            if let apiDef = cdef as? JGodotExtensionAPIClass {
                if let method = findMethod(name: member, on: apiDef) {
                    args = assembleArgs (method, method.arguments)
                }
            } else if let builtinDef = cdef as? JGodotBuiltinClass {
                if let method = findMethod(name: member, on: builtinDef) {
                    args = assembleArgs (nil, method.arguments)
                }
            }
        }
          
        
        return "\(godotMethodToSwift(member))(\(args))"
    }

    func convertMember (_ txt: String.SubSequence) -> String {
        let (type, member) = typeSplit(txt: txt)
        if let type {
            return "\(type)/\(godotMethodToSwift(member))"
        }
        return godotPropertyToSwift(member)
    }

    let oIndent = p.indentStr
    p.indentStr = "\(p.indentStr)/// "
    
    // Helper function to perform regex replacement
    func performRegexReplacement(regex: NSRegularExpression, in string: Substring, using transform: (NSTextCheckingResult) -> String) -> Substring {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        let matches = regex.matches(in: String(string), range: range)
        
        var modifiedString = string
        for match in matches.reversed() { // Process in reverse to not mess up indices
            let matchedString = String(string[Range(match.range, in: string)!])
            let replacement = transform(match)
            modifiedString.replaceSubrange(Range(match.range, in: modifiedString)!, with: replacement)
        }
        return modifiedString
    }
    
    var inCodeBlock = false
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for x in lines {
        if x.contains ("[codeblock") {
            inCodeBlock = true
            continue
        }
        if x.contains ("[/codeblock") {
            inCodeBlock = false
            continue
        }
        if inCodeBlock { continue }
        
        var mod = x
        
        // Replaces [params X] with `X`
        mod = performRegexReplacement(regex: rxConstantParam, in: mod) { match in
            guard let rangeType = Range(match.range(at: 1), in: mod),
                  let rangeValue = Range(match.range(at: 2), in: mod) else { return "" }
            
            let type = String(mod[rangeType])
            let value = mod[rangeValue]
            
            switch type {
            case "param":
                let pname = godotArgumentToSwift (String(value))
                if pname.starts(with: "`") {
                    // Do not escape parameters that are already escaped, Swift wont know
                    return pname
                }
                return "`\(pname)`"
            case "constant":
                return lookupConstant(value)
            default:
                print("Doc: Error, unexpected \(type) tag")
                return "[\(type) \(value)]"
            }
        }
        mod = performRegexReplacement(regex: rxEnumMethodMember, in: mod) { match in
            guard let rangeType = Range(match.range(at: 1), in: mod),
                  let rangeValue = Range(match.range(at: 2), in: mod) else { return "" }
            
            let type = String(mod[rangeType])
            let value = mod[rangeValue]
            
            switch type {
            case "method":
                return "``\(convertMethod (value))``"
            case "member":
                // Same as method for now?
                return "``\(convertMember(value))``"
            case "enum":
                if let cdef {
                    if let enums = cdef.enums {
                        // If it is a local enum
                        if enums.contains(where: { $0.name == value }) {
                            return "``\(cdef.name)/\(value)``"
                        }
                    }
                }
                return "``\(getGodotType(SimpleType(type: "enum::" + value)))``"
                
            default:
                print("Doc: Error, unexpected \(type) tag")
                return "[\(type) \(value)]"
            }
        }
        
        // [FirstLetterIsUpperCase] is a reference to a type
        mod = performRegexReplacement(regex: rxTypeName, in: mod) { match in
            guard let rangeWord = Range(match.range(at: 1), in: mod) else { return "" }
            let word = mod[rangeWord]
            return "``\(mapTypeNameDoc (String (word)))``"
        }
        
        // To avoid the greedy problem, it happens above, but not as much
        mod = Substring(mod.replacingOccurrences(of: "[b]Note:[/b]", with: "> Note:"))
        mod = Substring(mod.replacingOccurrences(of: "[int]", with: "integer"))
        mod = Substring(mod.replacingOccurrences(of: "[float]", with: "float"))
        
        mod = Substring(mod.replacingOccurrences(of: "[b]Warning:[/b]", with: "> Warning:"))
        mod = Substring(mod.replacingOccurrences(of: "[i]", with: "_"))
        mod = Substring(mod.replacingOccurrences(of: "[/i]", with: "_"))
        mod = Substring(mod.replacingOccurrences(of: "[b]", with: "**"))
        mod = Substring(mod.replacingOccurrences(of: "[/b]", with: "**"))
        mod = Substring(mod.replacingOccurrences(of: "[code]", with: "`"))
        mod = Substring(mod.replacingOccurrences(of: "[/code]", with: "`"))
        
        let range = NSRange(mod.startIndex..<mod.endIndex, in: mod)
        if let match = rxEmptyLeading.firstMatch(in: String(mod), range: range), match.range.location == 0 {
            mod.removeSubrange(mod.startIndex..<Range(match.range, in: mod)!.upperBound)
        }
        // TODO
        // [member X]
        // [signal X]
        
        if lines.count > 1 {
            p (String (mod)+"\n")
        } else {
            p (String (mod))
        }
    }
    p.indentStr = oIndent
}
