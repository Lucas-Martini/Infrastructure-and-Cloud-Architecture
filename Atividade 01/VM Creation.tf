#----------------------- DECLARA O TERRAFORM -----------------------
terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.0.1"
    }
  }
}

#----------------------- PULA A ETAPA DE AUTENTICAÇÃO -----------------------
provider "azurerm" {
  skip_provider_registration = true
    features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

#----------------------- CRIA GRUPO DE RECURSO -----------------------
resource "azurerm_resource_group" "GrupoRecurso-Atividade01" {
  name     = "GrupoRecurso-Atividade01"
  location = "eastus"
}

#----------------------- CRIA REDE VIRTUAL -----------------------
resource "azurerm_virtual_network" "RedeVirtual-Atividade01" {
  name                = "RedeVirtual-Atividade01"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.GrupoRecurso-Atividade01.location
  resource_group_name = azurerm_resource_group.GrupoRecurso-Atividade01.name
}

#----------------------- CRIA SUB-REDE -----------------------
resource "azurerm_subnet" "SubedeVirtual-Atividade01" {
  name                 = "SubedeVirtual-Atividade01"
  resource_group_name  = azurerm_resource_group.GrupoRecurso-Atividade01.name
  virtual_network_name = azurerm_virtual_network.RedeVirtual-Atividade01.name
  address_prefixes     = ["10.0.2.0/24"]
}

#----------------------- CRIA IP PÚBLICO -----------------------
resource "azurerm_public_ip" "IpPublico-Atividade01" {
    name                         = "IpPublico-Atividade01"
    location                     = "eastus"
    resource_group_name          = azurerm_resource_group.GrupoRecurso-Atividade01.name
    allocation_method            = "Static"
}

#----------------------- CRIA "PLACA DE REDE" -----------------------
resource "azurerm_network_interface" "PlacaRede-Atividade01" {
  name                = "PlacaRede-Atividade01"
  location            = azurerm_resource_group.GrupoRecurso-Atividade01.location
  resource_group_name = azurerm_resource_group.GrupoRecurso-Atividade01.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.SubedeVirtual-Atividade01.id
    private_ip_address_allocation = "Dynamic"
	public_ip_address_id          = azurerm_public_ip.IpPublico-Atividade01.id
  }
}

#----------------------- CRIA GRUPO DE SEGURANÇA -----------------------
resource "azurerm_network_security_group" "GrupoSeguranca-Atividade01" {
    name                = "GrupoSeguranca-Atividade01"
    location            = "eastus"
    resource_group_name = azurerm_resource_group.GrupoRecurso-Atividade01.name

    security_rule {
        name                       = "ConexaoSSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
	
	    security_rule {
        name                       = "ConexaoHTTP"
		priority                   = 1003
		direction                  = "Inbound"
		access                     = "Allow"
		protocol                   = "Tcp"
		source_port_range          = "*"
		destination_port_range     = "80"
		source_address_prefix      = "*"
		destination_address_prefix = "*"
    }
}

#----------------------- ASSOCIA "PLACA DE REDE" AO GRUPO DE SEGURANÇA -----------------------
resource "azurerm_network_interface_security_group_association" "AssocGrupoSeguranca-Atividade01" {
    network_interface_id      = azurerm_network_interface.PlacaRede-Atividade01.id
    network_security_group_id = azurerm_network_security_group.GrupoSeguranca-Atividade01.id
}

#----------------------- CRIA CRIA CHAVE PRIVADA -----------------------
resource "tls_private_key" "ChavePrivada-Atividade01" {
    algorithm = "RSA"
    rsa_bits = 4096
}
#----------------------- SALVA CHAVE PRIVADA LOCALMENTE -----------------------
resource "local_file" "ArquivoChavePrivada-Atividade01" {
  content         = tls_private_key.ChavePrivada-Atividade01.private_key_pem
  filename        = "ChavePrivada.pem"
  file_permission = "0600"
}

#----------------------- CRIA MÁQUINA VIRTUAL -----------------------
resource "azurerm_linux_virtual_machine" "MaquinaVirtual-Atividade01" {
  name                = "MaquinaVirtual-Atividade01"
  resource_group_name = azurerm_resource_group.GrupoRecurso-Atividade01.name
  location            = azurerm_resource_group.GrupoRecurso-Atividade01.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.PlacaRede-Atividade01.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key     = tls_private_key.ChavePrivada-Atividade01.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}

#----------------------- DEFINI QUE AS INSTALAÇÃO SÓ DEVEM SEGUIR A PARTIR DO MOMENTO QUE A VM E REDE ESTIVEREM PRONTAS -----------------------
data "azurerm_public_ip" "DataIpPublico-Atividade01"{
    name = azurerm_public_ip.IpPublico-Atividade01.name
    resource_group_name = azurerm_resource_group.GrupoRecurso-Atividade01.name
}

#----------------------- INSTALA O APACHE -----------------------
resource "null_resource" "InstalaApache" {
  triggers = {
    order = azurerm_linux_virtual_machine.MaquinaVirtual-Atividade01.id
  }

  connection {
    type = "ssh"
    host = data.azurerm_public_ip.DataIpPublico-Atividade01.ip_address
    user = "adminuser"
    private_key = tls_private_key.ChavePrivada-Atividade01.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y apache2",
    ]
  }
}