output "build_bucket_name" {
  value = aws_s3_bucket.build_bucket.id
}

output "artifacts_bucket_name" {
  value = aws_s3_bucket.artifacts_bucket.id
}
