output "vnetIdHub" {
  description = "Hub VNet ID"
  value       = module.network["hub"].vnet_id
}
output "vnetIdSpoke1" {
  description = "Spoke1 VNet ID"
  value       = module.network["spoke1"].vnet_id
}
output "vnetIdSpoke2" {
  description = "Spoke2 VNet ID"
  value       = module.network["spoke2"].vnet_id
}
output "bigipPublicIP" {
  description = "The public ip address allocated for the BIG-IP"
  value       = module.bigip.*.mgmtPublicIP
}
output "bigipUserName" {
  description = "The user name for the BIG-IP"
  value       = module.bigip.*.f5_username
}
output "bigipPassword" {
  description = <<-EOT
 "The password for the BIG-IP"( if dynamic_password is choosen it will be random generated password or if azure_keyvault is choosen it will be key vault secret name )
  EOT
  value       = module.bigip.*.bigip_password
}
