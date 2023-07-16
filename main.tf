terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "ansible_test" {
  name = "ansible_test"
  location = var.location
}

resource "azurerm_virtual_network" "ansible_vnet" {
  name = "ansible"
  address_space = ["10.0.0.0/16"]
  location = var.location
  resource_group_name = azurerm_resource_group.ansible_test.name
}

resource "azurerm_subnet" "ansible_host_subnet" {
  name = "ansible_host"
  resource_group_name = azurerm_resource_group.ansible_test.name
  virtual_network_name = azurerm_virtual_network.ansible_vnet.name
  address_prefixes = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "ansible_slaves_subnet" {
  name = "ansible_slaves"
  resource_group_name = azurerm_resource_group.ansible_test.name
  virtual_network_name = azurerm_virtual_network.ansible_vnet.name
  address_prefixes = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "ansible_host_pip" {
  name = "ansible_pip"
  resource_group_name = azurerm_resource_group.ansible_test.name
  location = var.location
  allocation_method = "Dynamic"
}

resource "azurerm_public_ip" "ansible_slave_pip" {
  #implement a var that when true, create pip for slaves, if false, dont create
  count = 3
  name = "ansible_slave${count.index}_pip"
  resource_group_name = azurerm_resource_group.ansible_test.name
  location = var.location
  allocation_method = "Dynamic"
}

resource "azurerm_network_interface" "host_nic" {
  name = "ansible_host_nic"
  location = var.location
  resource_group_name = azurerm_resource_group.ansible_test.name

  ip_configuration {
    name = "host_ip"
    subnet_id = azurerm_subnet.ansible_host_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.ansible_host_pip.id
  }
}

# https://developer.hashicorp.com/terraform/language/meta-arguments/count

resource "azurerm_network_interface" "slave_nics" {
  count = 3
  name = "ansible_slave_nic${count.index}"
  location = var.location
  resource_group_name = azurerm_resource_group.ansible_test.name

  ip_configuration {
    name = "slave_ip${count.index}"
    subnet_id = azurerm_subnet.ansible_slaves_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.ansible_slave_pip[count.index].id
  }
}

resource "azurerm_network_security_group" "nsg_host" {
  name = "nsg_host"
  location = var.location
  resource_group_name = azurerm_resource_group.ansible_test.name

  security_rule {
    name = "allow_22_ssh"
    priority = 200
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = 22
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet_host_to_nsg" {
  subnet_id = azurerm_subnet.ansible_host_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_host.id
}

resource "azurerm_network_security_group" "nsg_slaves" {
  name = "nsg_slaves"
  location = var.location
  resource_group_name = azurerm_resource_group.ansible_test.name

  security_rule {
    name = "allow_22_ssh"
    priority = 200
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = 22
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name = "allow_80"
    priority = 210
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = 80
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  
}

resource "azurerm_subnet_network_security_group_association" "subnet_slave_to_nsg" {
  subnet_id = azurerm_subnet.ansible_slaves_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_slaves.id
}

resource "azurerm_linux_virtual_machine" "ansible_host_vm" {
  name = "ansible-host"
  resource_group_name = azurerm_resource_group.ansible_test.name
  location = var.location
  size = "Standard_F2"
  admin_username = var.username
  admin_password = var.password
  disable_password_authentication = false

  network_interface_ids = [ 
    azurerm_network_interface.host_nic.id,
   ]

  os_disk {
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "test_script" {
  name = "ariel"
  virtual_machine_id = azurerm_linux_virtual_machine.ansible_host_vm.id
  publisher = "Microsoft.Azure.Extensions"
  type = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
  {
    "commandToExecute": "echo 'hello world' > /test.txt"
  }
SETTINGS
}

resource "azurerm_linux_virtual_machine" "ansible_slave_vms" {
  count = 3
  name = "ansible-slave-${count.index}"
  resource_group_name = azurerm_resource_group.ansible_test.name
  location = var.location
  size = "Standard_F2"
  admin_username = var.username
  admin_password = var.password
  disable_password_authentication = false

  network_interface_ids = [ 
    azurerm_network_interface.slave_nics[count.index].id,
   ]

  os_disk {
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }
}



#TODO
# add a script that terraform will execute on control node to set up ansible
  # curl -LJO https://raw.githubusercontent.com/arieluchka/ansibletest-terraform/main/test.txt
  #
# add a script to slaves to install python to latest version
