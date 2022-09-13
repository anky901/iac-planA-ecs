#------------------------------------------------------------
# main.tf
#------------------------------------------------------------

resource "aws_iam_role" "this" {
  name                = "ecsTaskRoleExecution"
  assume_role_policy  = data.aws_iam_policy_document.assume_role.json
  managed_policy_arns = [data.aws_iam_policy.AmazonECS_FullAccess.arn, data.aws_iam_policy.AmazonElasticContainerRegistryPublicReadOnly.arn]
}

resource "aws_iam_policy" "ecs_logs" {

  name   = "${var.app_id}-logs-${var.environment}"
  policy = data.aws_iam_policy_document.ecs_logs.json
}

resource "aws_iam_role_policy_attachment" "ecs_logs" {

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.ecs_logs.arn
}

resource "aws_ecs_cluster" "alpha-ecs" {
  name = "${var.app_id}-cluster-${var.environment}"
}

resource "aws_ecs_task_definition" "service" {
  family                   = "service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.this.arn
  task_role_arn            = aws_iam_role.this.arn
  container_definitions    = <<TASK_DEFINITION
[
  {
    "name": "${var.app_id}-container-${var.environment}",
    "image": "public.ecr.aws/nginx/nginx:latest",
    "cpu": 256,
    "memory": 512,
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80,
        "protocol": "tcp"
      }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
           "awslogs-group" : "/fargate/service/ecs",
           "awslogs-region": "${var.region}",
           "awslogs-create-group" : "true",
           "awslogs-stream-prefix": "ecs"
        }
    },
    "essential": true
  }
]
TASK_DEFINITION

}

resource "aws_ecs_service" "main" {
  name                               = "${var.app_id}-service-${var.environment}"
  cluster                            = aws_ecs_cluster.alpha-ecs.id
  task_definition                    = aws_ecs_task_definition.service.arn
  desired_count                      = 2
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = values(aws_subnet.private)[*].id
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.main.id
    container_name   = "${var.app_id}-container-${var.environment}"
    container_port   = "80"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
  depends_on = [aws_alb_listener.http]
}