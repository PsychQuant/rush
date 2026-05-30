## ADDED Requirements

### Requirement: TDX endpoint paths have a single source of truth

The system SHALL define every TDX API endpoint path in one registry. Production code SHALL reference the registry instead of embedding path string literals. Contract tests SHALL enumerate the registry so that every registered endpoint is covered.

#### Scenario: Production code resolves paths through the registry

- **WHEN** a tool constructs a TDX request
- **THEN** it obtains the endpoint path from the registry, not from an inline string literal

#### Scenario: New endpoint must be registered

- **WHEN** a new TDX endpoint is added to the server
- **THEN** it MUST have a registry entry, and the contract-test enumeration covers it without a separately maintained list

### Requirement: Each non-static endpoint has a live contract test

The system SHALL provide one contract test per non-static endpoint that issues a real request to TDX and asserts three conditions in order: the HTTP status is not 404, the HTTP status is 200, and the response body decodes into the registry-declared model type. Static endpoints that return hardcoded client-side data SHALL be exempt.

#### Scenario: Correct path and schema pass

- **WHEN** the contract test runs against a correctly registered endpoint
- **THEN** the request returns HTTP 200 and the body decodes into the declared model type

#### Scenario: Path drift fails the test

- **WHEN** an endpoint path no longer matches the current TDX API
- **THEN** the contract test fails on the non-404 or 200 assertion

#### Scenario: Schema drift fails the test

- **WHEN** TDX changes the response shape of an endpoint while still returning HTTP 200
- **THEN** the contract test fails at the decode step

### Requirement: Contract tests skip when credentials are absent

Contract tests SHALL skip rather than fail when TDX credentials are not available, so that environments without secrets keep a green test run.

#### Scenario: No credentials present

- **WHEN** contract tests run without TDX credentials in the keychain or CI secret
- **THEN** they are skipped and the overall test run does not fail on their account

### Requirement: Contract tests run on schedule, not on every pull request

Mock-based unit tests SHALL run on every pull request. Live contract tests SHALL run on a nightly schedule, on a release gate, and on manual dispatch, and SHALL NOT block an ordinary pull request.

#### Scenario: Pull request runs unit tests only

- **WHEN** a pull request triggers CI
- **THEN** mock-based unit tests run and live contract tests do not

#### Scenario: Nightly schedule runs contract tests

- **WHEN** the nightly schedule fires
- **THEN** live contract tests run against TDX using the CI-injected credentials
