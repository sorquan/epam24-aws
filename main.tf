terraform {
  backend "s3" {
    bucket         = "epam-learn-tfstate"
    key            = "wp-tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tfstate_lock"
  }
}

provider "aws" {
  region     = "eu-central-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  default_tags {
    tags = {
      Environment = "Development"
    }
  }
}

# resource "aws_s3_bucket" "tfstate" {
#   bucket = "epam-learn-tfstate"
# }

# resource "aws_dynamodb_table" "tfstate_lock" {
#   name           = "tfstate_lock"
#   read_capacity  = 1
#   write_capacity = 1
#   hash_key       = "LockID"

#   attribute {
#     name = "LockID"
#     type = "S"
#   }
# }

resource "aws_key_pair" "access_key" {
  key_name   = "access-key"
  public_key = var.aws_key_pair
}

resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "VPC_for_WP"
  }
}

resource "aws_internet_gateway" "main_ig" {
  vpc_id     = aws_vpc.main_vpc.id
  depends_on = [aws_vpc.main_vpc]

  tags = {
    Name = "main-ig"
  }
}

resource "aws_route" "route_to_main_ig" {
  route_table_id         = aws_vpc.main_vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main_ig.id
  depends_on             = [aws_internet_gateway.main_ig, aws_vpc.main_vpc]
}

resource "aws_subnet" "eu_central_1a_sn" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
}

resource "aws_subnet" "eu_central_1b_sn" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1b"
}

resource "aws_route_table_association" "eu_central_1a_route" {
  subnet_id      = aws_subnet.eu_central_1a_sn.id
  route_table_id = aws_vpc.main_vpc.main_route_table_id
}

resource "aws_route_table_association" "eu_central_1b_route" {
  subnet_id      = aws_subnet.eu_central_1b_sn.id
  route_table_id = aws_vpc.main_vpc.main_route_table_id
}

resource "aws_security_group" "sg_ec2" {
  name        = "sg_for_ec2"
  description = "Security group for EC2"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "Allow inbound HTTP traffic from VPC subnets"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Allow inbound SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["77.37.136.26/32"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name" = "sg-for-ec2"
  }
}

resource "aws_security_group" "sg_rds" {
  name        = "sg_for_rds"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description     = "Allow inbound MySQL traffic"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_ec2.id]
  }

  egress {
    description = "Allow outbound traffic to VPC subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  depends_on = [aws_security_group.sg_ec2]

  tags = {
    "Name" = "sg-for-rds"
  }
}

resource "aws_security_group" "sg_efs" {
  name        = "sg_for_efs"
  description = "Security group for EFS"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description     = "Allow inbound NFS traffic"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_ec2.id]
  }

  egress {
    description = "Allow outbound traffic to VPC subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  depends_on = [aws_security_group.sg_ec2]

  tags = {
    "Name" = "sg-for-efs"
  }
}

resource "aws_security_group" "sg_lb" {
  name        = "SG_for_LB"
  description = "Security group for LB"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "Allow inbound HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Allow outbound HTTP traffic to EC2 instances"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_ec2.id]
  }

  depends_on = [aws_security_group.sg_ec2]

  tags = {
    "Name" = "sg-for-lb"
  }
}

resource "aws_efs_file_system" "wp_efs" {
  encrypted = true

  tags = {
    Name = "efs-for-wp"
  }
}

resource "aws_efs_mount_target" "eu_central_1a_efs" {
  file_system_id  = aws_efs_file_system.wp_efs.id
  subnet_id       = aws_subnet.eu_central_1a_sn.id
  security_groups = [aws_security_group.sg_efs.id]
  depends_on      = [aws_efs_file_system.wp_efs, aws_security_group.sg_efs]
}

resource "aws_efs_mount_target" "eu_central_1b_efs" {
  file_system_id  = aws_efs_file_system.wp_efs.id
  subnet_id       = aws_subnet.eu_central_1b_sn.id
  security_groups = [aws_security_group.sg_efs.id]
  depends_on      = [aws_efs_file_system.wp_efs, aws_security_group.sg_efs]
}

resource "aws_db_subnet_group" "main_db_sg" {
  name       = "db_sg_for_wp"
  subnet_ids = [aws_subnet.eu_central_1a_sn.id, aws_subnet.eu_central_1b_sn.id]
}

