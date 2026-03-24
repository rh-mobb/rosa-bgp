# Test EC2 instance in vpc2 (external VPC) for connectivity testing
resource "aws_instance" "test_instance_vpc2" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  subnet_id     = module.ext-vpc.private_subnets[0]

  vpc_security_group_ids = [aws_security_group.test_instance_vpc2_sg.id]

  iam_instance_profile = aws_iam_instance_profile.test_instance_profile.name

  tags = merge(
    local.tags,
    {
      Name = "${var.owner}${var.project_id}-test-instance-vpc2"
    }
  )
}

resource "aws_security_group" "test_instance_vpc2_sg" {
  name_prefix = "test-instance-vpc2-sg-"
  description = "Security group for test instance in vpc2"
  vpc_id      = module.ext-vpc.vpc_id

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${var.owner}${var.project_id}-test-instance-vpc2-sg"
    }
  )
}

output "test_instance_vpc2_id" {
  value = aws_instance.test_instance_vpc2.id
}

output "test_instance_vpc2_private_ip" {
  value = aws_instance.test_instance_vpc2.private_ip
}
