#PROVIDER
provider "aws" {
  version = "~> 2.0"
  region  = "us-east-1"
}

#VPC
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  tags = {
      Name = "vpc-epsi-clf-tf"
  }
}

#SUBNETS
resource "aws_subnet" "public-c" {
  vpc_id     = aws_vpc.default.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1c"
  tags = {
    Name = "sub-epsi-clf-public-c-tf"
  }
}
resource "aws_subnet" "public-f" {
  vpc_id     = aws_vpc.default.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1f"
  tags = {
    Name = "sub-epsi-clf-public-f-tf"
  }
}

#INTERNET GATEWAY
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.default.id
  tags = {
    Name = "igw-epsi-clf-tf"
  }
}

#ROUTE TABLE ET ASSOCIATIONS
resource "aws_route_table" "r" {
  vpc_id = aws_vpc.default.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "route-epsi-clf-tf"
  }
}
resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.public-c.id
  route_table_id = aws_route_table.r.id
}
resource "aws_route_table_association" "f" {
  subnet_id      = aws_subnet.public-f.id
  route_table_id = aws_route_table.r.id
}

#PRIVATE KEY ET DEPLOIEMENT
resource "tls_private_key" "key" {
  algorithm   = "RSA"
  rsa_bits = 4096
}
resource "aws_key_pair" "deployer" {
  key_name   = "ec2key-epsi-clf-tf"
  public_key = tls_private_key.key.public_key_openssh
}

#EC2 SECURITY GROUP
resource "aws_security_group" "webtf" {
  name        = "webtf-epsi-clf-tf"
  description = "webtf-epsi-clf-tf"
  vpc_id      = aws_vpc.default.id
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "webtf-epsi-clf-tf"
  }
}

#LOAD BALANCER
resource "aws_lb" "lb-tf" {
  name               = "lb-epsi-clf-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.webtf.id]
  subnets            = [aws_subnet.public-c.id,aws_subnet.public-f.id]
}
resource "aws_lb_target_group" "lb-target-group-tf" {
  name     = "lbtargetgroup-epsi-clf-tf"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.default.id
}
resource "aws_lb_listener" "lb-listener-tf" {
  load_balancer_arn = aws_lb.lb-tf.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lb-target-group-tf.arn
  }
}
/* 
POUR QUE TOUT PUISSE FONCTIONNER CORRECTEMENT, IL NE MANQUE QUE CETTE RESSOURCE A BIEN RENSEIGNER
CEPENDANT JE N'ARRIVE PAS A TROUVER CE QUI RETOURNE LA VALEUR TARGET_ID QUI DOIT INDIQUER L'ID DES INSTANCES EC2...
resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.lb-target-group-tf.arn
  target_id        = 
  port             = 80
}
*/

#AUTO SCALLING
resource "aws_placement_group" "asg-placement-group-tf" {
  name     = "asgplacementgroup-epsi-clf-tf"
  strategy = "spread"
}
resource "aws_autoscaling_group" "asg-tf" {
  name                      = "asg-epsi-clf-tf"
  max_size                  = 4
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = true
  placement_group           = aws_placement_group.asg-placement-group-tf.id
  launch_configuration      = aws_launch_configuration.launch-configuration-tf.name
  vpc_zone_identifier       = [aws_subnet.public-c.id,aws_subnet.public-f.id]
  initial_lifecycle_hook {
    name                 = "asglifecycle-epsi-clf-tf"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 2000
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
  }
  timeouts {
    delete = "5m"
  }
}
resource "aws_autoscaling_attachment" "asg-attachment-tf" {
  autoscaling_group_name = aws_autoscaling_group.asg-tf.id
  alb_target_group_arn   = aws_lb_target_group.lb-target-group-tf.arn
}

#LAUNCH CONFIG
resource "aws_launch_configuration" "launch-configuration-tf" {
  image_id = "ami-0c5b7e326b13d0419"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.webtf.id]
  user_data = file("${path.module}/postinstall.sh")
  key_name = aws_key_pair.deployer.id
  associate_public_ip_address = true
}

#AFFICHAGES A DECOMMENTER AU BESOIN
/*
output "private-key" {
  value = tls_private_key.key.private_key_pem
}
*/
output "adresse-load-balencer" {
  value = aws_lb.lb-tf.dns_name
}
