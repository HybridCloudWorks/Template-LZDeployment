// ═════════════════════════════════════════════════════════════════════════════
// Legacy Azure Landing Zone .tfvars Generator (frontend/)
//
// LEGACY: the Landing Zone Factory wizard (../site/index.html) is the primary
// path. This page feeds only the legacy in-repo pipeline under terraform/live/.
//
// Zero-network: this page makes no network requests of any kind. Everything
// below runs in the browser; downloads are data: URIs built in memory.
//
// Emission contract: the generated files contain ONLY variables declared in
//   terraform/live/global/variables.tf              → terraform.auto.tfvars
//   terraform/live/platform-connectivity/variables.tf → connectivity.auto.tfvars
// Anything the form collects that no Terraform stack consumes is labelled in
// the UI and never emitted (reconciled 2026-08-02; see frontend/README.md).
// ═════════════════════════════════════════════════════════════════════════════

// Region short codes — must agree with the codes used by site/app.js and the
// region_code variables in terraform/live/*.
const REGION_CODES = {
  eastus: "eus", eastus2: "eus2", westus: "wus", westus2: "wus2",
  centralus: "cus", northcentralus: "ncus", southcentralus: "scus",
  canadacentral: "cnc", canadaeast: "cne",
  northeurope: "neu", westeurope: "weu", uksouth: "uks",
  eastasia: "ea", southeastasia: "sea",
  australiaeast: "aue", australiasoutheast: "ause"
};

// ─────────────────────────────────────────────────────────────────────────────
// Policy reconciliation (2026-08-02) against terraform/modules/policy-baseline/
// (main.tf + policy-tls-minimum.tf; the API Management TLS definition is being
// added to policy-tls-minimum.tf concurrently and is counted as implemented).
//
// enforcedPolicies: definitions/assignments that EXIST in policy-baseline. The
// module deploys them unconditionally from terraform/live/global — there is no
// per-policy variable, so nothing here is emitted into the .tfvars.
//
// officialPolicies: the official ALZ assignment catalog this page historically
// offered (47 toggles). Entries whose id appears in COVERED_BY_BASELINE are
// implemented (shown in the enforced list instead); every other entry is
// roadmap intent only — NO policy definition exists in this repository, the
// toggle is disabled, and nothing about it is ever emitted.
// ─────────────────────────────────────────────────────────────────────────────

const enforcedPolicies = [
  {
    id: "require-mandatory-tags",
    name: "Require mandatory tags (owner, application, environment, cost_center)",
    scope: "Root management group", effect: "Deny", source: "policy-baseline/main.tf"
  },
  {
    id: "allowed-locations",
    name: "Allowed locations (built-in e56962a6)",
    scope: "Root management group", effect: "Deny", source: "policy-baseline/main.tf",
    note: "Driven by the allowed_locations value in the generated terraform.auto.tfvars."
  },
  {
    id: "nsg-on-subnets",
    name: "Subnets should be associated with a Network Security Group (built-in e71308d3)",
    scope: "Platform management group", effect: "AuditIfNotExists (definition default — the assignment passes no parameters)", source: "policy-baseline/main.tf",
    note: "Audit-class only: the built-in supports AuditIfNotExists/Disabled, so the ALZ catalog's Deny variant is not implemented, and no assignment exists at the Landing Zones scope."
  },
  {
    id: "tls-12-enforcement",
    name: "Enforce TLS 1.2 minimum (Storage, App Service, Function Apps, MySQL, PostgreSQL, API Management)",
    scope: "Root management group", effect: "Deny", source: "policy-baseline/policy-tls-minimum.tf",
    note: "Custom initiative; covers the listed services only. Assigned at root, which is broader than the ALZ catalog's Landing Zones scope."
  },
  {
    id: "sandbox-guardrails",
    name: "Sandbox guardrails (environment=sandbox tag, expiry_date tag, deny VNet peering)",
    scope: "Sandbox management group", effect: "Deny", source: "policy-baseline/main.tf",
    note: "Repo-specific guardrail set — not the official ALZ Sandbox Guardrails initiative."
  }
];

