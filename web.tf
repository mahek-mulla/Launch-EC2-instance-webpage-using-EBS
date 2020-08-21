provider "aws" {
  region = "ap-south-1"
  profile = "default"
 }

// Key creation

resource "tls_private_key" "webkey" {
  algorithm   = "RSA"
  rsa_bits = 2048
}

resource "local_file" "private_key" {
    content     = tls_private_key.webkey.private_key_pem
    filename = "mywebkey.pem"
    file_permission = 0400	
}

resource "aws_key_pair" "key" {
  key_name   = "websitekey"
  public_key = tls_private_key.webkey.public_key_openssh
  }
//VPC default

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

//Security Group

resource "aws_security_group" "security" {
  name        = "websecurity"
  description = "Allows ssh and http connection"
  vpc_id = aws_default_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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
    Name = "websecuritygroup"
  }
}

//EC2 instance 

resource "aws_instance" "web" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name= aws_key_pair.key.key_name
  security_groups =[ "websecurity"]

 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.webkey.private_key_pem
    host     = aws_instance.web.public_ip
  }

 provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",	
     ]
  }

  tags = {
    Name = "WebOS"
  }
}

//EBS volume
resource "aws_ebs_volume" "ebs" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1

  tags = {
    Name = "EBS"
  }
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.ebs.id}"
  instance_id = "${aws_instance.web.id}"
  force_detach = true
}

//Make partition and mount

resource "null_resource" "nullremote3"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.webkey.private_key_pem
    host     = aws_instance.web.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/mahek-mulla/task1cloud.git /var/www/html/"
    ]
  }
}


// S3 bucket creation
resource "aws_s3_bucket" "s3-bucket" {
	bucket = "web-bucket-cook"  //unique name of s3 bucket in the entire region
  	acl    = "public-read"
	provisioner "local-exec" {
        	command     = "git clone https://github.com/mahek-mulla/task1cloud.git multi-cloud"
    	}
	
  	tags = {
   	Name        = "My-S3-bucket"
    	Environment = "Production"
  	}
	versioning {
	enabled= true
	}
}

//Upload images on S3
resource "aws_s3_bucket_object" "image-upload1" {
    bucket  = aws_s3_bucket.s3-bucket.bucket
    key     = "hamburger.jpg"
    source  = "multi-cloud/hamburger.jpg"
    acl     = "public-read"
}

resource "aws_s3_bucket_object" "image-upload2" {
    bucket  = aws_s3_bucket.s3-bucket.bucket
    key     = "tablesetting.jpg"
    source  = "multi-cloud/tablesetting.jpg"
    acl     = "public-read"
}

resource "aws_s3_bucket_object" "image-upload3" {
    bucket  = aws_s3_bucket.s3-bucket.bucket
    key     = "tablesetting2.jpg"
    source  = "multi-cloud/tablesetting2.jpg"
    acl     = "public-read"
}


//Cloudfront

locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
	origin {
		domain_name = "${aws_s3_bucket.s3-bucket.bucket_regional_domain_name}"
		origin_id   = "${local.s3_origin_id}"



        	custom_origin_config {
            		http_port = 80
            		https_port = 80
            		origin_protocol_policy = "match-viewer"
            	origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"] 
        	}
    	}
       
	enabled = true




    	default_cache_behavior {
        	allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        	cached_methods = ["GET", "HEAD"]
        	target_origin_id = "${local.s3_origin_id}"


        	forwarded_values {
            		query_string = false
        
            		cookies {
               			forward = "none"
            		}
        	}
        	viewer_protocol_policy = "allow-all"
        	min_ttl = 0
        	default_ttl = 3600
        	max_ttl = 86400
    	}


    	restrictions {
        	geo_restriction {
            		restriction_type = "none"
        	}
    	}


	viewer_certificate {
        cloudfront_default_certificate = true
    }
}


resource "null_resource" "nulllocal1"  {


depends_on = [
    null_resource.nullremote3,aws_s3_bucket_object.image-upload1,aws_s3_bucket_object.image-upload2,aws_s3_bucket_object.image-upload3,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.web.public_ip}"
  	}
}





