# 📖 Runbook: Operaciones Frontend Blue/Green

**Servicio:** Frontend Estático (S3 + CloudFront)  
**Arquitectura:** Blue/Green con Swap de Origin Path y Archivador de Releases  
**Herramientas:** GitHub Actions, Terraform, AWS (S3, CloudFront, SSM, CloudWatch)

---

## 📋 1. Resumen de Arquitectura

El despliegue utiliza una estrategia **Blue/Green** dentro de un único bucket S3, diferenciado por carpetas (prefijos).

* **Estado Actual:** Se almacena en AWS SSM Parameter Store (`/deployment/project-name/active-prefix`).
* **Tráfico:** CloudFront sirve tráfico desde `/blue` o `/green` basándose en el `Origin Path` de su *Default Cache Behavior*.
* **Despliegue (Release):** GitHub Actions construye, valida y sube el artefacto a la carpeta activa (ej. `/blue` o `/green`). Además, **archiva una copia inmutable** de ese artefacto en una carpeta `/releases/vX.Y.Z/` dentro del mismo bucket S3.
* **Rollback:** En lugar de reconstruir, el rollback ahora copia el artefacto archivado de la versión deseada (`/releases/vX.Y.Z/`) a la carpeta Blue/Green inactiva, y luego realiza el swap de CloudFront.

---

## 🚀 2. Procedimientos de Despliegue (SOP)

### 2.1. Despliegue de una Nueva Release
El despliegue es **totalmente automatizado** y se dispara por la publicación de una Release en GitHub.

1.  **Trigger:** Crear y **publicar una nueva Release** (con un tag como `v1.0.0`) en GitHub.
2.  **Proceso Automático (`Production Release Deploy` workflow):**
    * El pipeline hace checkout del código asociado al tag de la Release.
    * Construye la aplicación y calcula un checksum.
    * Determina el entorno inactivo (ej. `green` si `blue` está activo).
    * Sube el artefacto a una carpeta temporal en S3 (`/temp-deploy`).
    * Mueve atómicamente el artefacto a la carpeta del entorno inactivo (ej. `s3://bucket/green/`).
    * **Archiva una copia inmutable** del artefacto completo en `s3://bucket/releases/vX.Y.Z/`.
    * Ejecuta un `Smoke Test` (verifica HTTP 200) sobre el nuevo entorno inactivo.
    * Realiza el *Swap* en CloudFront (cambiando el `Origin Path` al nuevo entorno).
    * Invalida la caché de CloudFront.
    * Actualiza el parámetro en SSM con el nuevo entorno activo.
3.  **Verificación:** Revisar el GitHub Action "Production Release Deploy" para confirmar el éxito. Verificar visualmente el sitio web y el monitoreo.

### 2.2. Despliegue de Infraestructura (Terraform)
Cualquier cambio en archivos `.tf` dentro de `/iac` dispara un pipeline separado de Terraform.

1.  **Cambio:** Crear una rama y modificar archivos en `/iac`.
2.  **Plan:** Abrir un Pull Request. El bot comentará con el `terraform plan`. **Revisar cuidadosamente**.
3.  **Apply:** Al hacer merge a `main`, se ejecuta `terraform apply` automáticamente.

---

## 🚨 3. Procedimiento de Emergencia (Fast Rollback)

> **⚠️ CRÍTICO:** Ejecutar este procedimiento si se detectan errores 5xx elevados, pantalla blanca (WSOD) o fallos críticos de funcionalidad inmediatamente después de un despliegue, o si una versión antigua específica debe ser restaurada.

### Pasos para el Fast Rollback desde Archivo

1.  **Ir a GitHub Actions:** Navega a la pestaña "Actions" del repositorio.
2.  **Seleccionar Workflow:** Elige **"⚡ Fast Rollback from Archive"** en la barra lateral izquierda.
3.  **Ejecutar:**
    * Haz clic en **Run workflow**.
    * Branch: `main`.
    * **Rollback Tag:** Ingresa el **tag exacto** de la Release a la que deseas revertir (ej. `v1.0.0`).
        * **Importante:** Este tag debe corresponder a una versión previamente archivada en `s3://bucket/releases/vX.Y.Z/`.
    * **Reason:** Escribe una razón breve (ej. "Error 500 en checkout").
    * Haz clic en el botón verde **Run workflow**.
4.  **Validar:**
    * El proceso es muy rápido (aprox. **30-60 segundos**) ya que solo copia archivos en S3 y actualiza CloudFront.
    * Verifica que el sitio web carga la versión anterior/especificada.
    * El parámetro en SSM Parameter Store se actualizará automáticamente para reflejar el estado revertido.

