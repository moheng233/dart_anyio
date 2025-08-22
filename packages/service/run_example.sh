#!/bin/bash

# Example script to run the AnyIO service with example configuration

echo "Starting AnyIO Service Example..."

cd "$(dirname "$0")"

# Check if dart is available
if ! command -v dart &> /dev/null; then
    echo "Dart SDK not found. Please install Dart first."
    exit 1
fi

# Run the service with example configuration
dart bin/anyio.dart example/device.yaml example/templates 8080