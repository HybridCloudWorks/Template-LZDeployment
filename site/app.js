/* =====================================================================
 * Azure Landing Zone Factory — Configuration Wizard
 * =====================================================================
 * Offline-only. This file deliberately contains NO fetch, XMLHttpRequest,
 * WebSocket, EventSource, navigator.sendBeacon, or dynamic import. The page's
 * Content-Security-Policy sets connect-src 'none', so any attempt would be
 * blocked by the browser anyway. Factory CI greps this directory for those
 * identifiers and fails the build if one appears.
 *
 * The wizard's only job is to produce an lz-config.json that validates against
 * factory/schema/lz-config.schema.json, plus the artifacts that are directly
 * derivable from it. Rendering the full Terraform/workflow/doc corpus is the
 * renderer's job (factory/renderer/), not this page's — that boundary exists
 * so template changes never require touching the UI.
 * ===================================================================== */
'use strict';

/* ---------------------------------------------------------------------
 * Constants
 * ------------------------------------------------------------------- */

const SCHEMA_VERSION = '3.2.0';

/* Kept in sync with factory-version.json. This page cannot read that file
 * (a file:// fetch is both blocked by CSP and unreliable across browsers),
 * so the value is mirrored here and a factory CI check asserts the two match. */
const FACTORY_VERSION = '0.11.0';

const DRAFT_KEY = 'alz-factory-draft-v1';

/* The ALZ policy catalog, generated from the pinned library ref and delivered by
 * a sibling <script> tag (see index.html). It is a script rather than a fetched
 * JSON because this page's CSP sets connect-src 'none'.
 *
 * The guard is load-bearing, not defensive padding: factory/tests/harness.js
 * evaluates this file on its own with a stub document and no <script> chain, so
 * a bare read would throw ReferenceError and take the entire wizard suite down.
 * The harness loads the catalog explicitly, so the fallback should never be the
 * thing under test — but an empty catalog degrades to "no policies offered"
 * rather than a blank page. */
/* The answers that reach nothing but lz-config.json, generated from
 * factory/ci/schema-coverage-register.json by the same CI check that decides
 * an answer is not-deployed. Reading it here rather than restating the list is
 * the point: a UI marker and a CI gate that disagree are worse than either
 * alone. Empty fallback for the test harness and for a site served without it. */
const RECORDED_NOT_DEPLOYED = (typeof globalThis !== 'undefined' && Array.isArray(globalThis.LZ_RECORDED_NOT_DEPLOYED))
  ? globalThis.LZ_RECORDED_NOT_DEPLOYED
  : [];

const POLICY_CATALOG = (typeof globalThis !== 'undefined' && globalThis.ALZ_POLICY_CATALOG)
  ? globalThis.ALZ_POLICY_CATALOG
  : { groups: [], assignments: {}, defaults: {}, managementGroups: [], ungrouped: [] };

/* Region -> conventional CAF abbreviation. Not exhaustive; unknown regions
 * simply leave the code field for the user to fill. */
const REGION_CODES = {
  eastus: 'eus', eastus2: 'eus2', westus: 'wus', westus2: 'wus2', westus3: 'wus3',
  centralus: 'cus', northcentralus: 'ncus', southcentralus: 'scus', westcentralus: 'wcus',
  canadacentral: 'cnc', canadaeast: 'cne', brazilsouth: 'brs',
  northeurope: 'neu', westeurope: 'weu', uksouth: 'uks', ukwest: 'ukw',
  francecentral: 'frc', germanywestcentral: 'gwc', switzerlandnorth: 'chn',
  norwayeast: 'nwe', swedencentral: 'sdc', polandcentral: 'plc', italynorth: 'itn',
  spaincentral: 'spc', uaenorth: 'uan', southafricanorth: 'san', qatarcentral: 'qac',
  eastasia: 'ea', southeastasia: 'sea', japaneast: 'jpe', japanwest: 'jpw',
  koreacentral: 'krc', australiaeast: 'aue', australiasoutheast: 'ause',
  centralindia: 'inc', southindia: 'ins', westindia: 'inw', israelcentral: 'ilc'
};

const DEFENDER_PLANS = [
  ['CloudPosture', 'Cloud Security Posture Management'],
  ['VirtualMachines', 'Servers'],
  ['StorageAccounts', 'Storage'],
  ['SqlServers', 'SQL'],
  ['AppServices', 'App Service'],
  ['KeyVaults', 'Key Vault'],
  ['Containers', 'Containers'],
  ['Arm', 'Resource Manager'],
  ['OpenSourceRelationalDatabases', 'Open-source databases'],
  ['CosmosDbs', 'Cosmos DB'],
  ['Api', 'APIs']
];

const SENTINEL_CONNECTORS = [
  ['AzureActiveDirectory', 'Entra ID sign-in & audit'],
  ['AzureActivity', 'Azure Activity Log'],
  ['DefenderForCloud', 'Defender for Cloud alerts'],
  ['Office365', 'Office 365'],
  ['ThreatIntelligence', 'Threat intelligence'],
  ['Dns', 'DNS']
];

const COMPLIANCE_FRAMEWORKS = [
  ['cis-azure', 'CIS Azure Foundations'],
  ['nist-800-53', 'NIST SP 800-53'],
  ['iso-27001', 'ISO/IEC 27001'],
  ['pci-dss', 'PCI DSS'],
  ['hipaa-hitrust', 'HIPAA / HITRUST'],
  ['soc2', 'SOC 2'],
  ['fedramp-moderate', 'FedRAMP Moderate']
];

const APP_ENV_ORDER = ['sandbox', 'dev', 'test', 'uat', 'prod'];

const DEFAULT_ENV_ABBREV = {
  bootstrap: 'boot', identity: 'id', connectivity: 'conn', management: 'mgmt',
  'shared-services': 'shrd', sandbox: 'sbx', dev: 'dev', test: 'tst', uat: 'uat', prod: 'prd'
};

/* Rough managed-resource counts per feature. Order of magnitude only — enough
 * to tell "comfortably under 500" from "well over", which is the only question
 * the free-tier cap actually poses.
 *
 * Calibrated against the actual module corpus in terraform/modules/ by counting
 * top-level `resource` blocks, then scaling up the modules that fan out via
 * for_each (hub-network, defender-baseline, nsg-flow-logs, sandbox). Observed
 * block counts at time of writing: hub-network 24, spoke-network 17,
 * policy-baseline 17, defender-baseline 13, management-groups 10, management-
 * baseline 6, nsg-flow-logs 6, backup-baseline 5.
 *
 * These are estimates, not a plan. Treat the output as a rough sizing signal
 * for the estate, never as a billing figure. */
const RUM_WEIGHTS = {
  managementGroupsCafStandard: 9,
  managementGroupsCafMinimal: 4,
  policyBaselineCore: 28,        // 17 blocks, assignments fanning out across scopes
  policyPerFramework: 12,
  hubPerRegion: 30,              // 24 blocks; subnets/NSGs/routes fan out per for_each
  firewallAzfw: 14,
  firewallNva: 10,
  spokePerRegion: 20,            // 17 blocks + peerings
  bastion: 4,
  vpnGateway: 6,
  expressRoute: 7,
  privateDnsPerZone: 3,          // zone + vnet links
  privateDnsDefaultZones: 12,
  managementBaseline: 18,        // LAW, solutions, automation account
  backupBaseline: 12,
  nsgFlowLogsPerRegion: 8,
  defenderPerPlan: 2,
  sentinel: 16,
  keyVaultPerScope: 6,
  budgetEach: 1,
  costExports: 2,
  locksPlatform: 6,
  rbacPerEnvironment: 4,
  diagnosticsPerRegion: 10
};

/* ---------------------------------------------------------------------
 * State
 * ------------------------------------------------------------------- */

/** The live configuration object. Shaped exactly like lz-config.json. */
let config = defaultConfig();

/** Default tags are edited as an array of {k,v} rows, then folded into an
 *  object on export. Kept outside `config` under a __-prefixed repeater key. */
let defaultTagRows = [
  { k: 'owner', v: '' },
  { k: 'application', v: '' },
  { k: 'environment', v: '' },
  { k: 'cost_center', v: '' }
];

let steps = [];
let currentStep = 0;

function defaultConfig() {
  return {
    schemaVersion: SCHEMA_VERSION,
    factoryVersion: FACTORY_VERSION,
    generatedAt: null,
    organization: { companyName: '', companyShortName: '', businessUnit: '', outputDirectoryName: '' },
    azure: {
      tenantId: '', primaryRegion: '', primaryRegionCode: '', drRegion: '', drRegionCode: '',
      allowedLocations: [],
      subscriptions: { mode: 'create', management: '', identity: '', connectivity: '', workloadProd: '', workloadNonProd: '', sandbox: '' },
      managementGroups: { rootId: '', strategy: 'caf-standard', workloadPlacement: 'corp', customHierarchy: {} }
    },
    github: {
      ownershipModel: 'organization', ownerName: '', enterpriseSlug: '', repositoryName: '',
      visibility: 'private', defaultBranch: 'main',
      branchProtection: {
        enabled: true, requiredApprovals: 1, requireCodeOwnerReview: true,
        dismissStaleReviews: true, requireLinearHistory: true, enforceAdmins: false
      },
      useSelfHostedRunners: false
    },
    backend: {
      type: 'azurerm',
      hcpTerraform: { organization: '', workspacePrefix: '', acknowledgedResourceLimit: false },
      azurerm: {
        resourceGroupName: '', storageAccountName: '', containerName: 'tfstate',
        subscriptionId: '', useAzureAdAuth: true,
        privateEndpoint: { enabled: false }
      }
    },
    deploymentStrategy: {
      mode: 'greenfield',
      brownfield: {
        // Working shape for the repeater. buildConfig turns it into the
        // schema's dispositions map and strips it; adoptConfig turns the map
        // back into rows, the same round trip defaultTagRows makes.
        dispositionRows: [],
        excludedSubscriptionIds: [], inventoryExistingPolicies: true
      }
    },
    environments: {
      platform: ['bootstrap', 'connectivity', 'management'],
      application: ['dev', 'prod'],
      promotionPath: ['dev', 'prod'],
      approvals: {}
    },
    connectivity: {
      model: 'hub-spoke',
      hubSpoke: {
        primaryHubAddressSpace: '10.0.0.0/16', drHubAddressSpace: '10.10.0.0/16',
        primarySpokeAddressSpace: '10.2.0.0/16', drSpokeAddressSpace: '10.11.0.0/16',
        nonProdSpokeAddressSpaces: {
          dev: { primary: '10.3.0.0/16', dr: '10.12.0.0/16' },
          test: { primary: '10.4.0.0/16', dr: '10.13.0.0/16' },
          uat: { primary: '10.5.0.0/16', dr: '10.14.0.0/16' }
        },
        availabilityZones: ['1', '2', '3']
      },
      firewall: {
        // enabled has no default on purpose — see validate() and ADR 0017.
        type: 'azfw', enabled: null, azfwTier: 'Standard', threatIntelligenceMode: 'Deny',
      },
      expressRoute: { enabled: false, circuitName: '', peeringLocation: '', bandwidthMbps: null, serviceProvider: '' },
      vpn: { enabled: false, sku: 'VpnGw1AZ', activeActive: true },
      bastion: { enabled: null, sku: 'Standard' },
      privateDns: { enabled: true, centralizedInHub: true, zones: [] },
      privateEndpoints: { enabled: true, denyPublicNetworkAccessPolicy: true }
    },
    identity: {
      strategy: 'cloud-only', deployIdentitySubscription: false,
      cicdIdentityModel: 'minimal',
      privilegedAccessModel: 'pim-eligible', breakGlassAccounts: []
    },
    security: {
      defender: { enabled: false, plans: [], securityContactEmail: '' },
      sentinel: { enabled: false, dataConnectors: [], retentionDays: 90 },
      keyVault: {
        strategy: 'per-environment', enablePurgeProtection: true,
        softDeleteRetentionDays: 90, customerManagedKeys: false, enableRbacAuthorization: true
      },
      nsgFlowLogs: { enabled: true, retentionDays: 90, trafficAnalytics: true },
      backup: { enabled: true, immutableVault: true, geoRedundant: true }
    },
    governance: {
      policyBaseline: {
        enforcementMode: 'audit',
        requiredTags: ['owner', 'application', 'environment', 'cost_center'],
        enforceAllowedLocations: true, enforceTlsMinimum: true, enforceNsgOnSubnets: true,
        denyPublicIpOnNics: false, enforceDiagnosticSettings: true, enforceEncryptionAtRest: true
      },
      policyAsCodeEngines: ['azure-policy', 'conftest'],
      // An absent group id means enabled, so a config written before a library
      // bump keeps the ALZ baseline rather than silently dropping whatever the
      // new library added. DDoS is the one group off by default: the plan is
      // roughly USD 2,900/month, this factory does not create one, and the
      // assignment is worthless without a plan ID the client has to own.
      policySelection: { groups: { ddos: false }, assignments: {}, values: {} },
      complianceFrameworks: [],
      regulatoryNotes: '',
      dataResidencyRegions: [],
      resourceLocks: { lockPlatformResourceGroups: true, lockLevel: 'CanNotDelete' }
    },
    observability: {
      logAnalytics: { retentionDays: 90, dailyQuotaGb: -1, sku: 'PerGB2018' },
      diagnosticSettings: { enabled: true, sendActivityLog: true, sendToStorage: false, sendToEventHub: false },
      alerting: { actionGroupEmails: [], enablePlatformHealthAlerts: true, enableDriftAlerts: true },
      driftDetection: { enabled: true, schedule: '0 6 * * 1', failOnDrift: false, openIssueOnDrift: true }
    },
    operations: {
      operatingModel: 'centralized',
      platformTeam: { name: '', githubTeamSlug: '', contacts: [], supportHours: '', escalationUrl: '' },
      approvalChain: [],
      breakGlassContacts: []
    },
    finops: {
      costCenter: '',
      businessOwner: { name: '', email: '', role: 'Business Owner' },
      budgets: [],
      chargebackModel: 'showback',
      costExports: { enabled: false, storageAccountName: '', frequency: 'Daily' }
    },
    naming: {
      standard: 'caf', resourceGroupPattern: '', resourcePattern: '',
      environmentAbbreviations: {}, defaultTags: {}
    }
  };
}

/* ---------------------------------------------------------------------
 * Small utilities
 * ------------------------------------------------------------------- */

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

function getPath(obj, path) {
  return path.split('.').reduce((o, k) => (o === undefined || o === null ? undefined : o[k]), obj);
}

function setPath(obj, path, value) {
  const keys = path.split('.');
  const last = keys.pop();
  let node = obj;
  for (const k of keys) {
    if (typeof node[k] !== 'object' || node[k] === null) node[k] = {};
    node = node[k];
  }
  node[last] = value;
}

const csv = (s) => String(s || '').split(',').map((x) => x.trim()).filter(Boolean);
const lines = (s) => String(s || '').split('\n').map((x) => x.trim()).filter(Boolean);

/* No HTML-escaping helper exists here on purpose: every piece of dynamic text
 * is inserted via textContent / createTextNode, never via innerHTML with user
 * data. If a future change must interpolate user input into markup, add
 * escaping at that point rather than weakening this policy. */

/** Environment names arrive from persisted or imported data and are later used
 *  as object keys (approvals, abbreviations), so they must be shaped like real
 *  environment names and must never be prototype-related keys. */
const isSafeEnvName = (e) =>
  typeof e === 'string' &&
  /^[a-z][a-z0-9-]{0,29}$/.test(e) &&
  !['__proto__', 'prototype', 'constructor'].includes(e);

let toastTimer = null;
function toast(msg, kind = 'ok') {
  const el = $('#toast');
  el.textContent = msg;
  el.className = 'toast toast-show toast-' + kind;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.className = 'toast'; }, 3200);
}

/** Trigger a file download entirely client-side. No network involved: the Blob
 *  lives in memory and the object URL is revoked immediately after the click. */