---

## 🔧 4. Guía de Solución de Problemas (Troubleshooting)

### Escenario A: El Pipeline de Despliegue falla en "Smoke Test"
**Síntoma:** El job "Production Release Deploy" falla antes del paso "Swap CloudFront".
**Causa:** El `index.html` no se subió correctamente o la aplicación no compila bien.
**Acción:**
1.  Revisar logs de los pasos "Build Release Artifact" y "Atomic Upload to S3".
2.  **No se requiere Rollback:** El tráfico nunca se cambió a la nueva versión. El entorno productivo sigue sirviendo la versión anterior.

### Escenario B: Error "403 Forbidden" o "Access Denied" en el sitio
**Causa:** Problemas con permisos OAC (CloudFront) o Bloqueo de Acceso Público S3.
**Acción:**
1.  Verificar que el recurso `aws_s3_bucket_policy` en Terraform esté correcto.
2.  Asegurar que el bucket NO tenga ACLs públicas, pero que la política permita al `Principal: cloudfront.amazonaws.com`.

### Escenario C: Error "404 Not Found" en assets (JS/CSS)
**Causa:** El HTML está buscando archivos en una ruta que no coincide con el prefijo actual, o el caché del navegador tiene referencias viejas.
**Acción:**
1.  Verificar si el `<base href>` o los `publicPath` en la configuración de build (Vite/Webpack) son relativos (`./`) o absolutos.
2.  Si usas rutas absolutas, asegúrate de que no incluyan el prefijo `/blue` o `/green` hardcodeado. CloudFront hace el mapeo de `/a.js` a `s3://bucket/blue/a.js`.

### Escenario D: El Fast Rollback falla porque el "Rollback Tag" no existe en S3
**Síntoma:** El job "Fast Rollback from Archive" falla en el paso "Restore Artifact from Archive" con un mensaje de "Error: No existe un archivo para la release [TAG] en S3."
**Causa:** El tag de la Release especificado no corresponde a un artefacto que haya sido archivado previamente por un despliegue exitoso.
**Acción:**
1.  Verificar la lista de objetos en `s3://[TU_BUCKET_S3]/releases/` para confirmar los tags disponibles.
2.  Asegurarse de que el tag introducido en el input del workflow sea exactamente el mismo que el de una Release archivada.

---

## 📊 5. Monitoreo y Alertas

### Métricas Clave (CloudWatch)
* **`5xxErrorRate`:** Debe ser < 1%. Un pico indica fallo de servidor (ej. código JS corrupto) o configuración S3.
* **`OriginLatency`:** Normal < 200ms. Un aumento > 1s sugiere problemas con el bucket S3 o red.

### Suscripción a Alertas
Las alertas críticas de CloudWatch (ej. `5xxErrorRate` elevado) se publican en un tópico SNS. Para recibir estas alertas, debes suscribirte a este tópico:

1.  **Obtener ARN del Tópico SNS:**
    * En la consola de AWS, ve a **SNS > Temas**.
    * Busca el tema con el nombre que termina en `-alerts-topic` (ej. `[tu-proyecto]-alerts-topic`).
    * Copia el **ARN del Tema**. También está disponible en los `outputs.tf` de Terraform como `sns_alerts_topic_arn`.
2.  **Añadir Suscripción:**
    * Con el ARN del tema, haz clic en **"Crear suscripción"**.
    * **Protocolo:**
        * `Email`: Para recibir alertas por correo electrónico. Introduce tu dirección de correo.
        * `HTTPS`: Para integrar con sistemas de chat (Slack, Teams) o Lambda para automatización.
    * **Endpoint:** Introduce el correo electrónico o la URL del webhook (para HTTPS).
    * Haz clic en "Crear suscripción".
3.  **Confirmar (Email):** Si elegiste Email, recibirás un correo de AWS pidiéndote confirmar la suscripción. Haz clic en el enlace para activarla.

### Dashboards
* **Link al Dashboard:** `[INSERTAR LINK A CLOUDWATCH DASHBOARD]`
* **Logs:** Consultar logs de acceso de CloudFront si están habilitados (S3 logging bucket).

---

## 📞 6. Contactos de Escalado

| Rol | Nombre | Contacto |
| :--- | :--- | :--- |
| **DevOps On-Call** | Equipo SRE | `@sre-team` (Slack) |
| **Tech Lead** | [Nombre] | `+1-555-0100` |
| **AWS Support** | Soporte | [Link al portal] |
