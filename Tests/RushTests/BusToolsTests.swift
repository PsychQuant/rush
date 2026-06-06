import XCTest
@testable import Rush

final class BusToolsTests: XCTestCase {
    // MARK: - BusCity enum

    func testBusCityCovers22Cities() {
        XCTAssertEqual(BusCity.allCases.count, 22, "Taiwan TDX bus catalog covers 22 cities/counties")
    }

    func testBusCityRawValueMatchesURLSegment() {
        XCTAssertEqual(BusCity.Taipei.rawValue, "Taipei")
        XCTAssertEqual(BusCity.NewTaipei.rawValue, "NewTaipei")
        XCTAssertEqual(BusCity.HsinchuCounty.rawValue, "HsinchuCounty")
    }

    // MARK: - Fuzzy matching

    func testFuzzyMatchRoutesNormalizesTaiTai() {
        let routes = [
            BusRoute(routeUID: "TPE000001", routeID: "0",
                     routeName: LocalizedName(zhTw: "臺北環狀線", en: "Taipei Loop"),
                     departureStopNameZh: nil, destinationStopNameZh: nil),
            BusRoute(routeUID: "KAO000017", routeID: "1",
                     routeName: LocalizedName(zhTw: "高雄17路", en: "Kaohsiung 17"),
                     departureStopNameZh: nil, destinationStopNameZh: nil)
        ]
        let matches = BusTools.fuzzyMatchRoutes(query: "台北", in: routes)
        XCTAssertEqual(matches.count, 1, "台北 must match 臺北 via normalization")
        XCTAssertEqual(matches[0].routeUID, "TPE000001")
    }

    func testFuzzyMatchStopsByEnglish() {
        let stops = [
            BusStop(stopUID: "S1", stopID: "1", stopName: LocalizedName(zhTw: "市政府", en: "City Hall"), stopPosition: nil),
            BusStop(stopUID: "S2", stopID: "2", stopName: LocalizedName(zhTw: "忠孝復興", en: "Zhongxiao Fuxing"), stopPosition: nil)
        ]
        let matches = BusTools.fuzzyMatchStops(query: "city hall", in: stops)
        XCTAssertEqual(matches.count, 1, "English fuzzy match should be case-insensitive")
        XCTAssertEqual(matches[0].stopUID, "S1")
    }

    // MARK: - Tool surface

    func testDefineToolsReturnsSix() {
        let names = BusTools.defineTools().map(\.name)
        XCTAssertEqual(names.count, 6)
        XCTAssertEqual(Set(names), Set([
            "bus_search_routes",
            "bus_search_stops",
            "bus_find_routes",
            "bus_status_arrivals",
            "bus_status_positions",
            "bus_route"
        ]))
    }

    // MARK: - City parameter parsing

    func testParseCityRejectsUnknownCity() {
        do {
            _ = try BusTools.parseCity(["city": .string("Atlantis")])
            XCTFail("unknown city should throw")
        } catch let error as TDXError {
            guard case .decoding(let msg) = error else {
                return XCTFail("expected .decoding, got \(error)")
            }
            XCTAssertTrue(msg.contains("Atlantis"))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testParseCityAcceptsValid() throws {
        let city = try BusTools.parseCity(["city": .string("Kaohsiung")])
        XCTAssertEqual(city, .Kaohsiung)
    }

    // MARK: - BusSchedule decode (#bus-routing task 2)

    func testBusScheduleDecodesTimetablesAndFrequencys() throws {
        let json = """
        [
         {"RouteUID":"TPE1","RouteName":{"Zh_tw":"671"},"SubRouteName":{"Zh_tw":"671"},"Direction":0,
          "Timetables":[{"TripID":"t1","ServiceDay":{"Monday":1,"Sunday":0},
            "StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:00"},
                         {"StopSequence":2,"StopUID":"S2","ArrivalTime":"08:18","DepartureTime":"08:18"}]}]},
         {"RouteUID":"TPE2","RouteName":{"Zh_tw":"234"},"Direction":0,
          "Frequencys":[{"StartTime":"06:00","EndTime":"22:00","MinHeadwayMins":8,"MaxHeadwayMins":12,
            "ServiceDay":{"Monday":1,"Sunday":1}}]}
        ]
        """
        let list = TDXDecode.list(BusSchedule.self, from: Data(json.utf8))
        XCTAssertEqual(list.count, 2)
        let tt = try XCTUnwrap(list.first { ($0.timetables?.isEmpty == false) })
        let trip = try XCTUnwrap(tt.timetables?.first)
        XCTAssertEqual(trip.stopTimes.count, 2)
        XCTAssertEqual(trip.stopTimes[0].departureTime, "08:00")
        XCTAssertEqual(trip.stopTimes[1].arrivalTime, "08:18")
        XCTAssertTrue(trip.serviceDay?.active(weekday: 2) ?? false, "Monday active")
        XCTAssertFalse(trip.serviceDay?.active(weekday: 1) ?? true, "Sunday inactive")
        let fq = try XCTUnwrap(list.first { ($0.frequencys?.isEmpty == false) })
        XCTAssertEqual(fq.frequencys?.first?.minHeadwayMins, 8)
    }

}
