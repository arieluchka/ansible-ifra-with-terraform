variable tennant-ID {
  type        = string
  default     = "e88e23da-5c50-42e4-8175-2d79b4305ab6"
  description = "description"
}



variable "location" {
  type = string
  default = "eastus"
}

variable "username" {
  type = string
  default = "ariel"
}

variable "password" {
  type = string
  default = "AriK2001_"
  sensitive = true
}

variable "pip_for_slaves" {
  type = bool
  default = true
}