#------------------------------------------------------------
# vpc.tf
#------------------------------------------------------------
locals {
  cidr_block = "${var.cidr_prefix}/20"
  default_acl_rules = flatten([
    for direction in [true, false] : [
      {
        direction_key = direction == true ? "outbound" : "inbound"
        rule_number   = 100
        egress        = direction
        protocol      = -1
        rule_action   = "allow"
        cidr_block    = "0.0.0.0/0"
        from_port     = 0
        to_port       = 0
      }
    ]
  ])

  environment = lower(var.environment)
  region      = var.region
  
  selected_availability_zone_ids = flatten([
    for az_index in [0, 1] : [
      data.aws_availability_zones.available.zone_ids[az_index]
    ]
  ])

  propernets = [
    # The cidrsubnets() function splits a CIDR network by adding the specified number of bits to the original suffix.
    # In this case, taking a /20 and adding 2 bits, 2 separate times (one for each AZ), which will give us 2 x /22s.
    for propernet in cidrsubnets(local.cidr_block, 2, 2) :

    # Then, each /22 will be split it into two subnets:
    # /24 (public)
    # /23 (private)
    cidrsubnets(propernet, 2, 1)

    # The resulting output will be a list of lists and look something like this:
    /*
    propernets = [
      [
        "10.0.0.0/24", <- az2 public
        "10.0.2.0/23", <- az2 private
      ],
      [
        "10.0.4.0/24", <- az4 public
        "10.0.6.0/23", <- az4 private
      ],
    ]
    */
  ]

  # Map of friendly subnet types to subnet keys (indexes). Each key (index) is created in the inner for..in loop in the
  # subnets local variable.
  subnet_type_map = {
    0 = "public"
    1 = "private"
  }

  /*
  Transform the subnet nested list of lists into a flattened list of maps, which will look like the following:
  [
    {
      subnet_key = "public_use1-az2"
      subnet_type = "public"
      cidr_block = "10.0.0.0/24"
      availability_zone_id = "use1-az2"
    },
    {
      subnet_key = "private_use1-az2"
      subnet_type = "private"
      cidr_block = "10.0.2.0/23"
      availability_zone_id = "use1-az2"
    },
    ...
  ]
  */
  subnets = flatten([
    # propernet_index is the index of each propernet item in the for..in loop (e.g. 0, 1 etc.)
    for propernet_index, propernet in local.propernets : [

      # subnet_index is the index of each subnet item in the for..in loop (e.g. 0, 1 etc.)
      for subnet_index, subnet in propernet : {
        # Create a unique key for the subnet in the form of <friendly_subnet_type>.<az_id>.
        subnet_key = "${lookup(local.subnet_type_map, subnet_index)}_${data.aws_availability_zones.available.zone_ids[propernet_index]}"

        # Lookup the friendly subnet type. We will use this to make filtering easier later on.
        subnet_type = lookup(local.subnet_type_map, subnet_index)
        cidr_block  = subnet

        # Get the AZ with the same index as the propernet we are working with.
        availability_zone_id = data.aws_availability_zones.available.zone_ids[propernet_index]
      }

    ]
  ])
  vpc_name = "${local.vpc_type}_${local.environment}"
  vpc_type = "planA"
}

data "aws_availability_zones" "available" {
  state = "available"
}

#data "aws_region" "current" {}

resource "aws_vpc" "alpha" {
  cidr_block           = local.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = local.vpc_name
  }
}

resource "aws_default_network_acl" "alpha" {
  default_network_acl_id = aws_vpc.alpha.default_network_acl_id

  # No rules defined, deny all traffic in this ACL.
  tags = {
    Name = "DO NOT USE"
  }
}

resource "aws_default_route_table" "alpha" {
  default_route_table_id = aws_vpc.alpha.default_route_table_id

  tags = {
    Name = "DO NOT USE"
  }
}

resource "aws_default_security_group" "alpha" {
  vpc_id = aws_vpc.alpha.id

  # No rules defined, deny all traffic in this security group.
  tags = {
    Name = "DO NOT USE"
  }
}

resource "aws_internet_gateway" "alpha-igw" {
  vpc_id = aws_vpc.alpha.id

  tags = {
    Name = local.vpc_name
  }
}

