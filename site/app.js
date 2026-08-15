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

const SCHEMA_VERSION = '2.1.0';

/* Kept in sync with factory-version.json. This page cannot read that file
 * (a file:// fetch is both blocked by CSP and unreliable across browsers),
 * so the value is mirrored here and a factory CI check asserts the two match. */
const FACTORY_VERSION = '0.10.0';

const DRAFT_KEY = 'alz-factory-draft-v1';

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
      subscriptions: { management: '', identity: '', connectivity: '', workloadProd: '', workloadNonProd: '', sandbox: '' },
      managementGroups: { rootId: '', strategy: 'caf-standard', customHierarchy: [] }
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
      azurerm: {
        resourceGroupName: '', storageAccountName: '', containerName: 'tfstate',
        subscriptionId: '', useAzureAdAuth: true
      }
    },
    deploymentStrategy: {
      mode: 'greenfield',
      brownfield: {
        defaultClassification: 'ignore', generateImportBlocks: true,
        generateImportCommands: true, allowDestructivePlans: false
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
        type: 'azfw', azfwTier: 'Standard', threatIntelligenceMode: 'Deny',
      },
      expressRoute: { enabled: false, circuitName: '', peeringLocation: '', bandwidthMbps: null, serviceProvider: '' },
      vpn: { enabled: false, sku: 'VpnGw1AZ', activeActive: true },
      bastion: { enabled: true, sku: 'Standard' },
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
  for (const [key, required] of [['management', true], ['connectivity', true], ['workloadProd', true]]) {
    if (required && !RE.guid.test(a.subscriptions[key] || '')) {
      err('azure', `The ${key} subscription ID must be a GUID.`);
    }
  }
  for (const key of ['identity', 'workloadNonProd', 'sandbox']) {
    const v = a.subscriptions[key];
    if (v && !RE.guid.test(v)) err('azure', `The ${key} subscription ID is not a valid GUID.`);
  }
  const subVals = Object.values(a.subscriptions).filter(Boolean);
  const dupes = subVals.filter((v, i) => subVals.indexOf(v) !== i);
  if (dupes.length) {
    warn('azure', 'The same subscription ID is used for more than one role. This is valid but collapses the isolation boundary between those planes.');
  }
  if (!a.managementGroups.rootId.trim()) err('azure', 'Root management group ID is required.');
  if (a.managementGroups.strategy === 'custom') {
    const h = a.managementGroups.customHierarchy || [];
    if (!h.length) err('azure', 'Custom hierarchy selected but no management groups defined.');
    const ids = new Set(h.map((x) => x.id));
    for (const mg of h) {
      if (!mg.id || !mg.displayName || !mg.parentId) { err('azure', 'Every custom management group needs an ID, display name and parent.'); break; }
      if (mg.parentId !== a.managementGroups.rootId && !ids.has(mg.parentId)) {
        err('azure', `Management group "${mg.id}" has parent "${mg.parentId}", which is neither the root nor another entry.`);
      }
      if (mg.id === mg.parentId) err('azure', `Management group "${mg.id}" is its own parent.`);
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
  if (b.type !== 'azurerm') {
    err('backend', 'azurerm is the only supported state backend (ADR 0015).');
  } else {
    if (!b.azurerm.resourceGroupName.trim()) err('backend', 'State resource group name is required.');
    if (!RE.storageAccount.test(b.azurerm.storageAccountName || '')) {
      err('backend', 'State storage account must be 3–24 lowercase alphanumeric characters.');
    }
    if (!b.azurerm.useAzureAdAuth) {
      warn('backend', 'Storage-key authentication to state means a long-lived shared secret. Entra ID auth is strongly preferred.');
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
  if (config.azure.subscriptions.sandbox === '' && e.application.includes('sandbox')) {
    warn('environments', 'A sandbox environment is selected but no sandbox subscription was supplied. The sandbox layer will not be emitted.');
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
  if (c.firewall.type === 'azfw' && !['Standard', 'Premium'].includes(c.firewall.azfwTier)) {
    // Guards imported/drafted configs from before Basic was removed: the
    // hub-network module does not provision the dedicated management subnet
    // and management public IP the Basic tier mandates, so the schema (and
    // both connectivity layers) accept Standard and Premium only.
    err('connectivity', `Azure Firewall tier "${c.firewall.azfwTier}" cannot be deployed — the hub-network module supports Standard and Premium only. Re-select the tier.`);
  }
  if (c.firewall.type === 'azfw' && c.firewall.threatIntelligenceMode === 'Off') {
    warn('connectivity', 'Azure Firewall threat intelligence is Off. The secure default is Deny; this needs a recorded governance exception.');
  }
  if (!['azfw'].includes(c.firewall.type)) {
    // A landing zone always deploys at least one firewall (operator decision
    // 2026-08-06). This also guards configs drafted while "none" was briefly
    // offered here: it exported firewall_type = "none", which the connectivity
    // layer rejects. To run without platform networking at all, set Topology
    // to None — that drops the layer rather than leaving egress unfiltered.
    err('connectivity', `Firewall type "${c.firewall.type}" cannot be deployed — the AVM connectivity patterns require at least one Azure Firewall (ADR 0017). To deploy without platform networking entirely, set Topology to None.`);
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
    warn('governance', 'Deny enforcement on a brownfield tenant will block deployments against existing non-compliant resources. Start at Audit, clear the compliance report, then promote to Deny.');
  }
  if (gv.policyAsCodeEngines.includes('sentinel')) {
    err('governance', 'Sentinel policy enforcement was a Terraform Cloud feature; the azurerm-only pipeline (ADR 0015) does not support it. Use Azure Policy or OPA.');
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

  n += c.azure.managementGroups.strategy === 'caf-minimal'
    ? w.managementGroupsCafMinimal
    : c.azure.managementGroups.strategy === 'custom'
      ? (c.azure.managementGroups.customHierarchy || []).length
      : w.managementGroupsCafStandard;

  n += w.policyBaselineCore;
  n += (c.governance.complianceFrameworks || []).length * w.policyPerFramework;

  if (c.connectivity.model === 'hub-spoke') {
    n += w.hubPerRegion * regions;
    n += w.spokePerRegion * regions;
    if (c.connectivity.firewall.type === 'azfw') n += w.firewallAzfw * regions;
    else if (['palo', 'fortinet'].includes(c.connectivity.firewall.type)) n += w.firewallNva * regions;
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
  if (type === 'int') return el.value === '' ? null : parseInt(el.value, 10);
  if (type === 'float') return el.value === '' ? null : parseFloat(el.value);
  if (type === 'csv') return csv(el.value);
  if (type === 'lines') return lines(el.value);
  return el.value;
}

function writeControl(el, value) {
  const type = el.dataset.type || (el.type === 'checkbox' ? 'bool' : 'string');
  if (type === 'bool') { el.checked = !!value; return; }
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

      const input = document.createElement('input');
      input.type = f.type === 'float' ? 'number' : 'text';
      if (f.type === 'float') input.step = 'any';
      input.id = lbl.htmlFor;
      input.placeholder = f.placeholder || '';
      input.spellcheck = false;

      const v = row[f.key];
      input.value = Array.isArray(v) ? v.join(', ') : (v === undefined || v === null ? '' : v);

      input.addEventListener('input', () => {
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
    updateStepStatus();
    if (steps[currentStep] && steps[currentStep].key === 'review') renderReview();
  });
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
  if (out.azure.managementGroups.strategy !== 'custom') delete out.azure.managementGroups.customHierarchy;
  if (out.deploymentStrategy.mode !== 'brownfield') delete out.deploymentStrategy.brownfield;
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
function unmetDependencies(cfg) {
  const out = [];
  if (cfg.security.sentinel && cfg.security.sentinel.enabled) {
    out.push({ feature: 'Microsoft Sentinel', module: '(per-estate)', status: 'recorded-not-deployed', impact: 'Preserved in lz-config.json; onboard inside the generated repository against the management workspace (ADR 0017).' });
  }
  if (cfg.security.keyVault.customerManagedKeys) {
    out.push({ feature: 'Customer-managed keys', module: '(per-estate)', status: 'recorded-not-deployed', impact: 'Preserved in lz-config.json; implement inside the generated repository (ADR 0017).' });
  }
  if (cfg.security.defender.enabled) {
    out.push({ feature: 'Defender for Cloud plans', module: '(per-estate)', status: 'recorded-not-deployed', impact: 'ALZ policy archetypes govern Defender configuration; plan-level enablement is per-estate work recorded in lz-config.json (ADR 0017).' });
  }
  if (cfg.github.useSelfHostedRunners) {
    out.push({ feature: 'Self-hosted runners', module: '(workflows)', status: 'unsupported', impact: 'v1 emits GitHub-hosted workflows only.' });
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
    '| Role | Subscription ID |',
    '|---|---|',
    ...Object.entries(cfg.azure.subscriptions).map(([k, v]) => `| ${k} | \`${v}\` |`),
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
    `Topology: **${cfg.connectivity.model}**. Firewall: **${cfg.connectivity.firewall.type}**${cfg.connectivity.firewall.type === 'azfw' ? ` (${cfg.connectivity.firewall.azfwTier}, threat intel ${cfg.connectivity.firewall.threatIntelligenceMode})` : ''}.`,
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
  return md(
    `# Next steps — ${cfg.organization.companyName}`,
    '',
    `Generated ${cfg.generatedAt} by factory v${cfg.factoryVersion}.`,
    '',
    'Every command below is run from the **root of the factory clone**, in order:',
    'discovery → bootstrap (plan, then apply) → render → scaffold (plan, then apply).',
    'The broker and the scaffold builder are plan-by-default — nothing mutates Azure or',
    'GitHub until you pass `-Apply`.',
    '',
    '## 1. Place the exported files',
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
    '## 2. Authenticate',
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
    '## 3. Run discovery and the readiness check (read-only)',
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
    '## 4. Bootstrap — plan first, then apply',
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
    '## 5. Render the repository contents',
    '',
    '```powershell',
    `pwsh -Command "Import-Module ./factory/renderer/LZFactory.Renderer.psd1; Invoke-LzRender -ConfigPath ${cfgPath} -OutputDirectory ./${dir}/rendered"`,
    '```',
    '',
    'Rendering validates `lz-config.json` against the schema, then writes the full repository tree to',
    'a staging directory — never into a git working tree. A failed render leaves nothing half-written',
    'where a push could pick it up.',
    '',
    '## 6. Scaffold — plan first, then apply',
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
    '## 7. Deploy',
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
      ? md('## Brownfield note', '',
          'Run the `brownfield-discovery` workflow before the first plan. It is read-only and produces',
          '`brownfield-assessment.md` plus import blocks for review. The destroy-protection gate fails any',
          'plan containing a destroy or replace action unless the pull request carries the `approved-destroy` label.')
      : '',
    '',
    '## Before you trust this in production',
    '',
    'As of factory v0.9.0 the release gates in `factory-version.json` are not all met — in particular the',
    'pipeline has no recorded successful end-to-end run. Treat the first deployment as a verification',
    'exercise, not a production cutover.',
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
  renderAllRepeaters();
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
  renderAllRepeaters();

  // Track whether the user has hand-edited the repo name, so the derived
  // default stops overwriting it.
  $('#gh_repositoryName').addEventListener('input', function () { this.dataset.touched = '1'; });

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
