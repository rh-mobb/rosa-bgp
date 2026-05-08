# Bastion host in ROSA VPC public subnet for SSH access
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  subnet_id     = module.rosa-vpc.public_subnets[0]

  key_name = "daxelrod-bastion"

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  iam_instance_profile = aws_iam_instance_profile.test_instance_profile.name

  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y curl wget telnet nc jq amazon-ssm-agent

    # Enable and start SSM agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # Add ec2-user to sudoers
    echo "ec2-user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/90-cloud-init-users
  EOF

  tags = merge(
    local.tags,
    {
      Name = "${var.owner}${var.project_id}-bastion"
    }
  )
}

resource "aws_security_group" "bastion_sg" {
  name_prefix = "${var.owner}${var.project_id}-bastion-sg-"
  description = "Security group for bastion host"
  vpc_id      = module.rosa-vpc.vpc_id

  # SSH from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH from anywhere"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${var.owner}${var.project_id}-bastion-sg"
    }
  )
}

output "bastion_public_ip" {
  description = "Public IP address of bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IP address of bastion host"
  value       = aws_instance.bastion.private_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion"
  value       = "ssh -i ~/.ssh/daxelrod-bastion.pem ec2-user@${aws_instance.bastion.public_ip}"
}
