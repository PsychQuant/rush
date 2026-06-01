# tra-time-dependent-routing Specification

## Purpose

TBD - created by archiving change 'add-tra-time-dependent-routing'. Update Purpose after archive.

## Requirements

### Requirement: TRA time-dependent earliest-arrival routing tool

The system SHALL provide an MCP tool that, given an origin station ID, a destination station ID, an optional earliest departure time, and the TRA system code, returns the itinerary that reaches the destination earliest among the trains serving that origin–destination pair on the queried day. The tool SHALL route over the real timetable (each train's scheduled departure and arrival times), not over average headways, and SHALL only consider trains departing at or after the requested departure time. The departure time SHALL default to the current Asia/Taipei time when omitted. The tool SHALL accept only the TRA system code (the only mode with both a public timetable and a live train-delay board).

#### Scenario: Earliest arrival on schedule

- **WHEN** the tool is called with an origin, a destination, and a departure time, and no live delay data applies
- **THEN** it returns the itinerary (train number, departure time, arrival time) that departs at or after the requested time and arrives earliest, with each leg labelled as scheduled

#### Scenario: No reachable train

- **WHEN** no train serves the origin–destination pair at or after the requested departure time
- **THEN** the tool returns an empty itinerary plus a note, rather than an error (empty is not an error)

#### Scenario: Timetable data unavailable

- **WHEN** the timetable data source cannot be retrieved
- **THEN** the tool returns an empty itinerary plus a note explaining the data is unavailable, rather than crashing or surfacing an internal error

---
### Requirement: Live-delay adjustment and freshness labelling

The tool SHALL apply current per-train delays to the candidate trains' times before selecting the earliest arrival, so that the chosen itinerary reflects live conditions and can differ from the schedule-only choice. Each itinerary leg SHALL be labelled to indicate whether a live delay was applied (live) or no live data was available for that train (scheduled). When the live delay source is unavailable, the tool SHALL fall back to the scheduled times and label all legs scheduled rather than failing.

#### Scenario: A live delay changes the chosen train

- **WHEN** the train that arrives earliest by schedule is running late enough that another, later-scheduled train now arrives earlier
- **THEN** the tool returns the later-scheduled train as the earliest-arriving itinerary, with its legs reflecting the live-adjusted times

##### Example:

- **GIVEN** train X departs 08:00 and is scheduled to arrive 09:00 but is running 15 minutes late (live arrival 09:15), and train Y departs 08:10 and is scheduled to arrive 09:05 on time
- **WHEN** rail_route is called with a departure time of 08:00
- **THEN** the result is train Y (live-adjusted arrival 09:05 beats train X's 09:15), with train Y's legs labelled according to whether live data applied

#### Scenario: No live data falls back to scheduled

- **WHEN** the live delay source returns no data for the candidate trains
- **THEN** the tool still returns the schedule-based earliest-arrival itinerary with every leg labelled scheduled, rather than failing
