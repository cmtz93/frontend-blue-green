# 📘 Documentación: Pipeline de Automatización de Infraestructura (Terraform)

Este documento describe cómo utilizar el flujo de trabajo de GitHub Actions configurado en este repositorio para gestionar la infraestructura de AWS mediante **Terraform**.

El pipeline implementa prácticas de CI/CD para Infraestructura como Código (IaC), asegurando revisiones automáticas (`plan`) en Pull Requests y despliegues automáticos (`apply`) en la rama principal.

---

## 📋 1. Requisitos Previos

Antes de ejecutar este pipeline, es obligatorio tener configurados los siguientes recursos en AWS y GitHub.

### A. Infraestructura Base (Backend Remoto)
Terraform necesita un lugar para guardar su archivo de estado (`terraform.tfstate`) fuera del entorno efímero de GitHub. Estos recursos deben existir en AWS antes del primer despliegue:

1.  **Bucket S3:** Para almacenar el archivo de estado.
    * *Nombre sugerido:* `[proyecto]-terraform-state`
    * *Configuración:* Versionado habilitado, encriptación activada.
2.  **Tabla DynamoDB (Opcional):** Para el bloqueo de estado (evita condiciones de carrera).
    * *Partition key:* `LockID` (String).

### B. Autenticación (OIDC)
El pipeline utiliza un **Rol de IAM** con OpenID Connect (OIDC) para autenticarse sin usar *Access Keys* estáticas.
* El Rol debe tener una relación de confianza con el proveedor de identidad de GitHub.
* El Rol debe tener permisos suficientes (`s3:*`, `cloudfront:*`, `route53:*`, `iam:*`, `ssm:*`) para gestionar los recursos definidos.

### C. Secretos del Repositorio
Configura el siguiente secreto en **Settings > Secrets and variables > Actions**:

| Nombre del Secreto | Descripción | Ejemplo |
| :--- | :--- | :--- |
| `AWS_ROLE_ARN` | El ARN del rol de IAM que GitHub asumirá. | `arn:aws:iam::123456789:role/GitHubDeployRole` |

---

## 📂 2. Estructura del Repositorio

El pipeline está configurado para detectar cambios **exclusivamente** en la carpeta `/iac`.

```text
/ (Raíz del Repo)
├── .github/
│   └── workflows/
│       └── terraform-deploy.yml  <-- Definición del Pipeline
├── iac/                          <-- CARPETA VIGILADA
│   ├── main.tf                   <-- Configuración del Backend y Providers
│   ├── variables.tf
│   ├── outputs.tf
│   └── ... (.tf files)
└── README.md