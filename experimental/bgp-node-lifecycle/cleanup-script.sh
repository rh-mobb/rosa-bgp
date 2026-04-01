#!/bin/bash
# Cleanup stale BGP Route Server peers for deleted or replaced ROSA worker nodes
# This script identifies and deletes peers whose IP addresses no longer match
# any active EC2 instances tagged as router nodes.

set -euo pipefail

# Configuration
DRY_RUN="${DRY_RUN:-false}"
MIN_AGE_MINUTES="${MIN_AGE_MINUTES:-30}"
CLUSTER_ID="${CLUSTER_ID:?Required: Set CLUSTER_ID environment variable}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:?Required: Set AWS_DEFAULT_REGION environment variable}"

echo "Starting BGP peer cleanup (dry-run=$DRY_RUN, min-age=${MIN_AGE_MINUTES}min)"
echo "Cluster ID: $CLUSTER_ID"
echo "AWS Region: $AWS_DEFAULT_REGION"
echo ""

# 1. Get all active router node IPs from EC2
echo "Querying EC2 for active router node IPs..."
ACTIVE_IPS=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:kubernetes.io/cluster/${CLUSTER_ID},Values=owned" \
    "Name=tag:bgp_router,Values=true" \
    "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].PrivateIpAddress' \
  --output text)

if [ -z "$ACTIVE_IPS" ]; then
  echo "WARNING: No active router nodes found!"
  echo "This could mean the cluster is down or there's a configuration issue."
  echo "Exiting without deleting any peers to be safe."
  exit 0
fi

echo "Active router node IPs: $ACTIVE_IPS"
echo ""

# 2. Get all daemonset-managed peers (exclude already deleted)
echo "Querying Route Server for managed BGP peers..."
ALL_PEERS=$(aws ec2 describe-route-server-peers \
  --query "RouteServerPeers[?Tags[?Key=='managed-by' && Value=='daemonset'] && State!='deleted'].{Id:RouteServerPeerId,Ip:PeerAddress,State:State,Created:CreationTime}" \
  --output json)

TOTAL_PEERS=$(echo "$ALL_PEERS" | jq length)
echo "Total managed peers (excluding deleted): $TOTAL_PEERS"
echo ""

if [ "$TOTAL_PEERS" -eq 0 ]; then
  echo "No managed peers found. Nothing to do."
  exit 0
fi

# 3. Process each peer
NOW_EPOCH=$(date +%s)
DELETED_COUNT=0
SKIPPED_COUNT=0

echo "Processing peers..."
echo ""

for peer in $(echo "$ALL_PEERS" | jq -c '.[]'); do
  PEER_ID=$(echo "$peer" | jq -r '.Id')
  PEER_IP=$(echo "$peer" | jq -r '.Ip')
  PEER_STATE=$(echo "$peer" | jq -r '.State')
  CREATED_TIME=$(echo "$peer" | jq -r '.Created')

  # Check if IP is in active list
  if echo "$ACTIVE_IPS" | grep -qw "$PEER_IP"; then
    echo "SKIP: Peer $PEER_ID ($PEER_IP) - IP is active"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  # Calculate age
  CREATED_EPOCH=$(date -d "$CREATED_TIME" +%s 2>/dev/null || echo "$NOW_EPOCH")
  AGE_MINUTES=$(( (NOW_EPOCH - CREATED_EPOCH) / 60 ))

  # Check minimum age
  if [ "$AGE_MINUTES" -lt "$MIN_AGE_MINUTES" ]; then
    echo "SKIP: Peer $PEER_ID ($PEER_IP) - age ${AGE_MINUTES}min < ${MIN_AGE_MINUTES}min threshold"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  # Delete stale peer
  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY-RUN: Would delete peer $PEER_ID (ip=$PEER_IP state=$PEER_STATE age=${AGE_MINUTES}min)"
    DELETED_COUNT=$((DELETED_COUNT + 1))
  else
    echo "DELETING: Peer $PEER_ID (ip=$PEER_IP state=$PEER_STATE age=${AGE_MINUTES}min)"
    if aws ec2 delete-route-server-peer --route-server-peer-id "$PEER_ID"; then
      echo "✓ Deleted peer $PEER_ID"
      DELETED_COUNT=$((DELETED_COUNT + 1))
    else
      echo "✗ Failed to delete peer $PEER_ID" >&2
    fi
  fi
done

echo ""
echo "Cleanup complete: deleted=$DELETED_COUNT skipped=$SKIPPED_COUNT"
