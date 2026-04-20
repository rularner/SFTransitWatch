import Foundation

enum SIRIXMLParser {
    static func parseRecords(
        data: Data,
        entryElement: String,
        fields: Set<String>
    ) -> [[String: String]] {
        let delegate = RecordDelegate(entryElement: entryElement, fields: fields)
        let parser = XMLParser(data: Self.stripBOM(data))
        parser.delegate = delegate
        parser.parse()
        return delegate.records
    }

    static func parseRecords(
        data: Data,
        entryElement: String,
        fields: [String]
    ) -> [[String: String]] {
        return parseRecords(data: data, entryElement: entryElement, fields: Set(fields))
    }

    private static func stripBOM(_ data: Data) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        guard data.count >= bom.count, Array(data.prefix(bom.count)) == bom else {
            return data
        }
        return data.dropFirst(bom.count)
    }

    private final class RecordDelegate: NSObject, XMLParserDelegate {
        let entryElement: String
        let fields: Set<String>
        var records: [[String: String]] = []

        private var currentRecord: [String: String]?
        private var currentElement: String?
        private var currentText = ""

        init(entryElement: String, fields: Set<String>) {
            self.entryElement = entryElement
            self.fields = fields
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            if elementName == entryElement {
                currentRecord = [:]
            }
            currentElement = elementName
            currentText = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if var record = currentRecord, fields.contains(elementName), record[elementName] == nil {
                record[elementName] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                currentRecord = record
            }
            if elementName == entryElement, let record = currentRecord {
                records.append(record)
                currentRecord = nil
            }
            currentElement = nil
            currentText = ""
        }
    }
}
