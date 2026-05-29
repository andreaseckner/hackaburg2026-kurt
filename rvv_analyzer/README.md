# RVV Analyzer

A Flutter-based application for analyzing and visualizing GTFS (General Transit Feed Specification) data, specifically focused on the RVV (Regensburger Verkehrsverbund) network.

## Features

- **Map Visualization**: Interactive map using `flutter_map` to visualize transit routes and stops.
- **GTFS Parsing**: Efficiently parse GTFS data (`stops.txt`, `routes.txt`, etc.) from local assets.
- **State Management**: Robust state handling using `flutter_bloc`.
- **GTFS Data Analysis**: Tools to analyze transit schedules and performance.

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Dart SDK
- macOS/Android/iOS development environment

### Installation

1. Clone the repository.
2. Run `flutter pub get` to install dependencies.
3. If using FVM: `fvm flutter pub get`.
4. Run the app: `flutter run`.

## Project Structure

- `lib/features/map`: Map-related UI and logic.
- `lib/gtfs`: GTFS data models and parsing logic.
- `lib/core`: Core utilities and generated assets.
- `assets/gtfs`: Contains the raw GTFS data files.
