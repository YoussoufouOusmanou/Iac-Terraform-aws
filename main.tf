provider "aws" {
  region = "us-east-1"  # Remplacez par la région de votre choix
}

resource "aws_vpc" "vpc_lab1" {
  cidr_block = "10.0.0.0/16"  # Plage d'adresses IP pour le VPC

  tags = {
    Name = "VPC-Lab1"
  }
}

resource "aws_subnet" "public_subnet_lab1" {
  vpc_id     = aws_vpc.vpc_lab1.id
  cidr_block = "10.0.1.0/24"  # Plage d'adresses IP pour le subnet public

  tags = {
    Name = "PublicSubnet"
  }
}

resource "aws_subnet" "private_subnet_lab1" {
  vpc_id     = aws_vpc.vpc_lab1.id
  cidr_block = "10.0.2.0/24"  # Plage d'adresses IP pour le subnet privé

  tags = {
    Name = "PrivateSubnet"
  }
}


resource "aws_internet_gateway" "igw_lab1" {
  vpc_id = aws_vpc.vpc_lab1.id
}

resource "aws_nat_gateway" "nat_gateway_lab1" {
  allocation_id = aws_eip.my_eip.id
  subnet_id     = aws_subnet.private_subnet_lab1.id
}

resource "aws_eip" "my_eip" {
  vpc = true
}

# routage pour le subnet privé

# Creation de la table de routage
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc_lab1.id
}

# Association de la table de routage avec le sous resau privé
resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet_lab1.id
  route_table_id = aws_route_table.private_route_table.id
}

# Mis en place des routes
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_lab1.id
}

# routage pour le subnet public

# Creation de la table de routage
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc_lab1.id
}

# Association de la table de routage avec le sous resau public
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet_lab1.id
  route_table_id = aws_route_table.public_route_table.id
}

# Mis en place des routes
resource "aws_route" "public_igw_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw_lab1.id
}

resource "aws_security_group" "public_sg" {
  name        = "PublicSecurityGroup"
  description = "Security group for public subnet instances"
  vpc_id      = aws_vpc.vpc_lab1.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["91.160.158.145/32"] # remplacer par votre adresse public. c-a-d celle de votre box internet
  }
  egress{ 
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]  # Autorise tout le trafic sortant
  }
}

resource "aws_security_group" "private_sg" {
  name        = "PrivateSecurityGroup"
  description = "Security group for private subnet instances"
  vpc_id      = aws_vpc.vpc_lab1.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.public_sg.id] # permet à la machine frontend d'acceder à celle du backend en SSH 
  }
  egress{ 
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]  # Autorise tout le trafic sortant
  }
}


resource "aws_instance" "instance_frontend" {
  ami           = var.ami_id # Remplacez par l'AMI de votre choix
  instance_type = var.type_instance
  subnet_id     = aws_subnet.public_subnet_lab1.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  key_name      = aws_key_pair.lab1_key_pair.key_name
  root_block_device {
    delete_on_termination = true
  }
  tags          = {
    Name        = "instance_frontend"
  }
  depends_on = [aws_key_pair.lab1_key_pair]
  associate_public_ip_address = true  # Attribue une adresse IP publique

# Le user data permet d'executer le script d'installatin du web server lors de lancement de la machine
user_data = <<-EOF
             #!/bin/bash
             sleep 60 
             sudo yum update -y
             sudo yum install -y httpd
             sudo systemctl start httpd
             sudo systemctl enable httpd
             echo "<html><body><h1>Hello from your instance!</h1></body></html>" > /var/www/html/index.html

              EOF
}

resource "aws_instance" "instance_backend" {
  ami           = var.ami_id  # Remplacez par l'AMI de votre choix
  instance_type = var.type_instance
  subnet_id     = aws_subnet.private_subnet_lab1.id
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  key_name      = aws_key_pair.lab1_key_pair.key_name
  root_block_device {
    delete_on_termination = true
  }
  tags          = {
    Name        = "instance_backend"
  }
  depends_on = [aws_key_pair.lab1_key_pair]
}

variable "type_instance" {
  description = "Type d'instance à utiliser"
  default     = "t2.micro" 
}
variable "ami_id" {
  description = "ID de l'AMI à utiliser"
  default     = "ami-08a52ddb321b32a8c"  # Remplacez par l'AMI par défaut
}

resource "aws_key_pair" "lab1_key_pair" {
  key_name   = "lab1-keypair"  # Nom de la paire de clés
  public_key = file("~/.ssh/id_rsa.pub")  # Chemin vers la clé publique
}