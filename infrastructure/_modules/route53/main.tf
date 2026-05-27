data "aws_route53_zone" "this" {
  # Looks up the hosted zone by the root domain.
  # Assumes the zone already exists in Route 53.
  name         = join(".", slice(split(".", var.domain), 1, length(split(".", var.domain))))
  private_zone = false
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = var.cf_domain
    zone_id                = var.cf_zone_id
    evaluate_target_health = false
  }
}
