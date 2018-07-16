import Foundation
import Commander

//: - Private Interface

let fileManager = FileManager()
private var verbose = false
func vprint(_ thing: Any) {
  if (verbose) {
    print(thing)
  }
}

struct Tag {
    let name: String
    let attributes: [String: String]
}

class Parser: NSObject, XMLParserDelegate {
    static let parserManager = FileManager()

    let xmlParser: XMLParser
    let outputStream: OutputStream
    let from: URL
    let to: URL
    let key: String
    let createdDate: Date
    let modifiedDate: Date
    let appendMeta: Bool
    let completionHandler: (String) -> Void

    private var writingBegan = false
    private var waitingForTitle = false
    private var title: String?
    private var keywords = ""
    private var attachments = ""
    private var tags: [Tag] = []
    private var currentTag: Tag? {
        return tags.last
    }
    private var currentLink: String = ""

    init?(key: String, from url: URL, to destination: String,
          createdDate: Date, modifiedDate: Date, appendMeta: Bool,
          completionHandler: @escaping (String) -> Void) {
        guard let parser = XMLParser(contentsOf: url), let outputStream = OutputStream(toFileAtPath: destination, append: false) else {
            return nil
        }
        self.key = key
        self.from = url
        self.to = URL(fileURLWithPath: destination)
        self.xmlParser = parser
        self.outputStream = outputStream
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.appendMeta = appendMeta
        self.completionHandler = completionHandler
        super.init()
        self.xmlParser.delegate = self
    }

    func parse() -> Bool {
        return self.xmlParser.parse()
    }

    func parserDidStartDocument(_ parser: XMLParser) {
        self.outputStream.open()
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        if self.appendMeta {
            self.writeEndMatter()
        }
        self.outputStream.close()

        var wroteTo = self.to

        if let title = self.title {
            let cleanTitle = title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\\", with: "")
                .replacingOccurrences(of: ":", with: " - ")
            let destination = self.to.deletingLastPathComponent().appendingPathComponent(cleanTitle).appendingPathExtension("markdown")
            do {
                try Parser.parserManager.moveItem(atPath: self.to.path, toPath: destination.path.removingPercentEncoding ?? destination.path)
                wroteTo = destination
            }
            catch(let error) {
                vprint("Error exporting \(wroteTo): \(error)")
            }
        }

        vprint("Exported \(wroteTo)")
        try? Parser.parserManager.setAttributes([
            FileAttributeKey.creationDate: self.createdDate,
            FileAttributeKey.modificationDate: self.modifiedDate
            ], ofItemAtPath: wroteTo.path)

        self.completionHandler(self.key)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print("Error during parse: \(parseError)")
        print("In parser: \(key)")
        print("Parsing \(self.from)")
        print("To \(self.to)")
        self.outputStream.close()
        self.completionHandler(self.key)
        fatalError()
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        self.tags.append(Tag(name: elementName, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "element" && currentTag?.attributes["kind"] == "link" {
            self.currentLink = ""
        }
        else if elementName == "p" {
            waitingForTitle = false
            writeString("\n")
        }
        else if elementName == "tag" &&
            currentTag?.attributes["kind"]?.starts(with: "heading") ?? false &&
            !writingBegan {
            waitingForTitle = true
        }
        self.tags.removeLast()
    }

    func parser(_ parser: XMLParser,
                foundCharacters string: String) {
        let currentKind = currentTag?.attributes["kind"]
        let parent = tags.count >= 2 ? tags[tags.count - 2] : nil

        switch currentTag?.name {
        case "p":
            if waitingForTitle {
                self.title = (self.title ?? "").appending(string)
            }
            writingBegan = true
            writeString(string)
        case "tag":
            writeString(string)
        case "attribute" where currentTag?.attributes["identifier"] == "URL":
            self.currentLink.append(contentsOf: string)
        case "attribute" where currentTag?.attributes["identifier"] == "title" &&
            (parent?.attributes["kind"] == "link" || parent?.attributes["kind"] == "image"):
            break
        case "attribute" where currentTag?.attributes["identifier"] == "image" &&
            parent?.attributes["kind"] == "image":
            writeString("(image with ID \(string))")
            break
        case "element" where currentKind == "link":
            writeString("[\(string)](\(self.currentLink))")
        case "element" where currentKind == "strong":
            writeString("**\(string)**")
        case "element" where currentKind == "emph":
            writeString("_\(string)_")
        case "element" where currentKind == "code":
            writeString("`\(string)`")
        case "element" where currentKind == "inlineNative":
            writeString("```\(string)```")
        case "element" where currentKind == "delete":
            writeString("~~\(string)~~")
        case "element" where currentKind == "annotation":
            writeString("\(string): ")
        case "attachment" where currentTag?.attributes["type"] == "keywords":
            keywords += string
        case "attachment" where currentTag?.attributes["type"] == "file":
            attachments += string
        case "escape":
            let unescaped = string.replacingOccurrences(of: "\\", with: "")
            if (parent?.attributes["kind"] == "link") {
                self.currentLink.append(contentsOf: unescaped)
            }
            else {
                writeString(unescaped)
            }
        case "sheet", "markup", "string":
            break
        default:
            print("UNKNOWN TAG: \(currentTag?.name ?? "NONE")");
            print(currentTag?.attributes ?? [:])
            print("PARENT: \(parent?.name ?? "NONE")")
            print(parent?.attributes ?? [:])
            fatalError("unknown tag")
            break
        }
    }

    private func writeString(_ string: String) {
        let dataArray = [UInt8](string.utf8)
        self.outputStream.write(dataArray, maxLength: dataArray.count)
    }

    private func writeEndMatter() {
        let endMatter = """
        \n\n
        --- Exported from Ulysses on \(Date()) ---
        KEYWORDS: \(self.keywords)
        ATTACHMENTS: \(self.attachments)
        CREATED DATE: \(DateFormatter.localizedString(from: self.createdDate, dateStyle: .long, timeStyle: .long))
        MODIFIED DATE: \(DateFormatter.localizedString(from: self.modifiedDate, dateStyle: .long, timeStyle: .long))
        """

        writeString(endMatter)
    }
}

var sheetTotal = 0;
var parsers: [String: Parser] = [:]
let KeysToFetch: [URLResourceKey] = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]

func crawl(_ url: URL, output: String, preservingFolders: Bool = false, withMeta: Bool = true, onFoundDirectory: ((String) -> Void)? = nil) {
    vprint("Scanning \(url)...")
    let outputURL = URL(fileURLWithPath: output)
    let resourceValues = try? url.resourceValues(forKeys: Set(KeysToFetch))
    let isDirectory = resourceValues?.isDirectory ?? false
    if isDirectory, let results = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: KeysToFetch) {

        // If directory is a sheet
        if url.pathExtension == "ulysses" {
            let fileName = url.deletingPathExtension().lastPathComponent
            let key = UUID().uuidString
            let from = url.appendingPathComponent("Content.xml")
            let to = outputURL.appendingPathComponent("\(fileName).markdown")
            let createdDate = resourceValues?.creationDate ?? Date()
            let modifiedDate = resourceValues?.contentModificationDate ?? Date()
            let onComplete = { key in
                parsers[key] = nil
            }

            let parser = Parser(
                key: key,
                from: from,
                to: to.path,
                createdDate: createdDate,
                modifiedDate: modifiedDate,
                appendMeta: withMeta,
                completionHandler: onComplete
            )

            if let parser = parser {
                parsers[key] = parser
                let parseStarted = parser.parse()
                if (parseStarted) {
                    sheetTotal += 1

                    if (sheetTotal % 500 == 0) {
                        print("Exported \(sheetTotal) sheets.")
                    }
                }
            }
        }
        else if results.count == 1 && results[0].lastPathComponent == "Info.ulfilter" {
            // TODO: Handle filters?
        }
        else {
            var name = url.lastPathComponent
            if let plist = NSDictionary(contentsOfFile: url.appendingPathComponent("Info.ulgroup").path) {
                if let displayName = plist["DisplayName"] as? String {
                    name = displayName
                }
                else if let displayName = plist["displayName"] as? String {
                    name = displayName
                }
                else {
                    name = "Inbox" // Plist without displayName maps to Inbox
                }
            }

            let newOutput = preservingFolders ? outputURL.appendingPathComponent(name) : outputURL
            try? fileManager.createDirectory(at: newOutput, withIntermediateDirectories: true, attributes: nil)
            let newOutputPath = newOutput.path

            onFoundDirectory?(newOutputPath)

            for item in results {
                crawl(item, output: newOutputPath, preservingFolders: preservingFolders, withMeta: withMeta, onFoundDirectory: onFoundDirectory)
            }
        }
    }
}

