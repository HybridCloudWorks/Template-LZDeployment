Deliberately tiny stand-in for the Azure Landing Zones library, used only by
`Test-CI.ps1` to exercise `New-AlzPolicyCatalog.ps1`'s transformation without
reaching the network. It mirrors the real library's *shape* — a flat
management-group list carrying `parent_id`, archetype files listing assignment
names, and a defaults file mapping each default to the assignments and
parameters that consume it — not its content. Nothing here is vendored into a
generated repository.
