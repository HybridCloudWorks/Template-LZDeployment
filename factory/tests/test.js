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

console.log('\n== 11. CI/CD identity model (identity.cicdIdentityModel) ==');
ok('default config is the minimal model', A.defaultConfig().identity.cicdIdentityModel === 'minimal');
// An untouched wizard exports the default: c was built from defaultConfig()
// before this suite mutated other sections, so the key is still the default.
let exported = A.buildConfig();
ok('untouched config exports cicdIdentityModel minimal', exported.identity.cicdIdentityModel === 'minimal');
c.identity.cicdIdentityModel = 'minimal';
exported = A.buildConfig();
ok('minimal is exported in lz-config.json', exported.identity.cicdIdentityModel === 'minimal');
c.identity.cicdIdentityModel = 'per-environment';
exported = A.buildConfig();
ok('per-environment is exported in lz-config.json', exported.identity.cicdIdentityModel === 'per-environment');

// Count math. Current selections: platform [bootstrap,connectivity,management],
// application [dev,prod] -> 5 unique environments.
c.identity.cicdIdentityModel = 'minimal';
ok('minimal counts 2 identities', A.cicdIdentityCount() === 2, A.cicdIdentityCount());
c.identity.cicdIdentityModel = 'per-environment';
ok('per-environment counts 2 x unique environments (10)', A.cicdIdentityCount() === 10, A.cicdIdentityCount());
c.environments.application = ['sandbox', 'dev', 'test', 'uat', 'prod'];
ok('count recomputes when environment selections change (16)', A.cicdIdentityCount() === 16, A.cicdIdentityCount());
c.environments.application = ['dev', 'prod', 'management']; // overlap with platform plane
ok('count uses the UNION of planes (duplicates not double-counted)', A.cicdIdentityCount() === 10, A.cicdIdentityCount());
c.environments.application = ['dev', 'prod'];
c.identity.cicdIdentityModel = 'minimal';
ok('minimal count is environment-independent', A.cicdIdentityCount() === 2);

// environments.json must describe the estate the broker will actually build.
c.identity.cicdIdentityModel = 'minimal';
let envDefs = A.environmentDefinitions(A.buildConfig());
ok('environments.json records the minimal model', envDefs.cicdIdentityModel === 'minimal');
ok('minimal model shares one plan/apply app name', envDefs.application.every(e =>
  e.identities.plan.appName === 'sp-contoso-plan' && e.identities.apply.appName === 'sp-contoso-apply'));
ok('minimal apply subjects stay environment-pinned', envDefs.application.every(e =>
  e.identities.apply.subject === `repo:contoso-platform/contoso_LZ_Deployment:environment:${e.name}`));
c.identity.cicdIdentityModel = 'per-environment';
envDefs = A.environmentDefinitions(A.buildConfig());
ok('per-environment model keeps per-env app names', envDefs.application.every(e =>
  e.identities.plan.appName === `sp-contoso-${e.name}-plan`));
c.identity.cicdIdentityModel = 'minimal';

console.log('\n== 12. Schema declares the broker-only key ==');
const schema = JSON.parse(require('fs').readFileSync(require('path').resolve(__dirname, '..', 'schema', 'lz-config.schema.json'), 'utf8'));
const modelDecl = schema.properties.identity.properties.cicdIdentityModel;
ok('schema declares identity.cicdIdentityModel', !!modelDecl);
ok('schema enum is exactly [minimal, per-environment]', JSON.stringify(modelDecl && modelDecl.enum) === '["minimal","per-environment"]', JSON.stringify(modelDecl && modelDecl.enum));
ok('schema default is minimal', modelDecl && modelDecl.default === 'minimal');
ok('key stays optional (identity has no new required entries)', !Array.isArray(schema.properties.identity.required) || !schema.properties.identity.required.includes('cicdIdentityModel'));
// Wizard <select> options ⊂ schema enum (contract #7, wizard side).
const html = require('fs').readFileSync(require('path').resolve(__dirname, '..', '..', 'site', 'index.html'), 'utf8');
const selectBlock = (html.match(/<select id="id_cicdModel"[\s\S]*?<\/select>/) || [''])[0];
const optionValues = Array.from(selectBlock.matchAll(/option value="([^"]+)"/g)).map(m => m[1]);
ok('wizard offers exactly the schema enum values', JSON.stringify(optionValues.sort()) === JSON.stringify([...modelDecl.enum].sort()), JSON.stringify(optionValues));
ok('wizard binds the select to identity.cicdIdentityModel', /data-path="identity\.cicdIdentityModel"/.test(selectBlock));