// ALZ catalog ids that a policy-baseline implementation covers (shown above).
const COVERED_BY_BASELINE = {
  "Deny-Deploy-TLS": "tls-12-enforcement",
  "Deny-SubnetNoNSG": "nsg-on-subnets",
  "Sandbox-Guardrails": "sandbox-guardrails"
};

// Official ALZ Policy Assignments (from https://azure.github.io/Azure-Landing-Zones/policy/policyassignments/)
const officialPolicies = {
  "Intermediate Root": [
    { id: "Deploy-MDFC", name: "Deploy Microsoft Defender for Cloud configuration", effects: ["DeployIfNotExists"] },
    { id: "Deploy-MDEndpoints", name: "Deploy Microsoft Defender for Endpoint agent", effects: ["DeployIfNotExists"] },
    { id: "Deploy-MDEndpointsAMA", name: "Configure Defender for Endpoint integration with MDfC", effects: ["DeployIfNotExists"] },
    { id: "Deploy-Diag-Logs", name: "Enable allLogs category resource logging to Log Analytics", effects: ["DeployIfNotExists"] },
    { id: "Microsoft-Cloud-Security-Benchmark", name: "Microsoft Cloud Security Benchmark", effects: ["Audit", "AuditIfNotExists", "Disabled"] },
    { id: "Configure-ATP-OSS-DB", name: "Configure Advanced Threat Protection - OSS Databases", effects: ["DeployIfNotExists"] },
    { id: "Configure-Defender-SQL", name: "Configure Azure Defender - SQL Servers", effects: ["DeployIfNotExists"] },
    { id: "Deploy-ActivityLog-Diags", name: "Deploy Activity Log Diagnostics to Log Analytics", effects: ["DeployIfNotExists"] },
    { id: "Deny-Classic-Resources", name: "Deny the deployment of classic resources", effects: ["Deny"] },
    { id: "Enforce-ACSB", name: "Enforce Azure Compute Security Baseline compliance auditing", effects: ["AuditIfNotExists"] },
  ],
  "Platform": [
    { id: "Enforce-KV-Guardrails", name: "Enforce recommended guardrails for Azure Key Vault", effects: ["Deny", "Audit"] },
    { id: "Enforce-Backup", name: "Enforce enhanced recovery and backup policies", effects: ["Audit"] },
    { id: "Subnets-Private", name: "Subnets should be private", effects: ["Audit", "Deny"] },
    { id: "DDoS-Protection", name: "Virtual networks should be protected by Azure DDoS Protection Standard", effects: ["Modify"] },
    { id: "AMBA-Connectivity", name: "Deploy Azure Monitor Baseline Alerts for Connectivity", effects: ["DeployIfNotExists"] },
    { id: "AMBA-Management", name: "Deploy Azure Monitor Baseline Alerts for Management", effects: ["DeployIfNotExists"] },
    { id: "AMBA-Identity", name: "Deploy Azure Monitor Baseline Alerts for Identity", effects: ["DeployIfNotExists"] },
    { id: "Deny-PublicIP", name: "Deny the creation of public IP", effects: ["Deny"] },
    { id: "Deny-MgmtPorts", name: "Management port access from the Internet should be blocked", effects: ["Deny"] },
    { id: "Deny-SubnetNoNSG", name: "Subnets should have a Network Security Group", effects: ["Deny"] },
    { id: "Configure-VMBackup", name: "Configure backup on virtual machines", effects: ["DeployIfNotExists"] },
    { id: "Enable-AMAforVMs", name: "Enable Azure Monitor for VMs with Azure Monitoring Agent", effects: ["DeployIfNotExists"] },
    { id: "Enable-AMAforVMSS", name: "Enable Azure Monitor for VMSS with Azure Monitoring Agent", effects: ["DeployIfNotExists"] },
    { id: "Enable-AMAforHybrid", name: "Enable Azure Monitor for Hybrid VMs with AMA", effects: ["DeployIfNotExists"] },
    { id: "Deny-Unmanaged-Disk", name: "Deny virtual machines and virtual machine scale sets not using OS Managed Disk", effects: ["Deny"] },
  ],
  "Landing Zones": [
    { id: "Deny-Deploy-TLS", name: "Deny or Deploy and append TLS/SSL enforcement", effects: ["Audit", "AuditIfNotExists", "DeployIfNotExists", "Deny"] },
    { id: "Deny-MgmtPorts-LZ", name: "Management port access from the Internet should be blocked", effects: ["Deny"] },
    { id: "Deny-SubnetNoNSG-LZ", name: "Subnets should have a Network Security Group", effects: ["Deny"] },
    { id: "Deny-IPForwarding", name: "Network interfaces should disable IP forwarding", effects: ["Deny"] },
    { id: "Secure-Storage-HTTPS", name: "Secure transfer to storage accounts should be enabled", effects: ["Deny"] },
    { id: "Deploy-AKS-Policy", name: "Deploy Azure Policy Add-on to Azure Kubernetes Service clusters", effects: ["DeployIfNotExists"] },
    { id: "Configure-SQLAudit", name: "Configure SQL servers to have auditing enabled to Log Analytics", effects: ["DeployIfNotExists"] },
    { id: "Deploy-SQLThreat", name: "Deploy Threat Detection on SQL servers", effects: ["DeployIfNotExists"] },
    { id: "Deploy-SQLTDE", name: "Deploy TDE on SQL servers", effects: ["DeployIfNotExists"] },
    { id: "DDoS-Protection-LZ", name: "Virtual networks should be protected by Azure DDoS Protection Standard", effects: ["Modify"] },
    { id: "AKS-No-Privileged", name: "Kubernetes cluster should not allow privileged containers", effects: ["Deny"] },
    { id: "AKS-No-PrivEsc", name: "Kubernetes clusters should not allow container privilege escalation", effects: ["Deny"] },
    { id: "AKS-HTTPS-Only", name: "Kubernetes clusters should be accessible only over HTTPS", effects: ["Deny"] },
    { id: "Enforce-KV-Guardrails-LZ", name: "Enforce recommended guardrails for Azure Key Vault", effects: ["Deny", "Audit"] },
    { id: "AMBA-LandingZone", name: "Deploy Azure Monitor Baseline Alerts for Landing Zone", effects: ["DeployIfNotExists"] },
  ],
  "Landing Zones/Corp": [
    { id: "Deny-PublicPaaS", name: "Public network access should be disabled for PaaS services", effects: ["Deny"] },
    { id: "Configure-PrivateDNS", name: "Configure Azure PaaS services to use private DNS zones", effects: ["DeployIfNotExists"] },
    { id: "Deny-PublicIP-NIC", name: "Deny network interfaces having a public IP associated", effects: ["Deny"] },
    { id: "Audit-PrivateLinkDNS", name: "Audit the creation of Private Link Private DNS Zones", effects: ["Audit"] },
    { id: "Deny-HybridNetworking", name: "Deny the deployment of vWAN/ER/VPN gateway resources", effects: ["Deny"] },
  ],
  "Specialized": [
    { id: "Sandbox-Guardrails", name: "Enforce ALZ Sandbox Guardrails", effects: ["Deny"] },
    { id: "Decommissioned-Guardrails", name: "Enforce ALZ Decommissioned Guardrails", effects: ["Deny", "DeployIfNotExists"] },
  ]
};

