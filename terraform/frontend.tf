resource "aws_ecr_repository" "frontend" {
  name = "frontend"
}

resource "aws_ecs_task_definition" "frontend" {
  family             = "frontend"
  execution_role_arn = aws_iam_role.task_execution_role.arn

  container_definitions = templatefile("${abspath(path.root)}/../frontend/taskdef.json", {
    IMAGE_PATH = aws_ecr_repository.frontend.repository_url
  })
}

resource "aws_ecs_service" "frontend" {
  name                               = "frontend"
  cluster                            = aws_ecs_cluster.cluster.id
  task_definition                    = aws_ecs_task_definition.frontend.arn
  deployment_minimum_healthy_percent = 1
  desired_count                      = 2

  load_balancer {
    target_group_arn = aws_alb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 3000
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb.alb]
}

resource "aws_alb_target_group" "frontend" {
  name        = "frontend-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "instance"

  health_check {
    healthy_threshold   = 3
    interval            = 30
    protocol            = "HTTP"
    matcher             = 200
    timeout             = 3
    path                = "/"
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "frontend" {
  listener_arn = aws_lb_listener.http.arn

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.frontend.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

resource "aws_codebuild_project" "frontend" {
  name         = "frontend"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "./frontend/buildspec.yml"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:3.0"
    type         = "LINUX_CONTAINER"

    // Use privileged mode otherwise build errors out when building image:
    // Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
    // See https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codebuild_project#privileged_mode
    privileged_mode = true

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.id
    }

    // Use secrets manager on real builds:
    // https://stackoverflow.com/questions/64967922/docker-hub-login-for-aws-codebuild-docker-hub-limit
    environment_variable {
      name  = "DOCKERHUB_USERNAME"
      value = var.dockerhub_username
    }

    environment_variable {
      name  = "DOCKERHUB_PASSWORD"
      value = var.dockerhub_password
    }

    environment_variable {
      name  = "CONTAINER_REPOSITORY_URL"
      value = aws_ecr_repository.frontend.repository_url
    }
  }
}