func run(_ input: String, _ output: String, keepGroups: Bool, skipMeta: Bool) {
    print("Starting export...")

    // Prep input and output
    let inputURL = URL(fileURLWithPath: input)
    let outputURL = URL(fileURLWithPath: output)
    try? fileManager.createDirectory(at: URL(fileURLWithPath: output), withIntermediateDirectories: true, attributes: nil)

    // Write the directory yaml log, if applicable
    var directoryYAML: OutputStream?
    if keepGroups {
        directoryYAML = OutputStream(toFileAtPath: outputURL.appendingPathComponent("directories.yml").path, append: false)!
        directoryYAML?.open()
        let header = """
---
note_directories:

"""
        let headerArray = [UInt8](header.utf8)
        directoryYAML?.write(headerArray, maxLength: headerArray.count)
    }

    // Start crawl!
    crawl(inputURL,
          output: outputURL.path,
          preservingFolders: keepGroups,
          withMeta: !skipMeta,
          onFoundDirectory: { path in
            if keepGroups {
                let data = [UInt8]("- \"\(path)\"\n".utf8)
                directoryYAML?.write(data, maxLength: data.count)
            }
    })

    directoryYAML?.close()

    print("Exported \(sheetTotal) sheets.")
}

//: - Public Interface

let main = command(
    Argument<String>("input", description: "The path to your Ulysses notes. See README for hints on what this might be."),
    Argument<String>("output", description: "The path you want to export notes to."),
    Flag("keep-groups", description: "Create directories for each Ulysses Group, and export notes into them."),
    Flag("skip-meta", description: "Don’t append Ulysses keywords, attachment info, create date, and modify date to files. Files will still have the correct system create and modify dates."),
    Flag("verbose", flag: "v", description: "Log export activity and debugging statements.")
) { input, output, keepGroups, skipMeta, v in
    verbose = v
    run(input, output, keepGroups: keepGroups, skipMeta: skipMeta)
}

main.run()
