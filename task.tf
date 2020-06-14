provider "aws" {
	region = "ap-south-1"
	profile = "terraform_profile"
}

#creating ssh key pair

/* resource "tls_private_key" "webserver-private-key" {
    algorithm = "RSA"
}

resource "aws_key_pair" "webserver-key" {
  key_name   = "webserver-key"
  public_key = tls_private_key.webserver-private-key.public_key_openssh
} */

#creating security group

resource "aws_security_group" "tf_security_group" {
	name = "tf_security_group"
	description = "Security group to allow HTTP connection"
	vpc_id = "vpc-e409158c"
	
	ingress {
		description = "Allow inbound connection on port 80"
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = [ "0.0.0.0/0" ]
	}

	ingress {
		description = "Allow inbound connection on port 22 for SSH"
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = [ "0.0.0.0/0" ]
	}

	egress {
		description = "Allow outbound connections"
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = [ "0.0.0.0/0" ]
	}

	tags = {
		Name = "tf_security_group"
	}
}

#creating ec2 instance

resource "aws_instance" "webserver" {
	depends_on = [ aws_security_group.tf_security_group ]
	ami = "ami-0447a12f28fddb066"
	instance_type = "t2.micro"
	key_name = "webserver"
	security_groups = [ "tf_security_group" ]
	#user_data = "${file("startup.sh")}"
	tags = {
		Name = "WebServer"
	}

	connection {
		type     = "ssh"
    	user     = "ec2-user"
    	private_key = file("D:/AWS Node Server keys/webserver.pem")
    	host     = aws_instance.webserver.public_ip
	}

	provisioner "remote-exec" {
		inline = [
			"sudo setenforce 0",
			"sudo yum install httpd php git -y",
			"sudo systemctl start httpd",
			"sudo systemctl enable httpd",
		]
	}
	
}

#creating ebs volume

resource "aws_ebs_volume" "webserver_volume" {
	availability_zone = aws_instance.webserver.availability_zone
	depends_on = [ aws_instance.webserver ]
	size = 10
	tags = {
		Name = "webserver_volume"
	}
}

#attaching the ebs volume on the ec2 instance created above

resource "aws_volume_attachment" "webserver_volume_attachment" {
	device_name = "/dev/sdc"
	depends_on = [ aws_ebs_volume.webserver_volume ]
	volume_id = aws_ebs_volume.webserver_volume.id
	instance_id = aws_instance.webserver.id
}

#mounting the volume created and attached on the ec2 instance

resource "null_resource" "mount_webserver_volume" {
	depends_on = [ aws_volume_attachment.webserver_volume_attachment ]
	connection {
		type     = "ssh"
    	user     = "ec2-user"
    	private_key = file("webserver.pem")
    	host     = aws_instance.webserver.public_ip
	}

	provisioner "remote-exec" {
		inline = [
			"sudo parted -a opt /dev/xvdc mkpart primary 0% 100%",
			"sudo mkfs.ext4 /dev/xvdc",
			"sudo mount /dev/xvdc /var/www/html",
			"sudo rm -Rf /var/www/html/*",
			"https://github.com/kartikay1506/terraform-task1.git"
		]
	}
}

#creating s3 bucket

resource "aws_s3_bucket" "webserver-bucket" {
	depends_on = [ aws_volume_attachment.webserver_volume_attachment ]
	bucket = "terraform-webserver-bucket"
	region = "ap-south-1"
	tags = {
		Name = "webserver-bucket"
	}
}

#uploading the object to s3 bucket created above

resource "aws_s3_bucket_object" "webserver_bucket_object" {
	bucket = aws_s3_bucket.webserver-bucket.id
	acl = "public-read"
	key = "assets/image.jpg"
	source = "image.jpg"
}

#creating cloudfront distribution with origin set to s3 bucket created above

locals {
	s3_origin_id = "S3-terraform-webserver-bucket"
}

resource "aws_cloudfront_distribution" "terrform_distribution" {
	depends_on = [ aws_s3_bucket_object.webserver_bucket_object ]
	origin {
    		domain_name = aws_s3_bucket.webserver-bucket.bucket_domain_name
    		origin_id   = "S3-${aws_s3_bucket.webserver-bucket.bucket}"
  	}
	
	enabled             = true
  	is_ipv6_enabled     = true
  	comment             = "Cloudfront Distribution created through Terraform"
  	default_root_object = "index.html"

  

  	default_cache_behavior {
    		allowed_methods  = ["GET", "HEAD"]
    		cached_methods   = ["GET", "HEAD"]
    		target_origin_id = "${local.s3_origin_id}"

    		forwarded_values {
      			query_string = false

      			cookies {
        			forward = "none"
      			}
    		}

    		viewer_protocol_policy = "allow-all"
    		min_ttl                = 0
    		default_ttl            = 3600
    		max_ttl                = 86400
  	}

  	# Cache behavior with precedence 0
  	ordered_cache_behavior {
    		path_pattern     = "assets/*.jpg"
    		allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    		cached_methods   = ["GET", "HEAD", "OPTIONS"]
    		target_origin_id = "${local.s3_origin_id}"

    		forwarded_values {
      			query_string = false
      			headers      = ["Origin"]

      			cookies {
        			forward = "none"
      			}
    		}

    		min_ttl                = 0
    		default_ttl            = 86400
   			max_ttl                = 31536000
    		compress               = true
    		viewer_protocol_policy = "redirect-to-https"
  	}

  	price_class = "PriceClass_All"

  	restrictions {
    		geo_restriction {
      		restriction_type = "whitelist"
      		locations        = ["IN", "US"]
    		}
  	}

  	tags = {
    		Source = "terraform"
  	}

  	viewer_certificate {
    		cloudfront_default_certificate = true
  	}
}

output "cloudfront-cdn" {
	value = aws_cloudfront_distribution.terrform_distribution.domain_name
}