function download(filename, content, mime = 'text/plain') {
  // Strings get an explicit charset; binary payloads (Uint8Array) must not.
  const type = typeof content === 'string' ? mime + ';charset=utf-8' : mime;
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

/* ---------------------------------------------------------------------
 * Validators (mirror of the JSON Schema constraints)
 * ------------------------------------------------------------------- */

const RE = {
  guid: /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/,
  // Must match the org_prefix validation in terraform/live/global/variables.tf.
  shortName: /^[a-z0-9]{2,10}$/,
  region: /^[a-z0-9]+$/,
  regionCode: /^[a-z]{2,5}$/,
  email: /^[^@\s]+@[^@\s]+\.[^@\s]+$/,
  // Azure's own management-group name rule, mirrored from the schema pattern.
  mgId: /^[A-Za-z0-9._()-]{1,90}$/,
  ghLogin: /^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$/,
  repoName: /^[A-Za-z0-9._-]{1,100}$/,
  storageAccount: /^[a-z0-9]{3,24}$/,
  cidr: /^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\/(3[0-2]|[12]?[0-9])$/,
  ipv4: /^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$/,
  tagKey: /^[A-Za-z_][A-Za-z0-9_-]*$/,
  cron: /^(\S+\s+){4}\S+$/,
  // Must stay at least as strict as the private_dns_zones validation in
  // terraform/live/platform-connectivity/variables.tf and the schema pattern
  // for connectivity.privateDns.zones (contract #7: wizard subset of schema
  // subset of terraform).
  dnsZone: /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/
};

/** Parse a CIDR into [networkInt, broadcastInt] for overlap testing. */
function cidrRange(c) {
  const [ip, bitsStr] = c.split('/');
  const bits = parseInt(bitsStr, 10);
  const n = ip.split('.').reduce((acc, o) => (acc << 8 >>> 0) + parseInt(o, 10), 0) >>> 0;
  const mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
  const net = (n & mask) >>> 0;
  const bc = (net | (~mask >>> 0)) >>> 0;
  return [net, bc];
}

function cidrsOverlap(a, b) {
  const [a1, a2] = cidrRange(a);
  const [b1, b2] = cidrRange(b);
  return a1 <= b2 && b1 <= a2;
}

/**
 * Full-config validation. Returns { errors: [], warnings: [] } where each entry
 * is { step, message }. Errors block export; warnings do not.
 */
function validate() {
  const errors = [];
  const warnings = [];
  const err = (step, message) => errors.push({ step, message });
  const warn = (step, message) => warnings.push({ step, message });

  // --- Organization
  const o = config.organization;
  if (!o.companyName.trim()) err('organization', 'Company name is required.');
  if (!RE.shortName.test(o.companyShortName)) {
    err('organization', 'Short name must be 2–10 lowercase letters or digits.');
  }
  if (!o.businessUnit.trim()) err('organization', 'Business unit is required.');

  // --- Azure
  const a = config.azure;
  if (!RE.guid.test(a.tenantId)) err('azure', 'Tenant ID must be a GUID.');
  if (!RE.region.test(a.primaryRegion || '')) err('azure', 'Primary region is required.');
  if (!RE.regionCode.test(a.primaryRegionCode || '')) err('azure', 'Primary region code must be 2–5 lowercase letters.');
  if (a.drRegion && !RE.regionCode.test(a.drRegionCode || '')) {
    err('azure', 'A DR region was set, so a DR region code is required.');
  }
  if (!a.drRegion) warn('azure', 'No DR region set. The landing zone will be single-region, and the DR hub/spoke layers will not be emitted.');
  if (a.drRegion && a.drRegion === a.primaryRegion) err('azure', 'DR region must differ from the primary region.');
  if (!a.allowedLocations.length) err('azure', 'At least one allowed location is required.');
  const subMode = a.subscriptions.mode || 'create';
  if (subMode === 'existing') {
    for (const key of ['management', 'connectivity', 'workloadProd']) {
      if (!RE.guid.test(a.subscriptions[key] || '')) {
        err('azure', `The ${key} subscription ID must be a GUID.`);
      }
    }
  }
  for (const key of ['management', 'connectivity', 'workloadProd', 'identity', 'workloadNonProd', 'sandbox']) {
    const v = a.subscriptions[key];
    if (v && !RE.guid.test(v)) err('azure', `The ${key} subscription ID is not a valid GUID.`);
  }
  if (subMode === 'create') {
    warn('azure', 'Subscriptions will be created by scripts/New-LzSubscriptions.ps1 after export. The render guard blocks generation until the script has written the new subscription IDs back into this config.');
  }
  const subVals = Object.values(a.subscriptions).filter(Boolean);
  const dupes = subVals.filter((v, i) => subVals.indexOf(v) !== i);
  if (dupes.length) {
    warn('azure', 'The same subscription ID is used for more than one role. This is valid but collapses the isolation boundary between those planes.');
  }
  if (!a.managementGroups.rootId.trim()) err('azure', 'Root management group ID is required.');
  // Said out loud rather than left for the client to discover in the rendered
  // output: caf-minimal and caf-standard emit byte-identical Terraform today,
  // because the architecture is the pinned library's `alz` in both cases.
  if (a.managementGroups.strategy === 'caf-minimal') {
    warn('azure', 'CAF minimal currently deploys the same management groups as CAF standard: the hierarchy comes from the pinned Azure Landing Zones library architecture, which includes Corp, Online, Sandbox and Decommissioned. Trimming it needs a decision about where the sandbox subscription lands (REVIEW §23).');
  }
  if (a.managementGroups.strategy === 'custom') {
    const renames = a.managementGroups.customHierarchy || {};
    const library = new Map(POLICY_CATALOG.managementGroups.map((g) => [g.id, g]));
    const claimed = new Map();
    let changed = 0;
    // Without the catalog there is nothing to rename FROM: every key is
    // unverifiable and every collision invisible. Skipping the checks and
    // exporting anyway would produce an architecture definition full of groups
    // no archetype governs, which is the failure the checks below exist to
    // prevent — so the absence of the catalog is itself the blocker.
    if (library.size === 0) {
      err('azure', 'The generated policy catalog did not load, so the management groups this estate would rename cannot be checked. Reload the wizard, or choose a standard hierarchy strategy.');
    }
    for (const [libraryId, rename] of Object.entries(renames)) {
      // A key the pinned library does not define would emit a management group
      // no archetype claims: created, governed by nothing, and immutable.
      if (library.size && !library.has(libraryId)) {
        err('azure', `"${libraryId}" is not a management group the pinned Azure Landing Zones library defines, so renaming it would create a group no archetype governs.`);
        continue;
      }
      const id = (rename.id || '').trim();
      const displayName = (rename.displayName || '').trim();
      if (id && !RE.mgId.test(id)) {
        err('azure', `"${id}" is not a valid management group ID: 1-90 characters, letters, digits, and . _ ( ) - only.`);
      }
      // "Changed" means the effective value DIFFERS from the library's, not
      // that a field was filled in. Restating a library name is not a rename,
      // and counting it as one would let a config emit a local architecture
      // identical to the pinned library — pinning the estate to a copy that a
      // library bump can no longer update.
      const group = library.get(libraryId);
      if ((id && (!group || id !== group.id)) || (displayName && (!group || displayName !== group.displayName))) changed++;
      if (id) {
        if (claimed.has(id)) {
          err('azure', `Two management groups would both be created as "${id}". IDs must be unique across the hierarchy.`);
        }
        claimed.set(id, libraryId);
      }
    }
    // A rename that collides with a group keeping its library name is the same
    // collision, one step less obvious.
    for (const group of library.values()) {
      const own = renames[group.id];
      if (own && (own.id || '').trim()) continue;
      if (claimed.has(group.id)) {
        err('azure', `"${group.id}" is both the library name of one management group and the chosen ID of another. Rename both, or neither.`);
      }
    }
    if (!changed) {
      err('azure', 'Custom hierarchy selected but every management group still carries its library name. Rename at least one, or choose a standard strategy.');
    }
    const root = a.managementGroups.rootId.trim();
    if (root && claimed.has(root)) {
      err('azure', 'A management group cannot take the ID of the root the hierarchy is parented under.');
    }
  }
  if (a.managementGroups.rootId === a.tenantId) {
    warn('azure', 'Rooting at the Tenant Root Group requires write access at tenant root. If the readiness check fails on that, supply an existing intermediate management group ID instead.');
  }

  // --- GitHub
  const g = config.github;
  if (!RE.ghLogin.test(g.ownerName || '')) err('github', 'GitHub owner login is required and must be a valid login.');
  if (!RE.repoName.test(g.repositoryName || '')) err('github', 'Repository name is required.');
  if (g.ownershipModel === 'enterprise' && !g.enterpriseSlug.trim()) {
    err('github', 'Enterprise slug is required for the enterprise ownership model.');
  }
  if (g.visibility === 'internal' && g.ownershipModel !== 'enterprise') {
    err('github', 'Internal visibility is only available on GitHub Enterprise Cloud.');
  }
  if (g.ownershipModel === 'personal') {
    warn('github', 'Personal accounts on the Free plan cannot use environments or branch protection on private repositories. The broker will configure what it can and name every control it could not apply in the bootstrap report — it will not skip them silently.');
  }
  if (g.useSelfHostedRunners) {
    err('github', 'Self-hosted runners are not supported in v1. Discovery reports them, but the renderer emits GitHub-hosted workflows only.');
  }
  if (!g.branchProtection.enabled) {
    warn('github', 'Branch protection is disabled. Anyone with write access can push directly to the branch that triggers apply.');
  }

  // --- Backend
  const b = config.backend;
  if (b.type === 'hcp-terraform') {
    if (!b.hcpTerraform.organization.trim()) {
      err('backend', 'HCP Terraform organization is required. Workspaces are created as {prefix}-{layer} inside it.');
    }
    // The free tier caps resources UNDER MANAGEMENT, and holding state
    // elsewhere does not change that — the resources are in the state HCP
    // Terraform stores. A landing zone commonly exceeds it.
    const estimate = estimateRum();
    if (estimate > 500 && !b.hcpTerraform.acknowledgedResourceLimit) {
      err('backend', `This configuration estimates ${estimate} managed resources, above the HCP Terraform free tier's 500. Confirm the plan covers it, or choose the Azure Storage backend.`);
    }
    if (b.azurerm.privateEndpoint && b.azurerm.privateEndpoint.enabled) {
      err('backend', 'The state private-endpoint overlay hardens an Azure Storage account this backend does not create. Clear it, or choose the Azure Storage backend.');
    }
    warn('backend', 'HCP Terraform adds one static credential the Azure Storage path does not have: TF_API_TOKEN, set as a repository secret so the Terraform CLI can reach the workspace. Azure authentication is unchanged — GitHub OIDC, no stored Azure credential.');
  } else if (b.type !== 'azurerm') {
    err('backend', `"${b.type}" is not a supported state backend. Choose Azure Storage or HCP Terraform.`);
  } else {
    if (!b.azurerm.resourceGroupName.trim()) err('backend', 'State resource group name is required.');
    if (!RE.storageAccount.test(b.azurerm.storageAccountName || '')) {
      err('backend', 'State storage account must be 3–24 lowercase alphanumeric characters.');
    }
    // Not a preference: the broker creates the state account with
    // --allow-shared-key-access false, and every emitted backend.hcl and
    // remote-state block sets use_azuread_auth = true unconditionally. Answering
    // "no" produced a configuration that could not authenticate to its own
    // state, and the wizard only warned about it.
    if (!b.azurerm.useAzureAdAuth) {
      err('backend', 'Entra ID authentication to state is a contract, not a preference: the state storage account is created with shared-key access disabled, and every emitted backend sets use_azuread_auth = true. Storage-key auth would not be able to reach the account at all.');
    }
    if (b.azurerm.privateEndpoint && b.azurerm.privateEndpoint.enabled) {
      if (config.connectivity.model !== 'hub-spoke') {
        err('backend', 'State private endpoint requires the hub-and-spoke topology — the private DNS zone for blob storage is centralized in the hub (ADR 0019).');
      } else if (!config.connectivity.privateDns.enabled || !config.connectivity.privateDns.centralizedInHub) {
        err('backend', 'State private endpoint requires centralized private DNS in the hub (ADR 0019).');
      }
      if (!config.github.useSelfHostedRunners) {
        err('backend', 'State private endpoint requires self-hosted runners with a network path to the hub — GitHub-hosted runners cannot reach a private-only state account (ADR 0019).');
      }
    }
  }

  // --- Deployment strategy
  const ds = config.deploymentStrategy;
  if (ds.mode === 'brownfield') {
    const rows = brownfieldDispositionRows();
    const seen = new Set();
    for (const row of rows) {
      const id = (row.id || '').trim();
      if (!id) { err('deploymentStrategy', 'Every brownfield disposition needs a subscription ID.'); continue; }
      if (!RE.guid.test(id)) { err('deploymentStrategy', `"${id}" is not a subscription ID.`); continue; }
      if (seen.has(id)) err('deploymentStrategy', `Subscription ${id} has more than one disposition. It can only have one.`);
      seen.add(id);
      if (row.action === 'place-now') {
        if ((row.acknowledgement || '').trim() !== placementAcknowledgement(id)) {
          err('deploymentStrategy', `Placing ${id} needs the acknowledgement typed exactly. Placing an existing subscription starts every policy assignment above it evaluating the resources already in it — Deny assignments will refuse the next change to them, and DeployIfNotExists assignments will create and change things. Choose Defer if that is not what you want.`);
        }
        if ((ds.brownfield.excludedSubscriptionIds || []).includes(id)) {
          err('deploymentStrategy', `Subscription ${id} is both excluded and set to be placed. It cannot be both.`);
        }
      }
    }
    const excluded = ds.brownfield.excludedSubscriptionIds || [];
    for (const id of excluded) {
      if (!RE.guid.test(id)) err('deploymentStrategy', `Excluded subscription ID "${id}" is not a valid GUID.`);
    }
    const exDupes = excluded.filter((v, i) => excluded.indexOf(v) !== i);
    if (exDupes.length) err('deploymentStrategy', 'The excluded-subscription list contains duplicates.');
    const slotOverlap = Object.entries(config.azure.subscriptions)
      .filter(([k, v]) => k !== 'mode' && v && excluded.includes(v));
    for (const [slot, id] of slotOverlap) {
      err('deploymentStrategy', `Subscription ${id} is excluded from the landing zone but is also assigned to the ${slot} slot. A subscription cannot be both excluded and part of the new estate.`);
    }
    if (config.azure.subscriptions.mode === 'existing' && !excluded.length) {
      warn('deploymentStrategy', 'Brownfield with existing subscription IDs and no exclusions: confirm the supplied subscriptions are new, empty subscriptions — integrating existing deployments is out of scope (ADR 0018).');
    }
  }

  // --- Environments
  const e = config.environments;
  if (!e.platform.length) err('environments', 'At least one platform environment is required.');
  if (!e.application.length) err('environments', 'At least one application environment is required.');
  if (e.application.includes('prod')) {
    const rev = (e.approvals.prod && e.approvals.prod.requiredReviewers) || [];
    if (!rev.length) warn('environments', 'The prod environment has no required reviewers, so production applies run without human approval.');
  }
  if (e.application.includes('sandbox') && !config.azure.subscriptions.sandbox
      && !(subMode === 'create' && $('#az_planSandbox')?.checked)) {
    warn('environments', 'A sandbox environment is selected but no sandbox subscription was supplied or planned. The sandbox layer will not be emitted.');
  }

  // --- Connectivity
  const c = config.connectivity;
  if (c.model === 'virtual-wan') {
    if (c.bastion.enabled) warn('connectivity', 'Bastion is composed for hub-and-spoke only; with Virtual WAN, deploy Bastion per-spoke inside the generated repository.');
    if (c.privateDns.enabled) warn('connectivity', 'Centralized private DNS zones are composed for hub-and-spoke only; with Virtual WAN, create them inside the generated repository.');
  }
  if (c.model === 'hub-spoke') {
    const spaces = [
      ['primary hub', c.hubSpoke.primaryHubAddressSpace],
      ['DR hub', c.hubSpoke.drHubAddressSpace],
      ['primary spoke', c.hubSpoke.primarySpokeAddressSpace],
      ['DR spoke', c.hubSpoke.drSpokeAddressSpace],
      ...['dev', 'test', 'uat'].flatMap(env => {
        const pair = (c.hubSpoke.nonProdSpokeAddressSpaces || {})[env] || {};
        return [[`${env} primary spoke`, pair.primary], [`${env} DR spoke`, pair.dr]];
      })
    ].filter(([, v]) => v);
    for (const env of ['dev', 'test', 'uat']) {
      if (!config.environments.application.includes(env)) continue;
      const pair = (c.hubSpoke.nonProdSpokeAddressSpaces || {})[env];
      if (!pair || !pair.primary) err('connectivity', `${env} is selected but has no primary workload spoke CIDR.`);
      if (config.azure.drRegion && (!pair || !pair.dr)) err('connectivity', `${env} is selected in a dual-region configuration but has no DR workload spoke CIDR.`);
    }
    for (const [label, v] of spaces) {
      if (!RE.cidr.test(v)) err('connectivity', `The ${label} address space is not valid CIDR notation.`);
    }
    const valid = spaces.filter(([, v]) => RE.cidr.test(v));
    for (let i = 0; i < valid.length; i++) {
      for (let j = i + 1; j < valid.length; j++) {
        if (cidrsOverlap(valid[i][1], valid[j][1])) {
          err('connectivity', `The ${valid[i][0]} and ${valid[j][0]} address spaces overlap.`);
        }
      }
    }
    if (!c.hubSpoke.availabilityZones.length) {
      warn('connectivity', 'No availability zones selected. Zonal resources will be deployed without zone redundancy.');
    }
  }
  if (c.privateDns && c.privateDns.enabled) {
    // Zone names go straight into azurerm_private_dns_zone. Catching a bad one
    // here rather than at plan keeps the wizard at least as strict as the
    // schema, which is at least as strict as Terraform (contract #7).
    const zones = c.privateDns.zones || [];
    for (const z of zones) {
      if (!RE.dnsZone.test(z) || z.length > 253) {
        err('connectivity', `Private DNS zone "${z}" is not a valid zone name — lowercase dotted labels only, no leading or trailing dot or hyphen.`);
      }
    }
    if (new Set(zones).size !== zones.length) {
      err('connectivity', 'The private DNS zone list contains duplicates.');
    }
    // centralizedInHub = false has no implementation: cross-domain contract 9
    // puts the zones in the connectivity layer, and render guard G21 blocks a
    // configuration that unticks it. Failing here means the client sees it in
    // the wizard rather than at render time.
    if (c.privateDns.centralizedInHub === false) {
      err('connectivity', 'Centralizing Private DNS in the hub cannot be turned off: the generated Terraform creates the zones in the connectivity layer. Untick "Private DNS zones" instead if you do not want them.');
    }
  }
  // Both of these are unanswered by default. Azure Firewall Standard is roughly
  // USD 900-950/month per hub and Bastion Standard roughly USD 140 — spend of
  // that size is a decision the client makes, not one a default makes for them.
  if (c.firewall.enabled === null || c.firewall.enabled === undefined) {
    err('connectivity', 'Choose whether the hub deploys an Azure Firewall. There is no default: it is roughly USD 900-950 per month per hub before data processing.');
  }
  if (c.bastion.enabled === null || c.bastion.enabled === undefined) {
    err('connectivity', 'Choose whether the hub deploys Azure Bastion. There is no default: it is roughly USD 140 per month per hub, and there may be nothing to reach through it yet.');
  }
  if (c.firewall.enabled === true && !['Standard', 'Premium'].includes(c.firewall.azfwTier)) {
    // Guards imported/drafted configs from before Basic was removed: the
    // hub-network module does not provision the dedicated management subnet
    // and management public IP the Basic tier mandates, so the schema (and
    // both connectivity layers) accept Standard and Premium only.
    err('connectivity', `Azure Firewall tier "${c.firewall.azfwTier}" cannot be deployed — the hub-network module supports Standard and Premium only. Re-select the tier.`);
  }
  if (c.firewall.enabled === true && c.firewall.threatIntelligenceMode === 'Off') {
    warn('connectivity', 'Azure Firewall threat intelligence is Off. The secure default is Deny; this needs a recorded governance exception.');
  }
  if (!['azfw'].includes(c.firewall.type)) {
    // Azure Firewall is the only firewall this generator composes. Third-party
    // NVAs are per-estate work inside the generated repository. This also guards
    // configs drafted while "none" was briefly offered here: they exported
    // firewall_type = "none", which the connectivity layer rejects. To deploy
    // no firewall, set the firewall question to "no" — the AVM patterns accept
    // it (ADR 0017, amended 2026-08-30).
    err('connectivity', `Firewall type "${c.firewall.type}" cannot be deployed — Azure Firewall is the only type the generator composes (ADR 0017). A third-party NVA is per-estate work in the generated repository.`);
  }
  if (c.firewall.enabled === false) {
    warn('connectivity', 'The hub deploys no firewall. Egress from the spokes is unfiltered by the platform; whatever inspects it has to come from somewhere else.');
  }
  if (c.expressRoute.enabled && !c.expressRoute.peeringLocation.trim()) {
    err('connectivity', 'ExpressRoute is enabled but no peering location was given.');
  }

  // --- Identity
  const bg = config.identity.breakGlassAccounts.filter((x) => x.name || x.email);
  if (bg.length < 2) err('identity', 'At least two break-glass accounts are required.');
  for (const acct of bg) {
    if (acct.email && !RE.email.test(acct.email)) err('identity', `Break-glass notification address "${acct.email}" is not a valid email.`);
  }
  if (config.identity.privilegedAccessModel === 'standing-access') {
    warn('identity', 'Standing privileged access is selected. This is recorded as an explicit governance exception in the generated security documentation.');
  }

  // --- Security
  const s = config.security;
  if (s.sentinel.enabled) {
    warn('security', 'Sentinel is recorded in the answer record but not deployed by the generator (ADR 0017): onboard it inside the generated repository against the management workspace.');
  }
  if (s.keyVault.customerManagedKeys) {
    warn('security', 'Customer-managed keys are recorded in the answer record but not deployed by the generator (ADR 0017): implement the CMK estate inside the generated repository.');
  }
  if (s.defender.enabled) {
    if (!s.defender.plans.length) err('security', 'Defender is enabled but no plans were selected.');
    if (s.defender.securityContactEmail && !RE.email.test(s.defender.securityContactEmail)) {
      err('security', 'Defender security contact must be a valid email address.');
    }
    if (!s.defender.securityContactEmail) warn('security', 'No Defender security contact set — alerts will have no notification recipient.');
  }
  if (!s.backup.enabled) warn('security', 'The backup baseline is disabled. Nothing in the landing zone will be backed up by default.');

  // --- Governance
  const gv = config.governance;
  if (!gv.policyBaseline.requiredTags.length) err('governance', 'At least one required tag must be defined.');
  for (const t of gv.policyBaseline.requiredTags) {
    if (!RE.tagKey.test(t)) err('governance', `"${t}" is not a valid tag key.`);
  }
  if (gv.policyBaseline.enforcementMode === 'deny' && config.deploymentStrategy.mode === 'brownfield') {
    warn('governance', 'Deny enforcement in a brownfield tenant: the new management-group hierarchy only governs the new subscriptions, but tenant-root inheritance and legacy assignments can still collide. Start at Audit, review the policy inventory, then promote to Deny.');
  }
  if (gv.policyAsCodeEngines.includes('sentinel')) {
    err('governance', 'Sentinel policy enforcement was a Terraform Cloud feature; the azurerm-only pipeline (ADR 0015) does not support it. Use Azure Policy or OPA.');
  }
  // --- Policies
  // A required default that is not supplied does not fail the render, the
  // schema, or terraform validate: the ALZ provider resolves defaults at PLAN
  // time, and the assignment is then built from the library's own placeholder —
  // security_contact@replace_me, or a plan under an all-zeroes subscription.
  // This wizard is the only place that failure is visible before apply, so it
  // blocks the export.
  for (const [name, askedBy] of requiredPolicyValues()) {
    const copy = POLICY_VALUE_LABELS[name] || {};
    const supplied = (gv.policySelection && gv.policySelection.values || {})[name];
    if (!supplied || !String(supplied).trim()) {
      err('policies', `${copy.label || name} is required: ${askedBy.join(', ')} ${askedBy.length === 1 ? 'is' : 'are'} selected and the library declares no usable default. Supply it, or turn the assignment off.`);
      continue;
    }
    const value = String(supplied).trim();
    if (name === 'email_security_contact' && !RE.email.test(value)) {
      err('policies', `"${value}" is not a valid email address for the Defender security contact.`);
    }
    if (name === 'ddos_protection_plan_id' && !/^\/subscriptions\/[0-9a-fA-F-]{36}\/resourceGroups\/[^/]+\/providers\/Microsoft\.Network\/ddosProtectionPlans\/[^/]+$/.test(value)) {
      err('policies', 'The DDoS plan must be a full resource ID: /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Network/ddosProtectionPlans/<name>.');
    }
  }
  {
    const { enabled, total } = policyCounts();
    if (enabled === 0) {
      err('policies', 'Every policy assignment is turned off. The landing zone would be built with no Azure Policy governance at all.');
    } else if (enabled < total / 2) {
      warn('policies', `${total - enabled} of ${total} ALZ policy assignments are turned off. Each one you disable is a control the Azure Landing Zones baseline expects to be present.`);
    }
  }

  if (gv.dataResidencyRegions.length) {
    const outside = config.azure.allowedLocations.filter((r) => !gv.dataResidencyRegions.includes(r));
    if (outside.length) {
      err('governance', `Allowed locations include ${outside.join(', ')}, which fall outside the declared data-residency regions.`);
    }
  }

  // --- Observability
  const ob = config.observability;
  if (ob.logAnalytics.dailyQuotaGb > 0) {
    warn('observability', `A ${ob.logAnalytics.dailyQuotaGb} GB/day ingestion cap is set. Once hit, ingestion stops for the day and security telemetry is lost, not queued.`);
  }
  if (ob.driftDetection.enabled && !RE.cron.test(ob.driftDetection.schedule.trim())) {
    err('observability', 'Drift schedule must be a five-field cron expression.');
  }
  for (const em of ob.alerting.actionGroupEmails) {
    if (!RE.email.test(em)) err('observability', `Action group address "${em}" is not a valid email.`);
  }
  if (!ob.alerting.actionGroupEmails.length && ob.alerting.enablePlatformHealthAlerts) {
    warn('observability', 'Platform health alerts are enabled but no action group recipients are configured, so alerts will fire into nothing.');
  }

  // --- Operations
  const op = config.operations;
  if (!op.platformTeam.name.trim()) err('operations', 'Platform team name is required.');
  const contacts = op.platformTeam.contacts.filter((x) => x.name || x.email);
  if (!contacts.length) err('operations', 'At least one platform team contact is required.');
  for (const ct of contacts) {
    if (ct.email && !RE.email.test(ct.email)) err('operations', `Platform contact "${ct.email}" is not a valid email.`);
  }
  const bgc = op.breakGlassContacts.filter((x) => x.name || x.email);
  if (!bgc.length) err('operations', 'At least one break-glass contact is required.');

  // --- FinOps
  const f = config.finops;
  if (!f.costCenter.trim()) err('finops', 'Cost center is required.');
  if (!f.businessOwner.name.trim()) err('finops', 'Business owner name is required.');
  if (!RE.email.test(f.businessOwner.email || '')) err('finops', 'Business owner email is required and must be valid.');
  for (const bud of f.budgets) {
    if (!bud.scope) err('finops', 'Every budget needs a scope.');
    if (!(Number(bud.amountUsd) > 0)) err('finops', `Budget for "${bud.scope || 'unnamed'}" needs an amount greater than zero.`);
  }
  if (!f.budgets.length) warn('finops', 'No budgets defined. Nothing will alert on cost overrun.');
  if (f.costExports.enabled && !RE.storageAccount.test(f.costExports.storageAccountName || '')) {
    err('finops', 'Cost exports are enabled but the export storage account name is invalid.');
  }

  // --- Naming
  const n = config.naming;
  if (n.standard === 'custom') {
    const ALLOWED = ['org', 'scope', 'workload', 'type', 'region', 'regionCode', 'env', 'nn'];
    for (const [label, pat] of [['resource group', n.resourceGroupPattern], ['resource', n.resourcePattern]]) {
      if (!pat.trim()) { err('naming', `A custom ${label} pattern is required.`); continue; }
      const tokens = (pat.match(/\{([^}]*)\}/g) || []).map((t) => t.slice(1, -1));
      for (const t of tokens) {
        if (!ALLOWED.includes(t)) err('naming', `The ${label} pattern uses unknown token {${t}}. Allowed: ${ALLOWED.map((x) => '{' + x + '}').join(' ')}.`);
      }
    }
  }
  const tagObj = tagsObject();
  for (const t of gv.policyBaseline.requiredTags) {
    if (!tagObj[t] || !String(tagObj[t]).trim()) {
      err('naming', `Tag "${t}" is required by policy but has no default value. The landing zone would deny its own first apply.`);
    }
  }
  for (const row of defaultTagRows) {
    if (row.k && !RE.tagKey.test(row.k)) err('naming', `"${row.k}" is not a valid tag key.`);
  }

  return { errors, warnings };
}

