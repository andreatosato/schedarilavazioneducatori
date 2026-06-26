# Deployment Plan - Strade Aperte Azure Rebuild

Status: Validated - ready to deploy Application Insights and backend remediation

## Goal

Recreate the Azure resources from a clean baseline for the Strade Aperte Static Web App and API, using consistent resource names and a dedicated Azure Function App backend.

## Current Follow-up Goal

Add Application Insights monitoring to the dedicated Azure Function App, make the live backend observable, and use the collected telemetry to resolve the current `/api/schede` 503. The public browser check currently receives a platform `503 Service Unavailable` from `/api/schede`, so the request is failing before the application handler can return its own JSON error response.

## Proposed Monitoring and Backend Remediation

- Create a workspace-based Application Insights resource in `rg-stradeaperte-v2`, colocated with the Function App in `westeurope`.
- Create a Log Analytics workspace for the Application Insights component.
- Set `APPLICATIONINSIGHTS_CONNECTION_STRING` on `stradeaperte20260625-api` so Azure Functions host/runtime logs, requests, traces and exceptions are captured.
- Keep the Function App on Linux Consumption with Node 22, because Node 22 is the newest supported Node.js version for Linux Consumption Functions.
- Keep App Service Authentication disabled on the dedicated Function App for now. This API uses anonymous HTTP triggers and the linked backend has been observed returning proxy-level 503s when EasyAuth is active.
- Redeploy the current `api/` package to the Function App after infrastructure validation, then verify the live Static Web App route `/api/schede` with GET, POST and DELETE.
- Query Application Insights after deployment if the 503 persists, focusing on host startup errors, function indexing, package loading, Cosmos authentication and unhandled exceptions.

## .NET Backend Assessment

- Do not port to .NET as the first fix. The current failure is a platform-level HTML 503, not an application-level Node.js exception from `schedeStore.toHttpError()`.
- Consider a .NET isolated Functions backend only if telemetry shows repeated Node worker/package/runtime failures that are easier to eliminate with a typed .NET implementation.
- If a .NET port is chosen later, keep the HTTP contract unchanged: `GET /api/schede`, `POST /api/schede`, `DELETE /api/schede/{id}` and the same Cosmos DB document shape.

## Current Findings

- Static Web App exists as `stradeaperte` in resource group `rg-stradeaperte`, but that resource group is stuck in `Deleting` with active provider locks.
- Public hostname is `black-sand-00abc5803.7.azurestaticapps.net`.
- Static Web App SKU is `Standard`.
- Cosmos DB account exists as `stradeaperte`.
- No Function App exists in `rg-stradeaperte`.
- No Static Web App linked backend exists.
- Current repo defaults still reference `black-sand-00abc5803` / `black-sand-00abc5803-api`, which does not match the deployed resource names.

## Proposed Target State

- Resource group: `rg-stradeaperte-v2`.
- Static Web App: `stradeaperte20260625` on Standard SKU.
- Cosmos DB for NoSQL account: `stradeaperte20260625`.
- Database: `schede`.
- Container: `schede`, partition key `/id`.
- Dedicated Function App: `stradeaperte20260625-api` on Linux Consumption, Node 22, system-assigned managed identity, in `westeurope` because the plan was not supported in `italynorth`.
- Static Web App linked backend: `/api/*` routed to `stradeaperte20260625-api`.
- Cosmos DB access: Function App managed identity with Cosmos DB Built-in Data Contributor role.
- App setting on Function App: `COSMOS_ENDPOINT` pointing at the Cosmos DB account endpoint.

## Destructive Actions Requiring Approval

- Delete existing `stradeaperte` Static Web App.
- Delete existing `stradeaperte` Cosmos DB account and all schede data inside it.
- Delete related Application Insights resource(s) if they belong only to this app.
- Recreate resources with consistent names.

## Repository Changes Planned

- Update Bicep parameters to use `stradeaperte20260625` as the base name.
- Make Cosmos DB account naming explicit instead of deriving `name-cosmos`.
- Update the GitHub Actions Function App deploy target to `stradeaperte20260625-api`.
- Update README commands/names so future deploys do not recreate `black-sand-*` resources.
- Validate Bicep and API tests after edits.

## Validation Plan

- Compile Bicep parameter file. Completed: `infra/main.bicepparam` compiled successfully with no diagnostics.
- Run API unit tests with `npm test` under `api/`. Completed: 16 tests passed, 0 failed.
- Run Azure CLI what-if or validation if permissions allow.
- After deployment, verify:
  - Static site returns HTTP 200. Completed: `/` and `/history.html` returned 200.
  - `/api/schede` no longer returns `Backend call failure`. Completed: Static Web App `/api/schede` returned `{"items": [], "continuationToken": null}`.
  - Direct Function App endpoint resolves. Completed: direct host returned HTTP 400 with `Login not supported for provider azureStaticWebApps`; use the Static Web App `/api/*` route for public access.

## Validation Proof - Application Insights and Backend Remediation

- `az bicep build --file infra/main.bicep --outfile infra/main.json`: passed with no Bicep warnings or errors after the Application Insights patch.
- `az bicep build-params --file infra/main.bicepparam --outfile %TEMP%/stradeaperte-main.parameters.json`: passed.
- Generated ARM template checks: `APPLICATIONINSIGHTS_CONNECTION_STRING` present once, `Microsoft.Insights/components` present, `Microsoft.OperationalInsights/workspaces` present, `authsettingsV2` present, `Node|22` present, `Node|20` absent.
- `git diff --check`: passed; only line-ending conversion warnings were reported by Git on Windows.
- `npm test` in `api/`: passed, 16/16 tests.
- Browser-level live check before deploy: `/api/schede` returns platform HTML `503 Service Unavailable`, confirming the backend issue is still live and must be remediated by deploying the validated infrastructure/runtime settings and enabling telemetry.

## Execution Plan

1. Get explicit approval for destructive resource deletion and rebuild. Completed: user approved deleting and recreating all app resources in `rg-stradeaperte`.
2. Patch repo configuration for the real `stradeaperte` names. Completed.
3. Validate locally. Completed.
4. Delete/recreate Azure resources only after approval. Completed: old `rg-stradeaperte` remained stuck in `Deleting`, so a clean `rg-stradeaperte-v2` environment was created.
5. Deploy infrastructure. Completed.
6. Deploy API code. Completed via remote package URL because `config-zip` is not supported with this Function App/storage configuration.
7. Verify public endpoints. Completed.
