output "runner_instance_id" {
  value = aws_instance.runner.id
}

output "runner_label" {
  value = var.project_name
}

output "docker_build_ecr_repository_name" {
  value = aws_ecr_repository.docker_build.name
}

output "docker_build_ecr_repository_url" {
  value = aws_ecr_repository.docker_build.repository_url
}

output "runner_security_group_id" {
  value = aws_security_group.runner.id
}

output "runner_iam_role_name" {
  value = aws_iam_role.runner.name
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
