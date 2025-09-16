provider "aws" {
  region = "af-south-1"
}

data "aws_region" "current" {}

# ------------------------
# Networking
# ------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Public subnet for nginx
resource "aws_subnet" "nginx" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "af-south-1a"
}

# Private subnet for postgres
resource "aws_subnet" "postgres" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "af-south-1a"
}

# Public route table (nginx → IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "nginx" {
  subnet_id      = aws_subnet.nginx.id
  route_table_id = aws_route_table.public.id
}

# Private route table (postgres → endpoints only)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "postgres" {
  subnet_id      = aws_subnet.postgres.id
  route_table_id = aws_route_table.private.id
}

# ------------------------
# VPC Endpoints
# ------------------------
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.postgres.id]
  security_group_ids  = [aws_security_group.ssm.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.postgres.id]
  security_group_ids  = [aws_security_group.ssm.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.postgres.id]
  security_group_ids  = [aws_security_group.ssm.id]
  private_dns_enabled = true
}

# For Amazon Linux repos (yum/dnf via S3)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.id}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

# ------------------------
# Security Groups
# ------------------------
resource "aws_security_group" "nginx" {
  vpc_id = aws_vpc.main.id
  name   = "nginx-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "postgres" {
  vpc_id = aws_vpc.main.id
  name   = "postgres-sg"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ssm" {
  vpc_id = aws_vpc.main.id
  name   = "ssm-sg"

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    security_groups = [
      aws_security_group.nginx.id,
      aws_security_group.postgres.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------
# EC2 Instances
# ------------------------
data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "nginx" {
  ami                         = data.aws_ami.al2.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.nginx.id
  vpc_security_group_ids      = [aws_security_group.nginx.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ssm.name

  user_data = templatefile("${path.module}/userdata-nginx.sh", {
    git_pat     = var.git_pat
    db_host     = aws_instance.postgres.private_ip
    db_user     = var.db_user
    db_name     = var.db_name
    db_port     = var.db_port
    db_password = var.db_password
    ssm_log     = <<EOT
  systemctl enable amazon-ssm-agent
  systemctl restart amazon-ssm-agent
  systemctl status amazon-ssm-agent > /tmp/ssm-agent-status.log 2>&1
  amazon-ssm-agent -version >> /tmp/ssm-agent-status.log 2>&1
  EOT
  })


  depends_on = [
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages
  ]

  tags = {
    Name = "nginx-server"
  }
}


resource "aws_instance" "postgres" {
  ami                         = data.aws_ami.al2.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.postgres.id
  vpc_security_group_ids      = [aws_security_group.postgres.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  user_data = templatefile("${path.module}/userdata-postgres.sh.tpl", {
    db_user     = var.db_user
    db_name     = var.db_name
    db_port     = var.db_port
    db_password = var.db_password
    ssm_log     = <<EOT
  systemctl enable amazon-ssm-agent
  systemctl restart amazon-ssm-agent
  systemctl status amazon-ssm-agent > /tmp/ssm-agent-status.log 2>&1
  amazon-ssm-agent -version >> /tmp/ssm-agent-status.log 2>&1
  EOT
  })

  depends_on = [aws_vpc_endpoint.ssm, aws_vpc_endpoint.ssmmessages, aws_vpc_endpoint.ec2messages, aws_vpc_endpoint.s3]

  tags = {
    Name = "postgres-server"
  }
}

# ------------------------
# IAM Role for SSM
# ------------------------
resource "aws_iam_role" "ssm" {
  name = "ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ssm.name
}


# ------------------------
# Update application on run using git
# ------------------------

resource "null_resource" "update_app" {
  count = var.update_app ? 1 : 0

  # Forces this to run every time you do terraform apply -var="update_app=true"
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOT
INSTANCE_ID=${aws_instance.nginx.id}

echo "Waiting for instance $INSTANCE_ID to register with SSM..."

# Poll until Online
while true; do
  STATUS=$(aws ssm describe-instance-information \
    --region af-south-1 \
    --query "InstanceInformationList[?InstanceId=='$INSTANCE_ID'].PingStatus" \
    --output text)

  if [ "$STATUS" = "Online" ]; then
    echo "Instance $INSTANCE_ID is Online in SSM"
    break
  fi

  if [ -z "$STATUS" ]; then
    echo "Instance $INSTANCE_ID not found yet (waiting...)"
  else
    echo "Current status: $STATUS (waiting...)"
  fi

  sleep 5
done

# Send update command: refresh code + config.ini + restart service
CMD_ID=$(aws ssm send-command \
  --targets "Key=instanceIds,Values=$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --comment "Update Flask app repo & config" \
  --parameters 'commands=[
    "cd /opt/app/dummyapp",
    "sudo -u nginx git reset --hard",
    "sudo -u nginx git pull origin main",
    "printf \"[postgres]\\nhost=${aws_instance.postgres.private_ip}\\nport=5432\\nuser=appuser\\npassword=${var.db_password}\\ndatabase=appdb\\n\" | sudo tee /opt/app/dummyapp/config.ini > /dev/null",
    "sudo chown nginx:nginx /opt/app/dummyapp/config.ini",
    "sudo chmod 640 /opt/app/dummyapp/config.ini",
    "systemctl restart flask-app"
  ]' \
  --region af-south-1 \
  --query "Command.CommandId" \
  --output text)

echo "SSM Command ID: $CMD_ID"

# Poll until Success/Failed
STATUS="InProgress"
while [ "$STATUS" = "InProgress" ] || [ "$STATUS" = "Pending" ]; do
  sleep 5
  STATUS=$(aws ssm list-command-invocations \
    --command-id $CMD_ID \
    --details \
    --region af-south-1 \
    --query "CommandInvocations[0].Status" \
    --output text)
  echo "Current command status: $STATUS"
done

if [ "$STATUS" != "Success" ]; then
  echo "SSM command failed with status: $STATUS"
  exit 1
fi

echo "App update completed successfully."
EOT
  }
}