/* ---------------------------------------------------------------------
 * CI/CD identity estate
 * ------------------------------------------------------------------- */

/** Unique environments across both planes — the set the bootstrap broker
 *  federates deployment identities against. */
function uniqueEnvironments() {
  return new Set([
    ...(config.environments.platform || []),
    ...(config.environments.application || [])
  ]);
}

/**
 * How many Entra ID app registrations the bootstrap broker will create for
 * CI/CD, given identity.cicdIdentityModel. Broker-only key: it never reaches
 * a Terraform variable (see factory/schema/lz-config.schema.json).
 *   minimal          -> 2 (one shared plan + one shared apply identity)
 *   per-environment  -> 2 × |unique(platform ∪ application)|
 */
function cicdIdentityCount() {
  const model = (config.identity && config.identity.cicdIdentityModel) || 'minimal';
  if (model !== 'per-environment') return 2;
  return 2 * uniqueEnvironments().size;
}

function tagsObject() {
  const out = {};
  for (const row of defaultTagRows) {
    if (row.k && String(row.k).trim()) out[String(row.k).trim()] = String(row.v || '');
  }
  return out;
}

/* ---------------------------------------------------------------------
 * Managed-resource (RUM) estimate
 * ------------------------------------------------------------------- */

/**
 * Order-of-magnitude estimate of resources with mode="managed" that this
 * configuration would put into state. Used only to answer one question:
 * does this fit inside HCP Terraform's 500-resource free tier?
 */
function estimateRum() {
  const w = RUM_WEIGHTS;
  const c = config;
  let n = 0;

  const regions = 1 + (c.azure.drRegion ? 1 : 0);

  // Custom is a rename of the standard shape, not a different one: the group
  // count is the pinned library's either way.
  n += c.azure.managementGroups.strategy === 'caf-minimal'
    ? w.managementGroupsCafMinimal
    : w.managementGroupsCafStandard;

  // Scaled by what the client actually selected: a disabled group is an
  // assignment that is never created, not one created and ignored.
  const policy = policyCounts();
  n += Math.round(w.policyBaselineCore * (policy.total ? policy.enabled / policy.total : 1));
  n += (c.governance.complianceFrameworks || []).length * w.policyPerFramework;

  if (c.connectivity.model === 'hub-spoke') {
    n += w.hubPerRegion * regions;
    n += w.spokePerRegion * regions;
    if (c.connectivity.firewall.enabled) n += w.firewallAzfw * regions;
    if (c.connectivity.bastion.enabled) n += w.bastion * regions;
    if (c.connectivity.vpn.enabled) n += w.vpnGateway * regions;
    if (c.connectivity.expressRoute.enabled) n += w.expressRoute;
    if (c.connectivity.privateDns.enabled) {
      const z = (c.connectivity.privateDns.zones || []).length;
      n += (z > 0 ? z : w.privateDnsDefaultZones) * w.privateDnsPerZone;
    }
  }

  n += w.managementBaseline;
  n += w.diagnosticsPerRegion * regions;
  if (c.security.backup.enabled) n += w.backupBaseline;
  if (c.security.nsgFlowLogs.enabled) n += w.nsgFlowLogsPerRegion * regions;
  if (c.security.defender.enabled) n += (c.security.defender.plans || []).length * w.defenderPerPlan;
  if (c.security.sentinel.enabled) n += w.sentinel;

  const kvScopes = c.security.keyVault.strategy === 'centralized'
    ? 1
    : c.security.keyVault.strategy === 'per-subscription'
      ? Object.values(c.azure.subscriptions).filter(Boolean).length
      : c.environments.application.length;
  n += kvScopes * w.keyVaultPerScope;

  n += (c.finops.budgets || []).length * w.budgetEach;
  if (c.finops.costExports.enabled) n += w.costExports;
  if (c.governance.resourceLocks.lockPlatformResourceGroups) n += w.locksPlatform;
  n += (c.environments.platform.length + c.environments.application.length) * w.rbacPerEnvironment;

  return n;
}

/* ---------------------------------------------------------------------
 * Binding: DOM <-> config
 * ------------------------------------------------------------------- */

function readControl(el) {
  const type = el.dataset.type || (el.type === 'checkbox' ? 'bool' : 'string');
  if (type === 'bool') return el.checked;
  // tribool backs a required yes/no that must not carry a silent default: the
  // empty option means "not answered yet" and validate() refuses to export it.
  if (type === 'tribool') return el.value === '' ? null : el.value === 'true';
  if (type === 'int') return el.value === '' ? null : parseInt(el.value, 10);
  if (type === 'float') return el.value === '' ? null : parseFloat(el.value);
  if (type === 'csv') return csv(el.value);
  if (type === 'lines') return lines(el.value);
  return el.value;
}

function writeControl(el, value) {
  const type = el.dataset.type || (el.type === 'checkbox' ? 'bool' : 'string');
  if (type === 'bool') { el.checked = !!value; return; }
  if (type === 'tribool') { el.value = value === null || value === undefined ? '' : String(value); return; }
  if (type === 'csv') { el.value = Array.isArray(value) ? value.join(', ') : (value || ''); return; }
  if (type === 'lines') { el.value = Array.isArray(value) ? value.join('\n') : (value || ''); return; }
  el.value = value === null || value === undefined ? '' : value;
}

/** Bind every [data-path] control to its config path. */
function bindPathControls() {
  for (const el of $$('[data-path]')) {
    writeControl(el, getPath(config, el.dataset.path));
    const evt = el.tagName === 'SELECT' || el.type === 'checkbox' ? 'change' : 'input';
    el.addEventListener(evt, () => {
      setPath(config, el.dataset.path, readControl(el));
      onChange(el);
    });
  }
}

/** Bind every [data-set] checkbox group to an array in config. */
function bindSetControls() {
  const groups = {};
  for (const el of $$('[data-set]')) {
    (groups[el.dataset.set] = groups[el.dataset.set] || []).push(el);
  }
  for (const [path, els] of Object.entries(groups)) {
    const current = getPath(config, path) || [];
    for (const el of els) el.checked = current.includes(el.value);
    for (const el of els) {
      el.addEventListener('change', () => {
        const picked = els.filter((x) => x.checked).map((x) => x.value);
        setPath(config, path, picked);
        onChange(el);
      });
    }
  }
}

/* ---------------------------------------------------------------------
 * Repeaters (arrays of objects)
 * ------------------------------------------------------------------- */

function repeaterData(path) {
  if (path === '__defaultTags') return defaultTagRows;
  return getPath(config, path) || [];
}

function setRepeaterData(path, rows) {
  if (path === '__defaultTags') { defaultTagRows = rows; return; }
  setPath(config, path, rows);
}

function renderRepeater(host) {
  const path = host.dataset.repeater;
  const fields = JSON.parse(host.dataset.fields);
  const min = parseInt(host.dataset.min || '0', 10);
  const rows = repeaterData(path);

  while (rows.length < min) rows.push({});

  host.innerHTML = '';

  rows.forEach((row, idx) => {
    const rowEl = document.createElement('div');
    rowEl.className = 'rep-row';

    for (const f of fields) {
      const wrap = document.createElement('div');
      wrap.className = 'rep-field';

      const lbl = document.createElement('label');
      lbl.textContent = f.label;
      lbl.htmlFor = `rep_${path.replace(/\W/g, '_')}_${idx}_${f.key}`;
      wrap.appendChild(lbl);

      // A repeater column can be a closed set. Without this a field whose
      // legal values are an enum is a free-text box that fails at the schema
      // instead of at the point of entry.
      const isSelect = f.type === 'select' && Array.isArray(f.options);
      const input = document.createElement(isSelect ? 'select' : 'input');
      if (isSelect) {
        for (const option of f.options) {
          const opt = document.createElement('option');
          opt.value = typeof option === 'string' ? option : option.value;
          opt.textContent = typeof option === 'string' ? option : option.label;
          input.appendChild(opt);
        }
      }
      else {
        input.type = f.type === 'float' ? 'number' : 'text';
        if (f.type === 'float') input.step = 'any';
        input.placeholder = f.placeholder || '';
        input.spellcheck = false;
      }
      input.id = lbl.htmlFor;

      const v = row[f.key];
      if (isSelect) {
        const first = typeof f.options[0] === 'string' ? f.options[0] : f.options[0].value;
        input.value = (v === undefined || v === null || v === '') ? first : v;
        // Seed the row so an untouched select still exports the value it shows.
        row[f.key] = input.value;
      }
      else {
        input.value = Array.isArray(v) ? v.join(', ') : (v === undefined || v === null ? '' : v);
      }

      input.addEventListener(isSelect ? 'change' : 'input', () => {
        const raw = input.value;
        if (f.type === 'csv') row[f.key] = csv(raw);
        else if (f.type === 'csvint') row[f.key] = csv(raw).map((x) => parseInt(x, 10)).filter((x) => !Number.isNaN(x));
        else if (f.type === 'float') row[f.key] = raw === '' ? null : parseFloat(raw);
        else row[f.key] = raw;
        onChange(input);
      });

      wrap.appendChild(input);
      rowEl.appendChild(wrap);
    }

    const del = document.createElement('button');
    del.type = 'button';
    del.className = 'rep-del';
    del.title = 'Remove this row';
    del.setAttribute('aria-label', 'Remove row ' + (idx + 1));
    del.textContent = '×';
    del.disabled = rows.length <= min;
    del.addEventListener('click', () => {
      rows.splice(idx, 1);
      setRepeaterData(path, rows);
      renderRepeater(host);
      onChange(host);
    });
    rowEl.appendChild(del);

    host.appendChild(rowEl);
  });

  const add = document.createElement('button');
  add.type = 'button';
  add.className = 'btn btn-ghost btn-sm';
  add.textContent = '+ Add';
  add.addEventListener('click', () => {
    rows.push({});
    setRepeaterData(path, rows);
    renderRepeater(host);
    onChange(add);
  });
  host.appendChild(add);
}

