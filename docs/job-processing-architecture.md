# Job Processing — Components

```mermaid
%%{init: {"look":"neo"} }%%
flowchart TD
subgraph b_core["Core Services"]
db[("PostgreSQL")]
gateway(("API Gateway"))
subgraph b_core_workers["Worker Pool"]
subgraph b_core_workers_processing["Processing"]
subgraph b_core_workers_processing_executors["Executors"]
worker[["Worker"]]
end
scheduler(("Scheduler"))
end
queue[/"Job Queue"/]
end
end
db --> queue
db --> worker
gateway --> db
gateway -->|"AMQP"| queue
queue --> gateway
queue --> scheduler
scheduler --> worker
worker -->|"SQL"| db
worker --> gateway
classDef actor fill:#eef0ff,stroke:#5a67d8,color:#1a202c
classDef participant fill:#eaf5ff,stroke:#3182ce,color:#1a202c
classDef boundary fill:#edf2f7,stroke:#4a5568,color:#1a202c
classDef control fill:#e6fffa,stroke:#319795,color:#1a202c
classDef entity fill:#fffaf0,stroke:#dd6b20,color:#1a202c
classDef database fill:#faf5ff,stroke:#805ad5,color:#1a202c
classDef collections fill:#f0fff4,stroke:#38a169,color:#1a202c
classDef queue fill:#fff5f5,stroke:#e53e3e,color:#1a202c
classDef composite fill:#edf2f7,stroke:#4a5568,stroke-width:3px,color:#1a202c
classDef ancestor fill:#f7fafc,stroke:#718096,stroke-dasharray:5,5,color:#1a202c
class gateway control
class queue queue
class scheduler control
class worker collections
class db database
style db fill:#805ad5,stroke:#4a5568,color:#f7fafc
style gateway fill:#3182ce,stroke:#4a5568,color:#f7fafc
style queue fill:#38a169,stroke:#4a5568,color:#f7fafc
style scheduler fill:#3182ce,stroke:#4a5568,color:#f7fafc
style worker fill:#38a169,stroke:#4a5568,color:#f7fafc
style b_core fill:#2D3748,stroke:#4a5568,color:#f7fafc
style b_core_workers fill:#422C21,stroke:#4a5568,color:#f7fafc
```

## Related

- [Overview](README.md)
- [Job Processing](job-processing.md)
- [Acme Platform](architecture.md)

