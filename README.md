# iac-planA-ecs

## Synopsis

A Terraform module to create and configure an ECS service.

Apart from the ECS service this module also creates the following resources:

* VPC and all associated components
* Application Load Balancer
* Target Group
* Listener
* Security groups
* Task definition
* Task role

Install Terraform version : 1.0.11
- brew tap hashicorp/tap
- brew install hashicorp/tap/terraform
- brew install tfenv
- tfenv use 1.0.11


Configure AWS access & secrey key in your local to run this terraform project :
 - aws configure
 # keep your access , secret key handy.
 # decide the aws region you would want to deploy(I took us-east-1)
 
 - git clone https://github.com/anky901/iac-planA-ecs.git

Always run terraform fmt to format terraform configuration files and make them neat.
  - terraform validate
  - terraform fmt

run below commands now  
  - terraform init
  # It will take the input such as environment and region from user.
  - terraform plan
  - terraform apply

destroy all created infra
  - terraform destroy
