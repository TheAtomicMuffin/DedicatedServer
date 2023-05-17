terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.54.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "2.37.0"
    }
  }
}

provider "azurerm" {
  features {}
}
provider "azuread" {
}

resource "azurerm_resource_group" "rg" {
  name     = var.rsg_name
  location = var.location
}

#------- Virtual Network --------

resource "azurerm_virtual_network" "vnet" {
  name                = "VirtualNetwork"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet1" {
  name                 = "Subnet1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                    = "Public_IP"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  allocation_method       = "Static"
  idle_timeout_in_minutes = 30
}

resource "azurerm_network_interface" "nic" {
  name                = "NIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

#------- Virtual Machine --------

resource "azurerm_windows_virtual_machine" "server_vm" {
  name                  = var.vm_name
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = var.vm_size
  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_username = var.admin_username
  admin_password = var.admin_password
  timezone       = var.timezone

  os_disk {
    name                 = "OS_disk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter-smalldisk-g2"
    version   = "latest"
  }
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "vm_auto_shutdown" {
  virtual_machine_id = azurerm_windows_virtual_machine.server_vm.id
  location           = azurerm_resource_group.rg.location
  enabled            = true

  daily_recurrence_time = var.auto_shutdown_time
  timezone              = azurerm_windows_virtual_machine.server_vm.timezone

  notification_settings {
    enabled = false
  }
}

#----- Custom Script Extension for local PowerShell script file --------

data "template_file" "tf" {
  template = file("config.ps1")
}
resource "azurerm_virtual_machine_extension" "custom_script_extension" {
  name                 = "CustomScriptExtension"
  virtual_machine_id   = azurerm_windows_virtual_machine.server_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<SETTINGS
  { 
    "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.tf.rendered)}')) | Out-File -filepath config.ps1\" && powershell -ExecutionPolicy Unrestricted -File config.ps1"
  }
  SETTINGS
}

#------- Network Security Group (NSG) with associated Security Rules --------

data "http" "myip" {
  url = "https://ifconfig.me/ip"
}

resource "azurerm_network_security_group" "nsg" {
  name                = "NSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowRDP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefixes    = toset(concat(var.allow_rdp_from, [data.http.myip.response_body]))
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = var.nsg_rules
    content {
      name                       = security_rule.value["name"]
      priority                   = 150 + index(var.nsg_rules, security_rule.value)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = security_rule.value["protocol"]
      source_port_range          = security_rule.value["source_port_range"]
      source_address_prefix      = security_rule.value["source_address_prefix"]
      destination_port_range     = security_rule.value["destination_port_range"]
      destination_address_prefix = azurerm_network_interface.nic.private_ip_address
    }
  }
}
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.subnet1.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

#------- Recovery Service Vault and Azure Backup --------

resource "azurerm_recovery_services_vault" "recovery_vault" {
  name                = "SpelserverVault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
}

resource "azurerm_backup_policy_vm" "vm_backup_policy" {
  name                = "vm_backup_policy"
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.recovery_vault.name
  timezone            = azurerm_windows_virtual_machine.server_vm.timezone

  backup {
    frequency = "Daily"
    time      = "21:00"
  }
  retention_daily {
    count = 7
  }
  instant_restore_resource_group {
    prefix = "VM_Backup"
  }
  instant_restore_retention_days = 2
}

resource "azurerm_backup_protected_vm" "backup_server_vm" {
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.recovery_vault.name
  source_vm_id        = azurerm_windows_virtual_machine.server_vm.id
  backup_policy_id    = azurerm_backup_policy_vm.vm_backup_policy.id
}

#------- Log Analytics Workspace and VM Insights --------

resource "azurerm_log_analytics_workspace" "law" {
  name                       = "LogAnalyticsWorkspace"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  sku                        = "PerGB2018"
  retention_in_days          = "30"
}

resource "azurerm_log_analytics_solution" "vm_insights" {
  solution_name         = "VMInsights"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  workspace_resource_id = azurerm_log_analytics_workspace.law.id
  workspace_name        = azurerm_log_analytics_workspace.law.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/VMInsights"
  }
}

resource "azurerm_virtual_machine_extension" "dependency_agent" {
  name                       = "DependencyAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.server_vm.id
  publisher                  = "Microsoft.Azure.Monitoring.DependencyAgent"
  type                       = "DependencyAgentWindows"
  type_handler_version       = "9.10"
  auto_upgrade_minor_version = true
}

resource "azurerm_virtual_machine_extension" "monitor_agent" {
  name                       = "MicrosoftMonitoringAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.server_vm.id
  publisher                  = "Microsoft.EnterpriseCloud.Monitoring"
  type                       = "MicrosoftMonitoringAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {"workspaceId": "${azurerm_log_analytics_workspace.law.workspace_id}"}
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {"workspaceKey": "${azurerm_log_analytics_workspace.law.primary_shared_key}"}
  PROTECTED_SETTINGS

  depends_on = [azurerm_windows_virtual_machine.server_vm, azurerm_log_analytics_workspace.law]
}

#------- Custom Role Definition --------

data "azurerm_subscription" "primary" {
}

resource "azurerm_role_definition" "custom_role_definition" {
  name        = "VM Operator Admin"
  scope       = data.azurerm_subscription.primary.id
  description = "Permission to start/stop VMs and configure NSG Security Rules"

  permissions {
    actions = [
      "Microsoft.Compute/*/read",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/restart/action",
      "Microsoft.Compute/virtualMachines/deallocate/action",
      "Microsoft.Network/publicIPAddresses/read",
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Network/networkInterfaces/read",
      "Microsoft.Network/networkSecurityGroups/*/read",
      "Microsoft.Network/networkSecurityGroups/securityRules/write",
      "Microsoft.Network/networkSecurityGroups/securityRules/delete"
    ]
    data_actions = []
    not_actions  = []
  }
  assignable_scopes = [
    data.azurerm_subscription.primary.id
  ]
}

#------- VM Operator Admin role assignments --------

data "azuread_user" "user" {
  for_each            = toset(var.selected_users)
  user_principal_name = format("%s", each.key)
}

resource "azurerm_role_assignment" "custom_role_assignment" {
  for_each = data.azuread_user.user

  scope                = azurerm_resource_group.rg.id
  role_definition_name = azurerm_role_definition.custom_role_definition.name
  principal_id         = data.azuread_user.user[each.key].object_id
}
