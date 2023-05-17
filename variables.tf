variable "rsg_name" {
  type        = string
  description = "The name of the resource group"
}

variable "location" {
  type        = string
  description = "The location/region for the deployment"
  default     = "West Europe"
}

variable "vm_size" {
  type        = string
  description = "Name of the performance SKU for the VM"
  default     = "Standard_B2ms"
}

variable "vm_name" {
  type        = string
  description = "Name of the virtual machine"
}

variable "admin_username" {
  type        = string
  description = "Username for the VM's local administrator account"
}

variable "admin_password" {
  type        = string
  description = "Password for the VM's local administrator account"
}

variable "timezone" {
  type        = string
  description = "Timezone for the VM and Backup Policy"
  default     = "Central European Standard Time"
}

variable "auto_shutdown_time" {
  type        = string
  description = "Time when the VM should shutdown and deallocate"
  default     = "0600"
}

variable "nsg_rules" {
  type = list(object({
    name                   = string
    protocol               = string
    source_port_range      = string
    source_address_prefix  = string
    destination_port_range = string
  }))
  description = "List of the Security Rule values for specific games"
}

variable "allow_rdp_from" {
  type        = list(any)
  description = "List of public IP addresses allowed to connect to the VM through RDP"
}

variable "custom_role_name" {
  type        = string
  description = "Name of the custom administrator role"
  default     = "VM Operator Admin"
}

variable "selected_users" {
  type        = list(string)
  description = "List of Azure AD users to be assigned the role of VM Operator Admin"
}