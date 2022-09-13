#------------------------------------------------------------
# outputs.tf
#------------------------------------------------------------
output "vpc" {
  value = {
    availability_zone_ids = local.selected_availability_zone_ids
    cidr                  = aws_vpc.alpha.cidr_block
    environment           = local.environment
    id                    = aws_vpc.alpha.id
    name                  = local.vpc_name
    nat_gateway_ips       = values(aws_eip.nat)[*].public_ip
    private = {
      network_acl_id  = aws_network_acl.private.id
      route_table_ids = values(aws_route_table.private)[*].id
      subnet_ids      = values(aws_subnet.private)[*].id
    }
    public = {
      network_acl_id = aws_network_acl.public.id
      route_table_id = aws_route_table.public.id
      subnet_ids     = values(aws_subnet.public)[*].id
    }
    #region = data.aws_region.current.name
    route_table_ids = {
      private = values(aws_route_table.private)[*].id
      public  = aws_route_table.public.id
    }
  }
}
