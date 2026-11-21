// crear un nuevo bucket de s3
resource "aws_s3_bucket" "my_bucket" {
    // checks de checkov que se omiten de forma justificada para este laboratorio:
    //checkov:skip=CKV_AWS_18:El access logging requiere un bucket de logs dedicado; no aplica a este laboratorio
    //checkov:skip=CKV_AWS_144:La replicacion cross-region requiere un segundo bucket en otra region y genera costos extra

    // el nombre del bucket va a ser el nombre de la variable bucket_name
    // que se define en el archivo variables.tf
    // y se obtiene del archivo terraform.tfvars
    bucket        = var.bucket_name
    force_destroy = true

    tags = {
        Environment = "dev"
        Grupo       = "grupo2"
    }
}

// se habilita el versionamiento del bucket
// (reemplaza el bloque "versioning" que esta deprecado dentro de aws_s3_bucket)
resource "aws_s3_bucket_versioning" "my_bucket" {
    bucket = aws_s3_bucket.my_bucket.id

    versioning_configuration {
        status = "Enabled"
    }
}

// se desactivan las ACL: el dueño del bucket es dueño de todos los objetos
// (reemplaza el argumento "acl" que esta deprecado dentro de aws_s3_bucket)
resource "aws_s3_bucket_ownership_controls" "my_bucket" {
    bucket = aws_s3_bucket.my_bucket.id

    rule {
        object_ownership = "BucketOwnerEnforced"
    }
}

// se bloquea todo el acceso publico al bucket (CKV2_AWS_6 y CKV_AWS_20)
resource "aws_s3_bucket_public_access_block" "my_bucket" {
    bucket = aws_s3_bucket.my_bucket.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

// cifrado por defecto con KMS usando la llave administrada por AWS (aws/s3) (CKV_AWS_145)
resource "aws_s3_bucket_server_side_encryption_configuration" "my_bucket" {
    bucket = aws_s3_bucket.my_bucket.id

    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "aws:kms"
        }
        // reduce las llamadas a KMS (y su costo)
        bucket_key_enabled = true
    }
}

// reglas de ciclo de vida del bucket (CKV2_AWS_61)
resource "aws_s3_bucket_lifecycle_configuration" "my_bucket" {
    bucket = aws_s3_bucket.my_bucket.id

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
    depends_on = [aws_s3_bucket_versioning.my_bucket]
}

// notificaciones de eventos del bucket enviadas a EventBridge (CKV2_AWS_62)
resource "aws_s3_bucket_notification" "my_bucket" {
    bucket      = aws_s3_bucket.my_bucket.id
    eventbridge = true
}
