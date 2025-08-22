# Copilot instructions for dart_anyio

This is a Dart monorepo for industrial data gateways and RPC. Key packages live under `packages/` and are composed into the service in `packages/service`.

## Big picture
- Architecture (files: `packages/service/lib/src/*.dart`):
	- Transport → Channel → Device → Time-series → HTTP API.
	- Each device channel can run in an isolated Dart isolate for fault tolerance (`isolated_channel.dart`).
	- Managers wire things together:
		- `TransportManagerImpl` (`transport_manager.dart`) creates/reuses transport sessions.
		- `ChannelManagerImpl` (`channel_manager.dart`) creates either isolated or in-process channel sessions.
		- `ServiceManager` orchestrates devices, collection, and exposes APIs (`service.dart`, `http_api_server.dart`).
- Templates/config: device + protocol templates live in `packages/template` and example YAML under `packages/service/example`.

## Code generation and models
- Serialization uses `dart_mappable`.
	- DO NOT edit generated files: `*.mapper.dart`, `*.freezed.dart` (see headers like “GENERATED CODE - DO NOT MODIFY BY HAND”).
	- To add/change models: annotate with `@MappableClass()` in the source file (e.g., `time_series.dart`, `isolated_channel.dart`) and run codegen.
	- Polymorphic types use discriminators (e.g., transport option `type: tcp` in `transports/tcp.dart` → `tcp.mapper.dart`).
- Inter-isolate messages (in `isolated_channel.dart`) are mappable classes; keep fields JSON-serializable.

## Developer workflows (Windows PowerShell)
- Install deps (root uses path dependencies across packages):
	```pwsh
	dart pub get
	```
- Run code generation where needed (example: service):
	```pwsh
	pushd packages/service; dart run build_runner build --delete-conflicting-outputs; popd
	```
	Use `watch` during dev: `dart run build_runner watch`.
- Analyze and test (per package):
	```pwsh
	pushd packages/service; dart analyze; dart test; popd
	```
- Run the service example HTTP API:
	```pwsh
	dart run packages/service/bin/anyio.dart packages/service/example/device.yaml packages/service/example/templates
	```

## Project-specific conventions
- Use `on Exception catch (e, stackTrace)` for error handling and log via `LoggingManager` where available; avoid bare `catch`.
- Prefer explicit `Future<void>.delayed(...)` to satisfy analyzer rules seen in this repo.
- For events/DTOs, prefer `toMap()`/`toJson()` from mappable mixins and pass simple maps across isolate boundaries and HTTP responses.
- When registering factories:
	- Transport: implement `TransportFactoryBase<O>` and `TransportSessionBase`, then `TransportManagerImpl.register<O>()`; access `factory.optionMapper` once to initialize mappers.
	- Channel: implement `ChannelFactoryBase<CP,TP,S>` and `ChannelSessionBase`, then `ChannelManagerImpl.registerFactory<CP,TP,S>()`; accessing `channelOptionMapper/templateOptionMapper` primes mappers.

## Where to look/examples
- HTTP API surface and payload shapes: `packages/service/lib/src/http_api_server.dart`.
- Time-series API and stats models: `packages/service/lib/src/time_series.dart`.
- Isolated channel lifecycle and protocol: `packages/service/lib/src/isolated_channel.dart`.
- Transport registration pattern: `packages/service/lib/src/transport_manager.dart`.
- Channel registration and isolation toggle: `packages/service/lib/src/channel_manager.dart`.
- Modbus adapter and polling/mapping: `packages/adapter_modbus/lib/src/*`.

If anything is unclear or missing (e.g., how to reconstruct transports inside isolates, or expected YAML schema fields), tell me which part you’re working on, and I’ll refine these rules with concrete snippets and steps.
