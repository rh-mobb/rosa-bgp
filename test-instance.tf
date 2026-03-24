# Test EC2 instance in vpc1 for connectivity testing
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "test_instance" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  subnet_id     = module.rosa-vpc.private_subnets[0]

  vpc_security_group_ids = [aws_security_group.test_instance_sg.id]

  iam_instance_profile = aws_iam_instance_profile.test_instance_profile.name

  tags = merge(
    local.tags,
    {
      Name = "${var.owner}${var.project_id}-test-instance"
    }
  )
}

resource "aws_security_group" "test_instance_sg" {
  name_prefix = "test-instance-sg-"
  description = "Security group for test instance"
  vpc_id      = module.rosa-vpc.vpc_id

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
      Name = "${var.owner}${var.project_id}-test-instance-sg"
    }
  )
}

# IAM role for SSM access
resource "aws_iam_role" "test_instance_role" {
  name_prefix = "test-instance-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "test_instance_ssm" {
  role       = aws_iam_role.test_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "test_instance_profile" {
  name_prefix = "test-instance-profile-"
  role        = aws_iam_role.test_instance_role.name

  tags = local.tags
}

output "test_instance_id" {
  value = aws_instance.test_instance.id
}

output "test_instance_private_ip" {
  value = aws_instance.test_instance.private_ip
}