// HCL escaping: JSON string encoding is valid HCL string encoding.
function hclString(s) { return JSON.stringify(String(s === null || s === undefined ? "" : s)); }
function hclList(arr) { return "[" + (arr || []).map(hclString).join(", ") + "]"; }

// ═════════════════════════════════════════════════════════════════════════════
// Generator
// ═════════════════════════════════════════════════════════════════════════════

class LegacyTfvarsGenerator {
  constructor() {
    this.init();
  }

  init() {
    this.setupEventListeners();
    this.populatePolicies();
    this.setupRegionPairing();
    updateNamingExamples();
    this.showForm();
  }

  setupEventListeners() {
    const generateBtn = document.getElementById("generateBtn");
    const downloadBtn = document.getElementById("downloadBtn");
    const copyBtn = document.getElementById("copyBtn");
    const regenerateBtn = document.getElementById("regenerateBtn");

    if (generateBtn) generateBtn.addEventListener("click", () => this.generate());
    if (downloadBtn) downloadBtn.addEventListener("click", () => this.download());
    if (copyBtn) copyBtn.addEventListener("click", () => this.copyToClipboard());
    if (regenerateBtn) regenerateBtn.addEventListener("click", () => this.backToForm());

    // The CSP (script-src 'self', no 'unsafe-inline') blocks inline handler
    // attributes, so every control is wired here instead of in the HTML.
    const orgIdInput = document.getElementById("orgId");
    if (orgIdInput) orgIdInput.addEventListener("input", updateNamingExamples);
    const addRegionBtn = document.getElementById("addRegionBtn");
    if (addRegionBtn) addRegionBtn.addEventListener("click", addRegion);
    const tagEnforcement = document.getElementById("tagEnforcement");
    if (tagEnforcement) tagEnforcement.addEventListener("change", toggleTaggingFields);
  }

