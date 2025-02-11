output "svn_user_access_key_id" {
  value = aws_iam_access_key.key.id
}

output "svn_user_secret_access_key" {
  value = aws_iam_access_key.key.secret
}