import Foundation
import XCTest

class TestVisitsTable : AccountTest {
    var db: SwiftData!

    private func addVisit(visits: VisitsTable<Visit>, site: Site, s: Bool = true) -> Visit {
        var inserted = -1;
        var visit : Visit!
        db.withConnection(.ReadWrite) { connection -> NSError? in
            visit = Visit(site: site, date: NSDate())
            var err: NSError? = nil
            inserted = visits.insert(connection, item: visit, err: &err)
            return nil
        }

        if s {
            XCTAssert(inserted >= 0, "Inserted succeeded")
        } else {
            XCTAssert(inserted == -1, "Inserted failed")
        }
        return visit
    }

    private func checkVisits(visits: VisitsTable<Visit>, options: QueryOptions? = nil, vs: [Visit], s: Bool = true) {
        db.withConnection(.ReadOnly) { connection -> NSError? in
            var cursor = visits.query(connection, options: options)
            XCTAssertEqual(cursor.status, CursorStatus.Success, "returned success \(cursor.statusMessage)")
            XCTAssertEqual(cursor.count, vs.count, "cursor has right num of entries")

            for index in 0..<cursor.count {
                if let s = cursor[index] as? Visit {
                    XCTAssertNotNil(s, "cursor has a site for entry")
                    // These aren't currently filled in for the model results. Yeah, that kinda sucks :(
                    // XCTAssertEqual(s.site.url, vs[index].site.url, "Found right url")
                    // XCTAssertEqual(s.site.title, vs[index].site.title, "Found right title")
                    XCTAssertEqual(s.date.timeIntervalSince1970, vs[index].date.timeIntervalSince1970, "Found right date")
                } else {
                    XCTAssertFalse(true, "Should not be nil...")
                }
            }
            return nil
        }
    }

    private func clear(visits: VisitsTable<Visit>, visit: Visit? = nil, s: Bool = true) {
        var deleted = -1;
        db.withConnection(.ReadWrite) { connection -> NSError? in
            var err: NSError? = nil
            deleted = visits.delete(connection, item: visit, err: &err)
            return nil
        }

        if s {
            XCTAssert(deleted >= 0, "Delete worked")
        } else {
            XCTAssert(deleted == -1, "Delete failed")
        }
    }

    // This is a very basic test. Adds an entry. Retrieves it, and then clears the database
    func testVisitsTable() {
        withTestAccount { account -> Void in
            self.db = SwiftData(filename: account.files.get("test.db")!)
            let h = VisitsTable<Visit>()

            self.db.withConnection(SwiftData.Flags.ReadWriteCreate, cb: { (db) -> NSError? in
                h.create(db, version: 2)
                return nil
            })

            let site = Site(url: "url", title: "title")
            site.guid = "myguid"

            let site2 = Site(url: "url 2", title: "title 2")
            site2.guid = "myguid 2"

            let v1 = self.addVisit(h, site: site)
            let v2 = self.addVisit(h, site: site)
            let v3 = self.addVisit(h, site: site2)
            let v4 = self.addVisit(h, site: site2)

            self.checkVisits(h, options: nil, vs: [v1, v2, v3, v4])
            let options = QueryOptions()
            options.filter = v1.site.guid!
            self.checkVisits(h, options: options, vs: [v1, v2])

            self.clear(h, visit: v1, s: true)
            self.checkVisits(h, options: options, vs: [v2])
            self.clear(h, s: true)
            self.checkVisits(h, options: nil, vs: [])

            account.files.remove("test.db")
        }
    }
}