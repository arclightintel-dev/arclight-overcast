variable "admin_object_id" {
  description = "Object ID of john@arclightlabs.io, verified through the signed-in administrator's Microsoft Graph /me response."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.admin_object_id))
    error_message = "admin_object_id must be a verified Microsoft Entra object UUID."
  }
}

variable "certificate_pem" {
  description = "Public X.509 certificate in PEM format. Never provide a private key or PFX."
  type        = string
  nullable    = false

  validation {
    condition = (
      startswith(trimspace(var.certificate_pem), "-----BEGIN CERTIFICATE-----") &&
      endswith(trimspace(var.certificate_pem), "-----END CERTIFICATE-----") &&
      !strcontains(var.certificate_pem, "PRIVATE KEY")
    )
    error_message = "certificate_pem must contain only a public PEM certificate, never a private key."
  }
}

variable "certificate_start_date" {
  description = "Fixed certificate NotBefore date in RFC3339 format, supplied by the local credential-generation script."
  type        = string
  nullable    = false

  validation {
    condition     = can(timeadd(var.certificate_start_date, "0s"))
    error_message = "certificate_start_date must be an RFC3339 timestamp."
  }
}

variable "certificate_end_date" {
  description = "Fixed certificate NotAfter date in RFC3339 format, supplied by the local credential-generation script."
  type        = string
  nullable    = false

  validation {
    condition     = try(timecmp(var.certificate_end_date, var.certificate_start_date) > 0, false)
    error_message = "certificate_end_date must be an RFC3339 timestamp later than certificate_start_date."
  }
}