  setupRegionPairing() {
    const regionPairs = {
      "eastus2": "westus",
      "westus": "eastus2",
      "uksouth": "northeurope",
      "australiaeast": "australiasoutheast",
      "southeastasia": "eastasia",
      "centralus": "eastus2",
      "canadacentral": "canadaeast",
      "northeurope": "westeurope",
      "westeurope": "northeurope",
      "eastasia": "southeastasia",
      "canadaeast": "canadacentral",
    };

    const primarySelect = document.getElementById("primaryRegion");
    const secondary = document.getElementById("secondaryRegion");
    if (!primarySelect || !secondary) return;

    // The DR select ships empty in the HTML; populate it with every region we
    // have a short code for, so the paired default can actually be selected.
    secondary.innerHTML = "";
    Object.keys(REGION_CODES).forEach((region) => {
      const option = document.createElement("option");
      option.value = region;
      option.textContent = region;
      secondary.appendChild(option);
    });

    primarySelect.addEventListener("change", () => {
      const paired = regionPairs[primarySelect.value];
      if (paired) secondary.value = paired;
      updateNamingExamples();
    });
    secondary.value = regionPairs[primarySelect.value] || "eastus2";
  }

  populatePolicies() {
    const container = document.getElementById("policyAssignments");
    if (!container) return;

    container.innerHTML = "";

    // ── Group 1: enforced today by terraform/modules/policy-baseline ────────
    const enforcedDiv = document.createElement("div");
    enforcedDiv.className = "policy-scope policy-enforced-group";

    const enforcedTitle = document.createElement("div");
    enforcedTitle.className = "policy-scope-title";
    enforcedTitle.textContent = "Enforced today by terraform/modules/policy-baseline";
    enforcedDiv.appendChild(enforcedTitle);

    const enforcedNote = document.createElement("p");
    enforcedNote.className = "policy-group-note";
    enforcedNote.textContent =
      "These deploy unconditionally with the global layer. There is no per-policy " +
      "variable, so nothing in this section is written to the generated .tfvars " +
      "(allowed locations is the exception: it reads allowed_locations from " +
      "terraform.auto.tfvars).";
    enforcedDiv.appendChild(enforcedNote);

    enforcedPolicies.forEach((policy) => {
      const item = document.createElement("div");
      item.className = "policy-item policy-item-enforced";

      const details = document.createElement("div");
      details.className = "policy-details";

      const name = document.createElement("span");
      name.className = "policy-name";
      name.textContent = policy.name;

      const meta = document.createElement("span");
      meta.className = "policy-description";
      meta.textContent = `Scope: ${policy.scope} · Effect: ${policy.effect} · Source: ${policy.source}`;

      details.appendChild(name);
      details.appendChild(meta);

      if (policy.note) {
        const note = document.createElement("span");
        note.className = "policy-description policy-note";
        note.textContent = policy.note;
        details.appendChild(note);
      }

      const badge = document.createElement("span");
      badge.className = "badge badge-enforced";
      badge.textContent = "enforced";

      item.appendChild(badge);
      item.appendChild(details);
      enforcedDiv.appendChild(item);
    });

    container.appendChild(enforcedDiv);

    // ── Group 2: roadmap — the ALZ catalog this repo has not implemented ────
    const roadmapWrap = document.createElement("div");
    roadmapWrap.className = "policy-roadmap-group";

    const roadmapTitle = document.createElement("div");
    roadmapTitle.className = "policy-scope-title";
    roadmapTitle.textContent = "Roadmap — not yet enforced";
    roadmapWrap.appendChild(roadmapTitle);

    const roadmapNote = document.createElement("p");
    roadmapNote.className = "policy-group-note policy-group-warning";
    roadmapNote.textContent =
      "No policy definition exists in terraform/modules/policy-baseline for any " +
      "assignment below. They are listed to preserve the official ALZ roadmap " +
      "intent, cannot be selected, and are never written to the generated .tfvars. " +
      "Implementing one means adding its definition and assignment to the " +
      "policy-baseline module first.";
    roadmapWrap.appendChild(roadmapNote);

    for (const [scope, policies] of Object.entries(officialPolicies)) {
      const remaining = policies.filter((p) => !COVERED_BY_BASELINE[p.id]);
      if (!remaining.length) continue;

      const scopeDiv = document.createElement("div");
      scopeDiv.className = "policy-scope policy-scope-roadmap";

      const scopeTitle = document.createElement("div");
      scopeTitle.className = "policy-scope-title policy-scope-title-sub";
      scopeTitle.textContent = `${scope} (ALZ catalog scope)`;
      scopeDiv.appendChild(scopeTitle);

      remaining.forEach((policy) => {
        const item = document.createElement("div");
        item.className = "policy-item policy-item-roadmap";

        const info = document.createElement("div");
        info.className = "policy-info";

        const checkbox = document.createElement("input");
        checkbox.type = "checkbox";
        checkbox.className = "policy-checkbox";
        checkbox.disabled = true;
        checkbox.checked = false;
        checkbox.setAttribute("aria-label", `${policy.name} — not yet enforced, no policy definition exists`);

        const details = document.createElement("div");
        details.className = "policy-details";

        const name = document.createElement("span");
        name.className = "policy-name";
        name.textContent = policy.name;

        const description = document.createElement("span");
        description.className = "policy-description";
        description.textContent = `Policy: ${policy.id} · Catalog effects: ${policy.effects.join(", ")}`;

        const badge = document.createElement("span");
        badge.className = "badge badge-roadmap";
        badge.textContent = "not yet enforced — no policy definition exists";

        details.appendChild(name);
        details.appendChild(description);
        details.appendChild(badge);

        info.appendChild(checkbox);
        info.appendChild(details);
        item.appendChild(info);
        scopeDiv.appendChild(item);
      });

      roadmapWrap.appendChild(scopeDiv);
    }

    container.appendChild(roadmapWrap);
  }

