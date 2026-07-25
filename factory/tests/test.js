const A = require('./harness.js');

let pass = 0, fail = 0;
function ok(name, cond, extra) {
  if (cond) { pass++; console.log('  PASS ' + name); }
  else { fail++; console.log('  FAIL ' + name + (extra ? '  -> ' + extra : '')); }
}

console.log('\n== 1. Empty config must produce blocking errors ==');
let v = A.validate();
ok('empty config has errors', v.errors.length > 0, v.errors.length);
ok('errors carry a step key', v.errors.every(e => e.step && e.message));

console.log('\n== 2. CIDR overlap detection ==');
ok('10.0.0.0/16 vs 10.0.1.0/24 overlap', A.cidrsOverlap('10.0.0.0/16','10.0.1.0/24'));
ok('10.0.0.0/16 vs 10.1.0.0/16 do not', !A.cidrsOverlap('10.0.0.0/16','10.1.0.0/16'));
ok('identical overlap', A.cidrsOverlap('172.16.0.0/12','172.16.0.0/12'));
ok('adjacent do not overlap', !A.cidrsOverlap('10.0.0.0/24','10.0.1.0/24'));

console.log('\n== 3. Fully valid config ==');
const c = A.defaultConfig();
c.organization = { companyName: 'Contoso Health', companyShortName: 'contoso', businessUnit: 'Platform', outputDirectoryName: '' };
c.azure.tenantId = '11111111-2222-3333-4444-555555555555';
c.azure.primaryRegion = 'southcentralus'; c.azure.primaryRegionCode = 'scus';
c.azure.drRegion = 'northcentralus'; c.azure.drRegionCode = 'ncus';
c.azure.allowedLocations = ['southcentralus','northcentralus'];
c.azure.subscriptions.management   = 'aaaaaaaa-0000-0000-0000-000000000001';
c.azure.subscriptions.connectivity = 'aaaaaaaa-0000-0000-0000-000000000002';
c.azure.subscriptions.workloadProd = 'aaaaaaaa-0000-0000-0000-000000000003';
c.azure.managementGroups.rootId = 'mg-contoso';
c.github.ownerName = 'contoso-platform';
c.github.repositoryName = 'contoso_LZ_Deployment';
c.backend.hcpTerraform.organization = 'contoso';
c.identity.breakGlassAccounts = [
  { name: 'bg1@contoso.onmicrosoft.com', email: 'secops@contoso.com', role: 'GA' },
  { name: 'bg2@contoso.onmicrosoft.com', email: 'secops@contoso.com', role: 'GA' }
];
c.operations.platformTeam.name = 'Cloud Platform';
c.operations.platformTeam.contacts = [{ name: 'Alex', email: 'alex@contoso.com', role: 'Lead' }];
c.operations.breakGlassContacts = [{ name: 'Dana', email: 'dana@contoso.com' }];
c.finops.costCenter = 'CC-1';
c.finops.businessOwner = { name: 'Jordan', email: 'jordan@contoso.com', role: 'Owner' };
c.environments.approvals = { prod: { requiredReviewers: ['@platform'], waitTimerMinutes: 0, preventSelfReview: true } };
A.config = c;
A.defaultTagRows = [
  { k: 'owner', v: 'platform' }, { k: 'application', v: 'alz' },
  { k: 'environment', v: 'prod' }, { k: 'cost_center', v: 'CC-1' }
];

v = A.validate();
ok('valid config has zero blocking errors', v.errors.length === 0, JSON.stringify(v.errors, null, 1));

console.log('\n== 4. RUM estimate + free-tier gate ==');
const rum = A.estimateRum();
console.log('  estimate =', rum, 'resources');
ok('estimate is a positive number', rum > 0);
ok('a minimal 2-region ALZ stays under the 500 cap', rum <= 500, rum);
ok('minimal config needs no acknowledgement', !A.validate().errors.some(e => /free tier/.test(e.message)));

