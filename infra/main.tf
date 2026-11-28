// =====================================================================
// Grupo 2 - SiteSimple: sitio web estatico alojado directamente en S3
// =====================================================================

// obtiene el account_id de la cuenta para que el nombre del bucket sea unico en AWS
data "aws_caller_identity" "current" {}

locals {
  // dev  -> grupo2-sitio-dev-<account_id>
  // prod -> grupo2-sitio-<account_id>
  bucket_name = "${var.bucket_prefix}-${data.aws_caller_identity.current.account_id}"
}

// bucket que aloja el sitio web
resource "aws_s3_bucket" "grupo2-sitio" {
  // checks de checkov que se omiten de forma justificada para este laboratorio:
  //checkov:skip=CKV_AWS_18:El access logging requiere un bucket de logs dedicado; no aplica a este laboratorio
  //checkov:skip=CKV_AWS_144:La replicacion cross-region requiere un segundo bucket en otra region y genera costos extra
  //checkov:skip=CKV2_AWS_6:Sitio web publico por diseño (caso SiteSimple); el bloqueo de acceso publico debe ir en false
  //checkov:skip=CKV_AWS_145:El website endpoint no entrega objetos cifrados con KMS a usuarios anonimos; se usa SSE-S3

  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Environment = var.environment
    Grupo       = "grupo2"
    Proyecto    = "SiteSimple"
  }
}

// se desactivan las ACL: el dueño del bucket es dueño de todos los objetos
// (el acceso publico se da solo con la bucket policy, no con ACL)
resource "aws_s3_bucket_ownership_controls" "grupo2-propiedad" {
  bucket = aws_s3_bucket.grupo2-sitio.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

// los 4 flags en false: sin esto la bucket policy publica es rechazada
resource "aws_s3_bucket_public_access_block" "grupo2-acceso-publico" {
  //checkov:skip=CKV_AWS_53:Sitio web publico por diseño (caso SiteSimple)
  //checkov:skip=CKV_AWS_54:Sitio web publico por diseño; la bucket policy publica debe poder aplicarse
  //checkov:skip=CKV_AWS_55:Sitio web publico por diseño (caso SiteSimple)
  //checkov:skip=CKV_AWS_56:Sitio web publico por diseño (caso SiteSimple)

  bucket = aws_s3_bucket.grupo2-sitio.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

// habilita el website hosting del bucket
resource "aws_s3_bucket_website_configuration" "grupo2-website" {
  bucket = aws_s3_bucket.grupo2-sitio.id

  index_document {
    suffix = "index.html"
  }

  // punto extra: pagina de error
  error_document {
    key = "error.html"
  }
}

// permite s3:GetObject a cualquier persona (lectura publica del sitio)
resource "aws_s3_bucket_policy" "grupo2-politica" {
  //checkov:skip=CKV_AWS_70:Principal "*" solo con s3:GetObject para que cualquiera pueda ver el sitio

  bucket = aws_s3_bucket.grupo2-sitio.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "LecturaPublicaSitioWeb"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.grupo2-sitio.arn}/*"
      }
    ]
  })

  // la politica publica solo se acepta cuando el bloqueo de acceso publico ya esta en false
  depends_on = [aws_s3_bucket_public_access_block.grupo2-acceso-publico]
}

// punto extra: versionamiento del bucket
resource "aws_s3_bucket_versioning" "grupo2-versionamiento" {
  bucket = aws_s3_bucket.grupo2-sitio.id

  versioning_configuration {
    status = "Enabled"
  }
}

// cifrado por defecto con llaves administradas por S3 (SSE-S3).
// No se usa aws:kms porque el website endpoint no entrega objetos cifrados
// con KMS a usuarios anonimos y el rol del pipeline no tiene permisos de KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "grupo2-cifrado" {
  bucket = aws_s3_bucket.grupo2-sitio.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

// reglas de ciclo de vida del bucket
resource "aws_s3_bucket_lifecycle_configuration" "grupo2-ciclo-vida" {
  bucket = aws_s3_bucket.grupo2-sitio.id

  rule {
    id     = "limpieza"
    status = "Enabled"

    // aplica a todos los objetos del bucket
    filter {}

    // borra las cargas multiparte que quedaron incompletas
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    // borra las versiones viejas de los objetos despues de 30 dias
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  // el versionamiento debe existir antes de configurar el ciclo de vida
  depends_on = [aws_s3_bucket_versioning.grupo2-versionamiento]
}

// notificaciones de eventos del bucket enviadas a EventBridge
resource "aws_s3_bucket_notification" "grupo2-notificaciones" {
  bucket      = aws_s3_bucket.grupo2-sitio.id
  eventbridge = true
}

// sube la pagina de inicio
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.grupo2-sitio.id
  key          = "index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"

  // si cambia el contenido del archivo, Terraform lo vuelve a subir (nueva version)
  etag = filemd5("${path.module}/index.html")

  depends_on = [aws_s3_bucket_versioning.grupo2-versionamiento]
}

// punto extra: sube la pagina de error
resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.grupo2-sitio.id
  key          = "error.html"
  source       = "${path.module}/error.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/error.html")

  depends_on = [aws_s3_bucket_versioning.grupo2-versionamiento]
}

// URL del sitio: aparece al final del paso "Terraform Apply" del pipeline
output "website_url" {
  description = "URL del website endpoint del bucket"
  value       = "http://${aws_s3_bucket_website_configuration.grupo2-website.website_endpoint}"
}

output "bucket_name" {
  description = "Nombre del bucket del sitio"
  value       = aws_s3_bucket.grupo2-sitio.id
}