  getFormData() {
    const primaryRegion = document.getElementById("primaryRegion")?.value || "westus";
    const secondaryRegion = document.getElementById("secondaryRegion")?.value || "eastus2";
    const allRegions = [primaryRegion];
    if (secondaryRegion && secondaryRegion !== primaryRegion) allRegions.push(secondaryRegion);

    document.querySelectorAll('select[name="additionalRegion"]').forEach(select => {
      if (select.value && !allRegions.includes(select.value)) {
        allRegions.push(select.value);
      }
    });

    return {
      orgName: document.getElementById("orgName")?.value || "Contoso",
      orgId: document.getElementById("orgId")?.value || "",
      primaryRegion,
      secondaryRegion,
      allRegions,
      firewallSku: document.querySelector('input[name="firewallSku"]:checked')?.value || "Standard",
      bastionHost: document.getElementById("bastionHost")?.checked ?? true,
      privateDnsZones: document.getElementById("privateDnsZones")?.checked ?? true,
      network: {
        hubCidr: document.getElementById("hubCidr")?.value || "10.0.0.0/16",
        spokeCidrs: (document.getElementById("spokeCidrs")?.value || "").split("\n").map(c => c.trim()).filter(Boolean),
      },
      tagging: {
        enabled: document.getElementById("tagEnforcement")?.checked ?? false,
        environment: document.getElementById("tagEnvironment")?.value || "prod",
        owner: document.getElementById("tagOwner")?.value || "",
        costCenter: document.getElementById("tagCostCenter")?.value || "",
        application: document.getElementById("tagApplication")?.value || "",
      }
    };
  }

