# Decision 0012 — Hub subnet NSG scope: the three design answers for item 2.16

- **Status**: **Accepted** — operator-answered in-session 2026-08-15.
  Implemented the same day (DNS resolver and private-endpoint NSGs;
  `fw_trust`/`fw_untrust` re-scoped as vendor-conditional).
- **Date**: 2026-08-15 (authored, answered, and implemented)
- **Deciders**: operator (answered in-session 2026-08-15);
  `terraform-module-engineer` (implementation)
- **Technical depth**: L200 (rule derivation over settled mechanisms)

## Context and Problem Statement

[TODO.md](../../TODO.md) item 2.16 left five hub subnets without NSGs after
Bastion shipped (2026-08-10), and recorded — checked, not assumed — that the
remainder was **gated on design input this repository did not hold**:
Microsoft publishes no NSG rule set for DNS Private Resolver subnets, the NVA
data-path subnets follow the appliance vendor's guidance, and the
private-endpoint subnet's correct sources depend on which spokes must reach
which endpoint. Writing rules without those inputs would be guessing at a
security control.

The operator supplied the three missing answers in-session on 2026-08-15.

## The three answers

**These are estate answers, not factory constraints.** They describe the
operator's own landing zone and derive the rule sets shipped in the generic
module; the factory itself stays generic, and a client whose answers differ
tunes the same variables rather than forking the module.

1. **Firewall type is `azfw`** for the operator's estate. `fw_trust` and
   `fw_untrust` therefore never exist there — the hub-network module creates
   them for `palo`/`fortinet` hubs only. Because the factory stays generic
   and the rules for those subnets are the NVA vendor's, no vendor NSG is
   authored: item 2.16's residual is re-scoped to **vendor-conditional
   product work**, done when an NVA estate needs it, with a nil estate-need
   for the operator.
2. **The DNS Private Resolver is queried from spoke VNets only** — no
   on-premises ranges. That makes the `dns_inbound`/`dns_outbound` NSGs
   derivable with no client-subnet enumeration: resolver traffic is 53
   TCP+UDP from the `VirtualNetwork` service tag, which covers the hub and
   every peered spoke. A future on-premises range is one added allow rule per
   NSG.
3. **The private-endpoint subnet is reached over 443 from the
   flow-log-hosting spoke ranges only** — the endpoints hosted there today
   are the flow-log storage endpoints (items 2.10/2.11). The connectivity
   layer cannot derive spoke CIDRs (the workload layers read its state,
   never the reverse), so the ranges are operator-supplied via
   `private_endpoint_allowed_source_prefixes`, exactly as
   `private_endpoint_subnet_prefix` is. Empty associates the NSG with no
   custom rules — Azure's default rules govern, the pre-NSG behaviour —
   because an allowlist nobody populated would deny everything and silently
   break the flow-log endpoints.

## Decision

Ship NSGs for `dns_inbound`, `dns_outbound` and `private_endpoints` in the
`hub-network` module, both trees at parity, following the Bastion NSG's
house pattern (count-gating on the same condition as the subnet, explicit
deny terminators, count-indexed associations — which checkov cannot resolve,
so the `CKV2_AZURE_31` suppressions are rewritten to that truth rather than
removed). Do **not** author `fw_trust`/`fw_untrust` NSGs; narrow item 2.16
to that vendor-conditional residual and keep it open.

The new NSGs are deliberately **not** added to the module's `nsg_ids`
output: that output feeds the connectivity layer's flow-log calls, and
widening it would change flow-log scope, which decision 0009 set. Same
posture as the Bastion NSG.

## Consequences

- **Positive**: ten of the twelve `CKV2_AZURE_31` findings per estate now
  have the control present rather than suppressed-as-not-done; the DNS
  NSGs cannot block resolver traffic (53 TCP+UDP allowed, no custom
  outbound rules); the private-endpoint NSG defaults to a no-op
  association, so no shipped path breaks until an operator opts into the
  allowlist.
- **Negative**: the `dns_outbound` NSG's inbound 53 allow is inert (that
  endpoint originates queries), carried for pair-parity; the
  private-endpoint allowlist is another operator-supplied value that can
  be forgotten (the default is then no filtering, not breakage);
  `fw_trust`/`fw_untrust` remain suppressed until an NVA estate funds the
  vendor rule work.
- **Follow-up**: `private_endpoint_allowed_source_prefixes` is a new
  root-level connectivity variable — flagged to
  `frontend-experience-designer`; it is mapped `literal:operator-supplied`
  (contract #4 shape) and deliberately not collected by the wizard.
