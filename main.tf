# We'll be putting all our stuff in us-east-1 because that's the only region with support right now
provider "aws" {
  region     = "us-east-1"
}

# Let's create a network for our containers to run in
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "a" {
  vpc_id     = "${aws_vpc.vpc.id}"
  cidr_block = "10.0.10.0/24"
  availability_zone = "us-east-1a"
  # this is what allows us to talk to outside world
  map_public_ip_on_launch = true
}

resource "aws_subnet" "b" {
  vpc_id     = "${aws_vpc.vpc.id}"
  cidr_block = "10.0.20.0/24"
  availability_zone = "us-east-1b"
  # this is what allows us to talk to outside world
  map_public_ip_on_launch = true
}

# Only allow in on 80 but allow out on all
resource "aws_default_security_group" "default" {
  vpc_id = "${aws_vpc.vpc.id}"

  # expose HTTP
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  # let our apps talk to the outside world
  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# This lets out network talk with outside world
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.vpc.id}"
}

resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.gw.id}"
}

# Let's create the cluster our containers will run on
resource "aws_ecs_cluster" "halcyon" {
  name = "halcyon"
}

# Let's create a role that has the ability to deploy
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = "${file("ecs_execution_assume_role_policy.json")}"
}

resource "aws_iam_role_policy" "ecs_execution_role_policy" {
  role = "${aws_iam_role.ecs_execution_role.id}"
  policy = "${file("ecs_execution_policy.json")}"
}

# Let's create a task to run on Fargate
resource "aws_ecs_task_definition" "helloworld" {
  family                   = "helloworld"
  container_definitions    = "${file("task.json")}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "${aws_iam_role.ecs_execution_role.arn}"
  task_role_arn            = "${aws_iam_role.ecs_execution_role.arn}"
}

resource "aws_alb" "alb_web" {
  name            = "testweb"
  security_groups = ["${aws_default_security_group.default.id}"]
  subnets         = ["${aws_subnet.a.id}","${aws_subnet.b.id}"]
}

resource "aws_lb_target_group" "web" {
  name     = "web"
  target_type = "ip"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.vpc.id}"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_alb_listener" "openjobs" {
  load_balancer_arn = "${aws_alb.alb_web.arn}"
  port              = "80"
  protocol          = "HTTP"
  depends_on        = ["aws_lb_target_group.web"]

  default_action {
    target_group_arn = "${aws_lb_target_group.web.arn}"
    type             = "forward"
  }
}

resource "aws_ecs_service" "helloworld" {
  name            = "helloworld-service"
  task_definition = "${aws_ecs_task_definition.helloworld.family}:${aws_ecs_task_definition.helloworld.revision}"
  desired_count   = 1
  launch_type     = "FARGATE"
  cluster =       "${aws_ecs_cluster.halcyon.id}"

  load_balancer {
    target_group_arn = "${aws_lb_target_group.web.arn}"
    container_name   = "helloworld"
    container_port   = 80
  }

  network_configuration {
    # This control networking aspects of the scheduler
    security_groups = ["${aws_default_security_group.default.id}"]
    subnets         = ["${aws_subnet.a.id}","${aws_subnet.b.id}"]
    # You won't be able to pull from docker.io if you turn this off
    assign_public_ip = "true"
  }
}


resource "aws_route53_zone" "primary_route" {
  name              = "yourdomaingoeshere.com"
}

resource "aws_route53_record" "www-prod" {
  zone_id = "${aws_route53_zone.primary_route.id}"
  name    = "www.yourdomaingoeshere.com"
  type    = "A"

  alias {
    name                    = "${aws_alb.alb_web.dns_name}"
    zone_id                 = "${aws_alb.alb_web.zone_id}"
    evaluate_target_health  = true
  }
}