// Property test: the gate must fire exactly when the estimate exceeds the cap,
// whatever the estimate happens to be. Scale scope up until it does.
c.governance.complianceFrameworks = ['cis-azure','nist-800-53','iso-27001','pci-dss','hipaa-hitrust','soc2','fedramp-moderate'];
c.security.defender.enabled = true;
c.security.defender.plans = ['CloudPosture','VirtualMachines','StorageAccounts','SqlServers','AppServices','KeyVaults','Containers','Arm','CosmosDbs','Api','OpenSourceRelationalDatabases'];
c.security.defender.securityContactEmail = 'secops@contoso.com';
c.environments.application = ['sandbox','dev','test','uat','prod'];
c.environments.platform = ['bootstrap','identity','connectivity','management','shared-services'];
c.connectivity.vpn.enabled = true;
c.connectivity.expressRoute.enabled = true;
c.connectivity.expressRoute.peeringLocation = 'Dallas';
c.connectivity.privateDns.zones = Array.from({length:30},(_,i)=>'privatelink.svc'+i+'.azure.net');
const rumBig = A.estimateRum();
console.log('  large-scope estimate =', rumBig, 'resources');
ok('large scope exceeds the 500 free cap', rumBig > 500, rumBig);

c.backend.hcpTerraform.acknowledgedResourceLimit = false;
let gateFires = A.validate().errors.some(e => /free tier/.test(e.message));
ok('gate fires exactly when estimate > cap', gateFires === (rumBig > 500), 'estimate=' + rumBig + ' gate=' + gateFires);
c.backend.hcpTerraform.acknowledgedResourceLimit = true;
ok('acknowledging clears the block', !A.validate().errors.some(e => /free tier/.test(e.message)));

// Converse: a small scope must not fire the gate.
c.governance.complianceFrameworks = [];
c.security.defender.enabled = false; c.security.defender.plans = [];
c.environments.application = ['dev','prod'];
c.environments.platform = ['bootstrap','connectivity','management'];
c.connectivity.vpn.enabled = false;
c.connectivity.expressRoute.enabled = false;
c.connectivity.privateDns.zones = [];
c.backend.hcpTerraform.acknowledgedResourceLimit = false;
const rumSmall = A.estimateRum();
gateFires = A.validate().errors.some(e => /free tier/.test(e.message));
ok('small scope is under the cap', rumSmall <= 500, rumSmall);
ok('gate silent when under the cap', gateFires === false);
c.backend.hcpTerraform.acknowledgedResourceLimit = true;

console.log('\n== 5. Scaffold-module guards ==');
c.security.sentinel.enabled = true;
ok('sentinel blocked (scaffold module)', A.validate().errors.some(e => /sentinel-siem/.test(e.message)));
c.security.sentinel.enabled = false;
c.security.keyVault.customerManagedKeys = true;
ok('CMK blocked (scaffold module)', A.validate().errors.some(e => /keyvault-cmk/.test(e.message)));
c.security.keyVault.customerManagedKeys = false;
c.connectivity.model = 'virtual-wan';
ok('virtual-wan blocked (no module)', A.validate().errors.some(e => /Virtual WAN/.test(e.message)));
c.connectivity.model = 'hub-spoke';

console.log('\n== 6. Tag-coverage guard (policy would deny its own apply) ==');
A.defaultTagRows = [{ k: 'owner', v: 'platform' }];
ok('missing required tag defaults block export', A.validate().errors.some(e => /denies its own first apply|would deny its own first apply/.test(e.message)));
A.defaultTagRows = [
  { k: 'owner', v: 'platform' }, { k: 'application', v: 'alz' },
  { k: 'environment', v: 'prod' }, { k: 'cost_center', v: 'CC-1' }
];
ok('restored tags clear it', !A.validate().errors.some(e => /denies its own/.test(e.message) || /has no default value/.test(e.message)));

console.log('\n== 7. Overlapping address spaces ==');
c.connectivity.hubSpoke.primarySpokeAddressSpace = '10.0.0.0/16';
ok('overlap detected', A.validate().errors.some(e => /overlap/.test(e.message)));
c.connectivity.hubSpoke.primarySpokeAddressSpace = '10.1.0.0/16';

