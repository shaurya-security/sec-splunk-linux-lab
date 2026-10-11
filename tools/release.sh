#!/usr/bin/env bash
# Package the deploy client, manifest, and SPL; upload to S3; run it on the Splunk host via SSM.
# Usage: tools/release.sh <bucket> <splunk-instance-id> <password-ssm-param> [--apply] [--enable]
# Never opens port 8089: the client calls Splunk on 127.0.0.1 from the instance itself.
set -euo pipefail
BUCKET=$1; INSTANCE=$2; PARAM=$3; shift 3
FLAGS="$*"
cd "$(dirname "$0")/.."
VER=$(date -u +%Y%m%dT%H%M%SZ)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar czf "$TMP/sigma-deploy.tgz" tools/deploy_sigma_searches.py detections/sigma/deployment.yml \
  detections/generated/*.spl detections/sigma/*/*.yml
KEY="deployments/sigma/$VER/sigma-deploy.tgz"
aws s3 cp "$TMP/sigma-deploy.tgz" "s3://$BUCKET/$KEY"
CMD="set -e; d=\$(mktemp -d); cd \$d; aws s3 cp s3://$BUCKET/$KEY . ; tar xzf sigma-deploy.tgz; python3 tools/deploy_sigma_searches.py --repo-root . --password-param $PARAM $FLAGS"
aws ssm send-command --instance-ids "$INSTANCE" --document-name AWS-RunShellScript \
  --parameters "commands=[\"$CMD\"]" --query Command.CommandId --output text
