/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCGLogger

// To keep SwiftData happy.
typealias Args = [AnyObject?]

let TableBookmarks = "bookmarks"

let TableFavicons = "favicons"
let TableHistory = "history"
let TableVisits = "visits"
let TableFaviconSites = "favicon_sites"
let TableQueuedTabs = "queue"

let ViewFaviconsForSites = "view_favicons"
let ViewWidestFaviconsForSites = "view_favicons_widest"
let ViewHistoryIDsWithWidestFavicons = "view_history_id_favicon"
let ViewIconForURL = "view_icon_for_url"

let IndexHistoryShouldUpload = "idx_history_should_upload"
let IndexVisitsSiteIDDate = "idx_visits_siteID_date"

private let AllTables: Args = [
    TableFaviconSites,

    TableHistory,
    TableVisits,

    TableBookmarks,

    TableQueuedTabs,
]

private let AllViews: Args = [
    ViewHistoryIDsWithWidestFavicons,
    ViewWidestFaviconsForSites,
    ViewIconForURL,
]

private let AllIndices: Args = [
    IndexHistoryShouldUpload,
    IndexVisitsSiteIDDate,
]

private let AllTablesIndicesAndViews: Args = AllViews + AllIndices + AllTables

private let log = XCGLogger.defaultInstance()

/**
 * The monolithic class that manages the inter-related history etc. tables.
 * We rely on SQLiteHistory having initialized the favicon table first.
 */
public class BrowserTable: Table {
    var name: String { return "BROWSER" }
    var version: Int { return 7 }
    let supportsPartialIndices: Bool

    let CreateHistoryTable =
    "CREATE TABLE IF NOT EXISTS \(TableHistory) (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
        "guid TEXT NOT NULL UNIQUE, " +       // Not null, but the value might be replaced by the server's.
        "url TEXT UNIQUE, " +                 // May only be null for deleted records.
        "title TEXT NOT NULL, " +
        "server_modified INTEGER, " +         // Can be null. Integer milliseconds.
        "local_modified INTEGER, " +          // Can be null. Client clock. In extremis only.
        "is_deleted TINYINT NOT NULL, " +     // Boolean. Locally deleted.
        "should_upload TINYINT NOT NULL, " +  // Boolean. Set when changed or visits added.
        "CONSTRAINT urlOrDeleted CHECK (url IS NOT NULL OR is_deleted = 1)" +
    ") "

    // Right now we don't need to track per-visit deletions: Sync can't
    // represent them! See Bug 1157553 Comment 6.
    // We flip the should_upload flag on the history item when we add a visit.
    // If we ever want to support logic like not bothering to sync if we added
    // and then rapidly removed a visit, then we need an 'is_new' flag on each visit.
    let CreateVisitsTable =
    "CREATE TABLE IF NOT EXISTS \(TableVisits) (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
        "siteID INTEGER NOT NULL REFERENCES \(TableHistory)(id) ON DELETE CASCADE, " +
        "date REAL NOT NULL, " +           // Microseconds since epoch.
        "type INTEGER NOT NULL, " +
        "is_local TINYINT NOT NULL, " +    // Some visits are local. Some are remote ('mirrored'). This boolean flag is the split.
        "UNIQUE (siteID, date, type) " +
    ") "

    let CreateSiteIDDateIndex =
    "CREATE INDEX IF NOT EXISTS \(IndexVisitsSiteIDDate) " +
    "ON \(TableVisits) (siteID, date)"

    let CreateFaviconSitesTable =
    "CREATE TABLE IF NOT EXISTS \(TableFaviconSites) (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
        "siteID INTEGER NOT NULL REFERENCES \(TableHistory)(id) ON DELETE CASCADE, " +
        "faviconID INTEGER NOT NULL REFERENCES \(TableFavicons)(id) ON DELETE CASCADE, " +
        "date REAL DEFAULT 0, " +
        "UNIQUE (siteID, faviconID) " +
    ") "

    let CreateFaviconsView =
    "CREATE VIEW IF NOT EXISTS \(ViewFaviconsForSites) AS " +
        "SELECT " +
        "\(TableFaviconSites).siteID AS siteID, " +
        "\(TableFavicons).id AS iconID, " +
        "\(TableFavicons).url AS iconURL, " +
        "\(TableFaviconSites).date AS iconDate, " +
        "\(TableFavicons).type AS iconType, " +
        "\(TableFavicons).width AS iconWidth " +
        "FROM \(TableFaviconSites), \(TableFavicons) WHERE " +
    "\(TableFaviconSites).faviconID = \(TableFavicons).id"

