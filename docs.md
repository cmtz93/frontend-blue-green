# 🏛️ Documento de Arquitectura: Despliegue Blue/Green para Frontend Estático

## 1\. Resumen

Esta arquitectura define un flujo de Despliegue Continuo (CD) robusto para una aplicación frontend (SPA/Estática) alojada en **AWS S3** y distribuida globalmente vía **Amazon CloudFront**.

La estrategia **Blue/Green** se implementa a nivel de infraestructura utilizando **prefijos de S3** (`/blue` y `/green`) dentro de un único bucket y conmutando el tráfico mediante la actualización del **Origin Path** en la configuración de CloudFront. Esto garantiza despliegues con tiempo de inactividad cercano a cero y una capacidad de recuperación (rollback) inmediata.

-----

## 2\. Diagrama de Alto Nivel

El siguiente diagrama ilustra el flujo de datos y control desde la publicación de una Release en GitHub hasta la entrega del contenido al usuario final.

```mermaid
graph TD
    %% Actores
    Dev[👨‍💻 Developer]
    User[🌍 Usuario Final]

    %% GitHub Ecosystem
    subgraph GitHub ["GitHub Ecosystem"]
        Release[📦 Release (Tag v1.0)]
        Actions[⚙️ GitHub Actions Runner]
    end

    %% AWS Ecosystem
    subgraph AWS ["☁️ AWS Cloud"]
        subgraph State ["Gestión de Estado"]
            SSM[📝 SSM Parameter Store]
        end

        subgraph Storage ["S3 Bucket (Origen)"]
            Temp[/temp-deploy/]
            Blue[/blue/ (v1.0)]
            Green[/green/ (v0.9)]
        end

        subgraph CDN ["CloudFront Distribution"]
            Config[⚙️ Configuración]
            Cache[🗄️ Edge Cache]
        end
    end

    %% Flujo Principal
    Dev -- "Publica Release" --> Release
    Release -- "Trigger" --> Actions
    
    %% Pasos del CI/CD
    Actions -- "1. Build & Checksum" --> Actions
    Actions -- "2. Lee Estado Activo" --> SSM
    Actions -- "3. Sube a Temp" --> Temp
    Temp -- "4. Mueve (Atomic)" --> Blue
    
    %% Validación y Swap
    Actions -- "5. Smoke Test (HTTP 200)" --> Blue
    Actions -- "6. Update Origin Path (/blue)" --> Config
    
    %% Invalidación
    Actions -- "7. Invalida Caché" --> Cache
    Actions -- "8. Actualiza Estado" --> SSM

    %% Entrega
    Config -.-> Blue
    Config -.-> Green
    User -- "HTTPS Request" --> Cache
    Cache -- "Sirve Contenido Activo" --> User

    %% Estilos
    linkStyle default stroke-width:2px,fill:none,stroke:#333;
```

-----

## 3\. Descripción Paso a Paso del Flujo

El proceso se activa únicamente cuando se publica una **Release** (ej. `v1.0.0`) en GitHub.

### Fase 1: Preparación y Construcción

1.  **Inicio del Pipeline:** GitHub Actions detecta el evento `release: published`.
2.  **Build y Validaciones:** Se instalan dependencias (`npm ci`) y se construye el proyecto (`npm run build`).
3.  **Integridad:** Se calcula un *checksum* (SHA256) de la carpeta de distribución local para verificar integridad post-subida.
4.  **Determinación del Entorno (Target):** El pipeline consulta **AWS SSM Parameter Store** para identificar qué entorno está sirviendo tráfico actualmente (ej. `blue`). Automáticamente selecciona el contrario como objetivo (ej. `green`).

### Fase 2: Despliegue Atómico (Zero-Downtime)

5.  **Subida Segura:**
      * Los archivos se suben primero a una carpeta temporal (`/temp-deploy`) en S3.
      * Una vez completada la subida, se **mueven** atómicamente al prefijo destino (`/green`).
      * *Objetivo:* Evitar que un usuario descargue una mezcla de archivos viejos y nuevos si accede justo durante la subida.

### Fase 3: Verificación (Smoke Test)

6.  **Prueba de Humo:** Antes de cambiar el tráfico, el pipeline hace una petición HTTP directa al objeto `index.html` en el prefijo destino (ej. `https://bucket.s3.amazonaws.com/green/index.html`).
      * Si la respuesta no es **200 OK**, el despliegue se aborta. El tráfico sigue fluyendo a la versión vieja (`blue`) sin afectación.

### Fase 4: Conmutación (Swap) y Publicación

7.  **Cambio de Tráfico:** Se utiliza la API de CloudFront para actualizar la configuración de la distribución. Se cambia el **Origin Path** del *Default Cache Behavior* para apuntar al nuevo prefijo (`/green`).
8.  **Invalidación de Caché:** Se fuerza una invalidación (`/*`) para asegurar que los nodos de borde (Edge Locations) eliminen la versión anterior y sirvan la nueva inmediatamente.
9.  **Persistencia de Estado:** Se actualiza el parámetro en **SSM Parameter Store** indicando que `green` es ahora el entorno activo.

-----

## 4\. Supuestos y Decisiones Clave

### A. Estrategia de Diferenciación (Prefijos vs. Buckets)

  * **Decisión:** Usar un **único bucket** con carpetas separadas (`/blue`, `/green`).
  * **Razón:** Simplifica la gestión de infraestructura (un solo recurso S3, una sola política IAM, un solo Origin Access Control). Reduce la complejidad de Terraform.
  * **Limitación:** Requiere cuidado estricto con los permisos de limpieza para no borrar accidentalmente la versión activa.

### B. Mecanismo de Swap (Origin Path)

  * **Decisión:** Cambiar el tráfico modificando el `Origin Path` en la configuración de CloudFront.
  * **Razón:** Es una solución nativa de AWS que no requiere lógica compleja en el cliente (DNS) ni cómputo en el borde (Lambda@Edge) para este caso de uso simplificado.
  * **Limitación:** La propagación de cambios de configuración en CloudFront es rápida pero no instantánea (puede tomar de segundos a un par de minutos). Durante ese breve intervalo, algunos usuarios podrían recibir la versión anterior hasta que la invalidación se complete.

### C. Gestión del Estado (SSM Parameter Store)

  * **Decisión:** Externalizar el estado "Activo" a AWS SSM en lugar de deducirlo o guardarlo en artefactos de GitHub.
  * **Razón:** SSM actúa como la "Fuente de Verdad" persistente. Permite que cualquier proceso (humano o máquina) sepa exactamente qué versión está viva sin inspeccionar la configuración de CloudFront manualmente.

### D. Atomicidad en la Subida

  * **Decisión:** Subir a `/temp` y mover a destino.
  * **Razón:** S3 ofrece consistencia de lectura tras escritura para objetos nuevos, pero la sobrescritura directa puede tener latencia de consistencia eventual. El movimiento garantiza que el conjunto de archivos aparezca completo.

### E. Rollback

  * **Decisión:** El rollback es una acción de reversión de configuración, no de redepsiegue de código.
  * **Razón:** Al mantener la versión anterior intacta en su carpeta (`/blue`), volver atrás es tan simple como cambiar el puntero de CloudFront nuevamente. Esto reduce el tiempo de recuperación (RTO) a segundos.