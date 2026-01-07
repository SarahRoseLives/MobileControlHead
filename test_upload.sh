#!/bin/bash

# Test script to verify the upload endpoint works

# Create test files
mkdir -p /tmp/test_system
echo -e "\"Sysname\"\t\"Control Channel List\"\t\"Offset\"\t\"NAC\"\t\"Modulation\"\t\"TGID Tags File\"\t\"Whitelist\"\t\"Blacklist\"\t\"Center Frequency\"" > /tmp/test_system/test_trunk.tsv
echo -e "\"6643\"\t\"851.0125,852.3875\"\t\"0\"\t\"0\"\t\"cqpsk\"\t\"systems/6643/6643_talkgroups.tsv\"\t\"systems/6643/6643_whitelist.tsv\"\t\"systems/6643/6643_blacklist.tsv\"\t\"\"" >> /tmp/test_system/test_trunk.tsv

echo -e "12345\tTest Talkgroup" > /tmp/test_system/test_talkgroups.tsv

# Upload to the server
echo "Testing upload endpoint..."
curl -v -X POST http://192.168.1.240:9000/api/system/upload \
  -F "system_id=6643" \
  -F "site_id=16773" \
  -F "trunk_file=@/tmp/test_system/test_trunk.tsv" \
  -F "talkgroup_file=@/tmp/test_system/test_talkgroups.tsv"

echo ""
echo "Test complete. Check server logs for details."
