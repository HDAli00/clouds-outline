resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project}-${var.env}-redis-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.project}-${var.env}-redis-subnet-group" }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project}-${var.env}-redis"
  description          = "Outline ${var.env} Redis - Bull queues, Socket.IO pub/sub, Y.js sync"

  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.node_type
  num_cache_clusters   = var.num_replicas + 1  # 1 primary + replicas

  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = var.security_group_ids

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "preferred"  # accepts both TLS and plain during migration

  automatic_failover_enabled = var.num_replicas > 0

  tags = { Name = "${var.project}-${var.env}-redis" }
}
