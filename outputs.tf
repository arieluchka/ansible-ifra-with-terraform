output "host_public" {
  value = azurerm_public_ip.ansible_host_pip.ip_address
}