console.log('\n== 13. Azure Firewall tier bounds (Basic cannot deploy) ==');
// Basic mandates a dedicated AzureFirewallManagementSubnet + management public
// IP the hub-network module does not provision, so the whole contract chain
// (wizard, schema, both connectivity layers) is bounded to Standard|Premium.
const tierDecl = schema.properties.connectivity.properties.firewall.properties.azfwTier;
ok('schema azfwTier enum is exactly [Standard, Premium]', JSON.stringify(tierDecl.enum) === '["Standard","Premium"]', JSON.stringify(tierDecl.enum));
ok('schema azfwTier default is Standard', tierDecl.default === 'Standard');
const tierSelect = (html.match(/<select id="cn_fwTier"[\s\S]*?<\/select>/) || [''])[0];
const tierOptions = Array.from(tierSelect.matchAll(/option value="([^"]+)"/g)).map(m => m[1]);
ok('wizard tier options are exactly the schema enum', JSON.stringify(tierOptions.sort()) === JSON.stringify([...tierDecl.enum].sort()), JSON.stringify(tierOptions));
// Both connectivity layers must reject Basic (contract #7 right-hand side,
// narrowed in lockstep with the schema).
for (const varsPath of ['../../terraform/live/platform-connectivity/variables.tf', '../templates/terraform/live/platform-connectivity/variables.tf']) {
  const hcl = require('fs').readFileSync(require('path').resolve(__dirname, varsPath), 'utf8');
  const tierBlock = (hcl.match(/variable "azfw_tier" \{[\s\S]*?\n\}/) || [''])[0];
  ok(`${varsPath.includes('templates') ? 'template' : 'live'} layer validates ["Standard", "Premium"]`,
    /contains\(\["Standard", "Premium"\], var\.azfw_tier\)/.test(tierBlock) && !/Basic/.test(tierBlock.match(/condition[^\n]*/)[0]),
    tierBlock.split('\n').find(l => /condition/.test(l)));
}
// Imported/drafted configs from before the narrowing must block export.
c.connectivity.firewall.azfwTier = 'Basic';
ok('imported Basic tier blocks export', A.validate().errors.some(e => /Standard and Premium only/.test(e.message)));
c.connectivity.firewall.azfwTier = 'Standard';
ok('Standard clears the tier block', !A.validate().errors.some(e => /Standard and Premium only/.test(e.message)));

console.log('\n== 14. Firewall-less hub is supported end to end ==');
// Operator decision 2026-08-06: a landing zone need not ship a firewall. The
// whole contract chain has to agree, because "none" previously existed in the
// wizard while the connectivity layer rejected it — a clean export that failed
// at plan.
const fwDecl = schema.properties.connectivity.properties.firewall.properties.type;
ok('schema firewall enum includes none',
  JSON.stringify(fwDecl.enum) === '["azfw","palo","fortinet","none"]', JSON.stringify(fwDecl.enum));
const fwSelect = (html.match(/<select id="cn_fwType"[\s\S]*?<\/select>/) || [''])[0];
const fwOptions = Array.from(fwSelect.matchAll(/option value="([^"]+)"/g)).map(m => m[1]);
ok('wizard firewall options are exactly the schema enum',
  JSON.stringify(fwOptions.sort()) === JSON.stringify([...fwDecl.enum].sort()), JSON.stringify(fwOptions));
for (const varsPath of ['../../terraform/live/platform-connectivity/variables.tf', '../templates/terraform/live/platform-connectivity/variables.tf']) {
  const hcl = require('fs').readFileSync(require('path').resolve(__dirname, varsPath), 'utf8');
  const fwBlock = (hcl.match(/variable "firewall_type" \{[\s\S]*?\n\}/) || [''])[0];
  ok(`${varsPath.includes('templates') ? 'template' : 'live'} layer accepts none`,
    /contains\(\["azfw", "palo", "fortinet", "none"\], var\.firewall_type\)/.test(fwBlock),
    fwBlock.split('\n').find(l => /condition/.test(l)));
}
// hub-network must gate NVA resources on membership, not on "not azfw".
// Getting this wrong is what made "none" undeployable in the first place.
for (const modPath of ['../../terraform/modules/hub-network/main.tf', '../templates/terraform/modules/hub-network/main.tf']) {
  const hcl = require('fs').readFileSync(require('path').resolve(__dirname, modPath), 'utf8');
  const tree = modPath.includes('templates') ? 'template' : 'live';
  ok(`${tree} hub gates NVA on membership`, /has_nva\s*=\s*contains\(\["palo", "fortinet"\], var\.firewall_type\)/.test(hcl));
  ok(`${tree} hub has no "!= azfw" gate left`, !/var\.firewall_type != "azfw"/.test(hcl));
  ok(`${tree} hub route table is conditional`, /resource "azurerm_route_table" "to_firewall" \{\s*\n\s*count\s*=\s*local\.has_firewall/.test(hcl));
}
// Selecting none must not demand NVA trust IPs.
c.connectivity.firewall.type = 'none';
ok('none does not require an NVA trust IP', !A.validate().errors.some(e => /trust IP/i.test(e.message)));
ok('none warns about unfiltered egress', A.validate().warnings.some(w => /unfiltered/i.test(w.message)));
const tfvarsNone = A.tfvarsConnectivity(A.buildConfig());
ok('none emits firewall_type = "none"', /firewall_type\s+= "none"/.test(tfvarsNone),
  tfvarsNone.split('\n').find(l => /firewall_type/.test(l)));
// The NVA trust IP is meaningless without an NVA and must not be emitted.
ok('none emits no NVA trust IP', !/nva_trust_ip/.test(tfvarsNone));
c.connectivity.firewall.type = 'azfw';
ok('azfw remains valid', !A.validate().errors.some(e => /Firewall type/.test(e.message)));

console.log(`\n${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
