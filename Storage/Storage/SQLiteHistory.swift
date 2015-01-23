/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/**
 * The sqlite-backed implementation of the history protocol.
 */
public class SQLiteHistory : History {
    let files: FileAccessor
    let db: BrowserDB

    required public init(files: FileAccessor) {
        self.files = files
        self.db = BrowserDB(files: files)!
    }

    public func clear(complete: (success: Bool) -> Void) {
        let s: Site? = nil
        var err: NSError? = nil
        db.delete(HistoryVisits, item: s, err: &err)
        dispatch_async(dispatch_get_main_queue()) {
            if err != nil {
                self.debug("Clear failed: \(err!.localizedDescription)")
            }
        }
    }

    public func get(options: QueryOptions?, complete: (data: Cursor) -> Void) {
        let res = db.query(HistoryVisits, options: options)

        dispatch_async(dispatch_get_main_queue()) {
            complete(data: res)
        }
    }

    public func addVisit(visit: Visit, complete: (success: Bool) -> Void) {
        var err: NSError? = nil
        db.insert(HistoryVisits, item: visit, err: &err)
        dispatch_async(dispatch_get_main_queue()) {
            if err != nil {
                self.debug("Add failed: \(err!.localizedDescription)")
            }
            complete(success: err == nil)
        }
    }

    private let debug_enabled = true
    private func debug(msg: String) {
        if debug_enabled {
            println("HistorySqlite: " + msg)
        }
    }
}
