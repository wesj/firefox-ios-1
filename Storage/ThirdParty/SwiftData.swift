/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

/*
 * This is a heavily modified version of SwiftData.swift by Ryan Fowler
 * This has been enhanced to support custom files, correct binding, versioning,
 * and a streaming results via Cursors. The API has also been changed to use NSError, Cursors, and
 * to force callers to request a connection before executing commands. Database creation helpers, savepoint
 * helpers, image support, and other features have been removed.
 */

// SwiftData.swift
//
// Copyright (c) 2014 Ryan Fowler
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import UIKit
import sqlite3

// All database operations actually occur serially on this queue. Careful not to deadlock it!
private let queue = dispatch_queue_create("swiftdata queue", DISPATCH_QUEUE_SERIAL)

// The public interface for the database. This handles dispatching calls synchronously on the correct thread
public class SwiftData {
    let filename: String
    init(filename: String) {
        self.filename = filename
    }

    //The real meat of all the execute methods. This is used internally to open and close a database connection and
    // run a block of code inside it.
    public func withConnection(flags: SwiftData.Flags, cb: (db: SQLiteDBConnection) -> NSError?) -> NSError? {
        var error: NSError? = nil
        let task: () -> Void = {
            if let db = SQLiteDBConnection(filename: self.filename, flags: flags.toSQL(), error: &error) {
                error = cb(db: db)
            }
        }

        dispatch_sync(queue) { task() }
        return error
    }

    // Helper for opening a connection, starting a transaction, and then running a block of code inside it.
    // The code block can return true if the transaction should be commited. False if we should rollback.
    public func transaction(transactionClosure: (db: SQLiteDBConnection)->Bool) -> NSError? {
        return withConnection(SwiftData.Flags.ReadWriteCreate) { db in
            if let err = db.executeChange("BEGIN EXCLUSIVE") {
                return err
            }

            if transactionClosure(db: db) {
                if let err = db.executeChange("COMMIT") {
                    db.executeChange("ROLLBACK")
                    return err
                }
            } else {
                if let err = db.executeChange("ROLLBACK") {
                    return err
                }
            }

            return nil
        }
    }

    public enum Flags {
        case ReadOnly
        case ReadWrite
        case ReadWriteCreate

        private func toSQL() -> Int32 {
            switch self {
            case .ReadOnly:
                return SQLITE_OPEN_READONLY
            case .ReadWrite:
                return SQLITE_OPEN_READWRITE
            case .ReadWriteCreate:
                return SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            }
        }
    }
}

// We open the connection when this is created
public class SQLiteDBConnection {
    private var sqliteDB: COpaquePointer = nil
    private let filename: String
    private let debug_enabled = false

    public var version: Int {
        get {
            let res = executeQuery("PRAGMA user_version", factory: IntFactory)
            return res[0] as? Int ?? 0
        }

        set {
            executeChange("PRAGMA user_version = \(newValue)")
        }
    }

    init?(filename: String, flags: Int32, inout error: NSError?) {
        self.filename = filename
        if let err = openWithFlags(flags) {
            error = err
            return nil
        }
    }

    deinit {
        closeCustomConnection()
    }

    var lastInsertedRowID: Int {
        return Int(sqlite3_last_insert_rowid(sqliteDB))
    }

    var numberOfRowsModified: Int {
        return Int(sqlite3_changes(sqliteDB))
    }

