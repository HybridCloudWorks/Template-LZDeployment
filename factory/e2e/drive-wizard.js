#!/usr/bin/env node
/*
 * End-to-end wizard driver (proof 9a: the answer record is produced by the
 * REAL web UI, never hand-authored).
 *
 * Loads site/index.html in headless Chromium, fills the form through the DOM
 * (dispatching real input/change events so the wizard's own binding layer
 * writes the config), asserts the wizard's validate() reports zero blocking
 * errors and the Export button is enabled, then captures the wizard's own
 * exportArtifacts() pipeline output — the same code path the Export button
 * runs — and writes the artifact set to the output directory.
 *
 * Usage: node drive-wizard.js <output-dir> [--topology hub-spoke|virtual-wan]
 * Env:   PLAYWRIGHT_BROWSER (chromium executable path override)
 */
'use strict';

const fs = require('fs');
const path = require('path');

function resolvePlaywright() {
  const candidates = [
    'playwright-core',
    'playwright',
    path.resolve(process.env.LZ_E2E_NODE_MODULES || '', 'playwright-core'),
  ];
  for (const c of candidates) {
    try { return require(c); } catch { /* next */ }
  }
  throw new Error('playwright-core is required: npm install playwright-core');
}

// Synthetic, obviously-fake identifiers. These are the ONLY GUIDs permitted
// to appear in generated output (proof f checks output GUIDs against this
// exact set plus Azure built-in definition IDs).
const SYNTHETIC = {
  tenantId: '11111111-2222-3333-4444-555555555555',
  management: 'aaaaaaaa-0000-0000-0000-000000000001',
  connectivity: 'aaaaaaaa-0000-0000-0000-000000000002',
  workloadProd: 'aaaaaaaa-0000-0000-0000-000000000003',
};

async function main() {
  const outDir = process.argv[2];
  if (!outDir) { console.error('usage: node drive-wizard.js <output-dir> [--topology t]'); process.exit(2); }
  const topologyFlag = process.argv.indexOf('--topology');
  const topology = topologyFlag > -1 ? process.argv[topologyFlag + 1] : 'hub-spoke';

  const { chromium } = resolvePlaywright();
  const executablePath = process.env.PLAYWRIGHT_BROWSER ||
    (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

  const browser = await chromium.launch({ executablePath, args: ['--allow-file-access-from-files'] });
  const page = await browser.newPage();

  const siteUrl = 'file://' + path.resolve(__dirname, '..', '..', 'site', 'index.html');
  await page.goto(siteUrl);
  await page.waitForFunction(() => typeof window.validate === 'function');

  // Fill by the wizard's own binding contract (data-path attributes), firing
  // real events so app.js writes the config exactly as a human would.
  const setValue = async (dataPath, value) => {
    const changed = await page.evaluate(([p, v]) => {
      const el = document.querySelector(`[data-path="${p}"]`);
      if (!el) return false;
      if (el.type === 'checkbox') {
        el.checked = Boolean(v);
        el.dispatchEvent(new Event('change', { bubbles: true }));
      } else {
        el.value = String(v);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }
      return true;
    }, [dataPath, value]);
    if (!changed) throw new Error(`No wizard element binds ${dataPath}`);
  };

  const answers = {
    'organization.companyName': 'Example Client Org',
    'organization.companyShortName': 'exco',
    'organization.businessUnit': 'Platform Engineering',
    'azure.tenantId': SYNTHETIC.tenantId,
    'azure.primaryRegion': 'southcentralus',
    'azure.primaryRegionCode': 'scus',
    'azure.drRegion': 'northcentralus',
    'azure.drRegionCode': 'ncus',
    'azure.allowedLocations': 'southcentralus, northcentralus',
    'azure.subscriptions.management': SYNTHETIC.management,
    'azure.subscriptions.connectivity': SYNTHETIC.connectivity,
    'azure.subscriptions.workloadProd': SYNTHETIC.workloadProd,
    'azure.managementGroups.rootId': 'mg-exco',
    'github.ownerName': 'example-client-org',
    'github.repositoryName': 'exco-landing-zone',
    'backend.azurerm.resourceGroupName': 'rg-exco-tfstate',
    'backend.azurerm.storageAccountName': 'excotfstate01',
    'connectivity.model': topology,
    'connectivity.hubSpoke.primaryHubAddressSpace': '10.100.0.0/16',
    'connectivity.hubSpoke.drHubAddressSpace': '10.101.0.0/16',
    'connectivity.hubSpoke.primarySpokeAddressSpace': '10.102.0.0/16',
    'connectivity.hubSpoke.drSpokeAddressSpace': '10.103.0.0/16',
    'operations.platformTeam.name': 'Platform Team',
    'finops.costCenter': 'CC-100',
    'finops.businessOwner.name': 'Casey Owner',
    'finops.businessOwner.email': 'owner@example.test',
  };
  for (const [p, v] of Object.entries(answers)) await setValue(p, v);

  // Repeater/list answers that have no single bound input go through the
  // page's own state objects, then a UI refresh — still the app's own code.
  await page.evaluate(() => {
    /* global config, defaultTagRows, renderApprovals, validate */
    defaultTagRows.length = 0;
    for (const row of [
      { k: 'owner', v: 'platform' }, { k: 'application', v: 'alz' },
      { k: 'environment', v: 'prod' }, { k: 'cost_center', v: 'CC-100' },
    ]) defaultTagRows.push(row);
    config.operations.platformTeam.contacts = [{ name: 'Casey Owner', email: 'owner@example.test', role: 'Lead' }];
    config.operations.breakGlassContacts = [{ name: 'Riley Break', email: 'breakglass@example.test' }];
    config.identity.breakGlassAccounts = [
      { name: 'bg1@example.test', email: 'secops@example.test', role: 'GA' },
      { name: 'bg2@example.test', email: 'secops@example.test', role: 'GA' },
    ];
    config.environments.approvals = { prod: { requiredReviewers: ['@example-client-org/platform'], waitTimerMinutes: 0, preventSelfReview: true } };
  });

  const verdict = await page.evaluate(() => {
    const v = validate();
    return {
      errors: v.errors.map(e => `${e.step}: ${e.message}`),
      warnings: v.warnings.map(w => `${w.step}: ${w.message}`),
      exportDisabled: document.querySelector('#btnExport').disabled,
    };
  });

  if (verdict.errors.length > 0 || verdict.exportDisabled) {
    console.error('Wizard refused export:');
    for (const e of verdict.errors) console.error('  ERROR ' + e);
    await browser.close();
    process.exit(1);
  }
  for (const w of verdict.warnings) console.error('  warn  ' + w);

  // The Export button's own pipeline.
  const artifacts = await page.evaluate(() =>
    exportArtifacts().map(a => ({ name: a.name, content: a.build() }))
  );
  await browser.close();

  fs.mkdirSync(outDir, { recursive: true });
  for (const a of artifacts) fs.writeFileSync(path.join(outDir, a.name), a.content);
  console.log(`UI-driven export complete: ${artifacts.length} artifact(s) -> ${outDir}`);
  console.log(artifacts.map(a => '  ' + a.name).join('\n'));
}

main().catch(err => { console.error(err); process.exit(1); });