function renderAllRepeaters() {
  for (const host of $$('.repeater')) renderRepeater(host);
}

/* ---------------------------------------------------------------------
 * Dynamically-generated checkbox groups
 * ------------------------------------------------------------------- */

function buildCheckGroup(hostId, items, setPathStr) {
  const host = $('#' + hostId);
  if (!host) return;
  host.innerHTML = '';
  const current = getPath(config, setPathStr) || [];
  for (const [value, label] of items) {
    const lbl = document.createElement('label');
    lbl.className = 'check';
    const cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.value = value;
    cb.checked = current.includes(value);
    cb.addEventListener('change', () => {
      const picked = $$('input[type=checkbox]', host).filter((x) => x.checked).map((x) => x.value);
      setPath(config, setPathStr, picked);
      onChange(cb);
    });
    lbl.appendChild(cb);
    lbl.appendChild(document.createTextNode(' ' + label));
    host.appendChild(lbl);
  }
}

/* ---------------------------------------------------------------------
 * Azure Policy selection
 *
 * Everything offered here is read from site/alz-policy-catalog.js, generated
 * from the ALZ library ref pinned in factory-version.json. The wizard cannot
 * offer a policy the deployment would not produce, and a library bump changes
 * this step by regenerating the catalog rather than by editing this file.
 * ------------------------------------------------------------------- */

/** Short prompts for the default values a client can be asked to supply. The
 *  catalog carries the library's own description, which explains the value;
 *  this is the question. */
const POLICY_VALUE_LABELS = {
  ddos_protection_plan_id: {
    label: 'DDoS protection plan resource ID',
    placeholder: '/subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Network/ddosProtectionPlans/<name>'
  },
  email_security_contact: {
    label: 'Defender for Cloud security contact',
    placeholder: 'security@example.com'
  }
};

function policySelection() {
  const gv = config.governance;
  if (!gv.policySelection) gv.policySelection = { groups: {}, assignments: {}, values: {} };
  const sel = gv.policySelection;
  if (!sel.groups) sel.groups = {};
  if (!sel.assignments) sel.assignments = {};
  if (!sel.values) sel.values = {};
  return sel;
}

/** Absent means enabled — see the defaultConfig comment. */
function policyGroupEnabled(id) {
  const groups = policySelection().groups;
  return Object.prototype.hasOwnProperty.call(groups, id) ? groups[id] !== false : true;
}

function policyGroupOf(assignmentName) {
  return POLICY_CATALOG.groups.find((g) => (g.assignments || []).includes(assignmentName)) || null;
}

/** The per-assignment override wins over its group; an assignment no group
 *  claims is enabled, so nothing the library adds is dropped by omission. */
function policyAssignmentEnabled(name) {
  const override = policySelection().assignments[name];
  if (override && typeof override.creationEnabled === 'boolean') return override.creationEnabled;
  const group = policyGroupOf(name);
  return group ? policyGroupEnabled(group.id) : true;
}

/** Which library default values the current selection obliges the client to
 *  supply, and which enabled assignments are asking. Read per assignment, not
 *  per group, so switching one assignment off in the advanced list retires its
 *  question too. Values the factory already computes are never asked for. */
function requiredPolicyValues() {
  const owed = new Map();
  for (const [name, meta] of Object.entries(POLICY_CATALOG.assignments)) {
    if (!policyAssignmentEnabled(name)) continue;
    for (const d of meta.requiredDefaults || []) {
      const decl = POLICY_CATALOG.defaults[d];
      if (!decl || decl.supplied === 'factory') continue;
      if (!owed.has(d)) owed.set(d, []);
      owed.get(d).push(name);
    }
  }
  return [...owed.entries()].sort((a, b) => a[0].localeCompare(b[0]));
}

function policyCounts() {
  const names = Object.keys(POLICY_CATALOG.assignments);
  const enabled = names.filter(policyAssignmentEnabled).length;
  return { enabled, total: names.length };
}

function renderPolicyGroups() {
  const host = $('#policyGroups');
  if (!host) return;
  host.innerHTML = '';
  for (const group of POLICY_CATALOG.groups) {
    const wrap = document.createElement('div');
    wrap.className = 'policy-group';

    const lbl = document.createElement('label');
    lbl.className = 'check';
    const cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = policyGroupEnabled(group.id);
    cb.addEventListener('change', () => {
      policySelection().groups[group.id] = cb.checked;
      renderPolicyValues();
      renderPolicyAdvanced();
      onChange(cb);
    });
    const strong = document.createElement('strong');
    strong.textContent = group.label;
    lbl.appendChild(cb);
    lbl.appendChild(strong);
    wrap.appendChild(lbl);

    const meta = document.createElement('p');
    meta.className = 'hint policy-meta';
    const owed = (group.requiredDefaults || []).filter((d) => {
      const decl = POLICY_CATALOG.defaults[d];
      return decl && decl.supplied !== 'factory';
    });
    meta.textContent = `${group.assignments.length} assignment${group.assignments.length === 1 ? '' : 's'}`
      + (owed.length ? ` — needs ${owed.map((d) => (POLICY_VALUE_LABELS[d] || {}).label || d).join(', ')}` : '');
    wrap.appendChild(meta);

    const summary = document.createElement('p');
    summary.className = 'hint';
    summary.textContent = group.summary;
    wrap.appendChild(summary);

    host.appendChild(wrap);
  }
}

function renderPolicyValues() {
  const host = $('#policyValues');
  const field = $('#policyValuesField');
  if (!host || !field) return;
  const owed = requiredPolicyValues();
  field.hidden = owed.length === 0;
  host.innerHTML = '';

  for (const [name, askedBy] of owed) {
    const decl = POLICY_CATALOG.defaults[name] || {};
    const copy = POLICY_VALUE_LABELS[name] || {};

    const wrap = document.createElement('div');
    wrap.className = 'field';

    const lbl = document.createElement('label');
    lbl.htmlFor = 'pv_' + name;
    lbl.textContent = copy.label || name;
    wrap.appendChild(lbl);

    const input = document.createElement('input');
    input.id = lbl.htmlFor;
    input.type = 'text';
    input.spellcheck = false;
    if (copy.placeholder) input.placeholder = copy.placeholder;
    input.value = policySelection().values[name] || '';
    // Deliberately does not re-render this step: rebuilding the host under a
    // focused input would drop the caret on every keystroke.
    input.addEventListener('input', () => {
      policySelection().values[name] = input.value;
      onChange(input);
    });
    wrap.appendChild(input);

    const hint = document.createElement('p');
    hint.className = 'hint';
    hint.textContent = `${decl.description || ''} Required by ${askedBy.join(', ')}.`;
    wrap.appendChild(hint);

    host.appendChild(wrap);
  }
}

function renderPolicyAdvanced() {
  const host = $('#policyAdvanced');
  if (!host) return;
  host.innerHTML = '';

  for (const name of Object.keys(POLICY_CATALOG.assignments).sort()) {
    const meta = POLICY_CATALOG.assignments[name];
    const override = policySelection().assignments[name] || {};
    const group = policyGroupOf(name);

    const row = document.createElement('div');
    row.className = 'policy-row';

    const idCell = document.createElement('div');
    idCell.className = 'policy-name';
    const code = document.createElement('code');
    code.textContent = name;
    idCell.appendChild(code);
    const scope = document.createElement('span');
    scope.className = 'policy-scope';
    scope.textContent = (group ? group.label + ' — ' : '') + (meta.managementGroups || []).join(', ');
    idCell.appendChild(scope);
    row.appendChild(idCell);

    const create = document.createElement('select');
    create.setAttribute('aria-label', `Create ${name}`);
    for (const [value, text] of [
      ['', `Inherit${group ? ` (${policyGroupEnabled(group.id) ? 'create' : 'do not create'})` : ' (create)'}`],
      ['true', 'Create'],
      ['false', 'Do not create']
    ]) {
      const opt = document.createElement('option');
      opt.value = value; opt.textContent = text;
      create.appendChild(opt);
    }
    create.value = typeof override.creationEnabled === 'boolean' ? String(override.creationEnabled) : '';

    const enforce = document.createElement('select');
    enforce.setAttribute('aria-label', `Enforcement for ${name}`);
    for (const [value, text] of [
      ['', 'Inherit enforcement'],
      ['Default', 'Enforce'],
      ['DoNotEnforce', 'Report only']
    ]) {
      const opt = document.createElement('option');
      opt.value = value; opt.textContent = text;
      enforce.appendChild(opt);
    }
    enforce.value = override.enforcementMode || '';

    const writeBack = (changed) => {
      const next = {};
      if (create.value !== '') next.creationEnabled = create.value === 'true';
      if (enforce.value !== '') next.enforcementMode = enforce.value;
      if (Object.keys(next).length) policySelection().assignments[name] = next;
      else delete policySelection().assignments[name];
      // Only the value host is rebuilt: re-rendering this list would move
      // focus off the control the user just changed.
      renderPolicyValues();
      onChange(changed);
    };
    create.addEventListener('change', () => writeBack(create));
    enforce.addEventListener('change', () => writeBack(enforce));

    row.appendChild(create);
    row.appendChild(enforce);
    host.appendChild(row);
  }
}

/** The exact sentence a client must type to place an existing subscription
 *  into the hierarchy. Composed here the same way Get-LzPlacementAcknowledgement
 *  composes it in the renderer — the wizard blocking export on one sentence
 *  while guard G30 expects another would export a configuration that then
 *  refuses to render. It names the subscription on purpose: a sentence that is
 *  the same for every estate is one a client can paste without reading, and
 *  reading it is the entire control. */
function placementAcknowledgement(subscriptionId) {
  return `I accept that ${subscriptionId} will be governed by the landing zone policy set, including its existing resources.`;
}

function brownfieldDispositionRows() {
  const bf = config.deploymentStrategy.brownfield;
  if (!Array.isArray(bf.dispositionRows)) bf.dispositionRows = [];
  return bf.dispositionRows;
}

/** One acknowledgement box per subscription the client wants placed. Rendered
 *  rather than declared, because the required sentence depends on the row. */
function renderDispositionAcknowledgements() {
  const host = $('#dispositionAckHost');
  if (!host) return;
  host.innerHTML = '';
  for (const row of brownfieldDispositionRows()) {
    if (row.action !== 'place-now' || !(row.id || '').trim()) continue;
    const expected = placementAcknowledgement(row.id.trim());

    const wrap = document.createElement('div');
    wrap.className = 'field';
    const lbl = document.createElement('label');
    lbl.htmlFor = 'ack_' + row.id.trim();
    lbl.textContent = 'Type this to confirm placing ' + row.id.trim();
    wrap.appendChild(lbl);

    const sentence = document.createElement('p');
    sentence.className = 'hint';
    const code = document.createElement('code');
    code.textContent = expected;
    sentence.appendChild(code);
    wrap.appendChild(sentence);

    const input = document.createElement('input');
    input.id = lbl.htmlFor;
    input.type = 'text';
    input.spellcheck = false;
    input.value = row.acknowledgement || '';
    input.addEventListener('input', () => { row.acknowledgement = input.value; onChange(input); });
    wrap.appendChild(input);
    host.appendChild(wrap);
  }
}

/* ---------------------------------------------------------------------
 * Management-group names
 *
 * The library's shape, the client's names. Only ids and display names are
 * editable: re-nesting a group changes which archetype it inherits, and so
 * which policy set governs everything beneath it — a decision Azure will not
 * let anyone take back, because management-group IDs are immutable.
 * ------------------------------------------------------------------- */

function managementGroupRenames() {
  const mg = config.azure.managementGroups;
  if (!mg.customHierarchy || Array.isArray(mg.customHierarchy)) mg.customHierarchy = {};
  return mg.customHierarchy;
}

/** What this estate will actually create for a library group. */
function effectiveManagementGroup(group) {
  const rename = managementGroupRenames()[group.id] || {};
  return {
    id: (rename.id || '').trim() || group.id,
    displayName: (rename.displayName || '').trim() || group.displayName
  };
}

function setManagementGroupRename(libraryId, field, value) {
  const renames = managementGroupRenames();
  const entry = renames[libraryId] || (renames[libraryId] = {});
  entry[field] = value;
  // Keep the working config free of empty shells; buildConfig strips the
  // no-op renames, but an empty object here would make the "did the client
  // change anything" test lie.
  if (!(entry.id || '').trim() && !(entry.displayName || '').trim()) delete renames[libraryId];
}

function renderManagementGroupNames() {
  const host = $('#mgRenameHost');
  if (!host) return;
  host.innerHTML = '';

  const groups = POLICY_CATALOG.managementGroups;
  if (!groups.length) {
    host.innerHTML = '<p class="hint">The generated policy catalog did not load, so the library’s management groups cannot be listed.</p>';
    return;
  }

  const byId = new Map(groups.map((g) => [g.id, g]));
  for (const group of groups) {
    const row = document.createElement('div');
    row.className = 'mg-row';

    const origin = document.createElement('div');
    origin.className = 'mg-origin';
    const code = document.createElement('code');
    code.textContent = group.id;
    origin.appendChild(code);
    const parent = document.createElement('span');
    parent.className = 'mg-parent';
    // Show the parent as the client will see it, not as the library names it.
    parent.textContent = group.parent
      ? 'under ' + effectiveManagementGroup(byId.get(group.parent) || { id: group.parent, displayName: group.parent }).id
      : 'top of the hierarchy';
    origin.appendChild(parent);
    row.appendChild(origin);

    const rename = managementGroupRenames()[group.id] || {};

    const idWrap = document.createElement('div');
    idWrap.className = 'rep-field';
    const idLabel = document.createElement('label');
    idLabel.textContent = 'ID';
    idLabel.htmlFor = 'mgid_' + group.id;
    const idInput = document.createElement('input');
    idInput.id = idLabel.htmlFor;
    idInput.type = 'text';
    idInput.spellcheck = false;
    idInput.placeholder = group.id;
    idInput.value = rename.id || '';
    idInput.addEventListener('input', () => {
      setManagementGroupRename(group.id, 'id', idInput.value);
      onChange(idInput);
    });
    idWrap.appendChild(idLabel); idWrap.appendChild(idInput);
    row.appendChild(idWrap);

    const nameWrap = document.createElement('div');
    nameWrap.className = 'rep-field';
    const nameLabel = document.createElement('label');
    nameLabel.textContent = 'Display name';
    nameLabel.htmlFor = 'mgname_' + group.id;
    const nameInput = document.createElement('input');
    nameInput.id = nameLabel.htmlFor;
    nameInput.type = 'text';
    nameInput.placeholder = group.displayName;
    nameInput.value = rename.displayName || '';
    nameInput.addEventListener('input', () => {
      setManagementGroupRename(group.id, 'displayName', nameInput.value);
      onChange(nameInput);
    });
    nameWrap.appendChild(nameLabel); nameWrap.appendChild(nameInput);
    row.appendChild(nameWrap);

    host.appendChild(row);
  }
}

function applyManagementGroupPrefix(prefix) {
  const clean = (prefix || '').trim();
  if (!clean) return;
  for (const group of POLICY_CATALOG.managementGroups) {
    setManagementGroupRename(group.id, 'id', clean + group.id);
  }
  renderManagementGroupNames();
}

function resetManagementGroupNames() {
  config.azure.managementGroups.customHierarchy = {};
  renderManagementGroupNames();
}

function renderPolicyStep() {
  renderPolicyGroups();
  renderPolicyAdvanced();
  renderPolicyValues();
}

function buildRegionDatalist() {
  const dl = $('#regionList');
  dl.innerHTML = '';
  for (const r of Object.keys(REGION_CODES).sort()) {
    const opt = document.createElement('option');
    opt.value = r;
    dl.appendChild(opt);
  }
}

/* ---------------------------------------------------------------------
 * Derived UI: approvals, env abbreviations, promotion path
 * ------------------------------------------------------------------- */

