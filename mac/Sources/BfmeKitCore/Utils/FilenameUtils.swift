import Foundation

public enum FilenameUtils {
    /// Applies BFME's sigil-based load order to a list of archive filenames.
    /// The rules (ported verbatim from the C# implementation):
    ///   - Leading `!` => top priority (group 100), weight = leading bang count
    ///   - Leading `#` => next priority (group 99), weight = leading hash count
    ///   - Leading `_` => next priority (group 98), weight = leading underscore count
    ///   - anything else => base group 0, weight = 1
    /// Higher-numbered groups load first. Within a group, tie-breaking depends
    /// on `game`: BFME1 (game == 0) is a special case that sorts the base
    /// group ascending by weight then ascending by filename, but sigil groups
    /// ascending by weight then *descending* by filename. Other games sort
    /// descending by weight then ascending by filename.
    public static func orderFiles(_ files: [String], game: Int) -> [String] {
        struct Entry {
            let fileName: String
            let groupType: Int
            let weight: Int
        }

        var library: [Entry] = []
        library.reserveCapacity(files.count)
        for file in files {
            let stem = (file as NSString).deletingPathExtension as String
            let baseName = (stem as NSString).lastPathComponent
            if baseName.hasPrefix("!") {
                let weight = baseName.prefix(while: { $0 == "!" }).count
                library.append(Entry(fileName: file, groupType: 100, weight: weight))
            } else if baseName.hasPrefix("#") {
                let weight = baseName.prefix(while: { $0 == "#" }).count
                library.append(Entry(fileName: file, groupType: 99, weight: weight))
            } else if baseName.hasPrefix("_") {
                let weight = baseName.prefix(while: { $0 == "_" }).count
                library.append(Entry(fileName: file, groupType: 98, weight: weight))
            } else {
                library.append(Entry(fileName: file, groupType: 0, weight: 1))
            }
        }

        let grouped = Dictionary(grouping: library, by: { $0.groupType })
        let orderedGroupKeys = grouped.keys.sorted(by: >)

        var result: [String] = []
        result.reserveCapacity(library.count)
        for key in orderedGroupKeys {
            guard let entries = grouped[key] else { continue }
            if game == 0 {
                if key > 0 {
                    let sorted = entries.sorted { a, b in
                        if a.weight != b.weight { return a.weight < b.weight }
                        return a.fileName > b.fileName
                    }
                    result.append(contentsOf: sorted.map { $0.fileName })
                } else {
                    let sorted = entries.sorted { a, b in
                        if a.weight != b.weight { return a.weight < b.weight }
                        return a.fileName < b.fileName
                    }
                    result.append(contentsOf: sorted.map { $0.fileName })
                }
            } else {
                let sorted = entries.sorted { a, b in
                    if a.weight != b.weight { return a.weight > b.weight }
                    return a.fileName < b.fileName
                }
                result.append(contentsOf: sorted.map { $0.fileName })
            }
        }
        return result
    }
}