resource "aws_eip" "nat" {
  for_each = {
    # The syntax for looping over lists is: {for <ITEM> in <MAP> : <OUTPUT_KEY> => <OUTPUT_VALUE>}
    for subnet in local.subnets : subnet.subnet_key => subnet
    if subnet.subnet_type == "public"
  }

  vpc = true

  tags = {
    Name = each.value.availability_zone_id
  }

  depends_on = [
    aws_internet_gateway.alpha-igw
  ]
}

#region Public subnet network resources
resource "aws_subnet" "public" {
  for_each = {
    for subnet in local.subnets : subnet.subnet_key => subnet
    if subnet.subnet_type == "public"
  }

  vpc_id               = aws_vpc.alpha.id
  cidr_block           = each.value.cidr_block
  availability_zone_id = each.value.availability_zone_id

  tags = {
    Name = "${each.value.subnet_type}_${each.value.availability_zone_id}"
    Type = each.value.subnet_type
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes to tags because other deployments may add tags that we aren't managing (e.g. EKS)
      tags,
    ]
  }
}

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.alpha.id
  subnet_ids = values(aws_subnet.public)[*].id

  tags = {
    Name = "public"
  }
}

resource "aws_network_acl_rule" "public" {
  for_each = {
    for default_acl_rule in local.default_acl_rules : default_acl_rule.direction_key => default_acl_rule
  }
  network_acl_id = aws_network_acl.public.id
  rule_number    = each.value.rule_number
  egress         = each.value.egress
  protocol       = each.value.protocol
  rule_action    = each.value.rule_action
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
}
#endregion Public subnet network resources


#region Public route table network resources
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.alpha.id

  tags = {
    Name = "public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = {
    for subnet in local.subnets : subnet.subnet_key => subnet
    if subnet.subnet_type == "public"
  }

  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[each.key].id
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.alpha-igw.id
}
#endregion Public route table network resources

#region Private route table network resources
resource "aws_route_table" "private" {
  for_each = {
    for zone_id in local.selected_availability_zone_ids : zone_id => zone_id
  }

  vpc_id = aws_vpc.alpha.id

  tags = {
    Name = "private_${each.key}"
  }
}

resource "aws_route" "private_nat_gateway" {
  for_each = {
    for zone_id in local.selected_availability_zone_ids : zone_id => zone_id
  }

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"

  # Use Gateway ID instead of nat_gateway_id if gateway_id variable is assigned.
  gateway_id = var.gateway_id == null ? null : var.gateway_id

  # We need to reference to the public subnet in the same AZ as the private subnet.
  nat_gateway_id = var.gateway_id == null ? aws_nat_gateway.this["public_${each.key}"].id : null
}
#endregion Private route table network resources

#region Private subnet network resources
resource "aws_subnet" "private" {
  for_each = {
    for subnet in local.subnets : subnet.subnet_key => subnet
    if subnet.subnet_type == "private"
  }

  vpc_id               = aws_vpc.alpha.id
  cidr_block           = each.value.cidr_block
  availability_zone_id = each.value.availability_zone_id

  tags = {
    Name = "${each.value.subnet_type}_${each.value.availability_zone_id}"
    Type = each.value.subnet_type
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes to tags because other deployments may add tags that we aren't managing (e.g. EKS)
      tags,
    ]
  }
}

resource "aws_route_table_association" "private" {
  for_each = {
    for subnet in local.subnets : subnet.subnet_key => subnet
    if subnet.subnet_type == "private"
  }

  route_table_id = aws_route_table.private[each.value.availability_zone_id].id
  subnet_id      = aws_subnet.private[each.key].id
}

resource "aws_network_acl" "private" {

  vpc_id     = aws_vpc.alpha.id
  subnet_ids = values(aws_subnet.private)[*].id
  tags = {
    Name = "private"
  }
}

resource "aws_network_acl_rule" "private" {
  for_each = {
    for default_acl_rule in local.default_acl_rules : default_acl_rule.direction_key => default_acl_rule
  }

  network_acl_id = aws_network_acl.private.id
  rule_number    = each.value.rule_number
  egress         = each.value.egress
  protocol       = each.value.protocol
  rule_action    = each.value.rule_action
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
}
#endregion Private subnet network resources


resource "aws_nat_gateway" "this" {
  for_each = {
    for subnet in local.subnets : subnet.subnet_key => subnet
    if subnet.subnet_type == "public"
  }

  subnet_id     = aws_subnet.public[each.key].id
  allocation_id = aws_eip.nat[each.key].id

  tags = {
    Name = each.value.availability_zone_id
  }

  depends_on = [
    aws_internet_gateway.alpha-igw
  ]
}






