#!/bin/bash
set -euo pipefail
# FeedTo Feed Poller — called by cron every minute
# Fetches pending feeds and outputs them for the agent to process

API_URL="${FEEDTO_API_URL:-https://feedto.ai}"
API_KEY="${FEEDTO_API_KEY:-}"

if [ -z "$API_KEY" ]; then
  echo "ERROR: FEEDTO_API_KEY not configured. Set it in your OpenClaw skill config."
  exit 1
fi

# Fetch pending feeds with timeout
RESPONSE=$(curl -s -f --max-time 15 --connect-timeout 5 \
  -H "X-API-Key: $API_KEY" \
  "${API_URL}/api/feeds/pending?limit=10" 2>&1) || {
  echo "ERROR: Failed to fetch feeds from ${API_URL}: $RESPONSE"
  exit 1
}

# Validate JSON response
if ! echo "$RESPONSE" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  echo "ERROR: Invalid JSON response from server"
  exit 1
fi

# Check if there are any feeds
FEED_COUNT=$(echo "$RESPONSE" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    feeds = d.get('feeds', [])
    print(len(feeds))
except Exception:
    print(0)
" 2>/dev/null)

if [ "${FEED_COUNT:-0}" = "0" ]; then
  echo "NO_NEW_FEEDS"
  exit 0
fi

# Output feeds as structured data for the agent
echo "NEW_FEEDS: $FEED_COUNT"
echo ""
echo "$RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
feeds = data.get('feeds', [])
for i, feed in enumerate(feeds, 1):
    print(f'--- Feed {i}/{len(feeds)} ---')
    print(f'ID: {feed[\"id\"]}')
    print(f'Type: {feed.get(\"type\", \"unknown\")}')
    title = feed.get('title') or ''
    if title:
        print(f'Title: {title[:200]}')
    url = feed.get('url') or ''
    if url:
        print(f'URL: {url[:500]}')
    content = feed.get('content', '')
    # Truncate to 5000 chars per feed to stay within context budget
    if len(content) > 5000:
        content = content[:5000] + f'... [truncated, {len(content)} chars total]'
    print(f'Content:')
    print(content)
    print()
"