    let CreateWidestFaviconsView =
    "CREATE VIEW IF NOT EXISTS \(ViewWidestFaviconsForSites) AS " +
        "SELECT siteID, iconID, iconURL, iconDate, iconType, " +
        "MAX(iconWidth) AS iconWidth " +
        "FROM \(ViewFaviconsForSites)" +
    "GROUP BY siteID "

    let CreateHistoryIdWithIconView =
    "CREATE VIEW IF NOT EXISTS \(ViewHistoryIDsWithWidestFavicons) AS " +
        "SELECT \(TableHistory).id AS id, " +
        "iconID, iconURL, iconDate, iconType, iconWidth " +
        "FROM \(TableHistory) " +
        "LEFT OUTER JOIN " +
    "\(ViewWidestFaviconsForSites) ON history.id = \(ViewWidestFaviconsForSites).siteID "

    let CreateIconForURLView =
    "CREATE VIEW IF NOT EXISTS \(ViewIconForURL) AS " +
        "SELECT history.url AS url, icons.iconID AS iconID FROM " +
        "\(TableHistory), \(ViewWidestFaviconsForSites) AS icons WHERE " +
    "\(TableHistory).id = icons.siteID "

    let CreateBookmarksTable =
    "CREATE TABLE IF NOT EXISTS \(TableBookmarks) (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
        "guid TEXT NOT NULL UNIQUE, " +
        "type TINYINT NOT NULL, " +
        "url TEXT, " +
        "parent INTEGER REFERENCES \(TableBookmarks)(id) NOT NULL, " +
        "faviconID INTEGER REFERENCES \(TableFavicons)(id) ON DELETE SET NULL, " +
        "title TEXT" +
    ") "

    let CreateQueueTable =
    "CREATE TABLE IF NOT EXISTS \(TableQueuedTabs) (" +
        "url TEXT NOT NULL UNIQUE, " +
        "title TEXT" +
    ") "

    var CreateShouldUploadIndex: String {
        if self.supportsPartialIndices {
            // There's no point tracking rows that are not flagged for upload.
            return "CREATE INDEX IF NOT EXISTS \(IndexHistoryShouldUpload) " +
            "ON \(TableHistory) (should_upload) WHERE should_upload = 1"
        } else {
            return "CREATE INDEX IF NOT EXISTS \(IndexHistoryShouldUpload) " +
            "ON \(TableHistory) (should_upload)"
        }
    }

    public init() {
        let v = sqlite3_libversion_number()
        self.supportsPartialIndices = v >= 3008000          // 3.8.0.
    }

    func run(db: SQLiteDBConnection, sql: String, args: Args? = nil) -> Bool {
        let err = db.executeChange(sql, withArgs: args)
        if err != nil {
            log.error("Error running SQL in BrowserTable. \(err?.localizedDescription)")
            log.error("SQL was \(sql)")
        }
        return err == nil
    }

    // TODO: transaction.
    func run(db: SQLiteDBConnection, queries: [String]) -> Bool {
        for sql in queries {
            if !run(db, sql: sql, args: nil) {
                return false
            }
        }
        return true
    }

    func prepopulateRootFolders(db: SQLiteDBConnection) -> Bool {
        let type = BookmarkNodeType.Folder.rawValue
        let root = BookmarkRoots.RootID

        let titleMobile = NSLocalizedString("Mobile Bookmarks", tableName: "Storage", comment: "The title of the folder that contains mobile bookmarks. This should match bookmarks.folder.mobile.label on Android.")
        let titleMenu = NSLocalizedString("Bookmarks Menu", tableName: "Storage", comment: "The name of the folder that contains desktop bookmarks in the menu. This should match bookmarks.folder.menu.label on Android.")
        let titleToolbar = NSLocalizedString("Bookmarks Toolbar", tableName: "Storage", comment: "The name of the folder that contains desktop bookmarks in the toolbar. This should match bookmarks.folder.toolbar.label on Android.")
        let titleUnsorted = NSLocalizedString("Unsorted Bookmarks", tableName: "Storage", comment: "The name of the folder that contains unsorted desktop bookmarks. This should match bookmarks.folder.unfiled.label on Android.")

        let args: Args = [
            root, BookmarkRoots.RootGUID, type, "Root", root,
            BookmarkRoots.MobileID, BookmarkRoots.MobileFolderGUID, type, titleMobile, root,
            BookmarkRoots.MenuID, BookmarkRoots.MenuFolderGUID, type, titleMenu, root,
            BookmarkRoots.ToolbarID, BookmarkRoots.ToolbarFolderGUID, type, titleToolbar, root,
            BookmarkRoots.UnfiledID, BookmarkRoots.UnfiledFolderGUID, type, titleUnsorted, root,
        ]

        let sql =
        "INSERT INTO bookmarks (id, guid, type, url, title, parent) VALUES " +
            "(?, ?, ?, NULL, ?, ?), " +    // Root
            "(?, ?, ?, NULL, ?, ?), " +    // Mobile
            "(?, ?, ?, NULL, ?, ?), " +    // Menu
            "(?, ?, ?, NULL, ?, ?), " +    // Toolbar
            "(?, ?, ?, NULL, ?, ?)  "      // Unsorted

        return self.run(db, sql: sql, args: args)
    }

