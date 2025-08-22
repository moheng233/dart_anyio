#!/bin/bash

# API demonstration script for AnyIO Service
# This script demonstrates the HTTP API endpoints

echo "🚀 AnyIO Service API Demo"
echo "========================="

BASE_URL="http://localhost:8080"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to make API calls and display results
api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    local description=$4
    
    echo -e "\n${BLUE}📡 $description${NC}"
    echo -e "${YELLOW}$method $endpoint${NC}"
    
    if [ -n "$data" ]; then
        echo -e "${YELLOW}Data: $data${NC}"
        response=$(curl -s -X $method "$BASE_URL$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data" 2>/dev/null)
    else
        response=$(curl -s -X $method "$BASE_URL$endpoint" 2>/dev/null)
    fi
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo -e "${GREEN}✅ Response:${NC}"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    else
        echo -e "${RED}❌ Failed to connect to service${NC}"
        echo "Make sure the service is running: dart bin/anyio.dart example/device.yaml example/templates/"
        return 1
    fi
}

# Check if service is running
echo -e "\n${BLUE}🔍 Checking service status...${NC}"
if ! curl -s "$BASE_URL/health" > /dev/null 2>&1; then
    echo -e "${RED}❌ Service is not running!${NC}"
    echo "Please start the service first:"
    echo "  cd packages/service"
    echo "  dart bin/anyio.dart example/device.yaml example/templates/"
    echo ""
    echo "Then run this demo script again."
    exit 1
fi

echo -e "${GREEN}✅ Service is running!${NC}"

# API demonstrations
api_call "GET" "/health" "" "Health Check"

api_call "GET" "/devices" "" "List All Devices"

api_call "GET" "/devices/test" "" "Get Device Details"

api_call "GET" "/devices/test/values" "" "Get Current Values"

api_call "GET" "/devices/test/points" "" "Get Point Definitions"

api_call "GET" "/devices/test/points/n1" "" "Get Specific Point Value"

api_call "POST" "/devices/test/write" '{"pointId": "n2", "value": 1}' "Write to Device Point"

api_call "GET" "/history/test" "" "Query Historical Data"

api_call "GET" "/history/test/n1?limit=5" "" "Query Point History with Limit"

api_call "GET" "/stats" "" "Get System Statistics"

echo -e "\n${GREEN}🎉 API Demo Complete!${NC}"
echo -e "\n${BLUE}📖 Additional API Examples:${NC}"
echo "• Query history with time range:"
echo "  curl \"$BASE_URL/history/test/n1?start=2024-01-01T00:00:00Z&end=2024-12-31T23:59:59Z\""
echo ""
echo "• Write multiple values:"
echo "  curl -X POST $BASE_URL/devices/test/write -H 'Content-Type: application/json' -d '{\"pointId\": \"n1\", \"value\": 42.5}'"
echo ""
echo "• Get real-time values:"
echo "  while true; do curl -s $BASE_URL/devices/test/values | jq; sleep 1; done"