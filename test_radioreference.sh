#!/bin/bash

# Test RadioReference server-side system creation

# Replace with your actual RadioReference credentials
USERNAME="your_username"
PASSWORD="your_password"
SYSTEM_ID=6643

echo "Testing RadioReference Create System endpoint..."
echo "System ID: $SYSTEM_ID"
echo ""

# Test create system
curl -v -X POST http://localhost:9000/api/radioreference/create-system \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\", \"system_id\": $SYSTEM_ID}"

echo ""
echo ""
echo "Testing List Sites endpoint..."
curl -X GET "http://localhost:9000/api/radioreference/list-sites?system_id=$SYSTEM_ID"

echo ""
echo ""
echo "Test complete. Check server logs for details."
