graph TD
    %% --- Estilos ---
    classDef gh fill:#24292e,stroke:#ffffff,stroke-width:2px,color:white;
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:white;
    classDef decision fill:#f0db4f,stroke:#333,stroke-width:2px,color:black;
    classDef error fill:#ff4d4d,stroke:#333,stroke-width:2px,color:white;

    %% --- CI/CD Pipeline ---
    subgraph CI_CD ["🔄 CI/CD Pipeline (GitHub Actions)"]
        Start(("🚀 Push a Main")):::gh --> Build[Build & Checksum]:::gh
        
        Build --> ReadState["Leer Estado Actual (SSM)"]:::aws
        ReadState --> Logic{"¿Cuál es el Target?"}:::decision
        Logic -- "Actual: Blue" --> SetGreen[Target: GREEN]
        Logic -- "Actual: Green" --> SetBlue[Target: BLUE]
        
        SetGreen & SetBlue --> UploadTemp["1. Subir a S3 /temp"]:::aws
        UploadTemp --> AtomicMove["2. Mover a S3 /target"]:::aws
        
        AtomicMove --> SmokeTest{"3. Smoke Test (Curl)"}:::decision
        
        SmokeTest -- Fallo --> Fail["❌ Detener Pipeline"]:::error
        SmokeTest -- Éxito --> Swap["4. CloudFront Swap (Update Origin Path)"]:::aws
        
        Swap --> Invalidate["5. Invalidar Caché"]:::aws
        Invalidate --> UpdateState["6. Actualizar SSM Parameter"]:::aws
        UpdateState --> NotifySuccess["✅ Notificar Éxito"]:::gh
    end

    %% --- Infraestructura ---
    subgraph AWS ["☁️ AWS Infrastructure"]
        S3[("S3 Bucket: /blue & /green")]
        CF[CloudFront Distribution]
        SSM[SSM Parameter Store]
        
        CF -- Tráfico --> S3
        
        subgraph Monitoring ["👁️ Observability"]
            Metrics["Métricas (5xx / Latencia)"]
            Alarms{CloudWatch Alarms}
            SNS["SNS Topic (Email/Slack)"]
        end
    end

    %% --- Rollback Process ---
    subgraph Recovery ["↩️ Estrategia de Rollback"]
        SNS -- "🚨 Alerta Recibida" --> Engineer["👨‍💻 Ingeniero DevOps"]
        Engineer -- Ejecuta Workflow --> ManualRB["GitHub Action: Emergency Rollback"]:::gh
        ManualRB -- Revertir Path --> CF
        ManualRB -- Actualizar Estado --> SSM
    end

    %% Conexiones
    AtomicMove --> S3
    Swap --> CF
    UpdateState --> SSM
    CF --> Metrics --> Alarms --> SNS
    Fail --> NotifyFail["📢 Notificar Fallo"]:::gh