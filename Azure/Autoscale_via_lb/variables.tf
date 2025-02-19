# Variables

variable "sp_subscription_id" {
  type        = string
  default     = ""
  description = "This is the service principal subscription ID"
}
variable "sp_client_id" {
  type        = string
  default     = ""
  description = "This is the service principal application/client ID"
}
variable "sp_client_secret" {
  type        = string
  default     = ""
  description = "This is the service principal secret"
}
variable "sp_tenant_id" {
  type        = string
  default     = ""
  description = "This is the service principal tenant ID"
}
variable "prefix" {
  type        = string
  default     = "demo"
  description = "This value is inserted at the beginning of each Azure object (alpha-numeric, no special character)"
}
variable "location" {
  type        = string
  default     = null
  description = "Azure Location of the deployment"
}
variable "uname" {
  type        = string
  default     = "azureuser"
  description = "User name for the Virtual Machine"
}
variable "upassword" {
  type        = string
  default     = "Default12345!"
  description = "Password for the Virtual Machine"
}
variable "cidr" {
  type        = string
  default     = "10.90.0.0/16"
  description = "CIDR IP Address range of the Virtual Network"
}
variable "subnets" {
  type = map(any)
  default = {
    "subnet1" = "10.90.1.0/24"
    "subnet2" = "10.90.2.0/24"
    "subnet3" = "10.90.3.0/24"
  }
  description = "Subnet IP range of the management network (subnet1), external network (subnet2), and internal network (subnet3)"
}

variable "backend01ext" {
  type        = string
  default     = "10.90.2.101"
  description = "IP address for backend origin server"
}
variable "ext_gw" {
  type        = string
  default     = "10.90.2.1"
  description = "Default gateway for external subnet"
}
variable "instance_type" {
  type        = string
  default     = "Standard_DS4_v2"
  description = "Azure instance type to be used for the BIG-IP VE"
}
variable "image_name" {
  type        = string
  default     = "f5-bigip-virtual-edition-1g-best-hourly"
  description = "F5 SKU (image) to deploy. Note: The disk size of the VM will be determined based on the option you select.  **Important**: If intending to provision multiple modules, ensure the appropriate value is selected, such as ****AllTwoBootLocations or AllOneBootLocation****."
}
variable "product" {
  type        = string
  default     = "f5-big-ip-best"
  description = "Azure BIG-IP VE Offer"
}
variable "bigip_version" {
  type        = string
  default     = "15.1.201000"
  description = "BIG-IP Version"
}
# BIGIP Setup
variable "dns_server" {
  type        = string
  default     = "8.8.8.8"
  description = "Leave the default DNS server the BIG-IP uses, or replace the default DNS server with the one you want to use"
}
variable "ntp_server" {
  type        = string
  default     = "0.us.pool.ntp.org"
  description = "Leave the default NTP server the BIG-IP uses, or replace the default NTP server with the one you want to use"
}
variable "timezone" {
  type        = string
  default     = "UTC"
  description = "If you would like to change the time zone the BIG-IP uses, enter the time zone you want to use. This is based on the tz database found in /usr/share/zoneinfo (see the full list [here](https://github.com/F5Networks/f5-azure-arm-templates/blob/master/azure-timezone-list.md)). Example values: UTC, US/Pacific, US/Eastern, Europe/London or Asia/Singapore."
}
variable "DO_URL" {
  type        = string
  default     = "https://github.com/F5Networks/f5-declarative-onboarding/releases/download/v1.23.0/f5-declarative-onboarding-1.23.0-4.noarch.rpm"
  description = "URL to download the BIG-IP Declarative Onboarding module"
}
variable "AS3_URL" {
  type        = string
  default     = "https://github.com/F5Networks/f5-appsvcs-extension/releases/download/v3.30.0/f5-appsvcs-3.30.0-5.noarch.rpm"
  description = "URL to download the BIG-IP Application Service Extension 3 (AS3) module"
}
variable "TS_URL" {
  type        = string
  default     = "https://github.com/F5Networks/f5-telemetry-streaming/releases/download/v1.22.0/f5-telemetry-1.22.0-1.noarch.rpm"
  description = "URL to download the BIG-IP Telemetry Streaming module"
}
variable "onboard_log" {
  type        = string
  default     = "/var/log/startup-script.log"
  description = "This is where the onboarding script logs all the events"
}
variable "libs_dir" {
  type        = string
  default     = "/config/cloud/azure/node_modules"
  description = "This is where all the temporary libs and RPM will be store in BIG-IP"
}
variable "bigIqHost" {
  type        = string
  default     = ""
  description = "This is the BIG-IQ License Manager host name or IP address"
}
variable "bigIqUsername" {
  type        = string
  default     = "azureuser"
  description = "Admin name for BIG-IQ"
}
variable "bigIqPassword" {
  type        = string
  default     = "Default12345!"
  description = "Admin Password for BIG-IQ"
}
variable "bigIqLicenseType" {
  type        = string
  default     = "licensePool"
  description = "BIG-IQ license type"
}
variable "bigIqLicensePool" {
  type        = string
  default     = ""
  description = "BIG-IQ license pool name"
}
variable "bigIqSkuKeyword1" {
  type        = string
  default     = "key1"
  description = "BIG-IQ license SKU keyword 1"
}
variable "bigIqSkuKeyword2" {
  type        = string
  default     = "key2"
  description = "BIG-IQ license SKU keyword 2"
}
variable "bigIqUnitOfMeasure" {
  type        = string
  default     = "hourly"
  description = "BIG-IQ license unit of measure"
}
variable "bigIqHypervisor" {
  type        = string
  default     = "azure"
  description = "BIG-IQ hypervisor"
}
variable "owner" {
  type        = string
  default     = null
  description = "This is a tag used for object creation. Example is last name."
}
