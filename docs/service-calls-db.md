# Service → Database

Every deployed service queries the database.

This sequence is written once against the types; the architecture shows
the resulting **orders → db**, **auth → db** and **gateway → db** edges
without a sequence per service.

```mermaid
sequenceDiagram
accTitle: Service → Database
accDescr {
Every deployed service queries the database.

This sequence is written once against the types; the architecture shows
the resulting **orders → db**, **auth → db** and **gateway → db** edges
without a sequence per service.
}
participant deployed-service as Deployed Service
participant database@{ "type": "database" } as Database
deployed-service ->> database: query
```

## Related

- [Overview](./README.md)
- [Acme Platform](./architecture.md)
- [Service → Database — Components](./service-calls-db-architecture.md)
