# State migration for repositories generated before the corpus↔live
# reconciliation (docs/plans/corpus-live-reconciliation.md, WP4).
#
# The metric alert was renamed from the original CPU-alert scaffold to the
# ingestion-volume alert it actually implements. Without this block, a
# regenerated repository re-planning against existing state would destroy
# `cpu_high` and create `ingestion_volume_high`. With it, Terraform renames
# the address in place.
#
# Note: the Azure-side resource NAME also changed
# (`alert-cpu-<org>` → `alert-log-ingestion-<org>`), and metric-alert names
# force replacement — the moved block preserves the state address, but the
# first apply after regeneration still replaces the alert resource itself
# (momentary alerting gap; no data loss). That delete action trips the apply
# workflow's destroy-refusal gate; the operator path past it is documented in
# the generated upgrade guide (docs/upgrade-guide.md, "Known replacement
# boundary: management-baseline alert rename").
#
# This file is deliberately corpus-only: the live tree performed the rename
# directly and carries no legacy state under the old address.

moved {
  from = azurerm_monitor_metric_alert.cpu_high
  to   = azurerm_monitor_metric_alert.ingestion_volume_high
}
