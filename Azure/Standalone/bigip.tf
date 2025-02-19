# BIG-IP

# Create Public IPs
resource "azurerm_public_ip" "vm01mgmtpip" {
  name                = "${var.prefix}-vm01-mgmt-pip"
  location            = data.azurerm_resource_group.main.location
  sku                 = "Standard"
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  tags = {
    owner = var.owner
  }
}

resource "azurerm_public_ip" "vm01selfpip" {
  name                = "${var.prefix}-vm01-self-pip"
  location            = data.azurerm_resource_group.main.location
  sku                 = "Standard"
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  tags = {
    owner = var.owner
  }
}

resource "azurerm_public_ip" "pubvippip" {
  name                = "${var.prefix}-pubvip-pip"
  location            = data.azurerm_resource_group.main.location
  sku                 = "Standard"
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  tags = {
    owner = var.owner
  }
}

# Create NIC for Management
resource "azurerm_network_interface" "vm01-mgmt-nic" {
  name                = "${var.prefix}-mgmt0"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = data.azurerm_subnet.mgmt.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.f5vm01mgmt
    public_ip_address_id          = azurerm_public_ip.vm01mgmtpip.id
  }

  tags = {
    owner = var.owner
  }
}

# Create NIC for External
resource "azurerm_network_interface" "vm01-ext-nic" {
  name                 = "${var.prefix}-ext0"
  location             = data.azurerm_resource_group.main.location
  resource_group_name  = data.azurerm_resource_group.main.name
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = data.azurerm_subnet.external.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.f5vm01ext
    primary                       = true
    public_ip_address_id          = azurerm_public_ip.vm01selfpip.id
  }

  ip_configuration {
    name                          = "secondary1"
    subnet_id                     = data.azurerm_subnet.external.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.f5privatevip
  }

  ip_configuration {
    name                          = "secondary2"
    subnet_id                     = data.azurerm_subnet.external.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.f5publicvip
    public_ip_address_id          = azurerm_public_ip.pubvippip.id
  }

  tags = {
    owner = var.owner
  }
}

# Create NIC for Internal
resource "azurerm_network_interface" "vm01-int-nic" {
  name                 = "${var.prefix}-int0"
  location             = data.azurerm_resource_group.main.location
  resource_group_name  = data.azurerm_resource_group.main.name
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = data.azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    primary                       = true
  }

  ip_configuration {
    name                          = "secondary"
    subnet_id                     = data.azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = {
    owner = var.owner
  }
}


# Setup Onboarding scripts
data "template_file" "vm_onboard" {
  template = file("${path.module}/onboard.tpl")

  vars = {
    admin_user     = var.uname
    admin_password = var.upassword
    DO_URL         = var.DO_URL
    AS3_URL        = var.AS3_URL
    TS_URL         = var.TS_URL
    libs_dir       = var.libs_dir
    onboard_log    = var.onboard_log
  }
}

data "template_file" "vm01_do_json" {
  template = file("${path.module}/do.json")

  vars = {
    regKey         = var.license1
    host1          = var.host1_name
    local_host     = var.host1_name
    local_selfip   = var.f5vm01ext
    gateway        = var.ext_gw
    dns_server     = var.dns_server
    ntp_server     = var.ntp_server
    timezone       = var.timezone
    admin_user     = var.uname
    admin_password = var.upassword
  }
}

data "template_file" "as3_json" {
  template = file("${path.module}/as3.json")

  vars = {
    subscription_id = var.sp_subscription_id
    tenant_id       = var.sp_tenant_id
    client_id       = var.sp_client_id
    client_secret   = var.sp_client_secret
    backendvm_ip    = var.backend01ext
    publicvip       = var.f5publicvip
    privatevip      = var.f5privatevip
  }
}

data "template_file" "ts_json" {
  template = file("${path.module}/ts.json")

  vars = {
    region      = var.location
    law_id      = azurerm_log_analytics_workspace.law.workspace_id
    law_primkey = azurerm_log_analytics_workspace.law.primary_shared_key
  }
}