function renderApprovals() {
  const host = $('#approvalsHost');
  const envs = [...config.environments.platform, ...config.environments.application];
  host.innerHTML = '';

  if (!envs.length) {
    host.innerHTML = '<p class="hint">Select environments above first.</p>';
    return;
  }

  for (const env of envs) {
    // Own-property check, not truthiness: a truthiness test would read
    // inherited keys (e.g. "constructor") off the prototype chain.
    if (!Object.prototype.hasOwnProperty.call(config.environments.approvals, env)) {
      config.environments.approvals[env] = {
        requiredReviewers: [], waitTimerMinutes: 0, preventSelfReview: true
      };
    }
    const a = config.environments.approvals[env];

    const row = document.createElement('div');
    row.className = 'approval-row';

    const name = document.createElement('div');
    name.className = 'approval-name';
    name.textContent = env;
    row.appendChild(name);

    const revWrap = document.createElement('div');
    revWrap.className = 'rep-field';
    const revLbl = document.createElement('label');
    revLbl.textContent = 'Required reviewers';
    revLbl.htmlFor = 'apr_' + env;
    const rev = document.createElement('input');
    rev.id = revLbl.htmlFor;
    rev.type = 'text';
    rev.spellcheck = false;
    rev.placeholder = '@login or org/team, comma-separated';
    rev.value = (a.requiredReviewers || []).join(', ');
    rev.addEventListener('input', () => { a.requiredReviewers = csv(rev.value); onChange(rev); });
    revWrap.appendChild(revLbl); revWrap.appendChild(rev);
    row.appendChild(revWrap);

    const waitWrap = document.createElement('div');
    waitWrap.className = 'rep-field narrow';
    const waitLbl = document.createElement('label');
    waitLbl.textContent = 'Wait (min)';
    waitLbl.htmlFor = 'apw_' + env;
    const wait = document.createElement('input');
    wait.id = waitLbl.htmlFor;
    wait.type = 'number'; wait.min = '0'; wait.max = '43200';
    wait.value = a.waitTimerMinutes || 0;
    wait.addEventListener('input', () => {
      a.waitTimerMinutes = wait.value === '' ? 0 : parseInt(wait.value, 10);
      onChange(wait);
    });
    waitWrap.appendChild(waitLbl); waitWrap.appendChild(wait);
    row.appendChild(waitWrap);

    host.appendChild(row);
  }

  // Drop approvals for environments that are no longer selected.
  for (const key of Object.keys(config.environments.approvals)) {
    if (!envs.includes(key)) delete config.environments.approvals[key];
  }
}

function renderEnvAbbreviations() {
  const host = $('#envAbbrevHost');
  const envs = [...config.environments.platform, ...config.environments.application];
  host.innerHTML = '';
  const abbrevs = config.naming.environmentAbbreviations;
  for (const env of envs) {
    // Own-property checks so inherited keys are never read or trusted.
    if (!Object.prototype.hasOwnProperty.call(abbrevs, env) || !abbrevs[env]) {
      abbrevs[env] = Object.prototype.hasOwnProperty.call(DEFAULT_ENV_ABBREV, env)
        ? DEFAULT_ENV_ABBREV[env]
        : env.slice(0, 4);
    }
    const wrap = document.createElement('div');
    wrap.className = 'rep-field';
    const lbl = document.createElement('label');
    lbl.textContent = env;
    lbl.htmlFor = 'abbr_' + env;
    const inp = document.createElement('input');
    inp.id = lbl.htmlFor;
    inp.type = 'text';
    inp.maxLength = 6;
    inp.spellcheck = false;
    inp.value = config.naming.environmentAbbreviations[env];
    inp.addEventListener('input', () => {
      config.naming.environmentAbbreviations[env] = inp.value;
      onChange(inp);
    });
    wrap.appendChild(lbl); wrap.appendChild(inp);
    host.appendChild(wrap);
  }
  for (const key of Object.keys(config.naming.environmentAbbreviations)) {
    if (!envs.includes(key)) delete config.naming.environmentAbbreviations[key];
  }
}

function recomputePromotionPath() {
  config.environments.promotionPath = APP_ENV_ORDER.filter((e) => config.environments.application.includes(e));
  const el = $('#promotionPreview');
  el.textContent = config.environments.promotionPath.length
    ? config.environments.promotionPath.join('  →  ')
    : '— no application environments selected —';
}

/* ---------------------------------------------------------------------
 * Conditional visibility
 * ------------------------------------------------------------------- */

function conditionMet(expr) {
  // Split on the FIRST '=' only, so an expected value containing '=' survives.
  const i = expr.indexOf('=');
  if (i === -1) return false;
  const path = expr.slice(0, i);
  const expected = expr.slice(i + 1);
  const actual = getPath(config, path.trim());
  if (expected === 'true') return actual === true;
  if (expected === 'false') return actual === false;
  return String(actual) === expected;
}

function applyVisibility() {
  for (const el of $$('[data-visible-when]')) {
    el.hidden = !conditionMet(el.dataset.visibleWhen);
  }
  for (const el of $$('[data-visible-when-any]')) {
    el.hidden = !el.dataset.visibleWhenAny.split('|').some(conditionMet);
  }
}

/* ---------------------------------------------------------------------
 * Contextual hints
 * ------------------------------------------------------------------- */

const CRON_DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function describeCron(expr) {
  const p = expr.trim().split(/\s+/);
  if (p.length !== 5) return 'Not a valid five-field cron expression.';
  const [min, hr, dom, mon, dow] = p;
  if (dom === '*' && mon === '*' && dow === '*') {
    // A wildcard hour must not render as "*:00".
    if (hr === '*') return min === '*' ? 'Runs every minute.' : `Runs hourly at minute ${min} UTC.`;
    return `Runs daily at ${hr}:${min.padStart(2, '0')} UTC.`;
  }
  if (dom === '*' && mon === '*' && /^[0-6]$/.test(dow) && hr !== '*') {
    return `Runs weekly on ${CRON_DAYS[+dow]} at ${hr}:${min.padStart(2, '0')} UTC.`;
  }
  return 'Custom schedule.';
}

function updateHints() {
  const oh = $('#gh_ownershipHint');
  oh.textContent = {
    organization: 'Organizations support environments, branch protection, and team-based reviewers. This is the recommended model — and the ratified ownership policy (decision 0010): the owner is an organization the operator controls.',
    enterprise: 'Enterprise Cloud adds internal visibility, enterprise-level Actions policies, and enterprise SSO. Discovery reads the enterprise Actions policy during readiness checks.',
    personal: 'Personal accounts on the Free plan cannot use environments or branch protection on private repositories, so approval gates and protected applies are unavailable. Every control the broker cannot apply is named explicitly in the bootstrap report.'
  }[config.github.ownershipModel];

  const cm = $('#cn_modelHint');
  cm.textContent = {
    'hub-spoke': 'Uses the hub-network and spoke-network modules already present in this repository.',
    'virtual-wan': 'Emits the Azure Verified Modules Virtual WAN pattern (virtual hubs + Azure Firewall). Bastion and centralized private DNS are hub-and-spoke features.',
    none: 'No platform networking is emitted. Workload subscriptions will have no connectivity from the platform.'
  }[config.connectivity.model];

  $('#cronHint').textContent = describeCron(config.observability.driftDetection.schedule || '');

  const sth = $('#sentinelTierHint');
  sth.textContent = config.governance.policyAsCodeEngines.includes('sentinel')
    ? 'Sentinel policy enforcement was a Terraform Cloud feature and is not supported by the azurerm-only pipeline (ADR 0015). Use Azure Policy or OPA.'
    : '';

  // Tag coverage against the required-tag list.
  const tagObj = tagsObject();
  const required = config.governance.policyBaseline.requiredTags || [];
  const missing = required.filter((t) => !tagObj[t] || !String(tagObj[t]).trim());
  const cov = $('#tagCoverage');
  if (!required.length) {
    cov.textContent = '';
    cov.className = 'coverage';
  } else if (missing.length) {
    cov.textContent = `Missing a default value for required tag${missing.length > 1 ? 's' : ''}: ${missing.join(', ')}. Without these, the landing zone's own tagging policy denies its first apply.`;
    cov.className = 'coverage coverage-bad';
  } else {
    cov.textContent = `All ${required.length} policy-required tags have default values.`;
    cov.className = 'coverage coverage-ok';
  }

  // The managed-resource estimate survives in deployment-metadata.json as a
  // sizing signal; the HCP free-tier verdict UI retired with the backend
  // (ADR 0015).

  // CI/CD identity estate: recomputed live, because the count depends on the
  // environment selections made on the Environments step.
  const idCountEl = $('#cicdIdentityCount');
  if (idCountEl) {
    const model = (config.identity && config.identity.cicdIdentityModel) || 'minimal';
    const n = cicdIdentityCount();
    const envCount = uniqueEnvironments().size;
    idCountEl.textContent = model === 'per-environment'
      ? `This will create ${n} Entra identities: one plan and one apply identity for each of your ${envCount} unique environment${envCount === 1 ? '' : 's'}.`
      : `This will create ${n} Entra identities: one shared plan identity and one shared apply identity, federated to each of your ${envCount} environment${envCount === 1 ? '' : 's'}.`;
  }

  const outDir = config.organization.outputDirectoryName || config.organization.companyShortName || '<company>';
  const oph = $('#outPathHint');
  if (oph) oph.textContent = `generated-output/${outDir}/`;
}

/** Auto-fill derived values the user has not explicitly overridden. */
function applyDerivedDefaults(changedEl) {
  const id = changedEl && changedEl.id;

  if (id === 'az_primaryRegion') {
    const code = REGION_CODES[config.azure.primaryRegion];
    if (code) {
      config.azure.primaryRegionCode = code;
      writeControl($('#az_primaryRegionCode'), code);
    }
  }
  if (id === 'az_drRegion') {
    const code = REGION_CODES[config.azure.drRegion];
    if (code) {
      config.azure.drRegionCode = code;
      writeControl($('#az_drRegionCode'), code);
    }
  }
  // The Defender security contact and the library's email_security_contact
  // default are the same fact asked once. Seeding rather than aliasing keeps
  // the policy value editable: an estate can send policy-driven Defender
  // notifications somewhere other than the contact recorded on the plan.
  if (id === 'sec_defEmail' && config.security.defender.securityContactEmail) {
    const values = policySelection().values;
    if (!values.email_security_contact) {
      values.email_security_contact = config.security.defender.securityContactEmail;
      const input = $('#pv_email_security_contact');
      if (input) input.value = values.email_security_contact;
    }
  }

  if (id === 'org_companyShortName') {
    const sn = config.organization.companyShortName;
    if (sn && !$('#gh_repositoryName').dataset.touched) {
      config.github.repositoryName = `${sn}_LZ_Deployment`;
      writeControl($('#gh_repositoryName'), config.github.repositoryName);
    }
  }

  // Allowed locations must always contain the regions we deploy to, otherwise
  // the allowed-locations policy denies the landing zone's own resources.
  if (['az_primaryRegion', 'az_drRegion', 'az_allowedLocations'].includes(id)) {
    const need = [config.azure.primaryRegion, config.azure.drRegion].filter(Boolean);
    const set = new Set(config.azure.allowedLocations);
    let added = false;
    for (const r of need) if (!set.has(r)) { set.add(r); added = true; }
    if (added) {
      config.azure.allowedLocations = Array.from(set);
      writeControl($('#az_allowedLocations'), config.azure.allowedLocations);
    }
  }
}

/* ---------------------------------------------------------------------
 * Step navigation
 * ------------------------------------------------------------------- */

function buildStepNav() {
  steps = $$('.step').map((el) => ({ el, key: el.dataset.step, title: el.dataset.title }));
  const list = $('#stepList');
  list.innerHTML = '';
  steps.forEach((s, i) => {
    const li = document.createElement('li');
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'stepbtn';
    btn.dataset.index = i;
    btn.innerHTML = `<span class="stepnum">${i + 1}</span><span class="steptitle">${s.title}</span><span class="stepdot" aria-hidden="true"></span><span class="sr-only stepstate"></span>`;
    btn.addEventListener('click', () => goto(i));
    li.appendChild(btn);
    list.appendChild(li);
  });
}

function goto(index) {
  currentStep = Math.max(0, Math.min(steps.length - 1, index));
  steps.forEach((s, i) => s.el.classList.toggle('active', i === currentStep));
  $$('.stepbtn').forEach((b, i) => {
    b.classList.toggle('current', i === currentStep);
    if (i === currentStep) b.setAttribute('aria-current', 'step');
    else b.removeAttribute('aria-current');
  });
  $('#btnPrev').disabled = currentStep === 0;
  $('#btnNext').disabled = currentStep === steps.length - 1;
  $('#stepIndicator').textContent = `Step ${currentStep + 1} of ${steps.length} · ${steps[currentStep].title}`;
  $('#stepPanel').scrollTop = 0;
  $('#stepPanel').focus({ preventScroll: true });
  if (steps[currentStep].key === 'review') renderReview();
}

function updateStepStatus() {
  const { errors } = validate();
  const bad = new Set(errors.map((e) => e.step));
  let done = 0;
  steps.forEach((s, i) => {
    const btn = $$('.stepbtn')[i];
    if (!btn) return;
    const isBad = bad.has(s.key);
    btn.classList.toggle('has-error', isBad);
    btn.classList.toggle('is-done', !isBad && s.key !== 'review');
    // The status dot is color-only; this text carries the state for screen
    // readers and for anyone who cannot distinguish the dot colors.
    const state = $('.stepstate', btn);
    if (state) state.textContent = isBad ? ' — has blocking issues' : (s.key !== 'review' ? ' — complete' : '');
    if (!isBad && s.key !== 'review') done++;
  });
  const total = steps.length - 1;
  const pct = Math.round((done / total) * 100);
  const bar = $('#progressBar');
  bar.style.width = `${pct}%`;
  bar.setAttribute('aria-valuenow', String(pct));
  $('#progressText').textContent = `${done} of ${total} complete`;
}

/* ---------------------------------------------------------------------
 * Change pipeline
 * ------------------------------------------------------------------- */

let renderScheduled = false;
function onChange(changedEl) {
  applyDerivedDefaults(changedEl);
  recomputePromotionPath();
  applyVisibility();
  updateHints();

  if (renderScheduled) return;
  renderScheduled = true;
  requestAnimationFrame(() => {
    renderScheduled = false;
    renderApprovals();
    renderEnvAbbreviations();
    renderPlannedNames();
    renderDispositionAcknowledgements();
    updateStepStatus();
    if (steps[currentStep] && steps[currentStep].key === 'review') renderReview();
  });
}

/* ---------------------------------------------------------------------
 * Planned subscription names (mode=create)
 * ------------------------------------------------------------------- */

const SUB_SLOT_SUFFIX = {
  management: 'management', connectivity: 'connectivity', workloadProd: 'workload-prod',
  identity: 'identity', workloadNonProd: 'workload-nonprod', sandbox: 'sandbox'
};

/** Convention-derived display names for the subscriptions New-LzSubscriptions.ps1
 *  will create. The three required platform slots are always planned; the
 *  optional slots follow their opt-in checkboxes. */
function plannedSubscriptionNames() {
  const short = (config.organization.companyShortName || '').trim() || 'org';
  const slots = ['management', 'connectivity', 'workloadProd'];
  if ($('#az_planIdentity')?.checked) slots.push('identity');
  if ($('#az_planNonProd')?.checked) slots.push('workloadNonProd');
  if ($('#az_planSandbox')?.checked) slots.push('sandbox');
  const names = {};
  for (const slot of slots) names[slot] = `sub-${short}-${SUB_SLOT_SUFFIX[slot]}`;
  return names;
}

function renderPlannedNames() {
  const host = $('#az_plannedNames');
  if (!host) return;
  host.innerHTML = '';
  for (const name of Object.values(plannedSubscriptionNames())) {
    const li = document.createElement('li');
    const code = document.createElement('code');
    code.textContent = name;
    li.appendChild(code);
    host.appendChild(li);
  }
}

/* ---------------------------------------------------------------------
 * Review + export
 * ------------------------------------------------------------------- */