console.log('\n== 8. Artifact generation ==');
const cfg = A.buildConfig();
ok('buildConfig stamps generatedAt', !!cfg.generatedAt);
ok('buildConfig folds default tags', cfg.naming.defaultTags.owner === 'platform');
ok('hcp backend drops the azurerm block', cfg.backend.azurerm === undefined);
ok('workspacePrefix defaults to short name', cfg.backend.hcpTerraform.workspacePrefix === 'contoso');
ok('empty optional subs are stripped', cfg.azure.subscriptions.sandbox === undefined);

const tfg = A.tfvarsGlobal(cfg);
ok('global tfvars sets org_prefix', /org_prefix\s+= "contoso"/.test(tfg), tfg.split('\n').find(l=>/org_prefix/.test(l)));
ok('global tfvars sets allowed_locations', /allowed_locations\s+= \["southcentralus", "northcentralus"\]/.test(tfg));

const tfc = A.tfvarsConnectivity(cfg);
ok('connectivity tfvars sets firewall_type', /firewall_type\s+= "azfw"/.test(tfc));
ok('connectivity tfvars emits default_tags map', /default_tags = \{/.test(tfc) && /owner = "platform"/.test(tfc));
ok('connectivity tfvars includes DR when set', /dr_region\s+= "northcentralus"/.test(tfc));

const bh = A.backendHcl(cfg);
ok('backend.hcl uses TFC org', /organization = "contoso"/.test(bh));
ok('backend.hcl parameterises the layer', /<layer>/.test(bh));

const envs = A.environmentDefinitions(cfg);
ok('env defs have platform + application', envs.platform.length > 0 && envs.application.length > 0);
const prod = envs.application.find(e => e.name === 'prod');
ok('apply subject pinned to environment', prod.identities.apply.subject === 'repo:contoso-platform/contoso_LZ_Deployment:environment:prod', prod.identities.apply.subject);
ok('plan subject pinned to pull_request', prod.identities.plan.subject === 'repo:contoso-platform/contoso_LZ_Deployment:pull_request');
ok('plan identity is read-only', JSON.stringify(prod.identities.plan.azureRoles) === '["Reader"]');
const allSubjects = [...envs.platform, ...envs.application].flatMap(e => [e.oidcSubject, e.identities.plan.subject, e.identities.apply.subject]);
ok('no wildcard in any OIDC subject', allSubjects.every(s => !s.includes('*')), allSubjects.filter(s=>s.includes('*')).join());
ok('every subject is repo-scoped', allSubjects.every(s => s.startsWith('repo:contoso-platform/contoso_LZ_Deployment:')));

const meta = A.deploymentMetadata(cfg);
ok('metadata records the RUM estimate', typeof meta.estimatedManagedResources === 'number');
ok('metadata lists unmet dependencies array', Array.isArray(meta.unmetDependencies));

const cmd = A.configurationMarkdown(cfg);
ok('config markdown non-trivial', cmd.length > 1500, cmd.length);
ok('config markdown has no unresolved tokens', !/\{\{|\bundefined\b/.test(cmd), (cmd.match(/undefined/g)||[]).length + ' undefined');

const ns = A.nextStepsMarkdown(cfg);
ok('next steps names the tenant', ns.includes('11111111-2222-3333-4444-555555555555'));
ok('next steps has no undefined', !/undefined/.test(ns));

console.log('\n== 9. Personal-account degradation is a warning, not silence ==');
c.github.ownershipModel = 'personal';
v = A.validate();
ok('personal account warns', v.warnings.some(w => /Personal accounts/.test(w.message)));
ok('personal account does not hard-block', !v.errors.some(e => /Personal/.test(e.message)));
c.github.ownershipModel = 'organization';

console.log('\n== 10. Internal visibility requires enterprise ==');
c.github.visibility = 'internal';
ok('internal on non-enterprise blocks', A.validate().errors.some(e => /Enterprise Cloud/.test(e.message)));
c.github.visibility = 'private';

console.log(`\n${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