    func create(db: SQLiteDBConnection, version: Int) -> Bool {
        // We ignore the version.

        let queries = [
            CreateHistoryTable,
            CreateVisitsTable,
            CreateBookmarksTable,
            CreateFaviconSitesTable,
            CreateShouldUploadIndex,
            CreateSiteIDDateIndex,
            CreateFaviconsView,
            CreateWidestFaviconsView,
            CreateHistoryIdWithIconView,
            CreateIconForURLView,
            CreateQueueTable
        ]

        assert(queries.count == AllTablesIndicesAndViews.count, "Did you forget to add your table, index, or view to the list?")

        log.debug("Creating \(queries.count) tables, views, and indices.")
        return self.run(db, queries: queries) &&
               self.prepopulateRootFolders(db)
    }

    func updateTable(db: SQLiteDBConnection, from: Int, to: Int) -> Bool {
        if from == to {
            log.debug("Skipping update from \(from) to \(to).")
            return true
        }

        if from == 0 {
            // This is likely an upgrade from before Bug 1160399.
            log.debug("Updating browser tables from zero. Assuming drop and recreate.")
            return drop(db) && create(db, version: to)
        }

        log.debug("Updating browser tables from \(from) to \(to).")
        if from < 4 || to < from {
            return drop(db) && create(db, version: to)
        }

        // Create the queue table
        if from < 5 {
            if !self.run(db, queries: [CreateQueueTable]) {
                return false
            }
        }

        // Moved the date column from the favicons table to the faviconSites table.
        if (from < 6) {
            if !run(db, queries: [
                "PRAGMA foreign_keys=OFF",
                "ALTER TABLE \(TableFaviconSites) ADD COLUMN date REAL DEFAULT 0",

                // Create the new favicons table
                "CREATE TABLE new_favicons (id INTEGER PRIMARY KEY AUTOINCREMENT, " +
                    "url TEXT NOT NULL UNIQUE, " +
                    "width INTEGER, " +
                    "height INTEGER, " +
                    "type INTEGER NOT NULL)",

                // Copy the old data over
                "INSERT INTO new_favicons SELECT id, url, width, height, type from \(TableFavicons)",

                // Drop the old favicons table
                "DROP TABLE \(TableFavicons)",
                "ALTER TABLE new_favicons RENAME TO \(TableFavicons)",

                // Now drop and recreate any views associated with it.
                "DROP VIEW \(ViewWidestFaviconsForSites)",
                "DROP VIEW \(ViewIconForURL)",
                "DROP VIEW \(ViewHistoryIDsWithWidestFavicons)",
                CreateWidestFaviconsView,
                CreateIconForURLView,
                CreateHistoryIdWithIconView,
                "PRAGMA foreign_keys=ON",
            ]) {
                return false
            }
        }

        if (from < 7) {
            if !self.run(db, queries: [
                CreateFaviconsView,
                "DROP VIEW \(ViewWidestFaviconsForSites)",
                CreateWidestFaviconsView
            ]) {
                return false
            }
        }

        return true
    }

    /**
     * The Table mechanism expects to be able to check if a 'table' exists. In our (ab)use
     * of Table, that means making sure that any of our tables and views exist.
     * We do that by fetching all tables from sqlite_master with matching names, and verifying
     * that we get back more than one.
     * Note that we don't check for views -- trust to luck.
     */
    func exists(db: SQLiteDBConnection) -> Bool {
        return db.tablesExist(AllTables)
    }

    func drop(db: SQLiteDBConnection) -> Bool {
        log.debug("Dropping all browser tables.")
        let additional = [
            "DROP TABLE IF EXISTS faviconSites",  // We renamed it to match naming convention.
        ]
        let queries = AllViews.map { "DROP VIEW IF EXISTS \($0!)" } +
                      AllIndices.map { "DROP INDEX IF EXISTS \($0!)" } +
                      AllTables.map { "DROP TABLE IF EXISTS \($0!)" } +
                      additional

        return self.run(db, queries: queries)
    }
}