function buildConfig() {
  const out = JSON.parse(JSON.stringify(config));
  out.generatedAt = new Date().toISOString();
  out.factoryVersion = FACTORY_VERSION;
  out.schemaVersion = SCHEMA_VERSION;
  out.naming.defaultTags = tagsObject();
  if (!out.organization.outputDirectoryName) {
    out.organization.outputDirectoryName = out.organization.companyShortName;
  }
  if (!out.github.repositoryName) {
    out.github.repositoryName = `${out.organization.companyShortName}_LZ_Deployment`;
  }
  if (!out.backend.azurerm.subscriptionId) {
    out.backend.azurerm.subscriptionId = out.azure.subscriptions.management;
  }
  if (out.azure.managementGroups.strategy !== 'custom') {
    delete out.azure.managementGroups.customHierarchy;
  } else {
    // Only real renames travel. An entry that restates the library's own name
    // would read as a decision nobody made, and would have to be re-verified
    // against the library on every bump.
    const renames = out.azure.managementGroups.customHierarchy || {};
    const library = new Map(POLICY_CATALOG.managementGroups.map((g) => [g.id, g]));
    for (const [libraryId, rename] of Object.entries(renames)) {
      const group = library.get(libraryId);
      const id = (rename.id || '').trim();
      const displayName = (rename.displayName || '').trim();
      const kept = {};
      if (id && (!group || id !== group.id)) kept.id = id;
      if (displayName && (!group || displayName !== group.displayName)) kept.displayName = displayName;
      if (Object.keys(kept).length) renames[libraryId] = kept;
      else delete renames[libraryId];
    }
  }
  if ((out.azure.subscriptions.mode || 'create') === 'create') {
    out.azure.subscriptions.plannedNames = plannedSubscriptionNames();
  } else {
    delete out.azure.subscriptions.plannedNames;
  }
  if (out.deploymentStrategy.mode !== 'brownfield') {
    delete out.deploymentStrategy.brownfield;
  } else {
    // The repeater needs an array; the schema wants a map keyed by subscription
    // so a disposition cannot be recorded twice for the same subscription.
    const bf = out.deploymentStrategy.brownfield;
    const dispositions = {};
    for (const row of (bf.dispositionRows || [])) {
      const id = (row.id || '').trim();
      if (!id) continue;
      const entry = { action: row.action === 'place-now' ? 'place-now' : 'defer' };
      if (entry.action === 'place-now' && (row.acknowledgement || '').trim()) {
        entry.acknowledgement = row.acknowledgement.trim();
      }
      if ((row.note || '').trim()) entry.note = row.note.trim();
      dispositions[id] = entry;
    }
    delete bf.dispositionRows;
    if (Object.keys(dispositions).length) bf.dispositions = dispositions;
    else delete bf.dispositions;
  }
  if (out.naming.standard !== 'custom') {
    delete out.naming.resourceGroupPattern;
    delete out.naming.resourcePattern;
  }
  // Strip empty-string optionals so the export stays clean and the schema's
  // "" -> "not provided" convention is only used where it carries meaning.
  for (const k of ['identity', 'workloadNonProd', 'sandbox']) {
    if (!out.azure.subscriptions[k]) delete out.azure.subscriptions[k];
  }
  // Feature-detail blocks travel only when the feature is on: an untouched
  // number input exports null and an untouched text input exports '', both of
  // which fail the schema's typed/format checks (caught by render gate G00).
  if (!out.connectivity.expressRoute.enabled) out.connectivity.expressRoute = { enabled: false };
  if (!out.connectivity.vpn.enabled) out.connectivity.vpn = { enabled: false };
  if (!out.security.defender.securityContactEmail) delete out.security.defender.securityContactEmail;
  // Only the chosen backend's block travels. The schema requires whichever one
  // `type` names, and carrying the other would record coordinates for a state
  // location this estate does not use.
  if (out.backend.type === 'hcp-terraform') {
    if (!out.backend.hcpTerraform.workspacePrefix) delete out.backend.hcpTerraform.workspacePrefix;
  } else {
    delete out.backend.hcpTerraform;
  }
  // Policy selection travels only where it says something. A value for a
  // default nothing asks for any more would otherwise outlive the choice that
  // required it and be rendered into the layer regardless.
  {
    const sel = out.governance.policySelection || {};
    const stillOwed = new Set(requiredPolicyValues().map(([name]) => name));
    for (const name of Object.keys(sel.values || {})) {
      if (!stillOwed.has(name) || !String(sel.values[name]).trim()) delete sel.values[name];
    }
    for (const name of Object.keys(sel.assignments || {})) {
      if (!Object.keys(sel.assignments[name] || {}).length) delete sel.assignments[name];
    }
    for (const key of ['groups', 'assignments', 'values']) {
      if (sel[key] && !Object.keys(sel[key]).length) delete sel[key];
    }
    if (!Object.keys(sel).length) delete out.governance.policySelection;
  }
  if (!out.github.enterpriseSlug) delete out.github.enterpriseSlug;
  if (!out.azure.drRegion) { delete out.azure.drRegion; delete out.azure.drRegionCode; }
  // Nulls are never meaningful in this contract — they are unfilled inputs.
  const stripNulls = (o) => {
    for (const key of Object.keys(o)) {
      if (o[key] === null) delete o[key];
      else if (typeof o[key] === 'object' && !Array.isArray(o[key])) stripNulls(o[key]);
    }
  };
  stripNulls(out);
  return out;
}

function renderReview() {
  const { errors, warnings } = validate();
  const host = $('#validationHost');
  host.innerHTML = '';

  const summary = document.createElement('div');
  summary.className = 'val-summary ' + (errors.length ? 'val-bad' : warnings.length ? 'val-warn' : 'val-ok');
  summary.innerHTML = errors.length
    ? `<strong>${errors.length} blocking issue${errors.length > 1 ? 's' : ''}</strong> — export is disabled until these are resolved.`
    : warnings.length
      ? `<strong>Ready to export</strong> with ${warnings.length} advisory${warnings.length > 1 ? ' items' : ' item'} to review.`
      : '<strong>Ready to export</strong> — no issues found.';
  host.appendChild(summary);

  const renderList = (items, cls, heading) => {
    if (!items.length) return;
    const h = document.createElement('h3');
    h.className = 'sub';
    h.textContent = heading;
    host.appendChild(h);
    const ul = document.createElement('ul');
    ul.className = 'val-list ' + cls;
    for (const it of items) {
      const li = document.createElement('li');
      const step = steps.find((s) => s.key === it.step);
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'val-jump';
      btn.textContent = step ? step.title : it.step;
      btn.addEventListener('click', () => goto(steps.findIndex((s) => s.key === it.step)));
      li.appendChild(btn);
      li.appendChild(document.createTextNode(' ' + it.message));
      ul.appendChild(li);
    }
    host.appendChild(ul);
  };

  renderList(errors, 'val-list-bad', 'Blocking issues');
  renderList(warnings, 'val-list-warn', 'Advisories');

  $('#jsonPreview').textContent = JSON.stringify(buildConfig(), null, 2);
  renderExportGrid(errors.length === 0);
  $('#btnExport').disabled = errors.length > 0;
}

/** Artifacts this page can emit. Anything requiring the template corpus is
 *  deliberately NOT here — that is the renderer's responsibility. */
function exportArtifacts() {
  const cfg = buildConfig();
  return [
    {
      name: 'lz-config.json',
      desc: 'The configuration contract. Every downstream tool reads this file. Everything else below is derived from it.',
      primary: true,
      build: () => JSON.stringify(cfg, null, 2),
      mime: 'application/json'
    },
    {
      name: 'terraform.auto.tfvars',
      desc: 'Terraform variables for the global layer, mapped onto the variables already declared in terraform/live/global/variables.tf.',
      build: () => tfvarsGlobal(cfg)
    },
    {
      name: 'connectivity.auto.tfvars',
      desc: 'Terraform variables for the platform-connectivity layer.',
      build: () => tfvarsConnectivity(cfg)
    },
    {
      name: 'backend.hcl',
      desc: 'Partial backend configuration passed to terraform init -backend-config.',
      build: () => backendHcl(cfg)
    },
    {
      name: 'environments.json',
      desc: 'Environment definitions, promotion order, and approval gates. Consumed by the bootstrap broker to create GitHub environments.',
      build: () => JSON.stringify(environmentDefinitions(cfg), null, 2),
      mime: 'application/json'
    },
    {
      name: 'deployment-metadata.json',
      desc: 'Provenance: factory version, schema version, timestamp, and the release gates that must pass before this configuration is production-ready.',
      build: () => JSON.stringify(deploymentMetadata(cfg), null, 2),
      mime: 'application/json'
    },
    {
      name: 'CONFIGURATION.md',
      desc: 'Human-readable summary of every decision recorded here, for the generated repository and for change review.',
      build: () => configurationMarkdown(cfg),
      mime: 'text/markdown'
    },
    {
      name: 'NEXT-STEPS.md',
      desc: 'The exact commands to run next, in order, with the prerequisites each one assumes.',
      build: () => nextStepsMarkdown(cfg),
      mime: 'text/markdown'
    }
  ];
}

function renderExportGrid(enabled) {
  const grid = $('#exportGrid');
  grid.innerHTML = '';
  for (const art of exportArtifacts()) {
    const card = document.createElement('div');
    card.className = 'export-card' + (art.primary ? ' export-primary' : '');

    const h = document.createElement('h4');
    h.textContent = art.name;
    card.appendChild(h);

    const p = document.createElement('p');
    p.textContent = art.desc;
    card.appendChild(p);

    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'btn btn-sm ' + (art.primary ? 'btn-primary' : 'btn-ghost');
    btn.textContent = 'Download';
    btn.disabled = !enabled;
    btn.addEventListener('click', () => {
      download(art.name, art.build(), art.mime || 'text/plain');
      toast(`${art.name} downloaded.`);
    });
    card.appendChild(btn);

    grid.appendChild(card);
  }

  const bundleBtn = $('#btnBundle');
  if (bundleBtn) bundleBtn.disabled = !enabled;
}

/* ---------------------------------------------------------------------
 * Bundle download — store-only ZIP (no compression) plus a SHA-256
 * manifest, written in plain JS so the page stays library-free and
 * offline. One file lands in the download folder instead of eight.
 * ------------------------------------------------------------------- */

const CRC32_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(bytes) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) c = CRC32_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

