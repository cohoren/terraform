##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path_docker" {}
variable "key_name" {
  default = "docker"
}
variable "network_address_space" {
  default = "10.1.0.0/16"
}
variable "subnet1_address_space" {
  default = "10.1.0.0/24"
}

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "eu-west-1"
}

##################################################################################
# DATA
##################################################################################

data "aws_availability_zones" "available" {}

##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
resource "aws_vpc" "vpc" {
  cidr_block = "${var.network_address_space}"
  enable_dns_hostnames = "true"

}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"

}

resource "aws_subnet" "subnet1" {
  cidr_block        = "${var.subnet1_address_space}"
  vpc_id            = "${aws_vpc.vpc.id}"
  map_public_ip_on_launch = "true"
  availability_zone = "${data.aws_availability_zones.available.names[0]}"

}

# ROUTING #
resource "aws_route_table" "rtb" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }
}

resource "aws_route_table_association" "rta-subnet1" {
  subnet_id      = "${aws_subnet.subnet1.id}"
  route_table_id = "${aws_route_table.rtb.id}"
}

# SECURITY GROUPS #
# Nginx security group 
resource "aws_security_group" "nginx-sg" {
  name        = "nginx_sg_blue"
  vpc_id      = "${aws_vpc.vpc.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ALL"
  }

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ALL"
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# INSTANCES #
resource "aws_instance" "docker" {
  ami = "ami-035f90419bc9b535e"
  instance_type = "t2.micro"
  subnet_id     = "${aws_subnet.subnet1.id}"
  vpc_security_group_ids = ["${aws_security_group.nginx-sg.id}"]
  key_name        = "${var.key_name}"

  connection {
    user        = "ubuntu"
    private_key = "${file(var.private_key_path_docker)}"
  }

  provisioner "remote-exec" {
    script = "../docker_installtion.sh"
  
    # inline = [
    #   "echo 'Remove lock'",
    #   "sudo rm /var/lib/apt/lists/lock",
    #   "echo 'Remove lock from cache'",
    #   "sudo rm /var/cache/apt/archives/lock",
    #   "echo '***Add the GPG key for the official Docker repository to your system***'",
    #   "curl -fs SL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
    #   "echo '***Add the Docker repository to APT sources'***",
    #   "sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable'",
    #   "echo '***Update the package database with the Docker packages from the newly added repo***'",
    #   "sleep 10",
    #   "sudo apt-get update",
    #   "echo '***Make sure you are about to install from the Docker repo instead of the default Ubuntu 16.04 repo***'",
    #   "sleep 10",
    #   "apt-cache policy docker-ce",
    #   "echo '***Install Docker***'",
    #   "sleep 10",
    #   "sudo apt-get install -y docker-ce",
    #   "echo '***Check that docker is running***'",
    #   "sudo systemctl status docker",
    #   "echo '***add the current username to the docker group***'",
    #   "sudo usermod -aG docker ubuntu"
    # ]
  }
}

##################################################################################
# OUTPUT
##################################################################################

output "aws_instance_public_dns" {
    value = "${aws_instance.docker.public_dns}"
}
