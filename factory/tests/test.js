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
c.backend.azurerm.resourceGroupName = 'rg-contoso-tfstate';
c.backend.azurerm.storageAccountName = 'contosotfstate01';
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
// Neither of these has a default any more: they are the two largest recurring
// line items the connectivity layer can create, so the wizard makes the client
// say. A config that has not answered them is not a valid config.
c.connectivity.firewall.enabled = true;
c.connectivity.bastion.enabled = false;
// The Defender policy group is on by default and Deploy-MDFC-Config-H224
// consumes email_security_contact. Unsupplied, the assignment is created from
// the library's own security_contact@replace_me — which is exactly what the
// policies step exists to stop, so it is an export blocker, not a warning.
c.governance.policySelection.values.email_security_contact = 'secops@contoso.com';
A.config = c;
A.defaultTagRows = [
  { k: 'owner', v: 'platform' }, { k: 'application', v: 'alz' },
  { k: 'environment', v: 'prod' }, { k: 'cost_center', v: 'CC-1' }
];

v = A.validate();
ok('valid config has zero blocking errors', v.errors.length === 0, JSON.stringify(v.errors, null, 1));

console.log('\n== 4. Managed-resource estimate (sizing signal) ==');
// The HCP free-tier gate retired with the backend (ADR 0015); the estimate
// survives in deployment-metadata.json as a sizing signal.
const rum = A.estimateRum();
console.log('  estimate =', rum, 'resources');
ok('estimate is a positive number', rum > 0);
ok('no backend billing gate fires', !A.validate().errors.some(e => /free tier/.test(e.message)));

console.log('\n== 5. Recorded-not-deployed answers stay exportable (ADR 0017) ==');
c.security.sentinel.enabled = true;
ok('sentinel is a warning, not an export block', !A.validate().errors.some(e => /[Ss]entinel/.test(e.message)) && A.validate().warnings.some(e => /Sentinel/.test(e.message)));
c.security.sentinel.enabled = false;
c.security.keyVault.customerManagedKeys = true;
ok('CMK is a warning, not an export block', !A.validate().errors.some(e => /[Cc]ustomer-managed/.test(e.message)) && A.validate().warnings.some(e => /keys/.test(e.message)));
c.security.keyVault.customerManagedKeys = false;
c.connectivity.model = 'virtual-wan';
ok('virtual-wan exports cleanly (AVM pattern module)', !A.validate().errors.some(e => /Virtual WAN/.test(e.message)));
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
ok('backend is azurerm-only', cfg.backend.type === 'azurerm' && cfg.backend.hcpTerraform === undefined);
ok('state subscription defaults to management', cfg.backend.azurerm.subscriptionId === 'aaaaaaaa-0000-0000-0000-000000000001');
ok('empty optional subs are stripped', cfg.azure.subscriptions.sandbox === undefined);

const tfg = A.tfvarsGlobal(cfg);
ok('global tfvars sets the management subscription', /management_subscription_id\s+= "aaaaaaaa-0000-0000-0000-000000000001"/.test(tfg), tfg.split('\n').find(l=>/management_subscription_id/.test(l)));
ok('global tfvars carries the state coordinates', /state_storage_account_name = "contosotfstate01"/.test(tfg));

