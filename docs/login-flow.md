# Login Flow

End-user credentials are verified against PostgreSQL, with an optional
OIDC lookup at the identity provider.

- Invalid credentials return **401**.
- An unreachable identity provider returns **503**.

```mermaid
sequenceDiagram
title Login
accTitle: Login Flow
accDescr {
End-user credentials are verified against PostgreSQL, with an optional
OIDC lookup at the identity provider.

- Invalid credentials return **401**.
- An unreachable identity provider returns **503**.
}
box Internet
actor user as End User
end
box rgb(45,51,59) Edge / DMZ
participant web@{ "type": "boundary" } as Web App
end
box rgb(45,55,72) Core Services
participant gateway@{ "type": "control" } as API Gateway
participant auth as Auth Service
participant db@{ "type": "database" } as PostgreSQL
end
participant idp@{ "type": "entity" } as Identity Provider
link auth: Runbook @ https://wiki.example/auth
link db: Metrics @ https://grafana.example/db
%% Happy path with an invalid-credentials branch
user ->> web: enter credentials
activate web
web ->>+ gateway: POST /login
gateway ->> auth: verify(credentials)
activate auth
auth ->> db: SELECT user
Note over auth: constant-time<br/>hash compare
auth ->> idp: OIDC userinfo
idp -->> auth: profile
alt valid
auth -->> gateway: OK
gateway -->> web: 200
else invalid
auth -x gateway: 401
gateway -x web: 401
else identity provider timeout
idp --x auth: timeout
auth --x gateway: 503
end
deactivate auth
Note over user,web: session established
rect rgba(0, 128, 255, 0.1)
web -->> user: show dashboard
end
web ->- gateway: close
properties auth: owner: identity-team
details gateway: tier: edge
```

## Related

- [Overview](./README.md)
- [Acme Platform](./architecture.md)
- [Login Flow — Components](./login-flow-architecture.md)
