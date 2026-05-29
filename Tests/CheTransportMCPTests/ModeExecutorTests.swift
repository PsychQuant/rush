import XCTest
import MCP
@testable import CheTransportMCP

/// Executor-level tests for Bike / Air / Maritime / Traffic / Parking, driven
/// through `<Module>Tools.handleCall` against a mocked TDXClient. Same pattern
/// as RailBusExecutorTests: argument parsing → fetch (mocked) → decode →
/// output assembly.
final class ModeExecutorTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.stub = nil
        super.tearDown()
    }

    // MARK: - Bike

    func testBikeSearchStationsFiltersByNameAndServiceType() async {
        let fixture = Data("""
        [
          {"StationUID":"YT01","StationID":"01","StationName":{"Zh_tw":"臺大醫院","En":"NTU Hospital"},
           "StationPosition":{"PositionLat":25.04,"PositionLon":121.51},"ServiceType":2,"BikesCapacity":30},
          {"StationUID":"YT02","StationID":"02","StationName":{"Zh_tw":"西門","En":"Ximen"},
           "StationPosition":{"PositionLat":25.04,"PositionLon":121.50},"ServiceType":1,"BikesCapacity":20}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await BikeTools.handleCall(
            name: "bike_search_stations",
            arguments: ["query": .string("台大"), "city": .string("Taipei"), "service_type": .string("YouBike2.0")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"station_uid\":\"YT01\""), "台大 + 2.0 match present; got \(text)")
        XCTAssertFalse(text.contains("YT02"), "西門 (and 1.0) filtered out")
    }

    func testBikeStationsNearbyJoinsAvailabilityAndSortsByDistance() async {
        // Two API fetches: station list, then availability.
        let stations = Data("""
        [
          {"StationUID":"FAR","StationName":{"Zh_tw":"遠站"},"StationPosition":{"PositionLat":25.10,"PositionLon":121.55},"ServiceType":2},
          {"StationUID":"NEAR","StationName":{"Zh_tw":"近站"},"StationPosition":{"PositionLat":25.0405,"PositionLon":121.55},"ServiceType":2}
        ]
        """.utf8)
        let availability = Data("""
        [
          {"StationUID":"NEAR","ServiceStatus":1,"AvailableRentBikes":5,"AvailableReturnBikes":10},
          {"StationUID":"FAR","ServiceStatus":1,"AvailableRentBikes":1,"AvailableReturnBikes":2}
        ]
        """.utf8)
        TestSupport.queueTokenThenAll([stations, availability])

        let result = await BikeTools.handleCall(
            name: "bike_stations_nearby",
            arguments: ["lat": .double(25.04), "lon": .double(121.55), "city": .string("Taipei"), "radius_m": .int(3000)],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("NEAR"), "near station within radius present")
        XCTAssertTrue(text.contains("\"available_rent\":5"), "availability joined onto NEAR")
        // NEAR (≈0.05 km) should sort before FAR (≈6.7 km): its UID appears first.
        if let nearIdx = text.range(of: "NEAR"), let farIdx = text.range(of: "FAR") {
            XCTAssertLessThan(nearIdx.lowerBound, farIdx.lowerBound, "nearer station should sort first")
        }
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 3, "token + station list + availability")
        // Cross-module clean-coordinate guarantee (#1): station coords + the
        // echoed search center must carry no IEEE-754 17-digit noise. This is
        // the geo-heaviest executor, so it guards the centralized JSONSanitize
        // wiring for every non-bus mode.
        XCTAssertFalse(text.contains("999999"), "no float noise in bike output; got \(text)")
        XCTAssertTrue(text.contains("\"lat\":25.04"), "search center echoed clean; got \(text)")
    }

    func testBikeStatusStationReportsAvailability() async {
        let fixture = Data("""
        [{"StationUID":"YT01","ServiceStatus":1,"AvailableRentBikes":7,"AvailableReturnBikes":3}]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await BikeTools.handleCall(
            name: "bike_status_station",
            arguments: ["station_id": .string("YT01"), "city": .string("Taipei")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"found\":true"))
        XCTAssertTrue(text.contains("\"available_rent\":7"))
    }

    func testBikeStatusStationEmptyReportsNotFound() async {
        TestSupport.queueTokenThen(Data("[]".utf8))
        let result = await BikeTools.handleCall(
            name: "bike_status_station",
            arguments: ["station_id": .string("NOPE"), "city": .string("Taipei")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true, "empty result is not an error")
        XCTAssertTrue(TestSupport.textContent(result).contains("\"found\":false"))
    }

    // MARK: - Air

    func testAirListAirportsAssembles() async {
        let fixture = Data("""
        [
          {"AirportID":"TPE","AirportName":{"Zh_tw":"臺灣桃園國際機場","En":"Taiwan Taoyuan"},
           "AirportCityName":{"Zh_tw":"桃園","En":"Taoyuan"}},
          {"AirportID":"TSA","AirportName":{"Zh_tw":"臺北松山機場","En":"Taipei Songshan"}}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await AirTools.handleCall(
            name: "air_list_airports",
            arguments: [:],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"iata\":\"TPE\""))
        XCTAssertTrue(text.contains("\"iata\":\"TSA\""))
    }

    func testAirFindFlightsAssemblesSchedule() async {
        let fixture = Data("""
        [
          {"FlightNumber":"BR189","AirlineID":"BR","DepartureAirportID":"TPE","ArrivalAirportID":"NRT",
           "ScheduleDepartureTime":"2026-05-28T09:00:00","Terminal":"2","Gate":"A5"}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await AirTools.handleCall(
            name: "air_find_flights",
            arguments: ["airport": .string("TPE"), "direction": .string("Departure")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"flight_no\":\"BR189\""))
        XCTAssertTrue(text.contains("\"gate\":\"A5\""))
    }

    func testAirRejectsBadIATA() async {
        MockURLProtocol.stub = MockURLProtocol.Stub()
        let result = await AirTools.handleCall(
            name: "air_find_flights",
            arguments: ["airport": .string("TPEX"), "direction": .string("Departure")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertEqual(result.isError, true, "4-letter IATA should be rejected")
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 0)
    }

    // MARK: - Maritime

    func testMaritimeListRoutesAssembles() async {
        let fixture = Data("""
        [
          {"RouteID":"MTR001","RouteName":{"Zh_tw":"基隆-馬祖","En":"Keelung-Matsu"},
           "OperatorID":"TWNC","DepartureStopID":"KE","DestinationStopID":"MT",
           "DepartureStopName":{"Zh_tw":"基隆"},"DestinationStopName":{"Zh_tw":"馬祖"}}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await MaritimeTools.handleCall(
            name: "maritime_list_routes",
            arguments: [:],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"route_id\":\"MTR001\""))
        XCTAssertTrue(text.contains("\"operator\":\"TWNC\""))
    }

    func testMaritimeStatusScheduleWrapsRawJSON() async {
        let raw = Data(#"[{"DepartureTime":"08:00","ArrivalTime":"12:00"}]"#.utf8)
        TestSupport.queueTokenThen(raw)

        let result = await MaritimeTools.handleCall(
            name: "maritime_status_schedule",
            arguments: ["route_id": .string("MTR001")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"route_id\":\"MTR001\""), "envelope carries route_id")
        XCTAssertTrue(text.contains("\"raw\":"), "raw passthrough wrapped")
        XCTAssertTrue(text.contains("08:00"), "raw schedule content preserved")
    }

    // MARK: - Traffic

    func testTrafficFreewayLiveAssembles() async {
        let fixture = Data("""
        [{"RoadID":"000010","RoadName":"國道1號","SectionID":"0001","Direction":0,
          "Speed":78.5,"TravelTime":120,"CongestionLevel":2,"DataCollectTime":"2026-05-28T09:00:00+08:00"}]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await TrafficTools.handleCall(
            name: "traffic_freeway_live",
            arguments: [:],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"road_id\":\"000010\""))
        XCTAssertTrue(text.contains("\"congestion\":2"))
    }

    func testTrafficIncidentsKeywordFilter() async {
        let fixture = Data("""
        [
          {"NewsID":"N1","Title":"國道3號施工","Description":"夜間封閉","RoadName":"國道3號"},
          {"NewsID":"N2","Title":"省道台9線通車","Description":"全線開放","RoadName":"台9線"}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await TrafficTools.handleCall(
            name: "traffic_incidents",
            arguments: ["keyword": .string("施工")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"news_id\":\"N1\""), "施工 keyword matches N1")
        XCTAssertFalse(text.contains("N2"), "non-matching incident filtered out client-side")
    }

    func testTrafficCCTVAssemblesStreamURLs() async {
        let fixture = Data("""
        [{"CCTVID":"CCTV-001","RoadID":"000010","LocationName":{"Zh_tw":"汐止系統","En":"Xizhi"},
          "VideoStreamURL":"https://example.com/s.m3u8","ImageURL":"https://example.com/i.jpg",
          "Position":{"PositionLat":25.07,"PositionLon":121.65}}]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await TrafficTools.handleCall(
            name: "traffic_cctv",
            arguments: [:],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"cctv_id\":\"CCTV-001\""))
        XCTAssertTrue(text.contains("m3u8"), "video stream URL passed through")
    }

    // MARK: - Parking

    func testParkingListLotsKeywordFilter() async {
        let fixture = Data("""
        [
          {"CarParkID":"P1","CarParkName":{"Zh_tw":"市府轉運站","En":"City Hall"},"Address":"信義區","TotalSpaces":320,"CarParkType":2},
          {"CarParkID":"P2","CarParkName":{"Zh_tw":"圓山","En":"Yuanshan"},"Address":"中山區","TotalSpaces":100,"CarParkType":3}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await ParkingTools.handleCall(
            name: "parking_list_lots",
            arguments: ["city": .string("Taipei"), "keyword": .string("市府")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"lot_id\":\"P1\""), "市府 keyword matches P1")
        XCTAssertFalse(text.contains("P2"), "non-matching lot filtered out")
    }

    func testParkingStatusReportsAvailableSpaces() async {
        let fixture = Data("""
        [{"CarParkID":"P1","AvailableSpaces":42,"ServiceStatus":0,"DataCollectTime":"2026-05-28T09:00:00+08:00"}]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await ParkingTools.handleCall(
            name: "parking_status",
            arguments: ["city": .string("Taipei"), "lot_id": .string("P1")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"lot_id\":\"P1\""))
        XCTAssertTrue(text.contains("\"available\":42"))
    }

    func testParkingRejectsInvalidCity() async {
        MockURLProtocol.stub = MockURLProtocol.Stub()
        let result = await ParkingTools.handleCall(
            name: "parking_list_lots",
            arguments: ["city": .string("Atlantis")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertEqual(result.isError, true)
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 0)
    }
}