  fileHeader(data, layer, sourceFile) {
    return [
      "# Generated by frontend/ (legacy .tfvars generator) on " + new Date().toISOString().split("T")[0] + ".",
      "# Layer:  " + layer,
      "# Org:    " + data.orgName,
      "#",
      "# LEGACY PATH: the site/ wizard is the primary generator. This file only",
      "# contains variables declared in " + sourceFile + ";",
      "# everything else the form shows is labelled in the UI and not emitted.",
      ""
    ].join("\n");
  }

  /** terraform.auto.tfvars — variables of terraform/live/global/variables.tf. */
  generateGlobalTfvars(data) {
    return this.fileHeader(data, "global", "terraform/live/global/variables.tf") + [
      `org_prefix        = ${hclString(data.orgId)}`,
      `allowed_locations = ${hclList(data.allRegions)}`,
      "",
      "# REQUIRED — fill these in before terraform plan. This legacy page does not",
      "# collect subscription IDs (the site/ wizard does). identity_subscription_id",
      "# is the only optional one (defaults to \"\").",
      '# management_subscription_id       = "00000000-0000-0000-0000-000000000000"',
      '# connectivity_subscription_id     = "00000000-0000-0000-0000-000000000000"',
      '# workload_prod_subscription_id    = "00000000-0000-0000-0000-000000000000"',
      '# workload_nonprod_subscription_id = "00000000-0000-0000-0000-000000000000"',
      '# sandbox_subscription_id          = "00000000-0000-0000-0000-000000000000"',
      '# identity_subscription_id         = ""',
      ""
    ].join("\n");
  }

