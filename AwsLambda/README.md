# GTFS-RT Lambda pipeline

Two AWS Lambda functions that replace the Cloudflare Worker's inline GTFS-RT
decode (which exceeded Workers Free tier's fixed 10ms CPU ceiling for SF
Muni specifically):

- **`src/refresher/`** — scheduled (`rate(2 minutes)`), fetches the 511.org
  regional GTFS-RT feed, decodes it, builds the arrivals index, writes it to
  a single S3 object (`snapshots/RG.json`).
- **`src/reader/`** — behind a Function URL gated by a shared-secret header
  (`X-Internal-Key`), reads that S3 object (30s in-memory cache per warm
  execution environment), slices it per-stop, renders SIRI JSON. Stop names
  are intentionally left unresolved here (`StopPointName == StopPointRef`)
  — the Cloudflare Worker resolves real names from its own KV cache after
  calling this.

Full design rationale: `docs/superpowers/specs/2026-08-01-gtfsrt-lambda-migration-design.md`
(gitignored, local only). Full implementation plan:
`docs/superpowers/plans/2026-08-02-gtfsrt-lambda-migration.md` (same).

## Deploying

Infrastructure is defined in `template.yaml` (AWS SAM) and deployed by
`.github/workflows/deploy-lambda.yml` on every push to `main` that touches
`AwsLambda/**`, authenticated via GitHub OIDC (no long-lived AWS keys in
GitHub secrets).

**`sam build`/`sam validate` have never been run against `template.yaml`** —
no AWS/SAM CLI was available in the sandbox this was authored in. Run both
locally before the first real deploy:

```bash
cd AwsLambda
sam validate --lint
sam build
```

If `sam build` complains about the esbuild config (`CodeUri`/`Handler`/
`EntryPoints` in `template.yaml`), that's the one part of this template that
was never mechanically verified — fix it up based on the actual error.

### One-time AWS OIDC bootstrap (run once, by you — not automatable)

GitHub Actions can't create its own trust relationship with AWS, so this is
a manual, one-time setup in your AWS account.

```bash
# 1. Check whether a GitHub OIDC provider already exists in the account
#    (many AWS accounts already have one from other projects — skip step 2 if so).
aws iam list-open-id-connect-providers

# 2. If it's not listed, create it.
#    ⚠️ THUMBPRINT WARNING: do not copy a thumbprint value from this repo's
#    history or from memory — get the current one from AWS's own docs
#    (search "configure GitHub OIDC AWS thumbprint" for the current guide)
#    or let the AWS Console's "Add identity provider" flow fetch it for you
#    automatically. A stale or malformed thumbprint here silently breaks
#    every future deploy with an auth error, not a helpful validation error.
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list <GET-THE-CURRENT-VALUE-FROM-AWS-DOCS>

# 3. Write the trust policy, scoped to this repo's main branch only.
cat > /tmp/sftransitwatch-gha-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
        "StringLike": { "token.actions.githubusercontent.com:sub": "repo:rularner/SFTransitWatch:ref:refs/heads/main" }
      }
    }
  ]
}
EOF
# Replace ACCOUNT_ID above with your real 12-digit AWS account ID before running the next command.

# 4. Create the deploy role.
aws iam create-role \
  --role-name github-actions-sftransitwatch-deploy \
  --assume-role-policy-document file:///tmp/sftransitwatch-gha-trust-policy.json

# 5. Attach a deploy policy. `sam deploy` needs CloudFormation, the SAM-managed S3
#    deployment bucket, Lambda, IAM PassRole (scoped to roles this stack creates),
#    EventBridge Scheduler, and Budgets. This is broader than the Lambda functions'
#    own runtime roles (see template.yaml) by necessity — CloudFormation itself
#    needs permission to create those roles.
cat > /tmp/sftransitwatch-gha-deploy-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "cloudformation:*", "Resource": "arn:aws:cloudformation:*:ACCOUNT_ID:stack/sftransitwatch-gtfsrt/*" },
    { "Effect": "Allow", "Action": "cloudformation:*", "Resource": "arn:aws:cloudformation:*:ACCOUNT_ID:stack/aws-sam-cli-managed-default/*" },
    { "Effect": "Allow", "Action": "cloudformation:CreateChangeSet", "Resource": "arn:aws:cloudformation:*:aws:transform/Serverless-2016-10-31" },
    { "Effect": "Allow", "Action": ["s3:*"], "Resource": ["arn:aws:s3:::aws-sam-cli-managed-*", "arn:aws:s3:::aws-sam-cli-managed-*/*"] },
    { "Effect": "Allow", "Action": ["lambda:*"], "Resource": "arn:aws:lambda:*:ACCOUNT_ID:function:sftransitwatch-gtfsrt-*" },
    { "Effect": "Allow", "Action": ["iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PassRole", "iam:TagRole"], "Resource": "arn:aws:iam::ACCOUNT_ID:role/sftransitwatch-gtfsrt-*" },
    { "Effect": "Allow", "Action": ["scheduler:*", "events:*"], "Resource": "*" },
    { "Effect": "Allow", "Action": ["budgets:*"], "Resource": "*" },
    { "Effect": "Allow", "Action": ["s3:CreateBucket", "s3:PutBucketPolicy", "s3:PutEncryptionConfiguration", "s3:PutBucketPublicAccessBlock"], "Resource": "arn:aws:s3:::sam-*" }
  ]
}
EOF
# Replace ACCOUNT_ID above with your real account ID before running the next commands.

aws iam put-role-policy \
  --role-name github-actions-sftransitwatch-deploy \
  --policy-name sftransitwatch-gtfsrt-deploy \
  --policy-document file:///tmp/sftransitwatch-gha-deploy-policy.json

rm /tmp/sftransitwatch-gha-trust-policy.json /tmp/sftransitwatch-gha-deploy-policy.json
```

### Required GitHub repository secrets

Set these in the repo's Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `AWS_ACCOUNT_ID` | The 12-digit AWS account ID used above |
| `API_511_KEY` | The same 511.org API key already used by the Worker (this Lambda gets its own copy — it calls 511.org independently of the Worker) |
| `GTFSRT_INTERNAL_KEY` | A newly generated random secret (e.g. `openssl rand -hex 32`) — becomes the `X-Internal-Key` value both the Worker and the reader Lambda must agree on. **This same value also has to be set as the `GTFSRT_INTERNAL_KEY` Worker secret** (`wrangler secret put`, see `CloudflareWorker/README.md`) — it's one shared value, not two independent ones. |
| `BUDGET_ALERT_EMAIL` | Email address for the $1/month AWS Budgets alert |

### After first deploy

Get the reader Function URL from the stack output and verify it directly
before pointing the Worker at it:

```bash
aws cloudformation describe-stacks --stack-name sftransitwatch-gtfsrt \
  --query "Stacks[0].Outputs[?OutputKey=='ReaderFunctionUrl'].OutputValue" --output text

curl -H "X-Internal-Key: <the GTFSRT_INTERNAL_KEY value>" \
  "<reader function url>?agency=SF&stopCode=16393"
```

Then see `CloudflareWorker/README.md`'s "GTFS-RT Lambda dependency" section
for setting the Worker's two secrets and the recommended merge/deploy order.