resource "aws_db_instance" "wp_db" {
  identifier             = "wp-db"
  engine                 = "mysql"
  instance_class         = "db.t2.micro"
  db_subnet_group_name   = aws_db_subnet_group.main_db_sg.name
  db_name                = var.wp_db_name
  username               = var.wp_db_user
  password               = var.wp_db_pass
  allocated_storage      = 5
  max_allocated_storage  = 0
  storage_type           = "gp2"
  vpc_security_group_ids = [aws_security_group.sg_rds.id]
  skip_final_snapshot    = true
  depends_on             = [aws_security_group.sg_rds, aws_db_subnet_group.main_db_sg]

  tags = {
    Name = "DB_for_WP"
  }
}

resource "aws_lb" "wp_lb" {
  name                       = "wp-lb"
  drop_invalid_header_fields = true
  security_groups            = [aws_security_group.sg_lb.id]
  subnets                    = [aws_subnet.eu_central_1a_sn.id, aws_subnet.eu_central_1b_sn.id]
  depends_on                 = [aws_security_group.sg_lb]
}

resource "aws_lb_target_group" "lb_tg" {
  name     = "tg-for-lb"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id

  health_check {
    path     = "/wp-login.php"
    port     = "80"
    protocol = "HTTP"
    matcher  = "200"
  }
}

resource "aws_lb_listener" "lb_http_listener" {
  load_balancer_arn = aws_lb.wp_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.lb_tg.arn
    type             = "forward"
  }
}

resource "aws_launch_template" "wp_lt" {
  name          = "lt-for-wp"
  key_name      = aws_key_pair.access_key.key_name
  image_id      = "ami-0d527b8c289b4af7f"
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.sg_ec2.id]
  }

  user_data = base64encode(templatefile("${path.module}/init.tpl",
    {
      "efs_mount_dns" = aws_efs_file_system.wp_efs.dns_name
      "db_endpoint"   = aws_db_instance.wp_db.endpoint
      "db_name"       = var.wp_db_name
      "db_user"       = var.wp_db_user
      "db_pass"       = var.wp_db_pass
      "site_url"      = aws_lb.wp_lb.dns_name
      "admin_name"    = var.wp_admin_name
      "admin_pass"    = var.wp_admin_pass
      "admin_email"   = var.wp_admin_email
    }
    )
  )
}

resource "aws_autoscaling_group" "wp_asg" {
  name                      = "asg-for-wp"
  max_size                  = 4
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  target_group_arns         = [aws_lb_target_group.lb_tg.arn]

  launch_template {
    id      = aws_launch_template.wp_lt.id
    version = "$Latest"
  }

  vpc_zone_identifier = [aws_subnet.eu_central_1a_sn.id, aws_subnet.eu_central_1b_sn.id]
  depends_on          = [aws_db_instance.wp_db, aws_lb.wp_lb, aws_launch_template.wp_lt, aws_efs_mount_target.eu_central_1a_efs, aws_efs_mount_target.eu_central_1b_efs]
}

resource "aws_cloudwatch_metric_alarm" "cpu_over_60" {
  alarm_name                = "CPU_over_60_percent"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "60"
  statistic                 = "Average"
  threshold                 = "60"
  alarm_description         = "This metric monitors ec2 cpu utilization"
  insufficient_data_actions = []
  alarm_actions             = [aws_autoscaling_policy.scale_out_one.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_under_20" {
  alarm_name                = "CPU_under_20_percent"
  comparison_operator       = "LessThanOrEqualToThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "60"
  statistic                 = "Average"
  threshold                 = "20"
  alarm_description         = "This metric monitors ec2 cpu utilization"
  insufficient_data_actions = []
  alarm_actions             = [aws_autoscaling_policy.scale_in_one.arn]
}

resource "aws_autoscaling_policy" "scale_out_one" {
  name                   = "Add_one_instance"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.wp_asg.name
}

resource "aws_autoscaling_policy" "scale_in_one" {
  name                   = "Delete_one_instance"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.wp_asg.name
}

output "site_address" {
  value       = "http://${aws_lb.wp_lb.dns_name}"
  description = "ELB public address"
  depends_on  = [aws_lb.wp_lb]
}