  /** connectivity.auto.tfvars — variables of
   *  terraform/live/platform-connectivity/variables.tf. */
  generateConnectivityTfvars(data) {
    const out = [
      `primary_region            = ${hclString(data.primaryRegion)}`,
      `primary_region_code       = ${hclString(REGION_CODES[data.primaryRegion] || data.primaryRegion)}`,
      `dr_region                 = ${hclString(data.secondaryRegion)}`,
      `dr_region_code            = ${hclString(REGION_CODES[data.secondaryRegion] || data.secondaryRegion)}`,
      `primary_hub_address_space = ${hclString(data.network.hubCidr)}`,
      `firewall_type             = "azfw"`,
      `azfw_tier                 = ${hclString(data.firewallSku)}`,
      `deploy_bastion            = ${data.bastionHost}`,
      `deploy_dns                = ${data.privateDnsZones}`
    ];

    if (data.tagging.enabled) {
      const tags = [];
      // Keys match the required-tags policy (owner, application, environment,
      // cost_center) enforced at root by policy-baseline.
      if (data.tagging.owner) tags.push(`  owner       = ${hclString(data.tagging.owner)}`);
      if (data.tagging.application) tags.push(`  application = ${hclString(data.tagging.application)}`);
      if (data.tagging.environment) tags.push(`  environment = ${hclString(data.tagging.environment)}`);
      if (data.tagging.costCenter) tags.push(`  cost_center = ${hclString(data.tagging.costCenter)}`);
      if (tags.length) {
        out.push("");
        out.push("default_tags = {");
        out.push(...tags);
        out.push("}");
      }
    }

    out.push("");
    out.push("# REQUIRED — connectivity subscription ID (not collected by this page).");
    out.push('# connectivity_subscription_id = "00000000-0000-0000-0000-000000000000"');
    out.push("");
    out.push("# REQUIRED — operator-supplied; terraform plan fails until this is set.");
    out.push("# CIDR ranges permitted to reach firewall management interfaces. This is");
    out.push("# deliberately never collected by a generator (see");
    out.push("# factory/renderer/variable-map.json); '*' and '0.0.0.0/0' are rejected.");
    out.push('# management_ip_ranges = ["203.0.113.0/24"]');
    out.push("");
    out.push("# RECOMMENDED — Log Analytics workspace ID from the platform-management");
    out.push("# layer. Left unset, hub firewall diagnostics and threat-intel alerts are");
    out.push("# not created, and nothing else will warn about it.");
    out.push('# log_analytics_workspace_id = "<platform-management output log_analytics_workspace_id>"');

    if (data.network.spokeCidrs.length) {
      out.push("");
      out.push("# NOTE — spoke address space belongs to a different layer. Copy into");
      out.push("# terraform/live/workloads-prod tfvars by hand:");
      out.push(`#   primary_spoke_address_space = ${hclString(data.network.spokeCidrs[0])}`);
      if (data.network.spokeCidrs.length > 1) {
        out.push("# Additional spoke CIDRs entered in the form are not consumed by any");
        out.push("# stack (workloads-prod takes a single primary + optional DR space):");
        data.network.spokeCidrs.slice(1).forEach((c) => out.push(`#   ${c}`));
      }
    }
    out.push("");

    return this.fileHeader(data, "platform-connectivity", "terraform/live/platform-connectivity/variables.tf") + out.join("\n");
  }

  generateFiles() {
    const data = this.getFormData();
    return [
      { name: "terraform.auto.tfvars", content: this.generateGlobalTfvars(data) },
      { name: "connectivity.auto.tfvars", content: this.generateConnectivityTfvars(data) }
    ];
  }

  previewText() {
    return this.generateFiles()
      .map((f) => `# ══ file: ${f.name} ${"═".repeat(Math.max(4, 58 - f.name.length))}\n\n${f.content}`)
      .join("\n\n");
  }

  validate() {
    const data = this.getFormData();
    const errors = [];

    // org_prefix bound must match terraform/live/global/variables.tf
    // (^[a-z0-9]{2,10}$) — contract #1 in .claude/CROSS-DOMAIN-CONTRACTS.md.
    if (!data.orgId || !/^[a-z0-9]{2,10}$/.test(data.orgId)) {
      errors.push("Organization ID must be 2-10 lowercase alphanumeric characters (org_prefix validation in terraform/live/global).");
    }
    if (!data.primaryRegion) errors.push("Select a primary region.");
    if (!data.secondaryRegion) errors.push("Select a DR region.");
    if (data.secondaryRegion === data.primaryRegion) {
      errors.push("DR region must differ from the primary region.");
    }
    if (!data.network.hubCidr || !this.isValidCIDR(data.network.hubCidr)) {
      errors.push("Hub VNet CIDR must be a valid CIDR block (e.g., 10.0.0.0/16)");
    }
    if (data.network.spokeCidrs.length && !data.network.spokeCidrs.every(c => this.isValidCIDR(c))) {
      errors.push("Spoke VNet CIDRs must be valid CIDR blocks");
    }
    if (data.tagging.enabled && !data.tagging.owner) {
      errors.push("Tag enforcement is on: an owner tag value is required (the require-mandatory-tags policy denies resources without it).");
    }

    return errors;
  }

  isValidCIDR(cidr) {
    return /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$/.test(cidr);
  }

