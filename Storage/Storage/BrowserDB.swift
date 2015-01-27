/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

public enum QuerySort {
    case None, LastVisit, Frecency
}

public enum FilterType {
    case None
}

public class QueryOptions {
    // A filter string to apploy to the query
    public var filter: String? = nil

    // Allows for customizing how the filter is applied (i.e. only urls or urls and titles?)
    public var filterType: FilterType = .None

    // The way to sort the query
    public var sort: QuerySort = .None

    public init(filter: String? = nil, filterType: FilterType = .None, sort: QuerySort = .None) {
        self.filter = filter
        self.filterType = filterType
        self.sort = sort
    }
}

/* A table in our database. Note this doesn't have to be a real table. It might be backed by a join or something else interesting. */
protocol Table {
    var name: String { get }
    func create(db: SQLiteDBConnection, version: Int) -> Bool
    func updateTable(db: SQLiteDBConnection, from: Int, to: Int) -> Bool

    func insert<T>(db: SQLiteDBConnection, item: T?, inout err: NSError?) -> Int
    func update<T>(db: SQLiteDBConnection, item: T?, inout err: NSError?) -> Int
    func delete<T>(db: SQLiteDBConnection, item: T?, inout err: NSError?) -> Int
    func query(db: SQLiteDBConnection, options: QueryOptions?) -> Cursor
}

let DBCouldNotOpenErrorCode = 200

/* This is a base interface into our browser db. It holds arrays of tables and handles basic creation/updating of them. */
// Version 1 - Basic history table
// Version 2 - Added a visits table, refactored the history table to be a GenericTable
// Version 3 - Added a favicons table
class BrowserDB {
    private let db: SwiftData
    // XXX: Increasing this should blow away old history, since we currently dont' support any upgrades
    private let Version: Int = 3
    private let FileName = "browser.db"
    private let tables: [String: Table] = [
        HistoryVisits: JoinedHistoryVisitsTable(),
    ]

    private func exists(db: SQLiteDBConnection, table: Table) -> Bool {
        var found = false
        let sqlStr = "SELECT name FROM sqlite_master WHERE type = 'table' AND name=?"
        let res = db.executeQuery(sqlStr, factory: StringFactory, withArgs: [table.name])
        return res.count > 0
    }

    init?(files: FileAccessor) {
        tables[TableNameFaviconSites] = FaviconSiteTable(files: files)

        db = SwiftData(filename: files.get(FileName)!)
        if !createDB(files) {
            if !deleteAndRecreate(files) {
                return nil
            }
        }
    }

    private func createDB(files: FileAccessor) -> Bool {
        db.transaction({ connection -> Bool in
            let version = connection.version
            if self.Version != version {
                for table in self.tables {
                    // If it doesn't exist create it
                    if !self.exists(connection, table: table.1) {
                        if !table.1.create(connection, version: self.Version) {
                            return false
                        }
                    } else {
                        if !table.1.updateTable(connection, from: version, to: self.Version) {
                            return false
                        }
                    }
                }

                self.updateTable(connection, from: version, to: self.Version)
            }
            return true
        })
        return true
    }

    private func updateTable(connection: SQLiteDBConnection, from: Int, to: Int) {
        connection.executeChange("PRAGMA journal_mode = WAL")
        connection.version = self.Version
    }

    private func deleteAndRecreate(files: FileAccessor) -> Bool {
        let date = NSDate()
        let newFilename = "\(FileName).bak"

        if let file = files.get(newFilename) {
            if let attrs = NSFileManager.defaultManager().attributesOfItemAtPath(file, error: nil) {
                if let creationDate = attrs[NSFileCreationDate] as? NSDate {
                    // If the old backup is less than an hour old, we just give up
                    let interval = date.timeIntervalSinceDate(creationDate)
                    if interval < 60*60 {
                        return false
                    }
                }
            }
        }

        files.move(FileName, dest: newFilename)
        return createDB(files)
    }

    func insert<T>(name: String, item: T, inout err: NSError?) -> Int {
        var res = 0
        if let table = tables[name] {
            db.withConnection(SwiftData.Flags.ReadWrite) { connection in
                res = table.insert(connection, item: item, err: &err)
                if err != nil {
                    self.debug(err!)
                }
                return err
            }
        }
        return res
    }

    func update<T>(name: String, item: T, inout err: NSError?) -> Int {
        var res = 0
        if let table = tables[name] {
            db.withConnection(SwiftData.Flags.ReadWrite) { connection in
                res = table.update(connection, item: item, err: &err)
                if err != nil {
                    self.debug(err!)
                }
                return err
            }
        }
        return res
    }

    func delete<T>(name: String, item: T?, inout err: NSError?) -> Int {
        var res = 0
        if let table = tables[name] {
            db.withConnection(SwiftData.Flags.ReadWrite) { connection in
                res = table.delete(connection, item: item, err: &err)
                if err != nil {
                    self.debug(err!)
                }
                return err
            }
        }
        return res
    }

    func query(name: String, filter: String? = nil, options: QueryOptions?) -> Cursor {
        if let table = tables[name] {
            var c: Cursor!
            db.withConnection(SwiftData.Flags.ReadWrite) { connection in
                c = table.query(connection, options: options)
                return nil
            }
            return c
        }
        return Cursor(status: .Failure, msg: "Invalid table name")
    }

    private let debug_enabled = true
    private func debug(err: NSError) {
        debug("\(err.code): \(err.localizedDescription)")
    }

    private func debug(msg: String) {
        if debug_enabled {
            println("BrowserDB: " + msg)
        }
    }
}