/** MS-DOS date/time pair used by the ZIP headers (2-second resolution). */
function dosDateTime(d) {
  const year = Math.max(1980, d.getFullYear());
  return {
    date: ((year - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate(),
    time: (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1)
  };
}

/** Build a store-only (method 0) ZIP: local file headers, central directory,
 *  end-of-central-directory. Entries are { name, data: Uint8Array }. Flag
 *  0x0800 marks the file names as UTF-8. */
function buildZip(entries, when) {
  const enc = new TextEncoder();
  const { date, time } = dosDateTime(when || new Date());
  const u16 = (v) => [v & 0xFF, (v >>> 8) & 0xFF];
  const u32 = (v) => [v & 0xFF, (v >>> 8) & 0xFF, (v >>> 16) & 0xFF, (v >>> 24) & 0xFF];

  const chunks = [];
  const central = [];
  let offset = 0;

  for (const e of entries) {
    const name = enc.encode(e.name);
    const crc = crc32(e.data);
    const local = new Uint8Array([
      ...u32(0x04034B50), ...u16(20), ...u16(0x0800), ...u16(0),
      ...u16(time), ...u16(date),
      ...u32(crc), ...u32(e.data.length), ...u32(e.data.length),
      ...u16(name.length), ...u16(0)
    ]);
    chunks.push(local, name, e.data);
    central.push({ name, crc, size: e.data.length, offset });
    offset += local.length + name.length + e.data.length;
  }

  const cdStart = offset;
  let cdSize = 0;
  for (const c of central) {
    const hdr = new Uint8Array([
      ...u32(0x02014B50), ...u16(20), ...u16(20), ...u16(0x0800), ...u16(0),
      ...u16(time), ...u16(date),
      ...u32(c.crc), ...u32(c.size), ...u32(c.size),
      ...u16(c.name.length), ...u16(0), ...u16(0),
      ...u16(0), ...u16(0), ...u32(0), ...u32(c.offset)
    ]);
    chunks.push(hdr, c.name);
    cdSize += hdr.length + c.name.length;
  }
  chunks.push(new Uint8Array([
    ...u32(0x06054B50), ...u16(0), ...u16(0),
    ...u16(central.length), ...u16(central.length),
    ...u32(cdSize), ...u32(cdStart), ...u16(0)
  ]));

  const out = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let p = 0;
  for (const c of chunks) { out.set(c, p); p += c.length; }
  return out;
}

async function sha256Hex(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** All artifacts in one zip, under <outputDirectoryName>/, plus checksums.txt
 *  so placement into the factory clone can be verified file by file. */
async function downloadBundle() {
  const cfg = buildConfig();
  const slug = cfg.organization.outputDirectoryName;
  const enc = new TextEncoder();
  const files = exportArtifacts().map((a) => ({ name: a.name, data: enc.encode(a.build()) }));

  const hasSubtle = typeof crypto !== 'undefined' && crypto.subtle && crypto.subtle.digest;
  if (hasSubtle) {
    const lines = [
      '# SHA-256 of every artifact in this bundle. After extracting into the',
      `# factory clone, verify placement with:`,
      `#   pwsh: Get-FileHash generated-output/${slug}/* -Algorithm SHA256`,
      `#   bash: (cd generated-output && sha256sum -c ${slug}/checksums.txt)`
    ];
    for (const f of files) lines.push(`${await sha256Hex(f.data)}  ${slug}/${f.name}`);
    lines.push('');
    files.push({ name: 'checksums.txt', data: enc.encode(lines.join('\n')) });
  }

  const zip = buildZip(files.map((f) => ({ name: `${slug}/${f.name}`, data: f.data })), new Date());
  download(`${slug}-lz-artifacts.zip`, zip, 'application/zip');
  return hasSubtle;
}

/* ---------------------------------------------------------------------
 * Artifact builders
 * ------------------------------------------------------------------- */

function hclString(s) { return JSON.stringify(String(s === null || s === undefined ? '' : s)); }
function hclList(arr) { return '[' + (arr || []).map(hclString).join(', ') + ']'; }
function hclMap(obj, indent = '  ') {
  const entries = Object.entries(obj || {});
  if (!entries.length) return '{}';
  return '{\n' + entries.map(([k, v]) => `${indent}  ${k} = ${hclString(v)}`).join('\n') + `\n${indent}}`;
}

function tfvarsHeader(cfg, layer, sourceFile) {
  return [
    `# Generated by the Azure Landing Zone Factory wizard.`,
    `# Layer:      ${layer}`,
    `# Company:    ${cfg.organization.companyName}`,
    `# Generated:  ${cfg.generatedAt}`,
    `# Factory:    v${cfg.factoryVersion} (schema ${cfg.schemaVersion})`,
    `#`,
    `# Every value here comes from lz-config.json. Do not hand-edit: re-run the`,
    `# wizard and re-export, so the config and the variables cannot diverge.`,
    `# Variables correspond to those declared in ${sourceFile}.`,
    ''
  ].join('\n');
}

function tfvarsGlobal(cfg) {
  const s = cfg.azure.subscriptions;
  const a = cfg.backend.azurerm;
  const out = [
    `root_parent_management_group_id = ${hclString(cfg.azure.managementGroups.rootId || '')}`,
    `primary_region                  = ${hclString(cfg.azure.primaryRegion)}`,
    `management_subscription_id      = ${hclString(s.management)}`
  ];
  if (s.connectivity) out.push(`connectivity_subscription_id     = ${hclString(s.connectivity)}`);
  if (s.identity) out.push(`identity_subscription_id         = ${hclString(s.identity)}`);
  if (s.workloadProd) out.push(`workload_prod_subscription_id    = ${hclString(s.workloadProd)}`);
  if (s.workloadNonProd) out.push(`workload_nonprod_subscription_id = ${hclString(s.workloadNonProd)}`);
  if (s.sandbox) out.push(`sandbox_subscription_id          = ${hclString(s.sandbox)}`);
  out.push(`state_resource_group_name  = ${hclString(a.resourceGroupName)}`);
  out.push(`state_storage_account_name = ${hclString(a.storageAccountName)}`);
  out.push(`state_container_name       = ${hclString(a.containerName || 'tfstate')}`);
  out.push('');
  return tfvarsHeader(cfg, 'global', 'terraform/live/global/variables.tf') + out.join('\n');
}

function tfvarsConnectivity(cfg) {
  const c = cfg.connectivity;
  const hs = c.hubSpoke || {};
  const out = [
    `connectivity_subscription_id = ${hclString(cfg.azure.subscriptions.connectivity)}`,
    `org_prefix                   = ${hclString(cfg.organization.companyShortName)}`,
    `primary_region               = ${hclString(cfg.azure.primaryRegion)}`,
    `primary_region_code          = ${hclString(cfg.azure.primaryRegionCode)}`
  ];
  if (cfg.azure.drRegion) {
    out.push(`dr_region      = ${hclString(cfg.azure.drRegion)}`);
    out.push(`dr_region_code = ${hclString(cfg.azure.drRegionCode)}`);
  }
  if (hs.primaryHubAddressSpace) out.push(`primary_hub_address_space = ${hclString(hs.primaryHubAddressSpace)}`);
  if (hs.drHubAddressSpace && cfg.azure.drRegion) out.push(`dr_hub_address_space      = ${hclString(hs.drHubAddressSpace)}`);
  out.push(`firewall_enabled            = ${c.firewall.enabled === true}`);
  out.push(`azfw_tier                   = ${hclString(c.firewall.azfwTier)}`);
  out.push(`deploy_bastion              = ${c.bastion.enabled}`);
  out.push(`deploy_vpn_gateway          = ${(c.vpn || {}).enabled === true}`);
  out.push(`deploy_expressroute_gateway = ${(c.expressRoute || {}).enabled === true}`);
  out.push(`deploy_private_dns          = ${c.privateDns.enabled}`);
  out.push(`private_dns_zones           = ${hclList((c.privateDns || {}).zones || [])}`);
  out.push(`availability_zones          = ${hclList(hs.availabilityZones || [])}`);
  out.push(`default_tags = ${hclMap(cfg.naming.defaultTags)}`);
  out.push('');
  return tfvarsHeader(cfg, 'platform-connectivity', 'terraform/live/platform-connectivity/variables.tf') + out.join('\n');
}

function backendHcl(cfg) {
  const head = [
    '# Partial backend configuration.',
    '#   terraform init -backend-config=backend.hcl',
    `# Generated ${cfg.generatedAt} by factory v${cfg.factoryVersion}.`,
    '#',
    '# One backend.hcl per layer: replace <layer> below with the layer name so',
    '# each layer keeps an isolated state file. Shared state across layers is the',
    '# single most common cause of an unrecoverable landing zone.',
    ''
  ].join('\n');

  const a = cfg.backend.azurerm;
  return head + [
    `resource_group_name  = ${hclString(a.resourceGroupName)}`,
    `storage_account_name = ${hclString(a.storageAccountName)}`,
    `container_name       = ${hclString(a.containerName || 'tfstate')}`,
    `key                  = ${hclString('<layer>.tfstate')}`,
    `subscription_id      = ${hclString(a.subscriptionId)}`,
    `use_oidc             = true`,
    `use_azuread_auth     = true`,
    ''
  ].join('\n');
}

function environmentDefinitions(cfg) {
  // Own-property lookups so a hostile key in an imported config can never
  // pull inherited values off Object.prototype into the exported artifact.
  const own = (obj, key) => Object.prototype.hasOwnProperty.call(obj || {}, key) ? obj[key] : undefined;
  // Broker-only key: with the minimal model (the default) the broker creates
  // ONE shared plan and ONE shared apply app registration; each environment
  // below still gets its own environment:<name> federated credential on the
  // shared apply identity, so the subjects are identical in both models.
  const model = (cfg.identity && cfg.identity.cicdIdentityModel) || 'minimal';
  const shared = model !== 'per-environment';
  const mk = (name, plane) => ({
    name,
    plane,
    abbreviation: own(cfg.naming.environmentAbbreviations, name) || name,
    approvals: own(cfg.environments.approvals, name) || { requiredReviewers: [], waitTimerMinutes: 0, preventSelfReview: true },
    stateKey: `${name}.tfstate`,
    oidcSubject: `repo:${cfg.github.ownerName}/${cfg.github.repositoryName}:environment:${name}`,
    identities: {
      plan: {
        appName: shared
          ? `sp-${cfg.organization.companyShortName}-plan`
          : `sp-${cfg.organization.companyShortName}-${name}-plan`,
        subject: `repo:${cfg.github.ownerName}/${cfg.github.repositoryName}:pull_request`,
        azureRoles: ['Reader'],
        note: shared
          ? 'Shared plan-time identity (minimal model). Read-only by design so a compromised pull request cannot mutate Azure.'
          : 'Plan-time identity. Read-only by design so a compromised pull request cannot mutate Azure.'
      },
      apply: {
        appName: shared
          ? `sp-${cfg.organization.companyShortName}-apply`
          : `sp-${cfg.organization.companyShortName}-${name}-apply`,
        subject: `repo:${cfg.github.ownerName}/${cfg.github.repositoryName}:environment:${name}`,
        azureRoles: ['Contributor'],
        note: shared
          ? 'Shared apply-time identity (minimal model): one app registration carrying one federated credential per environment subject, so it still cannot be assumed from an arbitrary branch or pull request.'
          : 'Apply-time identity. Bound to the environment subject only, so it cannot be assumed from an arbitrary branch or pull request.'
      }
    }
  });

  return {
    generatedAt: cfg.generatedAt,
    factoryVersion: cfg.factoryVersion,
    repository: `${cfg.github.ownerName}/${cfg.github.repositoryName}`,
    cicdIdentityModel: model,
    platform: cfg.environments.platform.map((e) => mk(e, 'platform')),
    application: cfg.environments.application.map((e) => mk(e, 'application')),
    promotionPath: cfg.environments.promotionPath,
    notes: [
      shared
        ? 'Minimal identity model: 2 Entra identities in total. The plan/apply split is preserved — it stays structurally impossible for a pull-request-triggered run to hold write access.'
        : 'Two identities per environment is deliberate: it makes it structurally impossible for a pull-request-triggered run to hold write access.',
      'The apply subject is pinned to environment:<name>. A wildcard subject such as repo:owner/repo:* would let any branch assume the apply identity.'
    ]
  };
}

function deploymentMetadata(cfg) {
  return {
    generatedAt: cfg.generatedAt,
    factoryVersion: cfg.factoryVersion,
    schemaVersion: cfg.schemaVersion,
    company: cfg.organization.companyName,
    companyShortName: cfg.organization.companyShortName,
    tenantId: cfg.azure.tenantId,
    repository: `${cfg.github.ownerName}/${cfg.github.repositoryName}`,
    backend: cfg.backend.type,
    deploymentMode: cfg.deploymentStrategy.mode,
    estimatedManagedResources: estimateRum(),
    unmetDependencies: unmetDependencies(cfg),
    generatedBy: 'site/index.html (offline wizard)',
    dataHandling: 'This configuration was produced entirely on the operator workstation. The wizard makes no network requests.'
  };
}

/** Features the configuration asks for that the module corpus cannot yet deliver. */
/** Every value a schema path addresses, descending through arrays.
 *  The schema addresses an array-of-objects field as `path.field`, which is
 *  what the coverage register records, so a plain getPath() would read
 *  `finops.budgets.amountUsd` as undefined on a config that has three budgets. */
function readAnswerPath(node, segments) {
  if (Array.isArray(node)) return node.flatMap((item) => readAnswerPath(item, segments));
  if (!segments.length) return node === undefined ? [] : [node];
  if (node === null || typeof node !== 'object') return [];
  if (!Object.prototype.hasOwnProperty.call(node, segments[0])) return [];
  return readAnswerPath(node[segments[0]], segments.slice(1));
}

/** True when the client actually gave this path a value — one that differs from
 *  what defaultConfig() would have exported anyway. An untouched default is not
 *  an answer anyone is owed a warning about, and warning about it would teach
 *  the client to ignore the whole table. */
function pathWasAnswered(cfg, path, defaults) {
  const segments = path.split('.');
  const actual = readAnswerPath(cfg, segments).filter(
    (v) => v !== undefined && v !== null && v !== '' && !(Array.isArray(v) && !v.length)
  );
  if (!actual.length) return false;
  return JSON.stringify(actual) !== JSON.stringify(readAnswerPath(defaults, segments));
}

/** Everything the client answered that the deployment will not act on.
 *
 *  The first three entries used to be a hand-written list of four features,
 *  which is how the factory ended up shipping a dozen more of the same thing
 *  unnoticed. The rest is read from the generated ledger, so an answer cannot
 *  become unwired without the client being told, and cannot be wired up
 *  without the warning disappearing on its own. */
function unmetDependencies(cfg) {
  const out = [];
  if (cfg.github.useSelfHostedRunners) {
    out.push({ feature: 'Self-hosted runners', module: '(workflows)', status: 'unsupported', impact: 'v1 emits GitHub-hosted workflows only.' });
  }
  if (cfg.security.defender.enabled) {
    out.push({ feature: 'Defender for Cloud plans', module: '(per-estate)', status: 'recorded-not-deployed', impact: 'ALZ policy archetypes govern Defender configuration; plan-level enablement is per-estate work recorded in lz-config.json (ADR 0017).' });
  }
  if (cfg.security.sentinel && cfg.security.sentinel.enabled) {
    out.push({ feature: 'Microsoft Sentinel', module: '(per-estate)', status: 'recorded-not-deployed', impact: 'Preserved in lz-config.json; onboard inside the generated repository against the management workspace (ADR 0017).' });
  }
  if (cfg.security.keyVault.customerManagedKeys) {
    out.push({ feature: 'Customer-managed keys', module: '(per-estate)', status: 'recorded-not-deployed', impact: 'Preserved in lz-config.json; implement inside the generated repository (ADR 0017).' });
  }

  const defaults = defaultConfig();
  for (const entry of RECORDED_NOT_DEPLOYED) {
    const answered = (entry.paths || []).filter((p) => pathWasAnswered(cfg, p, defaults));
    if (!answered.length) continue;
    out.push({
      feature: entry.label,
      module: entry.module,
      status: 'recorded-not-deployed',
      impact: `${answered.join(', ')} — ${entry.impact}`
    });
  }
  return out;
}

function md(...ls) { return ls.join('\n'); }

function configurationMarkdown(cfg) {
  const t = cfg.naming.defaultTags;
  const unmet = unmetDependencies(cfg);
  const { warnings } = validate();

  return md(
    `# Landing Zone Configuration — ${cfg.organization.companyName}`,
    '',
    `Generated ${cfg.generatedAt} by Landing Zone Factory v${cfg.factoryVersion} (schema ${cfg.schemaVersion}).`,
    '',
    'This document is a rendering of `lz-config.json`. That file is the source of truth;',
    'if the two ever disagree, the JSON wins and this document is stale.',
    '',
    '## Organization',
    '',
    '| Field | Value |',
    '|---|---|',
    `| Company | ${cfg.organization.companyName} |`,
    `| Short name (\`org_prefix\`) | \`${cfg.organization.companyShortName}\` |`,
    `| Business unit | ${cfg.organization.businessUnit} |`,
    '',
    '## Azure',
    '',
    '| Field | Value |',
    '|---|---|',
    `| Tenant | \`${cfg.azure.tenantId}\` |`,
    `| Primary region | ${cfg.azure.primaryRegion} (\`${cfg.azure.primaryRegionCode}\`) |`,
    `| DR region | ${cfg.azure.drRegion ? `${cfg.azure.drRegion} (\`${cfg.azure.drRegionCode}\`)` : '_none — single-region deployment_'} |`,
    `| Allowed locations | ${cfg.azure.allowedLocations.join(', ')} |`,
    `| MG root | \`${cfg.azure.managementGroups.rootId}\` |`,
    `| MG strategy | ${cfg.azure.managementGroups.strategy} |`,
    '',
    '### Subscriptions',
    '',
    `Source: **${cfg.azure.subscriptions.mode || 'create'}**${(cfg.azure.subscriptions.mode || 'create') === 'create' ? ' — IDs are filled in by `scripts/New-LzSubscriptions.ps1` after export.' : ''}`,
    '',
    '| Role | Subscription ID |',
    '|---|---|',
    ...Object.entries(cfg.azure.subscriptions)
      .filter(([k]) => k !== 'mode' && k !== 'plannedNames')
      .map(([k, v]) => {
        const planned = (cfg.azure.subscriptions.plannedNames || {})[k];
        return `| ${k} | ${v ? `\`${v}\`` : planned ? `_(to be created as \`${planned}\`)_` : '_(not used)_'} |`;
      }),
    '',
    '## GitHub',
    '',
    '| Field | Value |',
    '|---|---|',
    `| Ownership model | ${cfg.github.ownershipModel} |`,
    `| Repository | \`${cfg.github.ownerName}/${cfg.github.repositoryName}\` |`,
    `| Visibility | ${cfg.github.visibility} |`,
    `| Branch protection | ${cfg.github.branchProtection.enabled ? `enabled, ${cfg.github.branchProtection.requiredApprovals} approval(s)` : '**disabled**'} |`,
    '',
    '## State backend',
    '',
    md(
      `Azure Storage — \`${cfg.backend.azurerm.storageAccountName}\` in \`${cfg.backend.azurerm.resourceGroupName}\`,`,
      `container \`${cfg.backend.azurerm.containerName}\`, OIDC + Entra ID auth (no storage keys).`,
      '',
      'One state key per layer, supplied through each layer\'s `backend.hcl`. The state resource group,',
      'account, and containers are created by the bootstrap broker before the first layer initialises.'
    ),
    '',
    '## Environments',
    '',
    `Platform: ${cfg.environments.platform.join(', ')}`,
    '',
    `Application: ${cfg.environments.application.join(', ')}`,
    '',
    `Promotion path: ${cfg.environments.promotionPath.join(' → ')}`,
    '',
    '| Environment | Reviewers | Wait (min) |',
    '|---|---|---|',
    ...[...cfg.environments.platform, ...cfg.environments.application].map((e) => {
      const a = cfg.environments.approvals[e] || {};
      const r = (a.requiredReviewers || []);
      return `| ${e} | ${r.length ? r.join(', ') : '_none — deploys without approval_'} | ${a.waitTimerMinutes || 0} |`;
    }),
    '',
    '## Connectivity',
    '',
    `Topology: **${cfg.connectivity.model}**. Firewall: **${cfg.connectivity.firewall.enabled ? cfg.connectivity.firewall.type : 'none'}**${cfg.connectivity.firewall.enabled ? ` (${cfg.connectivity.firewall.azfwTier}, threat intel ${cfg.connectivity.firewall.threatIntelligenceMode})` : ''}.`,
    '',
    cfg.connectivity.model === 'hub-spoke'
      ? md(
          '| Space | CIDR |',
          '|---|---|',
          `| Primary hub | \`${cfg.connectivity.hubSpoke.primaryHubAddressSpace}\` |`,
          `| DR hub | \`${cfg.connectivity.hubSpoke.drHubAddressSpace}\` |`,
          `| Primary spoke | \`${cfg.connectivity.hubSpoke.primarySpokeAddressSpace}\` |`,
          `| DR spoke | \`${cfg.connectivity.hubSpoke.drSpokeAddressSpace}\` |`
        )
      : '_No platform networking._',
    '',
    `Hybrid: ExpressRoute ${cfg.connectivity.expressRoute.enabled ? 'yes' : 'no'}, VPN ${cfg.connectivity.vpn.enabled ? 'yes' : 'no'}, Bastion ${cfg.connectivity.bastion.enabled ? 'yes' : 'no'}.`,
    '',
    '### Operator loop-back — the two placeholders in `connectivity.auto.tfvars`',
    '',
    'The exported `connectivity.auto.tfvars` deliberately carries two **commented** placeholders the',
    'wizard never collects (see `factory/renderer/variable-map.json`). They are closed by hand, in',
    'this order:',
    '',
    '1. **Fill `management_ip_ranges`** in `connectivity.auto.tfvars` before the first',
    '   `platform-connectivity` plan. It is required — the plan fails until it is set — and',
    '   wildcards (`*`, `0.0.0.0/0`) are rejected.',
    '2. **Plan and apply `platform-management`**, which creates the Log Analytics workspace.',
    '3. **Paste the `log_analytics_workspace_id` output** from that apply into',
    '   `connectivity.auto.tfvars`, uncommenting the placeholder line.',
    '4. **Re-plan `platform-connectivity`.** This second plan is what wires hub firewall diagnostics',
    '   and threat-intel alerts to the workspace — left unset, they are silently not created and',
    '   nothing else will warn about it.',
    '',
    'Do not add these values to `lz-config.json` or expect a wizard re-export to fill them; the',
    'omission is a factory contract, not a gap.',
    '',
    '## Governance',
    '',
    `Policy enforcement: **${cfg.governance.policyBaseline.enforcementMode}**.`,
    '',
    `Required tags: ${cfg.governance.policyBaseline.requiredTags.map((x) => `\`${x}\``).join(', ')}`,
    '',
    `Policy engines: ${cfg.governance.policyAsCodeEngines.join(', ')}`,
    '',
    (() => {
      const { enabled, total } = policyCounts();
      const off = POLICY_CATALOG.groups.filter((g) => !policyGroupEnabled(g.id)).map((g) => g.label);
      return `ALZ policy assignments selected: **${enabled} of ${total}** from `
        + `\`${POLICY_CATALOG.library.path}@${POLICY_CATALOG.library.ref}\``
        + (off.length ? `. Groups turned off: ${off.join(', ')}.` : '.');
    })(),
    '',
    `Compliance frameworks: ${cfg.governance.complianceFrameworks.length ? cfg.governance.complianceFrameworks.join(', ') : '_none declared_'}`,
    '',
    cfg.governance.regulatoryNotes ? md('### Regulatory notes', '', cfg.governance.regulatoryNotes) : '',
    '',
    '## Default tags',
    '',
    '| Key | Value |',
    '|---|---|',
    ...Object.entries(t).map(([k, v]) => `| \`${k}\` | ${v || '_(empty)_'} |`),
    '',
    '## Operations',
    '',
    `Operating model: **${cfg.operations.operatingModel}**. Platform team: ${cfg.operations.platformTeam.name}.`,
    '',
    '| Contact | Email | Role |',
    '|---|---|---|',
    ...cfg.operations.platformTeam.contacts.filter((c) => c.name || c.email).map((c) => `| ${c.name || ''} | ${c.email || ''} | ${c.role || ''} |`),
    '',
    '## FinOps',
    '',
    `Cost center \`${cfg.finops.costCenter}\`, ${cfg.finops.chargebackModel}, owner ${cfg.finops.businessOwner.name} <${cfg.finops.businessOwner.email}>.`,
    '',
    cfg.finops.budgets.length
      ? md('| Scope | Amount (USD) | Thresholds |', '|---|---|---|',
          ...cfg.finops.budgets.map((b) => `| ${b.scope} | ${b.amountUsd} | ${(b.alertThresholdPercents || [50, 80, 100]).join(', ')}% |`))
      : '_No budgets defined. Nothing will alert on cost overrun._',
    '',
    unmet.length
      ? md('## Unmet dependencies', '',
          'The configuration asks for capabilities the current module corpus cannot deliver. These are',
          'reported rather than silently dropped.',
          '',
          '| Feature | Module | Status | Impact |',
          '|---|---|---|---|',
          ...unmet.map((u) => `| ${u.feature} | \`${u.module}\` | ${u.status} | ${u.impact} |`))
      : '',
    '',
    warnings.length
      ? md('## Advisories', '', ...warnings.map((w) => `- **${w.step}** — ${w.message}`))
      : '',
    ''
  );
}

