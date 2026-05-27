# Origin Access Control for the S3 static assets bucket
resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "${var.project}-${var.env}-static-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project} ${var.env}"
  default_root_object = ""
  aliases             = [var.domain]
  price_class         = var.price_class
  wait_for_deployment = false

  # ---------------------------------------------------------------------------
  # Origin 1: S3 static assets (built Vite JS/CSS, fonts, images)
  # ---------------------------------------------------------------------------
  origin {
    origin_id                = "s3-static"
    domain_name              = "${var.static_bucket_id}.s3.amazonaws.com"
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  # ---------------------------------------------------------------------------
  # Origin 2: ALB (API, auth, SPA, WebSocket upgrades)
  # ---------------------------------------------------------------------------
  origin {
    origin_id   = "alb"
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ---------------------------------------------------------------------------
  # Cache behavior: /static/* → S3, 1 year immutable (Vite content-hashed assets)
  # ---------------------------------------------------------------------------
  ordered_cache_behavior {
    path_pattern     = "/static/*"
    target_origin_id = "s3-static"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    compress         = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 31536000
    default_ttl            = 31536000
    max_ttl                = 31536000
  }

  # ---------------------------------------------------------------------------
  # Cache behavior: /images/*, /fonts/* → S3, 7 days
  # ---------------------------------------------------------------------------
  ordered_cache_behavior {
    path_pattern     = "/images/*"
    target_origin_id = "s3-static"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    compress         = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    viewer_protocol_policy = "redirect-to-https"
    default_ttl            = 604800
    max_ttl                = 604800
  }

  ordered_cache_behavior {
    path_pattern     = "/fonts/*"
    target_origin_id = "s3-static"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    compress         = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    viewer_protocol_policy = "redirect-to-https"
    default_ttl            = 604800
    max_ttl                = 604800
  }

  # ---------------------------------------------------------------------------
  # Default behavior: /* → ALB (API, SPA, WebSocket)
  # No caching — forward all headers, cookies, query strings
  # ---------------------------------------------------------------------------
  default_cache_behavior {
    target_origin_id       = "alb"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies { forward = "all" }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { Name = "${var.project}-${var.env}-cdn" }
}

# Allow CloudFront to read the static S3 bucket via OAC
data "aws_iam_policy_document" "static_bucket" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.static_bucket_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static" {
  bucket = var.static_bucket_id
  policy = data.aws_iam_policy_document.static_bucket.json
}
