locals {
  tags = merge(
    {
      Project = var.project
    },
    var.tags
  )
}