  generate() {
    const errors = this.validate();
    if (errors.length > 0) {
      alert("Form validation errors:\n\n" + errors.join("\n"));
      return;
    }

    const preview = document.getElementById("configPreview");
    if (preview) preview.textContent = this.previewText();

    const form = document.getElementById("deploymentForm");
    const previewCard = document.getElementById("previewCard");
    if (form) form.classList.add("hidden");
    if (previewCard) previewCard.classList.remove("hidden");

    window.scrollTo(0, 0);
  }

  downloadFile(filename, content) {
    const element = document.createElement("a");
    element.setAttribute("href", "data:text/plain;charset=utf-8," + encodeURIComponent(content));
    element.setAttribute("download", filename);
    element.style.display = "none";
    document.body.appendChild(element);
    element.click();
    document.body.removeChild(element);
  }

  download() {
    // One file per layer, named exactly as the layer's auto-loaded tfvars so
    // they drop straight into terraform/live/global/ and
    // terraform/live/platform-connectivity/.
    for (const f of this.generateFiles()) this.downloadFile(f.name, f.content);
  }

  copyToClipboard() {
    navigator.clipboard.writeText(this.previewText()).then(() => {
      const copyBtn = document.getElementById("copyBtn");
      const originalText = copyBtn?.textContent;
      if (copyBtn) {
        copyBtn.textContent = "✓ Copied!";
        setTimeout(() => {
          copyBtn.textContent = originalText;
        }, 2000);
      }
    }).catch(err => {
      console.error("Failed to copy:", err);
      alert("Failed to copy to clipboard. Please try again.");
    });
  }

  backToForm() {
    const form = document.getElementById("deploymentForm");
    const previewCard = document.getElementById("previewCard");
    if (form) form.classList.remove("hidden");
    if (previewCard) previewCard.classList.add("hidden");
    window.scrollTo(0, 0);
  }

  showForm() {
    const formSection = document.getElementById("formSection");
    if (formSection) formSection.classList.remove("hidden");
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Global Helper Functions (called from HTML)
// ═════════════════════════════════════════════════════════════════════════════

function updateNamingExamples() {
  const prefix = document.getElementById("orgId")?.value || "org";
  const region = document.getElementById("primaryRegion")?.value || "westus";

  const set = (id, text) => {
    const el = document.getElementById(id);
    if (el) el.textContent = text;
  };
  set("exampleStorageAccount", `st${prefix}prod001`);
  set("exampleVM", `vm-${prefix}-prod-001`);
  set("exampleVNet", `vnet-${prefix}-prod`);
  set("exampleRG", `rg-${prefix}-prod-${region}`);
}

function toggleTaggingFields() {
  const enforcement = document.getElementById("tagEnforcement");
  const fields = document.getElementById("taggingFields");
  const additional = document.getElementById("additionalTags");

  if (fields) fields.classList.toggle("hidden-section", !enforcement.checked);
  if (additional) additional.classList.toggle("hidden-section", !enforcement.checked);
}

function addRegion() {
  const container = document.getElementById("additionalRegionsList");
  if (!container) return;

  const div = document.createElement("div");
  div.className = "region-item";

  const select = document.createElement("select");
  select.name = "additionalRegion";
  select.setAttribute("aria-label", "Additional allowed region");
  Object.keys(REGION_CODES).forEach(region => {
    const option = document.createElement("option");
    option.value = region;
    option.textContent = region;
    select.appendChild(option);
  });

  const btn = document.createElement("button");
  btn.type = "button";
  btn.className = "btn btn-small";
  btn.textContent = "✕";
  btn.setAttribute("aria-label", "Remove this region");
  btn.onclick = () => div.remove();

  div.appendChild(select);
  div.appendChild(btn);
  container.appendChild(div);
}

// ═════════════════════════════════════════════════════════════════════════════
// Initialize on page load
// ═════════════════════════════════════════════════════════════════════════════

document.addEventListener("DOMContentLoaded", () => {
  new LegacyTfvarsGenerator();
});