function nextStepsMarkdown(cfg) {
  const dir = `generated-output/${cfg.organization.outputDirectoryName}`;
  const cfgPath = `./${dir}/lz-config.json`;
  const subCreate = (cfg.azure.subscriptions.mode || 'create') === 'create';
  let stepNo = 0;
  const step = (title) => `## ${++stepNo}. ${title}`;
  const orderLine = subCreate
    ? 'subscription vending (plan, then apply) → discovery → bootstrap (plan, then apply) → render → scaffold (plan, then apply).'
    : 'discovery → bootstrap (plan, then apply) → render → scaffold (plan, then apply).';
  return md(
    `# Next steps — ${cfg.organization.companyName}`,
    '',
    `Generated ${cfg.generatedAt} by factory v${cfg.factoryVersion}.`,
    '',
    'Every command below is run from the **root of the factory clone**, in order:',
    orderLine,
    'Every mutating script is plan-by-default — nothing touches Azure or',
    'GitHub until you pass `-Apply`.',
    '',
    step('Place the exported files'),
    '',
    'Move every file you downloaded into the factory clone at:',
    '',
    '```',
    `${dir}/`,
    '```',
    '',
    'If you used **Download all as bundle**, extract the zip inside `generated-output/` — it already',
    `contains the \`${cfg.organization.outputDirectoryName}/\` folder — then verify placement against the bundled manifest:`,
    '',
    '```powershell',
    `Get-FileHash ${dir}/* -Algorithm SHA256   # compare against ${dir}/checksums.txt`,
    '```',
    '',
    '`lz-config.json` must be there; everything else is derived from it and can be regenerated.',
    '',
    step('Authenticate'),
    '',
    'These three sessions are the only manual step in the whole flow. Everything after this is scripted.',
    '',
    '```bash',
    `az login --tenant ${cfg.azure.tenantId}`,
    'gh auth login',
    '# state auth is OIDC + Entra ID — no separate backend login step',
    '```',
    '',
    `The account you sign in with needs, at minimum: Application Administrator in Entra (to create app registrations and federated credentials), and Owner or User Access Administrator at \`${cfg.azure.managementGroups.rootId}\` (to create management groups and assign roles).`,
    '',
    subCreate
      ? md(step('Create the subscriptions — plan first, then apply'), '',
          'The configuration plans new subscriptions by name (`azure.subscriptions.plannedNames`) but',
          'carries no subscription IDs yet — rendering is blocked (guard G25) until this step fills them in.',
          '',
          '```powershell',
          `pwsh ./scripts/New-LzSubscriptions.ps1 -ConfigPath ${cfgPath}`,
          '```',
          '',
          'Without `-Apply` it only resolves your billing scope (EA enrollment account or MCA invoice',
          'section) and prints the subscriptions it would create. Then:',
          '',
          '```powershell',
          `pwsh ./scripts/New-LzSubscriptions.ps1 -ConfigPath ${cfgPath} -Apply`,
          '```',
          '',
          'It creates each subscription via `az account alias create`, waits for the IDs, writes them back',
          'into `lz-config.json`, and re-validates the file. If your agreement type cannot create',
          'subscriptions programmatically (CSP, pay-as-you-go), create them in the portal / partner center',
          'and run the script with `-Manual` to paste the IDs — it does the same patch-back and validation.', '')
      : '',
    step('Run discovery and the readiness check (read-only)'),
    '',
    '```powershell',
    `pwsh ./factory/discovery/Invoke-Discovery.ps1 -ConfigPath ${cfgPath}`,
    '```',
    '',
    'Nothing is created, modified, or deleted — this is safe against a production tenant. It writes',
    `\`tenant-readiness-report.md\` and \`discovery-inventory.json\` beside the configuration file, in \`${dir}/\`.`,
    'Resolve every **Fail** before continuing; **Warning** entries are judgement calls with remediation',
    'guidance attached. (Optional: `-SkipDomain GitHub,Entra,Azure,Terraform` to narrow the sweep,',
    '`-FailOnNotReady` for CI.)',
    '',
    step('Bootstrap — plan first, then apply'),
    '',
    'Without `-Apply`, the broker only writes a deterministic plan/audit record under',
    '`./bootstrap-output/` and touches nothing:',
    '',
    '```powershell',
    `pwsh ./bootstrap-broker.ps1 -ConfigPath ${cfgPath} -DiscoveryPath ./${dir}/discovery-inventory.json`,
    '```',
    '',
    'Review the plan record, then apply:',
    '',
    '```powershell',
    `pwsh ./bootstrap-broker.ps1 -ConfigPath ${cfgPath} -DiscoveryPath ./${dir}/discovery-inventory.json -Apply`,
    '```',
    '',
    'Idempotent — safe to re-run after fixing a failure. It creates the app registrations and federated',
    `credentials, the private repository \`${cfg.github.ownerName}/${cfg.github.repositoryName}\`, branch protection,`,
    'environments, variables, RBAC assignments, and the state storage account.',
    '',
    'For CI, the environment-variable equivalents are `LZ_CONFIG_PATH`, `LZ_DISCOVERY_PATH`,',
    '`LZ_BOOTSTRAP_OUTPUT`, and `LZ_BOOTSTRAP_APPLY=true`. `-AllowNotReady` overrides a failed',
    'readiness gate — use it knowingly.',
    '',
    step('Render the repository contents'),
    '',
    '```powershell',
    `pwsh -Command "Import-Module ./factory/renderer/LZFactory.Renderer.psd1; Invoke-LzRender -ConfigPath ${cfgPath} -OutputDirectory ./${dir}/rendered"`,
    '```',
    '',
    'Rendering validates `lz-config.json` against the schema, then writes the full repository tree to',
    'a staging directory — never into a git working tree. A failed render leaves nothing half-written',
    'where a push could pick it up.',
    '',
    step('Scaffold — plan first, then apply'),
    '',
    'Like the broker, the scaffold builder is plan-by-default: it verifies the rendered tree and emits',
    'plan/audit evidence under `./scaffold-evidence/` without creating or pushing anything:',
    '',
    '```powershell',
    `pwsh ./scaffold-copy.ps1 -ConfigPath ${cfgPath} -RenderedDirectory ./${dir}/rendered`,
    '```',
    '',
    'Review the file inventory in the evidence output, then apply:',
    '',
    '```powershell',
    `pwsh ./scaffold-copy.ps1 -ConfigPath ${cfgPath} -RenderedDirectory ./${dir}/rendered -Apply`,
    '```',
    '',
    'Useful switches: `-Force` (write into a non-empty target), `-SkipRepositoryCreate`, and `-SkipPush`.',
    'Environment-variable equivalents: `LZ_SCAFFOLD_APPLY`, `LZ_SCAFFOLD_FORCE`,',
    '`LZ_SCAFFOLD_CREATE_REPOSITORY=false`, `LZ_SCAFFOLD_PUSH=false`, `LZ_RENDERED_PATH`,',
    '`LZ_SCAFFOLD_TARGET`, `LZ_SCAFFOLD_EVIDENCE`.',
    '',
    step('Deploy'),
    '',
    'Open a pull request in the generated repository. `terraform-plan` runs against it with the read-only',
    'plan identity. Merging triggers `terraform-apply`, which runs per layer in dependency order:',
    '',
    '```',
    'global → platform-connectivity → platform-management → workloads-prod → sandbox',
    '```',
    '',
    '### The two deliberate placeholders in `connectivity.auto.tfvars`',
    '',
    '1. Before the **first** `platform-connectivity` plan: uncomment `management_ip_ranges` and set your',
    '   operator CIDR ranges. The plan fails until it is set; `*` and `0.0.0.0/0` are rejected.',
    '2. After `platform-management` applies: copy its `log_analytics_workspace_id` output into',
    '   `connectivity.auto.tfvars`, then **re-plan** `platform-connectivity` to wire firewall diagnostics',
    '   and threat-intel alerts. `CONFIGURATION.md` walks this loop-back step by step.',
    '',
    cfg.deploymentStrategy.mode === 'brownfield'
      ? md('## Brownfield note (exclude-and-create, ADR 0018)', '',
          'This landing zone is built on **new** subscriptions only. The excluded subscriptions',
          (cfg.deploymentStrategy.brownfield && cfg.deploymentStrategy.brownfield.excludedSubscriptionIds || []).length
            ? `(${cfg.deploymentStrategy.brownfield.excludedSubscriptionIds.join(', ')}) stay outside the new management-group hierarchy`
            : 'you listed stay outside the new management-group hierarchy',
          'and are never planned, imported, or modified. Integrating existing deployments into the estate',
          'is a separate engagement, out of scope for the factory. Discovery inventories the assignments',
          'of existing tenant-level Azure Policy so you can spot collisions with the new baseline before',
          'the first policy apply.')
      : '',
    '',
    '## Before you trust this in production',
    '',
    `Check the release gates in \`factory-version.json\` for factory v${cfg.factoryVersion} before a`,
    'production cutover, and treat the first deployment as a verification exercise: review every plan',
    'in full before approving its apply.',
    ''
  );
}

/* ---------------------------------------------------------------------
 * Save / load draft
 * ------------------------------------------------------------------- */

function saveDraft(silent) {
  try {
    localStorage.setItem(DRAFT_KEY, JSON.stringify({ config, defaultTagRows }));
    if (!silent) toast('Draft saved in this browser.');
  } catch (e) {
    if (!silent) toast('Could not save the draft: ' + e.message, 'bad');
  }
}

function loadDraft() {
  try {
    const raw = localStorage.getItem(DRAFT_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || !parsed.config || typeof parsed.config !== 'object') return null;
    return { warnings: adoptConfig(parsed.config, parsed.defaultTagRows) };
  } catch {
    return null;
  }
}

/** Merge a loaded config over the defaults so a config from an older factory
 *  version does not lose keys added since. */
function mergeDefaults(target, source) {
  const blockedKeys = new Set(['__proto__', 'prototype', 'constructor']);

  for (const [k, v] of Object.entries(source || {})) {
    // Never copy prototype-related keys from untrusted persisted/imported data.
    if (blockedKeys.has(k)) continue;

    if (v && typeof v === 'object' && !Array.isArray(v) && Object.prototype.hasOwnProperty.call(target, k) && target[k] && typeof target[k] === 'object' && !Array.isArray(target[k])) {
      mergeDefaults(target[k], v);
    } else if (v !== undefined) {
      target[k] = v;
    }
  }
  return target;
}

/** Coarse JS "kind" used for import type reconciliation. */
function kindOf(v) {
  if (v === null || v === undefined) return 'null';
  if (Array.isArray(v)) return 'array';
  return typeof v;
}

/**
 * Walk the defaults shape and restore any adopted value whose kind differs
 * from the default's (string vs number vs array vs object vs boolean),
 * collecting one warning per restoration. This is what guarantees validate()
 * can never throw on .trim()/.length of a wrong-typed imported value.
 * Defaults whose value is null carry no type information and are skipped.
 */
function reconcileTypes(defaults, merged, prefix, warnings) {
  for (const k of Object.keys(defaults)) {
    if (!Object.prototype.hasOwnProperty.call(merged, k)) continue;
    const dKind = kindOf(defaults[k]);
    if (dKind === 'null') continue;
    const mKind = kindOf(merged[k]);
    const path = prefix ? `${prefix}.${k}` : k;
    if (dKind !== mKind) {
      warnings.push(`${path}: expected ${dKind}, got ${mKind} — kept the default.`);
      merged[k] = JSON.parse(JSON.stringify(defaults[k]));
    } else if (dKind === 'object') {
      reconcileTypes(defaults[k], merged[k], path, warnings);
    }
  }
}

/** Drop unsafe environment names from adopted data. Runs at every config
 *  adoption point (file import and localStorage draft restore), because these
 *  names are later used as object keys. */
function sanitizeEnvironments(cfg, warnings) {
  for (const key of ['platform', 'application']) {
    const list = cfg.environments[key];
    if (!Array.isArray(list)) continue;
    const kept = list.filter(isSafeEnvName);
    if (kept.length !== list.length) {
      warnings.push(`environments.${key}: removed ${list.length - kept.length} invalid environment name(s).`);
    }
    cfg.environments[key] = kept;
  }
}

/** Adopt an external config (imported file or restored draft). Returns an
 *  array of human-readable warnings for values that had to be corrected. */
function adoptConfig(loaded, tagRows) {
  const warnings = [];
  config = mergeDefaults(defaultConfig(), loaded);
  // Compare against a fresh copy: mergeDefaults mutated the first one.
  reconcileTypes(defaultConfig(), config, '', warnings);
  sanitizeEnvironments(config, warnings);
  config.schemaVersion = SCHEMA_VERSION;
  config.factoryVersion = FACTORY_VERSION;

  if (Array.isArray(tagRows) && tagRows.length) {
    defaultTagRows = tagRows;
  } else if (loaded.naming && loaded.naming.defaultTags && kindOf(loaded.naming.defaultTags) === 'object') {
    defaultTagRows = Object.entries(loaded.naming.defaultTags).map(([k, v]) => ({ k, v: String(v == null ? '' : v) }));
  }

  // The dispositions map is the contract; the repeater needs rows. Rebuild them
  // on adoption or a re-imported configuration shows an empty table beside a
  // populated answer record.
  const bf = config.deploymentStrategy.brownfield;
  if (bf) {
    const adopted = (loaded.deploymentStrategy && loaded.deploymentStrategy.brownfield || {}).dispositions;
    bf.dispositionRows = Object.entries(adopted || {}).map(([id, entry]) => ({
      id, action: entry.action || 'defer', acknowledgement: entry.acknowledgement || '', note: entry.note || ''
    }));
  }

  rebind();
  return warnings;
}

function rebind() {
  for (const el of $$('[data-path]')) writeControl(el, getPath(config, el.dataset.path));
  for (const el of $$('[data-set]')) {
    const cur = getPath(config, el.dataset.set) || [];
    el.checked = cur.includes(el.value);
  }
  buildCheckGroup('defenderPlans', DEFENDER_PLANS, 'security.defender.plans');
  buildCheckGroup('sentinelConnectors', SENTINEL_CONNECTORS, 'security.sentinel.dataConnectors');
  buildCheckGroup('complianceFrameworks', COMPLIANCE_FRAMEWORKS, 'governance.complianceFrameworks');
  renderPolicyStep();
  renderManagementGroupNames();
  renderAllRepeaters();
  renderDispositionAcknowledgements();
  onChange(null);
}

function handleFileLoad(file) {
  const reader = new FileReader();
  reader.onerror = () => toast('Could not read that file.', 'bad');
  reader.onload = () => {
    let parsed;
    try {
      parsed = JSON.parse(String(reader.result));
    } catch (e) {
      toast('That file is not valid JSON.', 'bad');
      return;
    }
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed) || !parsed.organization || !parsed.azure) {
      toast('That does not look like an lz-config.json.', 'bad');
      return;
    }
    const warnings = adoptConfig(parsed, null);
    if (warnings.length) {
      // Non-blocking: the load succeeds, corrected values fall back to defaults.
      for (const w of warnings) console.warn('Import: ' + w);
      toast(`Configuration loaded — ${warnings.length} value${warnings.length > 1 ? 's' : ''} had an unexpected type and kept the default (details in the browser console).`, 'warn');
    } else if (parsed.schemaVersion && parsed.schemaVersion !== SCHEMA_VERSION) {
      toast(`Loaded a schema ${parsed.schemaVersion} config into a ${SCHEMA_VERSION} wizard — review every step.`, 'warn');
    } else {
      toast('Configuration loaded.');
    }
    goto(0);
  };
  reader.readAsText(file);
}

/* ---------------------------------------------------------------------
 * Init
 * ------------------------------------------------------------------- */

function init() {
  $('#factoryVersionBadge').textContent = 'v' + FACTORY_VERSION;

  buildRegionDatalist();
  buildStepNav();
  bindPathControls();
  bindSetControls();
  buildCheckGroup('defenderPlans', DEFENDER_PLANS, 'security.defender.plans');
  buildCheckGroup('sentinelConnectors', SENTINEL_CONNECTORS, 'security.sentinel.dataConnectors');
  buildCheckGroup('complianceFrameworks', COMPLIANCE_FRAMEWORKS, 'governance.complianceFrameworks');
  renderPolicyStep();
  renderManagementGroupNames();
  renderAllRepeaters();

  // The prefix control is a convenience over the rename table, not a stored
  // answer: it writes ids and is then forgotten.
  $('#az_mg_applyPrefix')?.addEventListener('click', () => {
    applyManagementGroupPrefix($('#az_mg_prefix').value);
    onChange($('#az_mg_applyPrefix'));
  });
  $('#az_mg_resetNames')?.addEventListener('click', () => {
    resetManagementGroupNames();
    onChange($('#az_mg_resetNames'));
  });

  // Track whether the user has hand-edited the repo name, so the derived
  // default stops overwriting it.
  $('#gh_repositoryName').addEventListener('input', function () { this.dataset.touched = '1'; });

  // Optional-slot opt-ins for subscription vending (mode=create). Not
  // data-path bound: they only shape azure.subscriptions.plannedNames.
  for (const id of ['az_planIdentity', 'az_planNonProd', 'az_planSandbox']) {
    const cb = $('#' + id);
    if (cb) cb.addEventListener('change', () => onChange(cb));
  }

  $('#btnPrev').addEventListener('click', () => goto(currentStep - 1));
  $('#btnNext').addEventListener('click', () => goto(currentStep + 1));
  $('#btnSave').addEventListener('click', () => saveDraft(false));
  $('#btnClearDraft').addEventListener('click', () => {
    try {
      localStorage.removeItem(DRAFT_KEY);
      toast('Saved draft cleared from this browser. Editing further will autosave a new draft.');
    } catch (e) {
      toast('Could not clear the draft: ' + e.message, 'bad');
    }
  });
  $('#btnLoad').addEventListener('click', () => $('#fileLoad').click());
  $('#fileLoad').addEventListener('change', (e) => {
    if (e.target.files && e.target.files[0]) handleFileLoad(e.target.files[0]);
    e.target.value = '';
  });
  $('#btnExport').addEventListener('click', () => {
    const { errors } = validate();
    if (errors.length) {
      goto(steps.findIndex((s) => s.key === 'review'));
      toast(`${errors.length} blocking issue${errors.length > 1 ? 's' : ''} must be resolved first.`, 'bad');
      return;
    }
    goto(steps.findIndex((s) => s.key === 'review'));
    toast('Download each artifact below.');
  });
  $('#btnBundle').addEventListener('click', () => {
    const { errors } = validate();
    if (errors.length) {
      toast(`${errors.length} blocking issue${errors.length > 1 ? 's' : ''} must be resolved first.`, 'bad');
      return;
    }
    downloadBundle().then(
      (withChecksums) => toast(withChecksums
        ? 'Bundle downloaded — extract into generated-output/ and verify with checksums.txt.'
        : 'Bundle downloaded without checksums.txt — Web Crypto is unavailable in this browser.',
        withChecksums ? 'ok' : 'warn'),
      (e) => toast('Bundle failed: ' + e.message, 'bad')
    );
  });
  $('#btnCopyJson').addEventListener('click', () => {
    const text = JSON.stringify(buildConfig(), null, 2);
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(
        () => toast('Configuration copied.'),
        () => selectPreview()
      );
    } else {
      selectPreview();
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.altKey && e.key === 'ArrowRight') { goto(currentStep + 1); e.preventDefault(); }
    if (e.altKey && e.key === 'ArrowLeft') { goto(currentStep - 1); e.preventDefault(); }
  });

  // Autosave so a closed tab does not lose an hour of input.
  setInterval(() => saveDraft(true), 15000);
  window.addEventListener('beforeunload', () => saveDraft(true));

  const restored = loadDraft();
  onChange(null);
  goto(0);
  if (restored) {
    if (restored.warnings.length) {
      for (const w of restored.warnings) console.warn('Draft restore: ' + w);
      toast(`Restored your saved draft — ${restored.warnings.length} value${restored.warnings.length > 1 ? 's' : ''} had an unexpected type and kept the default (details in the browser console).`, 'warn');
    } else {
      toast('Restored your saved draft.');
    }
  }
}

function selectPreview() {
  const pre = $('#jsonPreview');
  const range = document.createRange();
  range.selectNodeContents(pre);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  toast('Selected — press Ctrl+C to copy.', 'warn');
}

document.addEventListener('DOMContentLoaded', init);
