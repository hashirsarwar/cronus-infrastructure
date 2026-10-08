# NSGs retain Azure's default private-network rules; public node ports are explicit environment inputs.
# Use separate rule resources because azurerm 5 removed inline rules.

resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks"
  resource_group_name = azurerm_virtual_network.this.resource_group_name
  location            = azurerm_virtual_network.this.location
  tags                = var.tags
}

# Open only ports an environment intentionally publishes; an empty list leaves public ingress closed.
# The Gateway's public address alone cannot bypass the NSG.
# DNS-01 needs no inbound port; future HTTP-to-HTTPS redirects still need port 80.
resource "azurerm_network_security_rule" "aks_public_ingress" {
  for_each = local.public_ingress_rules

  name                        = each.key
  resource_group_name         = azurerm_network_security_group.aks.resource_group_name
  network_security_group_name = azurerm_network_security_group.aks.name
  description                 = "Port ${each.value.port} from the internet to the Gateway API ingress."

  # The group's own default rules run from 65000, so these are evaluated before them. A list
  # rather than a set, so that the priorities follow the order the ports were listed in.
  priority = each.value.priority

  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = tostring(each.value.port)

  source_address_prefix = "Internet"

  # Floating IP preserves the public VIP and port, so subnet-prefix matches would drop Gateway traffic.
  # Use * for destinations; the NSG still limits this grant to the node subnet and published TCP ports.
  destination_address_prefix = "*"
}

# Instance keys are the rule names, so a rule's address in state names the rule; the priority
# follows the order the entries are listed in, which is what makes a second port an addition
# rather than a renumbering of the first.
locals {
  public_ingress_rules = {
    for index, rule in var.public_ingress : rule.name => {
      port     = rule.port
      priority = 100 + index
    }
  }
}

# Preserve both the state address and rule name during generalization.
# Replacing the live HTTP rule would temporarily close the port.
moved {
  from = azurerm_network_security_rule.aks_http_inbound
  to   = azurerm_network_security_rule.aks_public_ingress["allow-http-inbound"]
}

resource "azurerm_network_security_group" "postgres" {
  name                = "nsg-postgres"
  resource_group_name = azurerm_virtual_network.this.resource_group_name
  location            = azurerm_virtual_network.this.location
  tags                = var.tags
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-private-endpoints"
  resource_group_name = azurerm_virtual_network.this.resource_group_name
  location            = azurerm_virtual_network.this.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_subnet_network_security_group_association" "postgres" {
  subnet_id                 = azurerm_subnet.postgres.id
  network_security_group_id = azurerm_network_security_group.postgres.id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}
