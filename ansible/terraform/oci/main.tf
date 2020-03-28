provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

data "oci_identity_availability_domains" "infra" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id = var.tenancy_ocid

  operating_system         = "Canonical Ubuntu"
  operating_system_version = "18.04"

  # exclude GPU specific images
  filter {
    name   = "display_name"
    values = ["^([a-zA-z]+)-([a-zA-z]+)-([\\.0-9]+)-([\\.0-9-]+)$"]
    regex  = true
  }
}

resource "oci_identity_compartment" "infra" {
  description   = "${var.prefix}-${var.my_name} infra compartment"
  name          = "${var.prefix}-${var.my_name}-oic"
  enable_delete = true
  freeform_tags = var.tags
}

resource "oci_core_vcn" "infra" {
  cidr_block     = var.vcn_cidr_block
  dns_label      = "${var.prefix}${var.my_name}"
  compartment_id = oci_identity_compartment.infra.id
  display_name   = "${var.prefix}-${var.my_name}-vcn"
  freeform_tags  = var.tags
}

resource "oci_core_internet_gateway" "infra" {
  compartment_id = oci_identity_compartment.infra.id
  display_name   = "${var.prefix}-${var.my_name}-ig"
  vcn_id         = oci_core_vcn.infra.id
  freeform_tags  = var.tags
}

resource "oci_core_default_route_table" "infra" {
  manage_default_resource_id = oci_core_vcn.infra.default_route_table_id
  display_name               = "${var.prefix}-${var.my_name}-default-route-table"
  freeform_tags              = var.tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.infra.id
  }
}

resource "oci_core_default_dhcp_options" "infra" {
  manage_default_resource_id = oci_core_vcn.infra.default_dhcp_options_id
  display_name               = "${var.prefix}-${var.my_name}-default-dhcp-options"
  freeform_tags              = var.tags

  options {
    type        = "DomainNameServer"
    server_type = "CustomDnsServer"
    custom_dns_servers = [ "1.1.1.1", "8.8.8.8" ]
  }
  options {
    type                = "SearchDomain"
    search_domain_names = [ var.my_domain ]
  }
}

resource "oci_core_default_security_list" "infra" {
  manage_default_resource_id = oci_core_vcn.infra.default_security_list_id
  display_name               = "${var.prefix}-${var.my_name}-default-security-list"
  freeform_tags              = var.tags

  // allow outbound traffic on all ports
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  // allow inbound ssh traffic
  ingress_security_rules {
    protocol  = "6" // tcp
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  // allow inbound http traffic
  ingress_security_rules {
    protocol  = "6" // tcp
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 80
      max = 80
    }
  }

  // allow inbound http traffic
  ingress_security_rules {
    protocol  = "6" // tcp
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 443
      max = 443
    }
  }

  // allow inbound icmp traffic of a specific type
  ingress_security_rules {
    protocol  = 1
    source    = "0.0.0.0/0"
    stateless = true

    icmp_options {
      type = 3
      code = 4
    }
  }
  ingress_security_rules {
    protocol = "1"
    source = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "infra" {
  availability_domain = lookup(data.oci_identity_availability_domains.infra.availability_domains[0], "name")
  cidr_block          = cidrsubnet(var.vcn_cidr_block, 8, 1)
  display_name        = "${var.prefix}-${var.my_name}-subnet-01"
  compartment_id      = oci_identity_compartment.infra.id
  vcn_id              = oci_core_vcn.infra.id
  security_list_ids   = [ oci_core_vcn.infra.default_security_list_id ]
  route_table_id      = oci_core_vcn.infra.default_route_table_id
  dhcp_options_id     = oci_core_vcn.infra.default_dhcp_options_id
  dns_label           = var.my_name
  freeform_tags       = var.tags
}

resource "oci_core_instance" "infra" {
  count               = var.vm_count
  availability_domain = lookup(data.oci_identity_availability_domains.infra.availability_domains[0], "name")
  compartment_id      = oci_identity_compartment.infra.id
  display_name        = format("%s%02d.%s", var.my_name, count.index + 1, var.my_domain)
  shape               = var.instance_shape
  freeform_tags       = var.tags
  hostname_label      = format("%s%02d", var.my_name, count.index + 1)

  agent_config {
    is_monitoring_disabled = false
  }

  create_vnic_details {
    subnet_id     = oci_core_subnet.infra.id
    display_name  = "primaryvnic"
    freeform_tags = var.tags
  }

  metadata = {
    ssh_authorized_keys = chomp(file(var.ssh_public_key))
    user_data = base64encode("#cloud-config\nhostname: ${format("%s%02d", var.my_name, count.index + 1)}\nfqdn: ${format("%s%02d.%s", var.my_name, count.index + 1, var.my_domain)}\n")
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images.0.id
    boot_volume_size_in_gbs = "50"
  }
}

provider "cloudflare" {
  email   = var.cloudflare_email
  api_key = var.cloudflare_api_key
}

data "cloudflare_zones" "infra" {
  filter {
    name   = var.my_domain
    status = "active"
    paused = false
  }
}

resource "cloudflare_record" "infra-vms" {
  count   = var.vm_count
  zone_id = lookup(data.cloudflare_zones.infra.zones[0], "id")
  name    = split(".", element(oci_core_instance.infra.*.display_name, count.index))[0]
  value   = element(oci_core_instance.infra.*.public_ip, count.index)
  type    = "A"
  ttl     = 120
}

resource "cloudflare_record" "infra-first-vm" {
  zone_id = lookup(data.cloudflare_zones.infra.zones[0], "id")
  name    = var.my_name
  value   = element(oci_core_instance.infra.*.display_name, 0)
  type    = "CNAME"
}

resource "cloudflare_record" "infra-all" {
  zone_id = lookup(data.cloudflare_zones.infra.zones[0], "id")
  name    = "*.${var.my_name}"
  value   = element(oci_core_instance.infra.*.display_name, 0)
  type    = "CNAME"
}

output "infra_instances" {
  value = oci_core_instance.infra.*.display_name
}

output "infra_instance_public_ips" {
  value = oci_core_instance.infra.*.public_ip
}
