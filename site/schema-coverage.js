// GENERATED FILE. Do not hand-edit — regenerate with
// factory/ci/Test-SchemaCoverage.ps1 -WriteAsset, whose CI run fails when
// this file and factory/ci/schema-coverage-register.json disagree.
//
// The answers the wizard collects that reach nothing but lz-config.json.
// unmetDependencies() in app.js marks them so the client is told at export
// time, rather than discovering it in the repository they are handed.
globalThis.LZ_RECORDED_NOT_DEPLOYED = [
  {
    "label": "Non-prod spoke address spaces",
    "module": "(per-estate)",
    "impact": "Workload spokes are per-estate work built inside the generated repository against the connectivity layer's outputs (ADR 0017), so no layer renders these. The wizard does validate them for overlap against the hub ranges, which is why they are collected at all.",
    "paths": [
      "connectivity.hubSpoke.nonProdSpokeAddressSpaces.dev.primary",
      "connectivity.hubSpoke.nonProdSpokeAddressSpaces.dev.dr",
      "connectivity.hubSpoke.nonProdSpokeAddressSpaces.test.primary",
      "connectivity.hubSpoke.nonProdSpokeAddressSpaces.test.dr",
      "connectivity.hubSpoke.nonProdSpokeAddressSpaces.uat.primary",
      "connectivity.hubSpoke.nonProdSpokeAddressSpaces.uat.dr"
    ]
  },
  {
    "label": "ExpressRoute circuit detail",
    "module": "(carrier order)",
    "impact": "The connectivity layer deploys an ExpressRoute gateway from connectivity.expressRoute.enabled. The circuit itself is ordered from a carrier outside Terraform, and these four describe that order rather than anything the factory can create.",
    "paths": [
      "connectivity.expressRoute.circuitName",
      "connectivity.expressRoute.peeringLocation",
      "connectivity.expressRoute.bandwidthMbps",
      "connectivity.expressRoute.serviceProvider"
    ]
  },
  {
    "label": "VPN and Bastion SKUs",
    "module": "(AVM connectivity module)",
    "impact": "The layer deploys the VPN gateway and Bastion host from their enabled booleans; the AVM connectivity module owns the SKU, and these three answers select something the module does not take.",
    "paths": [
      "connectivity.vpn.sku",
      "connectivity.vpn.activeActive",
      "connectivity.bastion.sku"
    ]
  },
  {
    "label": "Identity strategy",
    "module": "(per-estate)",
    "impact": "The identity subscription is placed under its management group by the global layer from azure.subscriptions.identity. This answer describes an intended identity architecture that no layer builds.",
    "paths": [
      "identity.strategy"
    ]
  },
  {
    "label": "Security retention and hardening detail",
    "module": "(per-estate)",
    "impact": "Per-estate work under ADR 0017: the factory deploys neither Sentinel, nor the estate's key vaults, nor NSG flow logs, so their retention and hardening detail configures nothing. The wizard already marks Sentinel and customer-managed keys recorded-not-deployed; these are the same decision at a finer grain.",
    "paths": [
      "security.sentinel.retentionDays",
      "security.keyVault.enablePurgeProtection",
      "security.keyVault.softDeleteRetentionDays",
      "security.keyVault.enableRbacAuthorization",
      "security.nsgFlowLogs.retentionDays",
      "security.nsgFlowLogs.trafficAnalytics"
    ]
  },
  {
    "label": "Bespoke policy-baseline toggles",
    "module": "(superseded by the Policies step)",
    "impact": "Superseded rather than merely unwired. These six booleans predate the ALZ policy surface: allowed locations, TLS minimums, NSGs on subnets, public IPs on NICs, diagnostic settings and encryption at rest are all enforced by assignments the pinned library ships, and the client now chooses those in the wizard's Policies step. Leaving them collected offers the same decision twice, in two places, with only one of them connected to anything.",
    "paths": [
      "governance.policyBaseline.enforceAllowedLocations",
      "governance.policyBaseline.enforceTlsMinimum",
      "governance.policyBaseline.enforceNsgOnSubnets",
      "governance.policyBaseline.denyPublicIpOnNics",
      "governance.policyBaseline.enforceDiagnosticSettings",
      "governance.policyBaseline.enforceEncryptionAtRest"
    ]
  },
  {
    "label": "Operating-model contacts and approvals",
    "module": "(docs)",
    "impact": "Collected and rendered nowhere. OPERATING-MODEL.md.tmpl references none of them, so a client who records a support-hours window, an escalation URL, an approval chain and a break-glass contact list finds none of it in the repository they are handed.",
    "paths": [
      "operations.platformTeam.githubTeamSlug",
      "operations.platformTeam.supportHours",
      "operations.platformTeam.escalationUrl",
      "operations.approvalChain.stage",
      "operations.approvalChain.approvers",
      "operations.approvalChain.appliesToEnvironments",
      "operations.breakGlassContacts"
    ]
  },
  {
    "label": "FinOps budgets and cost exports",
    "module": "(docs)",
    "impact": "FINOPS.md.tmpl names finops.budgets in prose and renders no field of it, and no Azure Consumption budget or cost export is created by any layer. A client who sets a USD amount and alert thresholds gets neither the budget nor a document saying what they asked for.",
    "paths": [
      "finops.budgets.scope",
      "finops.budgets.amountUsd",
      "finops.budgets.timeGrain",
      "finops.budgets.alertThresholdPercents",
      "finops.budgets.contactEmails",
      "finops.costExports.storageAccountName",
      "finops.costExports.frequency"
    ]
  }
];