# Create F5 BIG-IP VMs
resource "azurerm_linux_virtual_machine" "f5vm01" {
  name                            = "${var.prefix}-f5vm01"
  location                        = data.azurerm_resource_group.main.location
  resource_group_name             = data.azurerm_resource_group.main.name
  network_interface_ids           = [azurerm_network_interface.vm01-mgmt-nic.id, azurerm_network_interface.vm01-ext-nic.id, azurerm_network_interface.vm01-int-nic.id]
  size                            = var.instance_type
  admin_username                  = var.uname
  admin_password                  = var.upassword
  disable_password_authentication = false
  computer_name                   = "${var.prefix}vm01"
  custom_data                     = base64encode(data.template_file.vm_onboard.rendered)

  os_disk {
    name                 = "${var.prefix}vm01-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "f5-networks"
    offer     = var.product
    sku       = var.image_name
    version   = var.bigip_version
  }

  plan {
    name      = var.image_name
    publisher = "f5-networks"
    product   = var.product
  }

  tags = {
    owner = var.owner
  }
}

# Run Startup Script
resource "azurerm_virtual_machine_extension" "f5vm01-run-startup-cmd" {
  name                 = "${var.prefix}-f5vm01-run-startup-cmd"
  virtual_machine_id   = azurerm_linux_virtual_machine.f5vm01.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
    {
        "commandToExecute": "bash /var/lib/waagent/CustomData; exit 0;"
    }
  SETTINGS

  tags = {
    owner = var.owner
  }
}

# Run REST API for configuration
resource "local_file" "vm01_do_file" {
  content  = data.template_file.vm01_do_json.rendered
  filename = "${path.module}/${var.rest_vm01_do_file}"
}

resource "local_file" "vm_as3_file" {
  content  = data.template_file.as3_json.rendered
  filename = "${path.module}/${var.rest_vm_as3_file}"
}

resource "local_file" "vm_ts_file" {
  content  = data.template_file.ts_json.rendered
  filename = "${path.module}/${var.rest_vm_ts_file}"
}

resource "null_resource" "f5vm01_DO" {
  depends_on = [azurerm_virtual_machine_extension.f5vm01-run-startup-cmd]
  # Running DO REST API
  provisioner "local-exec" {
    command = <<-EOF
      #!/bin/bash
      curl -k -X ${var.rest_do_method} https://${azurerm_public_ip.vm01mgmtpip.ip_address}${var.rest_do_uri} -u ${var.uname}:${var.upassword} -d @${var.rest_vm01_do_file}
      x=1; while [ $x -le 30 ]; do STATUS=$(curl -s -k -X GET https://${azurerm_public_ip.vm01mgmtpip.ip_address}/mgmt/shared/declarative-onboarding/task -u ${var.uname}:${var.upassword}); if ( echo $STATUS | grep "OK" ); then break; fi; sleep 10; x=$(( $x + 1 )); done
      sleep 10
    EOF
  }
}

resource "null_resource" "f5vm01_TS" {
  depends_on = [null_resource.f5vm01_DO]
  # Running TS REST API
  provisioner "local-exec" {
    command = <<-EOF
      #!/bin/bash
      curl -H 'Content-Type: application/json' -k -X POST https://${azurerm_public_ip.vm01mgmtpip.ip_address}${var.rest_ts_uri} -u ${var.uname}:${var.upassword} -d @${var.rest_vm_ts_file}
    EOF
  }
}

resource "null_resource" "f5vm_AS3" {
  depends_on = [null_resource.f5vm01_TS]
  # Running AS3 REST API
  provisioner "local-exec" {
    command = <<-EOF
      #!/bin/bash
      curl -k -X ${var.rest_as3_method} https://${azurerm_public_ip.vm01mgmtpip.ip_address}${var.rest_as3_uri} -u ${var.uname}:${var.upassword} -d @${var.rest_vm_as3_file}
    EOF
  }
}