const tfc = A.tfvarsConnectivity(cfg);
ok('connectivity tfvars sets azfw_tier', /azfw_tier\s+= "Standard"/.test(tfc));
ok('connectivity tfvars emits default_tags map', /default_tags = \{/.test(tfc) && /owner = "platform"/.test(tfc));
ok('connectivity tfvars includes DR when set', /dr_region\s+= "northcentralus"/.test(tfc));
ok('connectivity tfvars wires the gateways', /deploy_vpn_gateway\s+= false/.test(tfc) && /deploy_expressroute_gateway = false/.test(tfc));

const bh = A.backendHcl(cfg);
ok('backend.hcl authenticates with OIDC + Entra', /use_oidc\s+= true/.test(bh) && /use_azuread_auth\s+= true/.test(bh));
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
for (const varsPath of ['../templates/terraform/live/platform-connectivity/variables.tf']) {
  const hcl = require('fs').readFileSync(require('path').resolve(__dirname, varsPath), 'utf8');
  const tierBlock = (hcl.match(/variable "azfw_tier" \{[\s\S]*?\n\}/) || [''])[0];
  ok('template layer validates ["Standard", "Premium"]',
    /contains\(\["Standard", "Premium"\], var\.azfw_tier\)/.test(tierBlock) && !/Basic/.test(tierBlock.match(/condition[^\n]*/)[0]),
    tierBlock.split('\n').find(l => /condition/.test(l)));
}
// Imported/drafted configs from before the narrowing must block export. The
// tier only matters when a firewall is actually deployed, so assert with the
// firewall on.
c.connectivity.firewall.enabled = true;
c.connectivity.firewall.azfwTier = 'Basic';
ok('imported Basic tier blocks export', A.validate().errors.some(e => /Standard and Premium only/.test(e.message)));
c.connectivity.firewall.azfwTier = 'Standard';
ok('Standard clears the tier block', !A.validate().errors.some(e => /Standard and Premium only/.test(e.message)));

console.log('\n== 14. Deploying a firewall is an answer, not a default ==');
// ADR 0017 amended 2026-08-30. The AVM connectivity patterns take
// firewall_enabled as a plain boolean (main.tf.tmpl threads it into the module
// beside bastion), so "always on" was never a module constraint — it was an
// unemitted tfvars line letting a variable default decide roughly USD 11k/year
// on the client's behalf. The type stays bounded to azfw; whether to deploy one
// is now a required question with no default.
const fwDecl = schema.properties.connectivity.properties.firewall.properties.type;
// ADR 0017: the AVM connectivity patterns deploy Azure Firewall; NVA options
// retired with the bespoke hub-network module. "none" stays excluded — a
// landing zone requires at least one firewall (operator decision 2026-08-06).
ok('schema firewall enum is exactly [azfw]',
  JSON.stringify(fwDecl.enum) === '["azfw"]', JSON.stringify(fwDecl.enum));
const fwSelect = (html.match(/<select id="cn_fwType"[\s\S]*?<\/select>/) || [''])[0];
const fwOptions = Array.from(fwSelect.matchAll(/option value="([^"]+)"/g)).map(m => m[1]);
ok('wizard firewall options are exactly the schema enum',
  JSON.stringify(fwOptions.sort()) === JSON.stringify([...fwDecl.enum].sort()), JSON.stringify(fwOptions));
// Topology keeps its own "none" — that drops the whole layer and is a
// different, supported choice from a hub with unfiltered egress.
const modelSelect = (html.match(/<select id="cn_model"[\s\S]*?<\/select>/) || [''])[0];
ok('topology None survives (it drops the layer entirely)', /option value="none"/.test(modelSelect));
// Neither boolean may carry a default in the template layer: the renderer
// always emits both, so a missing value means a hand-edited tfvars and should
// fail loudly rather than quietly deploy a firewall nobody asked for.
{
  const hcl = require('fs').readFileSync(require('path').resolve(__dirname, '../templates/terraform/live/platform-connectivity/variables.tf'), 'utf8');
  const fwBlock = (hcl.match(/variable "firewall_enabled" \{[\s\S]*?\n\}/) || [''])[0];
  const baBlock = (hcl.match(/variable "deploy_bastion" \{[\s\S]*?\n\}/) || [''])[0];
  ok('template layer gives firewall_enabled no default', /variable "firewall_enabled"/.test(fwBlock) && !/default/.test(fwBlock), fwBlock);
  ok('template layer gives deploy_bastion no default', /variable "deploy_bastion"/.test(baBlock) && !/default/.test(baBlock), baBlock);
}
// The renderer must actually emit the answer, or the no-default variable above
// turns every render into a prompt.
{
  const tfvars = require('fs').readFileSync(require('path').resolve(__dirname, '../templates/terraform/live/platform-connectivity/terraform.auto.tfvars.tmpl'), 'utf8');
  ok('tfvars template emits firewall_enabled', /firewall_enabled\s+=\s+\{\{FACTORY-BOOL:connectivity\.firewall\.enabled\}\}/.test(tfvars));
  ok('tfvars template emits deploy_bastion', /deploy_bastion\s+=\s+\{\{FACTORY-BOOL:connectivity\.bastion\.enabled\}\}/.test(tfvars));
}
// An unanswered cost question blocks export — this is the whole point.
c.connectivity.firewall.enabled = null;
ok('unanswered firewall blocks export', A.validate().errors.some(e => /whether the hub deploys an Azure Firewall/.test(e.message)));
c.connectivity.bastion.enabled = null;
ok('unanswered bastion blocks export', A.validate().errors.some(e => /whether the hub deploys Azure Bastion/.test(e.message)));
c.connectivity.bastion.enabled = false;
// Answering "no" is a supported answer, not an error — but it is worth saying
// out loud that nothing is inspecting egress.
c.connectivity.firewall.enabled = false;
ok('declining a firewall is allowed', !A.validate().errors.some(e => /Azure Firewall/.test(e.message)));
ok('declining a firewall warns about egress', A.validate().warnings.some(e => /no firewall/i.test(e.message)));
c.connectivity.firewall.enabled = true;
ok('deploying a firewall clears both', !A.validate().errors.some(e => /Azure Firewall|Azure Bastion/.test(e.message)));
// Imported/drafted configs from while type "none" was offered must block export.
c.connectivity.firewall.type = 'none';
ok('imported firewall type "none" blocks export', A.validate().errors.some(e => /only type the generator composes/.test(e.message)));
c.connectivity.firewall.type = 'azfw';
ok('azfw clears the firewall-type block', !A.validate().errors.some(e => /only type the generator composes/.test(e.message)));

console.log('\n== 15. Policy selection is read from the pinned library ==');
{
  const catalog = A.POLICY_CATALOG;
  ok('the catalog reached the wizard', catalog.groups.length > 0 && Object.keys(catalog.assignments).length > 0,
    'harness.js must load site/alz-policy-catalog.js before app.js');

  // Every group in the catalog names assignments the catalog also declares —
  // otherwise a toggle in the UI governs nothing.
  const orphans = catalog.groups.flatMap(g => g.assignments.filter(a2 => !catalog.assignments[a2]));
  ok('every grouped assignment exists', orphans.length === 0, orphans.join(', '));

  // Absence means enabled: a config written before a library bump must keep the
  // ALZ baseline rather than silently dropping whatever the bump added.
  delete c.governance.policySelection.groups['aks-hardening'];
  ok('an unmentioned group is enabled', A.policyGroupEnabled('aks-hardening'));
  c.governance.policySelection.groups['aks-hardening'] = false;
  ok('an explicitly disabled group is off', !A.policyGroupEnabled('aks-hardening'));
  const aks = catalog.groups.find(g => g.id === 'aks-hardening');
  ok('its assignments follow the group', aks.assignments.every(n => !A.policyAssignmentEnabled(n)));

  // The per-assignment override beats its group, in both directions.
  const one = aks.assignments[0];
  c.governance.policySelection.assignments[one] = { creationEnabled: true };
  ok('a per-assignment override wins over the group', A.policyAssignmentEnabled(one));
  delete c.governance.policySelection.assignments[one];
  c.governance.policySelection.groups['aks-hardening'] = true;

  // The values the client owes are derived from what is selected, and only for
  // defaults the factory does not already compute.
  const owed = () => A.requiredPolicyValues().map(([n]) => n);
  ok('a factory-computed default is never asked for', !owed().includes('log_analytics_workspace_id'),
    'the global layer composes it from remote state');
  ok('DDoS is off by default, so no plan ID is owed', !owed().includes('ddos_protection_plan_id'));
  c.governance.policySelection.groups.ddos = true;
  ok('enabling DDoS asks for the plan ID', owed().includes('ddos_protection_plan_id'));
  ok('an unanswered plan ID blocks export',
    A.validate().errors.some(e => /DDoS protection plan resource ID is required/.test(e.message)));
  c.governance.policySelection.values.ddos_protection_plan_id = 'ddos-plan-1';
  ok('a bare name is rejected — the policy needs a resource ID',
    A.validate().errors.some(e => /must be a full resource ID/.test(e.message)));
  c.governance.policySelection.values.ddos_protection_plan_id =
    '/subscriptions/aaaaaaaa-0000-0000-0000-000000000002/resourceGroups/rg-contoso-connectivity-scus/providers/Microsoft.Network/ddosProtectionPlans/ddos-contoso';
  ok('a full resource ID clears it', !A.validate().errors.some(e => /DDoS/.test(e.message)));

  // Turning the assignment off retires its question, rather than leaving a
  // required value the client can no longer see a reason for.
  c.governance.policySelection.groups.ddos = false;
  ok('disabling the group retires the question', !owed().includes('ddos_protection_plan_id'));
  ok('and the stale answer does not travel', !('ddos_protection_plan_id' in (A.buildConfig().governance.policySelection.values || {})),
    'buildConfig must drop values nothing asks for any more');

  // The security contact is one fact asked once.
  const supplied = c.governance.policySelection.values.email_security_contact;
  delete c.governance.policySelection.values.email_security_contact;
  ok('an unanswered security contact blocks export',
    A.validate().errors.some(e => /Defender for Cloud security contact is required/.test(e.message)));
  c.governance.policySelection.values.email_security_contact = 'not-an-email';
  ok('a malformed security contact blocks export',
    A.validate().errors.some(e => /not a valid email address/.test(e.message)));
  c.governance.policySelection.values.email_security_contact = supplied;

  // Turning everything off is a configuration the wizard refuses to export.
  const saved = JSON.parse(JSON.stringify(c.governance.policySelection.groups));
  for (const g of catalog.groups) c.governance.policySelection.groups[g.id] = false;
  ok('an ungoverned landing zone blocks export',
    A.validate().errors.some(e => /no Azure Policy governance at all/.test(e.message)));
  c.governance.policySelection.groups = saved;
  ok('the fixture is exportable again', A.validate().errors.length === 0, JSON.stringify(A.validate().errors, null, 1));
}

console.log('\n== 16. Answers that reach nothing are declared, not discovered ==');
{
  ok('the ledger reached the wizard', A.RECORDED_NOT_DEPLOYED.length > 0,
    'harness.js must load site/schema-coverage.js before app.js');
  ok('every ledger entry is showable', A.RECORDED_NOT_DEPLOYED.every(
    (e) => e.label && e.module && e.impact && Array.isArray(e.paths) && e.paths.length));

  // An untouched default is not an answer, and warning about one would train
  // the client to ignore the whole table.
  const clean = A.buildConfig();
  const untouched = A.unmetDependencies(clean).filter((u) => u.feature === 'FinOps budgets and cost exports');
  ok('an untouched default raises nothing', untouched.length === 0, JSON.stringify(untouched));

  // A real answer does raise one, naming the path so the client can see which
  // of their answers is the one going nowhere.
  c.finops.budgets = [{ scope: 'management', amountUsd: 5000, timeGrain: 'Monthly', alertThresholdPercents: [80], contactEmails: ['fin@contoso.com'] }];
  const withBudget = A.unmetDependencies(A.buildConfig()).filter((u) => u.feature === 'FinOps budgets and cost exports');
  ok('a real answer raises a recorded-not-deployed row', withBudget.length === 1, JSON.stringify(withBudget));
  ok('the row names the answered path', withBudget.length === 1 && /finops\.budgets\.amountUsd/.test(withBudget[0].impact));
  ok('and it is not reported as deployed', withBudget.length === 1 && withBudget[0].status === 'recorded-not-deployed');
  c.finops.budgets = [];

  // The four hand-written entries survive — they are conditions on a feature
  // being switched on, not on a path carrying a value.
  c.security.sentinel.enabled = true;
  ok('Sentinel is still called out', A.unmetDependencies(A.buildConfig()).some((u) => u.feature === 'Microsoft Sentinel'));
  c.security.sentinel.enabled = false;

  // Found by this check on its first run: the wizard warned about storage-key
  // state auth and delivered Entra-only regardless, because the broker creates
  // the account with shared-key access disabled. An answer the factory cannot
  // honour is an export blocker, not a warning.
  c.backend.azurerm.useAzureAdAuth = false;
  ok('an unhonourable state-auth answer blocks export',
    A.validate().errors.some((e) => /Entra ID authentication to state is a contract/.test(e.message)));
  c.backend.azurerm.useAzureAdAuth = true;

  ok('the fixture is exportable throughout', A.validate().errors.length === 0, JSON.stringify(A.validate().errors, null, 1));
}

console.log('\n== 17. Management-group names are the client’s; the shape is not ==');
{
  const mg = c.azure.managementGroups;
  const libraryIds = A.POLICY_CATALOG.managementGroups.map((g) => g.id);
  ok('the library groups reached the wizard', libraryIds.length > 0);

  mg.strategy = 'custom';
  mg.customHierarchy = {};
  ok('custom with no rename blocks export',
    A.validate().errors.some((e) => /still carries its library name/.test(e.message)));

  mg.customHierarchy = { alz: { id: 'contoso-alz', displayName: 'Contoso Landing Zones' } };
  ok('one rename is enough', !A.validate().errors.some((e) => /still carries its library name/.test(e.message)));

  // A key outside the library would create a group no archetype governs, and
  // management-group IDs are immutable once applied.
  mg.customHierarchy['not-a-library-group'] = { id: 'x' };
  ok('an unknown library id blocks export',
    A.validate().errors.some((e) => /not a management group the pinned Azure Landing Zones library defines/.test(e.message)));
  delete mg.customHierarchy['not-a-library-group'];

  mg.customHierarchy.platform = { id: 'contoso-alz' };
  ok('two groups claiming one id blocks export',
    A.validate().errors.some((e) => /would both be created as/.test(e.message)));
  mg.customHierarchy.platform = { id: 'contoso-platform' };

  // Colliding with a group that kept its library name is the same collision.
  mg.customHierarchy.platform = { id: 'corp' };
  ok('colliding with an unrenamed group blocks export',
    A.validate().errors.some((e) => /both the library name of one management group and the chosen ID of another/.test(e.message)));
  mg.customHierarchy.platform = { id: 'contoso-platform' };

  mg.customHierarchy.landingzones = { id: 'not a valid mg id!' };
  ok('an invalid id blocks export',
    A.validate().errors.some((e) => /is not a valid management group ID/.test(e.message)));
  delete mg.customHierarchy.landingzones;

  // A "rename" that restates the library's own name is not a decision, and
  // must not travel into the answer record as though it were.
  mg.customHierarchy.sandbox = { id: 'sandbox' };
  const exported = A.buildConfig().azure.managementGroups.customHierarchy;
  ok('a no-op rename is stripped from the export', !('sandbox' in exported), JSON.stringify(exported));
  ok('a real rename survives', exported.alz && exported.alz.id === 'contoso-alz');
  delete mg.customHierarchy.sandbox;

  ok('the fixture still exports', A.validate().errors.length === 0, JSON.stringify(A.validate().errors, null, 1));

  mg.strategy = 'caf-standard';
  ok('a standard strategy drops the renames entirely',
    !('customHierarchy' in A.buildConfig().azure.managementGroups));
}

console.log(`\n${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
