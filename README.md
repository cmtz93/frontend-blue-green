# frontend-blue-green

-----

# ✅ Checklist de "Vuelo" (Pre-Despliegue)

Este checklist detalla los pasos y verificaciones esenciales que deben realizarse **antes del primer despliegue real** de la infraestructura y aplicación. Una configuración incorrecta en esta fase puede llevar a fallos en el pipeline o problemas de seguridad.

-----

## 📋 1. Configuración de AWS

### 1.1. Backend de Terraform

El estado de Terraform (`terraform.tfstate`) debe persistir en un backend remoto para garantizar la consistencia y permitir el trabajo en equipo.

  * [ ] **Bucket S3 para `tfstate`:**
      * [ ] Asegurarse de que el bucket S3 especificado en el bloque `backend "s3"` de `iac/main.tf` **ya existe** en tu cuenta de AWS.
      * [ ] (Recomendado) Verificar que el **Versionamiento** está habilitado en este bucket para recuperar estados anteriores.
      * [ ] (Recomendado) Verificar que la **Encriptación por defecto** (SSE-S3 o KMS) está habilitada en este bucket.
  * [ ] **Tabla DynamoDB para Locks (Opcional pero recomendado):**
      * [ ] Si estás utilizando `dynamodb_table` en tu backend de Terraform, asegurarte de que la tabla DynamoDB especificada **ya existe** y tiene una clave primaria llamada `LockID` (tipo String).

### 1.2. Dominio y Certificado SSL

El acceso seguro y público a tu aplicación requiere una configuración de DNS y SSL adecuada.

  * [ ] **Zona Hosted en Route 53:**
      * [ ] Verificar que la Zona Hosted (`var.hosted_zone_id`) para tu dominio (`var.domain_name`) existe en AWS Route 53.
  * [ ] **Certificado ACM:**
      * [ ] Asegurarse de que el certificado ACM (`aws_acm_certificate.cert`) ha sido **validado** (generalmente por DNS a través de Route 53) en la región `us-east-1`. Este proceso puede tomar varios minutos.

-----

## 2\. Configuración de GitHub

### 2.1. Secretos del Repositorio

Los pipelines de GitHub Actions necesitan credenciales seguras para interactuar con AWS.

  * [ ] Navegar a **Settings \> Secrets and variables \> Actions** en tu repositorio de GitHub.
  * [ ] Verificar que los siguientes secretos existen y contienen los valores correctos (obtenidos de los `outputs` de Terraform después del primer `terraform apply` exitoso):
      * [ ] `AWS_ROLE_ARN`: ARN del Rol de IAM que GitHub asumirá.
      * [ ] `S3_BUCKET_NAME`: Nombre del bucket S3 de tu frontend.
      * [ ] `CF_DISTRIBUTION_ID`: ID de la distribución de CloudFront de Producción.
      * [ ] `CF_DIST_ID_STAGING`: ID de la distribución de CloudFront de Staging.
      * [ ] `SSM_PARAMETER_NAME`: Nombre del parámetro SSM que gestiona el estado Blue/Green.

### 2.2. Rol de IAM y OIDC

La seguridad entre GitHub Actions y AWS se basa en OpenID Connect (OIDC).

  * [ ] En la consola de AWS IAM, buscar el rol creado por Terraform (ej. `[project_name]-github-deploy-role`).
  * [ ] En la pestaña **"Trust relationships"** (Relaciones de Confianza) del rol, verificar que la política permite a `token.actions.githubusercontent.com` asumir el rol, específicamente para tu repositorio:
      * `"Condition": { "StringLike": { "token.actions.githubusercontent.com:sub": "repo:cmtz93/frontend-blue-green:*" } }`

-----

## 3\. Estructura y Código del Repositorio

### 3.1. Archivos Terraform

  * [ ] Verificar que todos los archivos `.tf` están en la carpeta **`/iac`** en la raíz del repositorio.
  * [ ] Confirmar que el `main.tf` dentro de `/iac` tiene el bloque `backend "s3"` correctamente configurado con los detalles del bucket y tabla DynamoDB pre-existentes.

### 3.2. Workflows de GitHub Actions

  * [ ] Verificar que los archivos `deploy.yml`, `staging.yml`, `terraform-deploy.yml` y `rollback-fast.yml` existen en la carpeta **`.github/workflows/`**.
  * [ ] (Opcional) Revisar las variables de entorno (`env`) dentro de cada workflow para asegurarse de que apuntan a los secretos correctos.

-----

## 4\. Primer Despliegue (Secuencia Recomendada)

1.  **Ejecutar Terraform:** Primero, asegúrate de que Terraform construya la infraestructura en AWS.
    ```bash
    cd iac
    terraform init
    terraform apply --auto-approve
    ```
      * **Importante:** Copia todos los `outputs` relevantes para los secretos de GitHub.
2.  **Configurar Secretos:** Pegar los `outputs` de Terraform en los Secrets de GitHub (Paso 2.1).
3.  **Primer Despliegue de Staging:** Realiza un `git push` a la rama `main` para activar el pipeline de Staging.
4.  **Primer Despliegue de Producción:** Si Staging se ve bien, crea y publica una **Release** en GitHub (ej. `v1.0.0`) para activar el pipeline de Producción.

-----
