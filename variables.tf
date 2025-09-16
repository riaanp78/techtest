variable "db_password" {
  description = "Password for the PostgreSQL database user"
  type        = string
  sensitive   = true
}

variable "git_pat" {
  description = "GitHub Personal Access Token for cloning the repository"
  type        = string
  sensitive   = true
}


variable "db_user" {
  description = "PostgreSQL username for the app"
  type        = string
  default     = "appuser"
}

variable "db_name" {
  description = "PostgreSQL database name for the app"
  type        = string
  default     = "appdb"
}

variable "db_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "update_app" {
  description = "Whether to trigger an app update via SSM"
  type        = bool
  default     = false
}
