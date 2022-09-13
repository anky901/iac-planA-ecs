#------------------------------------------------------------
# variables.tf
#------------------------------------------------------------
variable "app_id" {
  type        = string
  description = "Name of the ecs app"
  default     = "energy"
}

variable "cidr_prefix" {
  type        = string
  description = "Prefix for the CIDR range to be used by the VPC (e.g. 10.0.0.0)"
  default     = "10.0.0.0"
}

variable "container_port" {
  type        = string
  description = "Allowing Ingress access only to the port that is exposed by the task."
  default     = "80"
}

variable "container_image" {
  type        = string
  description = "Docker Standard Image to pass."
  default     = "nginx"
}

variable "environment" {
  type        = string
  description = "Type of environment for the VPC. Valid values are dev, prod, and stage."

  validation {
    condition     = contains(["dev", "prod", "stage"], var.environment)
    error_message = "Invalid VPC environment. Must be 'dev', 'prod', or 'stage'."
  }
}

variable "gateway_id" {
  type        = string
  description = "Identifier of a VPC internet gateway or a virtual private gateway. Provide this to use instead of the default nat_gateway_id used by this module."
  default     = null
}

variable "region" {
  type        = string
  description = "which region"
  default     = ""
}

