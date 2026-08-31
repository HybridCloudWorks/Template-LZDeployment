// GENERATED FILE. Do not hand-edit — regenerate with
// factory/ci/New-AlzPolicyCatalog.ps1, which emits this alongside
// alz-policy-catalog.json from the ALZ library ref pinned in
// factory-version.json.
//
// This exists because the wizard is zero-network by contract: the page's
// Content-Security-Policy sets connect-src 'none', so the .json sibling cannot
// be fetched at runtime. A same-origin script is allowed, so the catalog
// arrives as a global instead.
globalThis.ALZ_POLICY_CATALOG = {
  "$comment": "GENERATED FILE. Do not hand-edit. Produced by factory/ci/New-AlzPolicyCatalog.ps1 from the Azure Landing Zones library at the ref pinned in factory-version.json. The wizard reads this as a static asset because site/ makes zero network requests by contract.",
  "catalogVersion": "1.0.0",
  "library": {
    "path": "platform/alz",
    "ref": "2026.04.2",
    "architecture": "alz"
  },
  "managementGroups": [
    {
      "id": "alz",
      "displayName": "Azure Landing Zones",
      "parent": "",
      "archetypes": [
        "root"
      ]
    },
    {
      "id": "platform",
      "displayName": "Platform",
      "parent": "alz",
      "archetypes": [
        "platform"
      ]
    },
    {
      "id": "landingzones",
      "displayName": "Landing zones",
      "parent": "alz",
      "archetypes": [
        "landing_zones"
      ]
    },
    {
      "id": "corp",
      "displayName": "Corp",
      "parent": "landingzones",
      "archetypes": [
        "corp"
      ]
    },
    {
      "id": "online",
      "displayName": "Online",
      "parent": "landingzones",
      "archetypes": [
        "online"
      ]
    },
    {
      "id": "local",
      "displayName": "Local",
      "parent": "landingzones",
      "archetypes": [
        "local"
      ]
    },
    {
      "id": "sandbox",
      "displayName": "Sandbox",
      "parent": "alz",
      "archetypes": [
        "sandbox"
      ]
    },
    {
      "id": "security",
      "displayName": "Security",
      "parent": "platform",
      "archetypes": [
        "security"
      ]
    },
    {
      "id": "management",
      "displayName": "Management",
      "parent": "platform",
      "archetypes": [
        "management"
      ]
    },
    {
      "id": "connectivity",
      "displayName": "Connectivity",
      "parent": "platform",
      "archetypes": [
        "connectivity"
      ]
    },
    {
      "id": "identity",
      "displayName": "Identity",
      "parent": "platform",
      "archetypes": [
        "identity"
      ]
    },
    {
      "id": "decommissioned",
      "displayName": "Decommissioned",
      "parent": "alz",
      "archetypes": [
        "decommissioned"
      ]
    }
  ],
  "archetypes": {
    "connectivity": [
      "Enable-DDoS-VNET"
    ],
    "corp": [
      "Audit-PeDnsZones",
      "Deny-HybridNetworking",
      "Deny-Public-Endpoints",
      "Deny-Public-IP-On-NIC",
      "Deploy-Private-DNS-Zones"
    ],
    "decommissioned": [
      "Enforce-ALZ-Decomm"
    ],
    "identity": [
      "Deny-MgmtPorts-Internet",
      "Deny-Public-IP",
      "Deny-Subnet-Without-Nsg",
      "Deploy-VM-Backup"
    ],
    "landing_zones": [
      "Audit-AppGW-WAF",
      "Deny-IP-forwarding",
      "Deny-MgmtPorts-Internet",
      "Deny-Priv-Esc-AKS",
      "Deny-Privileged-AKS",
      "Deny-Storage-http",
      "Deny-Subnet-Without-Nsg",
      "Deploy-AzSqlDb-Auditing",
      "Deploy-GuestAttest",
      "Deploy-MDFC-DefSQL-AMA",
      "Deploy-SQL-TDE",
      "Deploy-SQL-Threat",
      "Deploy-VM-Backup",
      "Deploy-VM-ChangeTrack",
      "Deploy-VM-Monitoring",
      "Deploy-vmArc-ChangeTrack",
      "Deploy-vmHybr-Monitoring",
      "Deploy-VMSS-ChangeTrack",
      "Deploy-VMSS-Monitoring",
      "Enable-AUM-CheckUpdates",
      "Enable-DDoS-VNET",
      "Enforce-AKS-HTTPS",
      "Enforce-ASR",
      "Enforce-Encrypt-CMK0",
      "Enforce-GR-APIM0",
      "Enforce-GR-AppServices0",
      "Enforce-GR-Automation0",
      "Enforce-GR-BotService0",
      "Enforce-GR-CogServ0",
      "Enforce-GR-Compute0",
      "Enforce-GR-ContApps0",
      "Enforce-GR-ContInst0",
      "Enforce-GR-ContReg0",
      "Enforce-GR-CosmosDb0",
      "Enforce-GR-DataExpl0",
      "Enforce-GR-DataFactory0",
      "Enforce-GR-EventGrid0",
      "Enforce-GR-EventHub0",
      "Enforce-GR-KeyVault",
      "Enforce-GR-KeyVaultSup0",
      "Enforce-GR-Kubernetes0",
      "Enforce-GR-MachLearn0",
      "Enforce-GR-MySQL0",
      "Enforce-GR-Network0",
      "Enforce-GR-OpenAI0",
      "Enforce-GR-PostgreSQL0",
      "Enforce-GR-ServiceBus0",
      "Enforce-GR-SQL0",
      "Enforce-GR-Storage0",
      "Enforce-GR-Synapse0",
      "Enforce-GR-VirtualDesk0",
      "Enforce-Subnet-Private",
      "Enforce-TLS-SSL-Q225"
    ],
    "local": [
      "Enforce-ALDO-Services"
    ],
    "management": [],
    "online": [],
    "platform": [
      "DenyAction-DeleteUAMIAMA",
      "Deploy-GuestAttest",
      "Deploy-MDFC-DefSQL-AMA",
      "Deploy-VM-ChangeTrack",
      "Deploy-VM-Monitoring",
      "Deploy-vmArc-ChangeTrack",
      "Deploy-vmHybr-Monitoring",
      "Deploy-VMSS-ChangeTrack",
      "Deploy-VMSS-Monitoring",
      "Enable-AUM-CheckUpdates",
      "Enforce-ASR",
      "Enforce-Encrypt-CMK0",
      "Enforce-GR-APIM0",
      "Enforce-GR-AppServices0",
      "Enforce-GR-Automation0",
      "Enforce-GR-BotService0",
      "Enforce-GR-CogServ0",
      "Enforce-GR-Compute0",
      "Enforce-GR-ContApps0",
      "Enforce-GR-ContInst0",
      "Enforce-GR-ContReg0",
      "Enforce-GR-CosmosDb0",
      "Enforce-GR-DataExpl0",
      "Enforce-GR-DataFactory0",
      "Enforce-GR-EventGrid0",
      "Enforce-GR-EventHub0",
      "Enforce-GR-KeyVault",
      "Enforce-GR-KeyVaultSup0",
      "Enforce-GR-Kubernetes0",
      "Enforce-GR-MachLearn0",
      "Enforce-GR-MySQL0",
      "Enforce-GR-Network0",
      "Enforce-GR-OpenAI0",
      "Enforce-GR-PostgreSQL0",
      "Enforce-GR-ServiceBus0",
      "Enforce-GR-SQL0",
      "Enforce-GR-Storage0",
      "Enforce-GR-Synapse0",
      "Enforce-GR-VirtualDesk0",
      "Enforce-Subnet-Private"
    ],
    "root": [
      "Audit-ResourceRGLocation",
      "Audit-TrustedLaunch",
      "Audit-UnusedResources",
      "Audit-ZoneResiliency",
      "Deny-Classic-Resources",
      "Deny-UnmanagedDisk",
      "Deploy-ASC-Monitoring",
      "Deploy-AzActivity-Log",
      "Deploy-Diag-LogsCat",
      "Deploy-MCSB2-Monitoring",
      "Deploy-MDEndpoints",
      "Deploy-MDEndpointsAMA",
      "Deploy-MDFC-Config-H224",
      "Deploy-MDFC-OssDb",
      "Deploy-MDFC-SqlAtp",
      "Deploy-SvcHealth-BuiltIn",
      "Enforce-ACSB"
    ],
    "sandbox": [
      "Enforce-ALZ-Sandbox"
    ],
    "security": []
  },
  "defaults": {
    "private_dns_zone_subscription_id": {
      "description": "The subscription id that hosts the private link DNS zones.",
      "consumedBy": [
        {
          "assignment": "Deploy-Private-DNS-Zones",
          "parameters": [
            "dnsZoneSubscriptionId"
          ]
        }
      ],
      "supplied": "factory"
    },
    "private_dns_zone_resource_group_name": {
      "description": "The resource group name that hosts the private link DNS zones.",
      "consumedBy": [
        {
          "assignment": "Deploy-Private-DNS-Zones",
          "parameters": [
            "dnsZoneResourceGroupName"
          ]
        }
      ],
      "supplied": "factory"
    },
    "private_dns_zone_region": {
      "description": "The region short name (e.g. `westus`) that should be used for the region specific private link DNS zones.",
      "consumedBy": [
        {
          "assignment": "Deploy-Private-DNS-Zones",
          "parameters": [
            "dnsZoneRegion"
          ]
        }
      ],
      "supplied": "factory"
    },
    "ama_user_assigned_managed_identity_id": {
      "description": "The user assigned managed identity id that should be used for the AMA deployment.",
      "consumedBy": [
        {
          "assignment": "Deploy-VM-ChangeTrack",
          "parameters": [
            "userAssignedIdentityResourceId"
          ]
        },
        {
          "assignment": "Deploy-VMSS-ChangeTrack",
          "parameters": [
            "userAssignedIdentityResourceId"
          ]
        },
        {
          "assignment": "Deploy-VM-Monitoring",
          "parameters": [
            "userAssignedIdentityResourceId"
          ]
        },
        {
          "assignment": "Deploy-VMSS-Monitoring",
          "parameters": [
            "userAssignedIdentityResourceId"
          ]
        },
        {
          "assignment": "Deploy-MDFC-DefSQL-AMA",
          "parameters": [
            "userAssignedIdentityResourceId"
          ]
        }
      ],
      "supplied": "factory"
    },
    "ama_user_assigned_managed_identity_name": {
      "description": "The user assigned managed identity name that is used for the deny action policy to prevent the accidental deletion of the AMA identity.",
      "consumedBy": [
        {
          "assignment": "DenyAction-DeleteUAMIAMA",
          "parameters": [
            "resourceName"
          ]
        }
      ],
      "supplied": "factory"
    },
    "ama_vm_insights_data_collection_rule_id": {
      "description": "The data collection rule id that should be used for the VM Insights deployment.",
      "consumedBy": [
        {
          "assignment": "Deploy-VM-Monitoring",
          "parameters": [
            "dcrResourceId"
          ]
        },
        {
          "assignment": "Deploy-VMSS-Monitoring",
          "parameters": [
            "dcrResourceId"
          ]
        },
        {
          "assignment": "Deploy-vmHybr-Monitoring",
          "parameters": [
            "dcrResourceId"
          ]
        }
      ],
      "supplied": "factory"
    },
    "ama_mdfc_sql_data_collection_rule_id": {
      "description": "The data collection rule id that should be used for the SQL MDFC deployment.",
      "consumedBy": [
        {
          "assignment": "Deploy-MDFC-DefSQL-AMA",
          "parameters": [
            "dcrResourceId"
          ]
        }
      ],
      "supplied": "factory"
    },
    "ama_change_tracking_data_collection_rule_id": {
      "description": "The data collection rule id that should be used for the change tracking deployment.",
      "consumedBy": [
        {
          "assignment": "Deploy-VM-ChangeTrack",
          "parameters": [
            "dcrResourceId"
          ]
        },
        {
          "assignment": "Deploy-vmArc-ChangeTrack",
          "parameters": [
            "dcrResourceId"
          ]
        },
        {
          "assignment": "Deploy-VMSS-ChangeTrack",
          "parameters": [
            "dcrResourceId"
          ]
        }
      ],
      "supplied": "factory"
    },
    "ddos_protection_plan_id": {
      "description": "The DDoS protection plan id that should be used for the DDoS protection plan deployment. If this is invalid or you do not use DDoS protection, make sure to change the enforcement mode of the Enable-DDoS-VNET policy to 'DoNotEnforce'.",
      "consumedBy": [
        {
          "assignment": "Enable-DDoS-VNET",
          "parameters": [
            "ddosPlan"
          ]
        }
      ],
      "supplied": "none"
    },
    "log_analytics_workspace_id": {
      "description": "The Log Analytics workspace id that should be used for centralized log collection.",
      "consumedBy": [
        {
          "assignment": "Deploy-AzActivity-Log",
          "parameters": [
            "logAnalytics"
          ]
        },
        {
          "assignment": "Deploy-AzSqlDb-Auditing",
          "parameters": [
            "logAnalyticsWorkspaceId"
          ]
        },
        {
          "assignment": "Deploy-Diag-LogsCat",
          "parameters": [
            "logAnalytics"
          ]
        },
        {
          "assignment": "Deploy-MDFC-Config-H224",
          "parameters": [
            "logAnalytics"
          ]
        },
        {
          "assignment": "Deploy-MDFC-DefSQL-AMA",
          "parameters": [
            "userWorkspaceResourceId"
          ]
        }
      ],
      "supplied": "factory"
    },
    "resource_group_location": {
      "description": "The default location for resource groups. This is used for policies that create resource groups without a specified location.",
      "consumedBy": [
        {
          "assignment": "Deploy-MDFC-Config-H224",
          "parameters": [
            "ascExportResourceGroupLocation"
          ]
        },
        {
          "assignment": "Deploy-SvcHealth-BuiltIn",
          "parameters": [
            "resourceGroupLocation"
          ]
        }
      ],
      "supplied": "factory"
    },
    "resource_group_name_service_health_alerts": {
      "description": "The default resource group name for service health alerts. This is used for the Deploy-SvcHealth-BuiltIn policy assignment to create the necessary resources for service health alerting.",
      "consumedBy": [
        {
          "assignment": "Deploy-SvcHealth-BuiltIn",
          "parameters": [
            "resourceGroupName"
          ]
        }
      ],
      "supplied": "factory"
    },
    "resource_group_name_mdfc": {
      "description": "The default resource group name for microsoft defender for cloud export. This is used for the Deploy-MDFC-Config-H224 policy assignment to create the necessary resources.",
      "consumedBy": [
        {
          "assignment": "Deploy-MDFC-Config-H224",
          "parameters": [
            "ascExportResourceGroupName"
          ]
        }
      ],
      "supplied": "factory"
    },
    "email_security_contact": {
      "description": "The default email address for the security contact. This is used for the Deploy-MDFC-Config-H224 policy assignment to set up the security contact in Microsoft Defender for Cloud.",
      "consumedBy": [
        {
          "assignment": "Deploy-MDFC-Config-H224",
          "parameters": [
            "emailSecurityContact"
          ]
        }
      ],
      "supplied": "none"
    }
  },
  "assignments": {
    "Audit-AppGW-WAF": {
      "archetypes": [
        "landing_zones"
      ],
      "managementGroups": [
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Audit-PeDnsZones": {
      "archetypes": [
        "corp"
      ],
      "managementGroups": [
        "corp"
      ],
      "requiredDefaults": []
    },
    "Audit-ResourceRGLocation": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Audit-TrustedLaunch": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Audit-UnusedResources": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Audit-ZoneResiliency": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Deny-Classic-Resources": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Deny-HybridNetworking": {
      "archetypes": [
        "corp"
      ],
      "managementGroups": [
        "corp"
      ],
      "requiredDefaults": []
    },
    "Deny-IP-forwarding": {
      "archetypes": [
        "landing_zones"
      ],
      "managementGroups": [
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Deny-MgmtPorts-Internet": {
      "archetypes": [
        "identity",
        "landing_zones"
      ],
      "managementGroups": [
        "identity",
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Deny-Priv-Esc-AKS": {
      "archetypes": [
        "landing_zones"
      ],
      "managementGroups": [
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Deny-Privileged-AKS": {
      "archetypes": [
        "landing_zones"
      ],
      "managementGroups": [
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Deny-Public-Endpoints": {
      "archetypes": [
        "corp"
      ],
      "managementGroups": [
        "corp"
      ],
      "requiredDefaults": []
    },
    "Deny-Public-IP": {
      "archetypes": [
        "identity"
      ],
      "managementGroups": [
        "identity"
      ],
      "requiredDefaults": []
    },
    "Deny-Public-IP-On-NIC": {
      "archetypes": [
        "corp"
      ],
      "managementGroups": [
        "corp"
      ],
      "requiredDefaults": []
    },
    "Deny-Storage-http": {
      "archetypes": [
        "landing_zones"
      ],
      "managementGroups": [
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Deny-Subnet-Without-Nsg": {
      "archetypes": [
        "identity",
        "landing_zones"
      ],
      "managementGroups": [
        "identity",
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Deny-UnmanagedDisk": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "DenyAction-DeleteUAMIAMA": {
      "archetypes": [
        "platform"
      ],
      "managementGroups": [
        "platform"
      ],
      "requiredDefaults": [
        "ama_user_assigned_managed_identity_name"
      ]
    },
    "Deploy-ASC-Monitoring": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Deploy-AzActivity-Log": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": [
        "log_analytics_workspace_id"
      ]
    },
    "Deploy-AzSqlDb-Auditing": {
      "archetypes": [
        "landing_zones"
      ],
      "managementGroups": [
        "landingzones"
      ],
      "requiredDefaults": [
        "log_analytics_workspace_id"
      ]
    },
    "Deploy-Diag-LogsCat": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": [
        "log_analytics_workspace_id"
      ]
    },
    "Deploy-GuestAttest": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Deploy-MCSB2-Monitoring": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Deploy-MDEndpoints": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Deploy-MDEndpointsAMA": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Deploy-MDFC-Config-H224": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": [
        "email_security_contact",
        "log_analytics_workspace_id",
        "resource_group_location",
        "resource_group_name_mdfc"
      ]
    },
    "Deploy-MDFC-DefSQL-AMA": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": [
        "ama_mdfc_sql_data_collection_rule_id",
        "ama_user_assigned_managed_identity_id",
        "log_analytics_workspace_id"
      ]
    },
    "Deploy-MDFC-OssDb": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Deploy-MDFC-SqlAtp": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Deploy-Private-DNS-Zones": {
      "archetypes": [
        "corp"
      ],
      "managementGroups": [
        "corp"
      ],
      "requiredDefaults": [
        "private_dns_zone_region",
        "private_dns_zone_resource_group_name",
        "private_dns_zone_subscription_id"
      ]
    },
    "Deploy-SQL-TDE": {
      "archetypes": [
        "landing_zones"
      ],
      "managementGroups": [
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Deploy-SQL-Threat": {
      "archetypes": [
        "landing_zones"
      ],
      "managementGroups": [
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Deploy-SvcHealth-BuiltIn": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": [
        "resource_group_location",
        "resource_group_name_service_health_alerts"
      ]
    },
    "Deploy-VM-Backup": {
      "archetypes": [
        "identity",
        "landing_zones"
      ],
      "managementGroups": [
        "identity",
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Deploy-VM-ChangeTrack": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": [
        "ama_change_tracking_data_collection_rule_id",
        "ama_user_assigned_managed_identity_id"
      ]
    },
    "Deploy-VM-Monitoring": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": [
        "ama_user_assigned_managed_identity_id",
        "ama_vm_insights_data_collection_rule_id"
      ]
    },
    "Deploy-vmArc-ChangeTrack": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": [
        "ama_change_tracking_data_collection_rule_id"
      ]
    },
    "Deploy-vmHybr-Monitoring": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": [
        "ama_vm_insights_data_collection_rule_id"
      ]
    },
    "Deploy-VMSS-ChangeTrack": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": [
        "ama_change_tracking_data_collection_rule_id",
        "ama_user_assigned_managed_identity_id"
      ]
    },
    "Deploy-VMSS-Monitoring": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": [
        "ama_user_assigned_managed_identity_id",
        "ama_vm_insights_data_collection_rule_id"
      ]
    },
    "Enable-AUM-CheckUpdates": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enable-DDoS-VNET": {
      "archetypes": [
        "connectivity",
        "landing_zones"
      ],
      "managementGroups": [
        "connectivity",
        "landingzones"
      ],
      "requiredDefaults": [
        "ddos_protection_plan_id"
      ]
    },
    "Enforce-ACSB": {
      "archetypes": [
        "root"
      ],
      "managementGroups": [
        "alz"
      ],
      "requiredDefaults": []
    },
    "Enforce-AKS-HTTPS": {
      "archetypes": [
        "landing_zones"
      ],
      "managementGroups": [
        "landingzones"
      ],
      "requiredDefaults": []
    },
    "Enforce-ALDO-Services": {
      "archetypes": [
        "local"
      ],
      "managementGroups": [
        "local"
      ],
      "requiredDefaults": []
    },
    "Enforce-ALZ-Decomm": {
      "archetypes": [
        "decommissioned"
      ],
      "managementGroups": [
        "decommissioned"
      ],
      "requiredDefaults": []
    },
    "Enforce-ALZ-Sandbox": {
      "archetypes": [
        "sandbox"
      ],
      "managementGroups": [
        "sandbox"
      ],
      "requiredDefaults": []
    },
    "Enforce-ASR": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-Encrypt-CMK0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-APIM0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-AppServices0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-Automation0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-BotService0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-CogServ0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-Compute0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-ContApps0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-ContInst0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-ContReg0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-CosmosDb0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-DataExpl0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-DataFactory0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-EventGrid0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-EventHub0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-KeyVault": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-KeyVaultSup0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-Kubernetes0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-MachLearn0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-MySQL0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-Network0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-OpenAI0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-PostgreSQL0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-ServiceBus0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-SQL0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-Storage0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-Synapse0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-GR-VirtualDesk0": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-Subnet-Private": {
      "archetypes": [
        "landing_zones",
        "platform"
      ],
      "managementGroups": [
        "landingzones",
        "platform"
      ],
      "requiredDefaults": []
    },
    "Enforce-TLS-SSL-Q225": {
      "archetypes": [
        "landing_zones"
      ],
      "managementGroups": [
        "landingzones"
      ],
      "requiredDefaults": []
    }
  },
  "groups": [
    {
      "id": "ddos",
      "label": "DDoS network protection",
      "summary": "Attaches an Azure DDoS Network Protection plan to every virtual network. The plan itself is roughly USD 2,900/month and is NOT created by this factory — enabling this group requires an existing plan ID.",
      "assignments": [
        "Enable-DDoS-VNET"
      ],
      "requiredDefaults": [
        "ddos_protection_plan_id"
      ]
    },
    {
      "id": "defender",
      "label": "Microsoft Defender for Cloud",
      "summary": "Defender plans, security contact, and the Defender-for-SQL agent estate. Every plan parameter defaults to Disabled in the library, so enabling this group costs nothing until plans are turned on.",
      "assignments": [
        "Deploy-ASC-Monitoring",
        "Deploy-MCSB2-Monitoring",
        "Deploy-MDEndpoints",
        "Deploy-MDEndpointsAMA",
        "Deploy-MDFC-Config-H224",
        "Deploy-MDFC-DefSQL-AMA",
        "Deploy-MDFC-OssDb",
        "Deploy-MDFC-SqlAtp"
      ],
      "requiredDefaults": [
        "ama_mdfc_sql_data_collection_rule_id",
        "ama_user_assigned_managed_identity_id",
        "email_security_contact",
        "log_analytics_workspace_id",
        "resource_group_location",
        "resource_group_name_mdfc"
      ]
    },
    {
      "id": "vm-monitoring",
      "label": "VM monitoring, change tracking and updates",
      "summary": "Azure Monitor Agent, VM Insights, change tracking and update management. Needs the managed identity and data collection rules the management layer creates.",
      "assignments": [
        "DenyAction-DeleteUAMIAMA",
        "Deploy-GuestAttest",
        "Deploy-VM-ChangeTrack",
        "Deploy-VM-Monitoring",
        "Deploy-vmArc-ChangeTrack",
        "Deploy-vmHybr-Monitoring",
        "Deploy-VMSS-ChangeTrack",
        "Deploy-VMSS-Monitoring",
        "Enable-AUM-CheckUpdates"
      ],
      "requiredDefaults": [
        "ama_change_tracking_data_collection_rule_id",
        "ama_user_assigned_managed_identity_id",
        "ama_user_assigned_managed_identity_name",
        "ama_vm_insights_data_collection_rule_id"
      ]
    },
    {
      "id": "private-dns",
      "label": "Private DNS zones for private endpoints",
      "summary": "Central private DNS zone records for private endpoints, created in the connectivity subscription.",
      "assignments": [
        "Audit-PeDnsZones",
        "Deploy-Private-DNS-Zones"
      ],
      "requiredDefaults": [
        "private_dns_zone_region",
        "private_dns_zone_resource_group_name",
        "private_dns_zone_subscription_id"
      ]
    },
    {
      "id": "service-health",
      "label": "Service health alerts",
      "summary": "Azure Service Health alert rules and their action group.",
      "assignments": [
        "Deploy-SvcHealth-BuiltIn"
      ],
      "requiredDefaults": [
        "resource_group_location",
        "resource_group_name_service_health_alerts"
      ]
    },
    {
      "id": "platform-diagnostics",
      "label": "Platform diagnostic settings",
      "summary": "Routes activity logs and resource diagnostics to the platform Log Analytics workspace. Additive: it does not replace diagnostic settings a resource already has.",
      "assignments": [
        "Deploy-AzActivity-Log",
        "Deploy-AzSqlDb-Auditing",
        "Deploy-Diag-LogsCat"
      ],
      "requiredDefaults": [
        "log_analytics_workspace_id"
      ]
    },
    {
      "id": "network-restrictions",
      "label": "Network restrictions",
      "summary": "Denies public endpoints, public IPs on NICs, management ports open to the internet, subnets without an NSG, and hybrid networking. The sharpest group in the set for an estate with public-facing services.",
      "assignments": [
        "Deny-HybridNetworking",
        "Deny-IP-forwarding",
        "Deny-MgmtPorts-Internet",
        "Deny-Public-Endpoints",
        "Deny-Public-IP",
        "Deny-Public-IP-On-NIC",
        "Deny-Subnet-Without-Nsg",
        "Enforce-Subnet-Private"
      ],
      "requiredDefaults": []
    },
    {
      "id": "service-guardrails",
      "label": "Per-service guardrails",
      "summary": "The Enforce-GR-* family: per-service hardening initiatives for storage, Key Vault, SQL, Kubernetes, OpenAI and the rest. Most ship with enforcement disarmed in the library.",
      "assignments": [
        "Enforce-GR-APIM0",
        "Enforce-GR-AppServices0",
        "Enforce-GR-Automation0",
        "Enforce-GR-BotService0",
        "Enforce-GR-CogServ0",
        "Enforce-GR-Compute0",
        "Enforce-GR-ContApps0",
        "Enforce-GR-ContInst0",
        "Enforce-GR-ContReg0",
        "Enforce-GR-CosmosDb0",
        "Enforce-GR-DataExpl0",
        "Enforce-GR-DataFactory0",
        "Enforce-GR-EventGrid0",
        "Enforce-GR-EventHub0",
        "Enforce-GR-KeyVault",
        "Enforce-GR-KeyVaultSup0",
        "Enforce-GR-Kubernetes0",
        "Enforce-GR-MachLearn0",
        "Enforce-GR-MySQL0",
        "Enforce-GR-Network0",
        "Enforce-GR-OpenAI0",
        "Enforce-GR-PostgreSQL0",
        "Enforce-GR-ServiceBus0",
        "Enforce-GR-SQL0",
        "Enforce-GR-Storage0",
        "Enforce-GR-Synapse0",
        "Enforce-GR-VirtualDesk0"
      ],
      "requiredDefaults": []
    },
    {
      "id": "data-protection",
      "label": "Data protection and encryption",
      "summary": "Transparent data encryption, SQL threat detection, VM backup, site recovery, customer-managed keys, and TLS/HTTPS enforcement.",
      "assignments": [
        "Deny-Storage-http",
        "Deploy-SQL-TDE",
        "Deploy-SQL-Threat",
        "Deploy-VM-Backup",
        "Enforce-AKS-HTTPS",
        "Enforce-ASR",
        "Enforce-Encrypt-CMK0",
        "Enforce-TLS-SSL-Q225"
      ],
      "requiredDefaults": []
    },
    {
      "id": "aks-hardening",
      "label": "Kubernetes hardening",
      "summary": "Denies privileged and privilege-escalating containers in AKS.",
      "assignments": [
        "Deny-Priv-Esc-AKS",
        "Deny-Privileged-AKS"
      ],
      "requiredDefaults": []
    },
    {
      "id": "resource-hygiene",
      "label": "Resource hygiene and audit",
      "summary": "Audit-only checks plus bans on classic and unmanaged-disk resources. Cheap to leave on: these report, they do not block.",
      "assignments": [
        "Audit-AppGW-WAF",
        "Audit-ResourceRGLocation",
        "Audit-TrustedLaunch",
        "Audit-UnusedResources",
        "Audit-ZoneResiliency",
        "Deny-Classic-Resources",
        "Deny-UnmanagedDisk",
        "Enforce-ACSB",
        "Enforce-ALDO-Services"
      ],
      "requiredDefaults": []
    },
    {
      "id": "mg-lifecycle",
      "label": "Sandbox and decommissioned guardrails",
      "summary": "The lifecycle guardrails attached to the sandbox and decommissioned management groups.",
      "assignments": [
        "Enforce-ALZ-Decomm",
        "Enforce-ALZ-Sandbox"
      ],
      "requiredDefaults": []
    }
  ],
  "ungrouped": []
};
