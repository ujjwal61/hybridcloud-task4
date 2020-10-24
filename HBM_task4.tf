//provider info

provider "aws" {
  region = "ap-south-1"
 
 profile = "ujjwal61"   
}

//create VPC

resource "aws_vpc" "myVPC" {
  cidr_block           = "192.168.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true


  tags = {
    Name = "MyVPC1"
  }
}

# Creating and attaching internet gateway to VPC
resource "aws_internet_gateway" "mygw" {
  depends_on = [
    aws_vpc.myVPC,
  ]
  vpc_id = aws_vpc.myVPC.id


  tags = {
    Name = "MyGateway"
  }
}

//Create a public subnet in this VPC in availability zone 1a

resource "aws_subnet" "firstsubnet_1a" {
  depends_on = [
    aws_vpc.myVPC,
  ]
  vpc_id = aws_vpc.myVPC.id
  cidr_block = "192.168.1.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "FirstSubnet"
  }
}


//create a route table with information regarding internet gateway and attach it to this subnet.

resource "aws_route_table" "routetable" {
  depends_on = [
    aws_vpc.myVPC,
    aws_internet_gateway.mygw,
  ]
  vpc_id = aws_vpc.myVPC.id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mygw.id
  }


  tags = {
    Name = "RouteTable"
  }
}

resource "aws_route_table_association" "associate" {
  depends_on = [
    aws_subnet.firstsubnet_1a,
    aws_route_table.routetable,
  ]
  subnet_id      = aws_subnet.firstsubnet_1a.id
  route_table_id = aws_route_table.routetable.id
}

//Create private subnet in the created VPC above in Availability zone 1b

resource "aws_subnet" "secondsubnet_1b" {
  depends_on = [
    aws_vpc.myVPC,
  ]
  vpc_id = aws_vpc.myVPC.id
  cidr_block = "192.168.2.0/24"
  availability_zone = "ap-south-1b"
  map_public_ip_on_launch = false
  tags = {
    Name = "SecondSubnet"
  }
}


//create and attach one NAT gateway to the private subnet

resource "aws_eip" "nat" {
  vpc      = true
}

resource "aws_nat_gateway" "mygw" {
  depends_on = [
    aws_internet_gateway.mygw
  ]
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.firstsubnet_1a.id
}

//Route table for NAT gateway and association

resource "aws_route_table" "routetable1" {
  depends_on = [
    aws_vpc.myVPC,
    aws_nat_gateway.mygw,
  ]
  vpc_id = aws_vpc.myVPC.id


  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.mygw.id
  }


  tags = {
    Name = "RouteTable1"
  }
}


resource "aws_route_table_association" "associate1" {
  depends_on = [
    aws_subnet.secondsubnet_1b,
    aws_route_table.routetable,
  ]
  subnet_id      = aws_subnet.secondsubnet_1b.id
  route_table_id = aws_route_table.routetable1.id
}


//Creating Key Pair

resource "tls_private_key" "mykey1"  {
    algorithm = "RSA"
    rsa_bits =   4096
}

// Creating a file for key on local system

resource "local_file" "private_key" {
  depends_on = [
    tls_private_key.mykey1,
  ]
  content = tls_private_key.mykey1.private_key_pem
  filename = "task_3key.pem"
  file_permission = 0777
}


resource "aws_key_pair" "mykey1"{
  key_name = "freshkey"
  public_key = tls_private_key.mykey1.public_key_openssh
}

//Create a security group for wordpress VM allowing port 80 and port 22 for instance login
//for 1a

resource "aws_security_group" "allow_traffic_1" {
  name        = "allowed_traffic_1"
  vpc_id      = aws_vpc.myVPC.id
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
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

//for 1b

resource "aws_security_group" "allow_traffic_2" {
  name        = "allowed_traffic_2"
  vpc_id      = aws_vpc.myVPC.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.allow_traffic_1.id]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

//Creating security group for Bastion host in public subnet

resource "aws_security_group" "allow_traffic_3" {
  name        = "allowed_traffic_3"
  vpc_id      = aws_vpc.myVPC.id
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

//Create a security group for mysql VM allowing port 22 and 7

resource "aws_security_group" "allow_traffic_4" {
  name        = "allowed_traffic_4"
  vpc_id      = aws_vpc.myVPC.id
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.allow_traffic_3.id]
  }
  ingress {
    from_port       = 7
    to_port         = 7
    protocol        = "tcp"
    security_groups = [aws_security_group.allow_traffic_3.id]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

// Now will create instances for wordpress and mysql and bastion host
// for wordpress

resource "aws_instance" "wp"{
depends_on = [
    aws_key_pair.mykey1,
    aws_security_group.allow_traffic_1,
    aws_subnet.firstsubnet_1a,
  ]


  ami                    = "ami-000cbce3e1b899ebd" 
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.firstsubnet_1a.id
  key_name               = aws_key_pair.mykey1.key_name
  vpc_security_group_ids = [aws_security_group.allow_traffic_1.id]


    tags = {
    Name = "Wordpress"
 }
}

// for mysql

resource "aws_instance" "mysql"{
depends_on = [
    aws_key_pair.mykey1,
    aws_security_group.allow_traffic_2,
    aws_subnet.secondsubnet_1b,
  ]


  ami                    = "ami-0019ac6129392a0f2" 
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.secondsubnet_1b.id
  key_name               = aws_key_pair.mykey1.key_name
  vpc_security_group_ids = [
                aws_security_group.allow_traffic_2.id,
                aws_security_group.allow_traffic_4.id]


    tags = {
    Name = "MySQL"
 }
}

// for bastion host

resource "aws_instance" "bastion"{
depends_on = [
    aws_key_pair.mykey1,
    aws_security_group.allow_traffic_3,
    aws_subnet.firstsubnet_1a,
  ]


  ami                    = "ami-005956c5f0f757d37" 
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.firstsubnet_1a.id
  key_name               = aws_key_pair.mykey1.key_name
  vpc_security_group_ids = [aws_security_group.allow_traffic_3.id]


    tags = {
    Name = "Bastion host"
 }
}