    // Creates an error from a sqlite status. Will print to the console if debug_enabled is set.
    // (i.e. Do not call this unless you're going to return this error)
    private func createErr(description: String, status: Int) -> NSError {
        var msg = SDError.errorMessageFromCode(status)

        if (debug_enabled) {
            println("SwiftData Error -> \(description)")
            println("                -> Code: \(status) - \(msg)")
        }

        if let errMsg = String.fromCString(sqlite3_errmsg(sqliteDB)) {
            msg += " " + errMsg
            if (debug_enabled) {
                println("                -> Details: \(errMsg)")
            }
        }

        return NSError(domain: "org.mozilla", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    // Open the connection. This is called when the db is created. You should not call it yourself
    private func openWithFlags(flags: Int32) -> NSError? {
        let status = sqlite3_open_v2(filename.cStringUsingEncoding(NSUTF8StringEncoding)!, &sqliteDB, flags, nil)
        if status != SQLITE_OK {
            return createErr("During: Opening Database with Flags", status: Int(status))
        }
        return nil
    }

    // Closes a connection This is called a deinit. Do not call this yourself
    private func closeCustomConnection() -> NSError? {
        let status = sqlite3_close(sqliteDB)

        sqliteDB = nil

        if status != SQLITE_OK {
            return createErr("During: Closing Database with Flags", status: Int(status))
        }

        return nil
    }

    // Executes a change on the datbase
    func executeChange(sqlStr: String, withArgs: [AnyObject?]? = nil) -> NSError? {
        var err: NSError? = nil
        var pStmt: COpaquePointer = nil

        var status = sqlite3_prepare_v2(sqliteDB, sqlStr, -1, &pStmt, nil)
        if status != SQLITE_OK {
            let err = createErr("During: SQL Prepare \(sqlStr)", status: Int(status))
            sqlite3_finalize(pStmt)
            return err
        }

        if let args = withArgs {
            if let err = bind(args, stmt: pStmt) {
                sqlite3_finalize(pStmt)
                return err
            }
        }

        status = sqlite3_step(pStmt)

        if status != SQLITE_DONE && status != SQLITE_OK {
            err = createErr("During: SQL Step \(sqlStr)", status: Int(status))
        }

        sqlite3_finalize(pStmt)
        return err
    }

    // Execute a query on the database
    func executeQuery<T>(sqlStr: String, factory: ((SDRow) -> T), withArgs: [AnyObject?]? = nil) -> Cursor {
        var pStmt: COpaquePointer = nil

        let status = sqlite3_prepare_v2(sqliteDB, sqlStr, -1, &pStmt, nil)
        if status != SQLITE_OK {
            let err = createErr("During: SQL Prepare \(sqlStr)", status: Int(status))
            sqlite3_finalize(pStmt)
            return Cursor(err: err)
        }

        if let args = withArgs {
            if let err = bind(args, stmt: pStmt) {
                sqlite3_finalize(pStmt)
                return Cursor(err: err)
            }
        }

        return SDCursor(db: self, stmt: pStmt, factory: factory)
    }

    // Bind objects to a query
    private func bind(objects: [AnyObject?], stmt: COpaquePointer) -> NSError? {
        let count = Int(sqlite3_bind_parameter_count(stmt))
        if (count < objects.count) {
            return createErr("During: Bind", status: 202)
        } else if (count > objects.count) {
            return createErr("During: Bind", status: 201)
        }

        for (index, obj) in enumerate(objects) {
            var status: Int32 = SQLITE_OK

            // Double's also pass obj is Int, so order is important here
            if obj is Double {
                status = sqlite3_bind_double(stmt, Int32(index+1), obj as! Double)
            } else if obj is Int {
                status = sqlite3_bind_int(stmt, Int32(index+1), Int32(obj as! Int))
            } else if obj is Bool {
                status = sqlite3_bind_int(stmt, Int32(index+1), (obj as! Bool) ? 1 : 0)
            } else if obj is String {
                let negativeOne = UnsafeMutablePointer<Int>(bitPattern: -1)
                let opaquePointer = COpaquePointer(negativeOne)
                let transient = CFunctionPointer<((UnsafeMutablePointer<()>) -> Void)>(opaquePointer)
                status = sqlite3_bind_text(stmt, Int32(index+1), (obj as! String).cStringUsingEncoding(NSUTF8StringEncoding)!, -1, transient)
            } else if obj is NSData {
                status = sqlite3_bind_blob(stmt, Int32(index+1), (obj as! NSData).bytes, -1, nil)
            } else if obj is NSDate {
                var timestamp = (obj as! NSDate).timeIntervalSince1970
                status = sqlite3_bind_double(stmt, Int32(index+1), timestamp)
            } else if obj === nil {
                status = sqlite3_bind_null(stmt, Int32(index+1))
            }

            if status != SQLITE_OK {
                return createErr("During: Binding", status: Int(status))
            }
        }

        return nil
    }
}

// Helper for queries that return a single integer result
func IntFactory(row: SDRow) -> Int {
    return row[0] as! Int
}

// Helper for queries that return a single String result
func StringFactory(row: SDRow) -> String {
    return row[0] as! String
}

// Wrapper around a statment for getting data from a row. This provides accessors for subscript indexing
// and a generator for iterating over columns.
public class SDRow : SequenceType {
    private var data = [String: AnyObject]()

    private init(stmt: COpaquePointer, columns: [String]) {
        for (idx, column) in enumerate(columns) {
            data[column] = getValue(stmt, index: idx)
        }
    }

    // Return the value at this index in the row
    private func getValue(stmt: COpaquePointer, index: Int) -> AnyObject? {
        let i = Int32(index)

        let type = sqlite3_column_type(stmt, i)
        var ret: AnyObject? = nil

        switch type {
        case SQLITE_NULL, SQLITE_INTEGER:
            ret = NSNumber(longLong: sqlite3_column_int64(stmt, i))
        case SQLITE_TEXT:
            let text = UnsafePointer<Int8>(sqlite3_column_text(stmt, i))
            ret = String.fromCString(text)
        case SQLITE_BLOB:
            let blob = sqlite3_column_blob(stmt, i)
            if blob != nil {
                let size = sqlite3_column_bytes(stmt, i)
                ret = NSData(bytes: blob, length: Int(size))
            }
        case SQLITE_FLOAT:
            ret = Double(sqlite3_column_double(stmt, i))
        default:
            println("SwiftData Warning -> Column: \(index) is of an unrecognized type, returning nil")
        }

        return ret
    }

    // Accessor getting column 'key' in the row
    public subscript(key: Int) -> AnyObject? {
        return data.values.array[key]
    }

    // Accessor getting a named column in the row. This (currently) depends on
    // the columns array passed into this Row to find the correct index.
    public subscript(key: String) -> AnyObject? {
        get {
            return data[key]
        }
    }

    // Allow iterating through the row. This is currently broken.
    public func generate() -> GeneratorOf<Any> {
        var nextIndex = 0
        return GeneratorOf<Any>() {
            let val = self[nextIndex]
            nextIndex++
            return val
        }
    }
}

// Helper for pretty printing sql (and other custom) error codes
private struct SDError {
    private static func errorMessageFromCode(errorCode: Int) -> String {
        switch errorCode {
        case -1:
            return "No error"
            // SQLite error codes and descriptions as per: http://www.sqlite.org/c3ref/c_abort.html
        case 0:
            return "Successful result"
        case 1:
            return "SQL error or missing database"
        case 2:
            return "Internal logic error in SQLite"
        case 3:
            return "Access permission denied"
        case 4:
            return "Callback routine requested an abort"
        case 5:
            return "The database file is busy"
        case 6:
            return "A table in the database is locked"
        case 7:
            return "A malloc() failed"
        case 8:
            return "Attempt to write a readonly database"
        case 9:
            return "Operation terminated by sqlite3_interrupt()"
        case 10:
            return "Some kind of disk I/O error occurred"
        case 11:
            return "The database disk image is malformed"
        case 12:
            return "Unknown opcode in sqlite3_file_control()"
        case 13:
            return "Insertion failed because database is full"
        case 14:
            return "Unable to open the database file"
        case 15:
            return "Database lock protocol error"
        case 16:
            return "Database is empty"
        case 17:
            return "The database schema changed"
        case 18:
            return "String or BLOB exceeds size limit"
        case 19:
            return "Abort due to constraint violation"
        case 20:
            return "Data type mismatch"
        case 21:
            return "Library used incorrectly"
        case 22:
            return "Uses OS features not supported on host"
        case 23:
            return "Authorization denied"
        case 24:
            return "Auxiliary database format error"
        case 25:
            return "2nd parameter to sqlite3_bind out of range"
        case 26:
            return "File opened that is not a database file"
        case 27:
            return "Notifications from sqlite3_log()"
        case 28:
            return "Warnings from sqlite3_log()"
        case 100:
            return "sqlite3_step() has another row ready"
        case 101:
            return "sqlite3_step() has finished executing"

            // Custom SwiftData errors
            // Binding errors
        case 201:
            return "Not enough objects to bind provided"
        case 202:
            return "Too many objects to bind provided"

            // Custom connection errors
        case 301:
            return "A custom connection is already open"
        case 302:
            return "Cannot open a custom connection inside a transaction"
        case 303:
            return "Cannot open a custom connection inside a savepoint"
        case 304:
            return "A custom connection is not currently open"
        case 305:
            return "Cannot close a custom connection inside a transaction"
        case 306:
            return "Cannot close a custom connection inside a savepoint"

            // Index and table errors
        case 401:
            return "At least one column name must be provided"
        case 402:
            return "Error extracting index names from sqlite_master"
        case 403:
            return "Error extracting table names from sqlite_master"

            // Transaction and savepoint errors
        case 501:
            return "Cannot begin a transaction within a savepoint"
        case 502:
            return "Cannot begin a transaction within another transaction"

            // Unknown error
        default:
            return "Unknown error"
        }
    }
}

// Wrapper around a statement to help with iterating through the results. This currently
// only fetches items when asked for, and caches (all) old requests. Ideally it will
// at somepoint fetch a window of items to keep in memory
public class SDCursor<T> : ArrayCursor<T> {
    // Function for generating objects of type T from a row.
    private let factory: (SDRow) -> T

    private init(db: SQLiteDBConnection, stmt: COpaquePointer, factory: (SDRow) -> T) {
        // We will hold the db open until we're thrown away
        self.factory = factory

        // This untangles all of the columns and values for this row when its created
        let columnCount = sqlite3_column_count(stmt)
        var columns = [String]()
        for var i: Int32 = 0; i < columnCount; ++i {
            let columnName = String.fromCString(sqlite3_column_name(stmt, i))!
            columns.append(columnName)
        }

        // The only way I know to get a count. Walk through the entire statement to see how many rows there are.
        var sqlStatus = sqlite3_step(stmt)
        var cache = [T]()
        while sqlStatus != SQLITE_DONE {
            if sqlStatus == SQLITE_ROW {
                let row = SDRow(stmt: stmt, columns: columns)
                let res = self.factory(row)
                cache.append(res)
            }
            sqlStatus = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        super.init(data: cache, status: .Success, statusMessage: "Success")
    }
}
