# tbot Go API -- Embedding tbot Programmatically

Use the tbot Go libraries to embed Teleport Machine Identity directly in a Go application. This avoids running tbot as a sidecar or writing credentials to disk -- the application obtains and renews certificates in-process and builds Teleport API clients from them.

**Primary packages:**

| Package | Import Path | Purpose |
|---------|-------------|---------|
| `embeddedtbot` | `github.com/gravitational/teleport/integrations/lib/embeddedtbot` | High-level wrapper for embedding tbot in Go applications |
| `tbot` | `github.com/gravitational/teleport/lib/tbot` | Full tbot binary logic (config parsing, service orchestration) |
| `bot` | `github.com/gravitational/teleport/lib/tbot/bot` | Core bot engine: `Config`, `Bot`, `Service`, `ServiceBuilder` |
| `config` | `github.com/gravitational/teleport/lib/tbot/config` | YAML config parsing (`BotConfig`) for the tbot binary |
| `onboarding` | `github.com/gravitational/teleport/lib/tbot/bot/onboarding` | Join method and token configuration |
| `connection` | `github.com/gravitational/teleport/lib/tbot/bot/connection` | Address and connection configuration |
| `destination` | `github.com/gravitational/teleport/lib/tbot/bot/destination` | Storage backends (memory, directory) |
| `clientcredentials` | `github.com/gravitational/teleport/lib/tbot/services/clientcredentials` | In-memory `client.Credentials` service |

---

## Quick Start: Embedded tbot

The `embeddedtbot` package is the recommended way to embed tbot. It handles configuration, lifecycle, and provides a ready-to-use Teleport API client.

```go
package main

import (
    "context"
    "log"
    "log/slog"
    "time"

    "github.com/gravitational/teleport/api/types"
    "github.com/gravitational/teleport/integrations/lib/embeddedtbot"
    "github.com/gravitational/teleport/lib/tbot/bot"
    "github.com/gravitational/teleport/lib/tbot/bot/onboarding"
)

func main() {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()

    logger := slog.Default()

    botCfg := &embeddedtbot.BotConfig{
        AuthServer: "teleport.example.com:443",
        Onboarding: onboarding.Config{
            TokenValue: "my-bot-token",
            JoinMethod: types.JoinMethodKubernetes,
        },
    }

    ebot, err := embeddedtbot.New(botCfg, logger)
    if err != nil {
        log.Fatal(err)
    }

    // StartAndWaitForClient starts the bot, waits for the first certificate
    // renewal, and returns a ready Teleport API client.
    client, err := ebot.StartAndWaitForClient(ctx, 30*time.Second)
    if err != nil {
        log.Fatal(err)
    }
    defer client.Close()

    // Use the client -- it auto-renews credentials in the background.
    nodes, err := client.GetNodes(ctx, "default")
    if err != nil {
        log.Fatal(err)
    }
    for _, n := range nodes {
        log.Printf("Node: %s", n.GetHostname())
    }

    // Block until the bot exits or context is canceled.
    if err := ebot.Start(ctx); err != nil {
        log.Fatal(err)
    }
}
```

---

## embeddedtbot Package Reference

### BotConfig

Simplified configuration struct for embedded use. Maps to the core `bot.Config` internally.

```go
type BotConfig struct {
    Kind               bot.Kind               // Identifies the embedding component
    AuthServer         string                 // Auth or Proxy Server address
    Onboarding         onboarding.Config      // Token, join method, CA pins
    CredentialLifetime bot.CredentialLifetime  // TTL and renewal interval
    Insecure           bool                   // Skip TLS verification (dev only)
}
```

**Defaults** (when using `BindFlags`): AuthServer=`127.0.0.1:3025`, Token=`teleport-operator`, JoinMethod=`kubernetes`, TTL=`1h`, RenewalInterval=`30m`.

#### BindFlags

Binds `BotConfig` fields to a `flag.FlagSet` for CLI integration:

```go
fs := flag.NewFlagSet("myapp", flag.ExitOnError)
botCfg := &embeddedtbot.BotConfig{}
botCfg.BindFlags(fs)
fs.Parse(os.Args[1:])
```

Registered flags: `--auth-server`, `--token`, `--join-method`, `--certificate-ttl`, `--renewal-interval`, `--ca-pin`, `--insecure`.

### EmbeddedBot

```go
type EmbeddedBot struct { /* unexported fields */ }
```

| Method | Signature | Description |
|--------|-----------|-------------|
| `New` | `func New(cfg *BotConfig, log *slog.Logger) (*EmbeddedBot, error)` | Create a new EmbeddedBot |
| `Preflight` | `func (b *EmbeddedBot) Preflight(ctx) (*proto.PingResponse, error)` | Connect, get first cert, validate setup, return server features. Use for fail-fast validation. |
| `StartAndWaitForClient` | `func (b *EmbeddedBot) StartAndWaitForClient(ctx, deadline) (*client.Client, error)` | Start bot, wait for credentials, return a Teleport API `*client.Client` |
| `StartAndWaitForCredentials` | `func (b *EmbeddedBot) StartAndWaitForCredentials(ctx, deadline) (client.Credentials, error)` | Start bot, wait for credentials, return `client.Credentials` interface |
| `Start` | `func (b *EmbeddedBot) Start(ctx) error` | Block until the bot exits or context is canceled. Must call `StartAndWaitForClient` or `StartAndWaitForCredentials` first. |

### Lifecycle

```text
New() --> Preflight() [optional] --> StartAndWaitForClient() --> Start()
                                     or StartAndWaitForCredentials()
```

1. **`New`** -- validates config, creates the internal `clientcredentials.UnstableConfig` and `bot.Config`.
2. **`Preflight`** (optional) -- performs a one-shot join to validate the bot can connect. Returns `PingResponse` with server features. Use this to fail fast before starting a manager/controller.
3. **`StartAndWaitForClient`** / **`StartAndWaitForCredentials`** -- starts the bot goroutine, blocks until the first certificate is obtained (or the deadline expires). Returns an API client or raw credentials.
4. **`Start`** -- blocks until the bot exits (error) or the context is canceled. Canceling the context triggers graceful shutdown.

---

## Core bot Package (Lower-Level API)

Use this when you need full control over services, or when `embeddedtbot` does not provide enough flexibility.

### bot.Config

```go
type Config struct {
    Kind               Kind                    // KindTbot, KindKubernetesOperator, etc.
    Connection         connection.Config       // How to connect to the cluster
    Onboarding         onboarding.Config       // Join method, token, CA pins
    InternalStorage    destination.Destination  // Where to store bot state (memory or directory)
    CredentialLifetime CredentialLifetime       // TTL and renewal interval
    FIPS               bool                    // FIPS compliance mode
    Logger             *slog.Logger
    ReloadCh           <-chan struct{}          // Trigger certificate reload
    Services           []ServiceBuilder        // User-defined services
    ClientMetrics      *prometheus.ClientMetrics
}
```

### bot.Bot

```go
// Create a bot.
bt, err := bot.New(cfg)

// Run in daemon mode (blocks until context canceled or error).
err = bt.Run(ctx)

// Or run in one-shot mode (generate once and exit).
err = bt.OneShot(ctx)
```

### Service Interface

Every tbot service implements:

```go
type Service interface {
    String() string
    Run(ctx context.Context) error
}

// Optional one-shot support:
type OneShotService interface {
    Service
    OneShot(ctx context.Context) error
}
```

### ServiceBuilder Interface

Services are registered as builders that receive dependencies at construction time:

```go
type ServiceBuilder interface {
    GetTypeAndName() (string, string)
    Build(ServiceDependencies) (Service, error)
}
```

Create one with `NewServiceBuilder`:

```go
builder := bot.NewServiceBuilder("my-service", "my-instance", func(deps bot.ServiceDependencies) (bot.Service, error) {
    // deps.Client           -- *apiclient.Client to Auth Server
    // deps.IdentityGenerator -- generate impersonated identities
    // deps.BotIdentity()     -- get bot's own identity
    // deps.BotIdentityReadyCh -- wait for first identity
    // deps.ReloadCh          -- certificate reload notifications
    // deps.Logger            -- pre-configured logger
    // deps.GetStatusReporter() -- health reporting
    return myService, nil
})
```

### ServiceDependencies

Passed to every `ServiceBuilder.Build()`:

| Field | Type | Description |
|-------|------|-------------|
| `Client` | `*apiclient.Client` | Auth server client using bot's identity |
| `Resolver` | `reversetunnelclient.Resolver` | Proxy address resolver |
| `Logger` | `*slog.Logger` | Logger with service component set |
| `ProxyPinger` | `connection.ProxyPinger` | Ping proxy for connection info |
| `IdentityGenerator` | `*identity.Generator` | Generate impersonated identities |
| `ClientBuilder` | `*client.Builder` | Build new API clients from identities |
| `BotIdentity` | `func() *identity.Identity` | Get bot's internal identity |
| `BotIdentityReadyCh` | `<-chan struct{}` | Closed when first identity is ready |
| `ReloadCh` | `<-chan struct{}` | Reload/renew notification channel |
| `GetStatusReporter` | `func() readyz.Reporter` | Health status reporter |
| `StatusRegistry` | `readyz.ReadOnlyRegistry` | Read service health statuses |

---

## Bot Kind Constants

Identify what component is embedding the bot. Used in heartbeats and telemetry.

```go
const (
    KindUnspecified        = Kind(machineidv1.BotKind_BOT_KIND_UNSPECIFIED)
    KindTbot               = Kind(machineidv1.BotKind_BOT_KIND_TBOT)
    KindTerraformProvider  = Kind(machineidv1.BotKind_BOT_KIND_TERRAFORM_PROVIDER)
    KindKubernetesOperator = Kind(machineidv1.BotKind_BOT_KIND_KUBERNETES_OPERATOR)
    KindTctl               = Kind(machineidv1.BotKind_BOT_KIND_TCTL)
)
```

---

## Connection Configuration

```go
import "github.com/gravitational/teleport/lib/tbot/bot/connection"

cfg := connection.Config{
    Address:     "teleport.example.com:443",
    AddressKind: connection.AddressKindProxy,  // or AddressKindAuth
    Insecure:    false,

    // For embedded use, allow proxy address as auth address:
    AuthServerAddressMode: connection.AllowProxyAsAuthServer,
}
```

| AddressKind | Constant | Description |
|-------------|----------|-------------|
| Proxy | `AddressKindProxy` | Connect via Teleport Proxy |
| Auth | `AddressKindAuth` | Connect directly to Auth Server |

| AuthServerAddressMode | Constant | Description |
|-----------------------|----------|-------------|
| Strict | `AuthServerMustBeAuthServer` | Only accept real auth addresses |
| Warn | `WarnIfAuthServerIsProxy` | Accept proxy, log warning |
| Allow | `AllowProxyAsAuthServer` | Silently accept proxy as auth |

---

## Onboarding Configuration

```go
import "github.com/gravitational/teleport/lib/tbot/bot/onboarding"

cfg := onboarding.Config{
    TokenValue: "my-bot-token",           // or path to file containing token
    JoinMethod: types.JoinMethodKubernetes,
    CAPins:     []string{"sha256:..."},   // optional, for first connect
    CAPath:     "/path/to/ca.pem",        // alternative to CAPins
}
```

The `TokenValue` field supports both literal tokens and file paths. Call `cfg.Token()` to resolve the value (reads file if path).

### Supported Join Methods

All `types.JoinMethod*` constants are supported: `JoinMethodToken`, `JoinMethodKubernetes`, `JoinMethodIAM`, `JoinMethodGCP`, `JoinMethodAzure`, `JoinMethodGitHub`, `JoinMethodGitLab`, `JoinMethodCircleCI`, `JoinMethodSpacelift`, `JoinMethodTerraformCloud`, `JoinMethodTPM`, `JoinMethodBoundKeypair`, and more.

---

## Credential Lifetime

```go
import "github.com/gravitational/teleport/lib/tbot/bot"

lifetime := bot.CredentialLifetime{
    TTL:             time.Hour,        // certificate validity duration
    RenewalInterval: 20 * time.Minute, // how often to renew
}

// Defaults:
bot.DefaultCredentialLifetime // TTL=60m, RenewalInterval=20m
```

Rules:

- `RenewalInterval` must be less than `TTL` (unless oneshot mode).
- `TTL` must not exceed `defaults.MaxRenewableCertTTL` (24h) for standard credentials.
- Set `SkipMaxTTLValidation = true` for services with non-standard limits (e.g. X.509 SVIDs allow up to 2 weeks).

---

## Destination (Storage) Types

```go
import "github.com/gravitational/teleport/lib/tbot/bot/destination"

// In-memory storage (recommended for embedded use):
store := destination.NewMemory()

// Directory-based storage:
store := &destination.Directory{
    Path: "/var/lib/teleport/bot",
}
```

The `Destination` interface:

```go
type Destination interface {
    Init(ctx context.Context, subdirs []string) error
    Read(ctx context.Context, name string) ([]byte, error)
    Write(ctx context.Context, name string, data []byte) error
    TryLock() (func() error, error)
    IsPersistent() bool
    String() string
}
```

Use `destination.NewMemory()` for embedded bots to keep all state in-process. Use a directory destination for persistent storage across restarts (survives process restart without re-joining).

---

## In-Memory Client Credentials (clientcredentials)

The `clientcredentials.UnstableConfig` implements `client.Credentials` and can be used as an in-memory credential source for the Teleport API client.

```go
import "github.com/gravitational/teleport/lib/tbot/services/clientcredentials"

cred := &clientcredentials.UnstableConfig{}

// Wait for credentials to become ready:
<-cred.Ready()

// Use as client.Credentials:
tlsCfg, err := cred.TLSConfig()
sshCfg, err := cred.SSHClientConfig()
expiry, ok := cred.Expiry()
```

> **Note:** The `Unstable` prefix indicates this API may change in future releases.

---

## Patterns

### Embedding in a Kubernetes Operator

The Teleport Kubernetes operator uses `embeddedtbot` to get credentials:

```go
func setupBot(ctx context.Context) (*client.Client, *embeddedtbot.EmbeddedBot, error) {
    logger := slog.Default()

    botCfg := &embeddedtbot.BotConfig{
        Kind:       bot.KindKubernetesOperator,
        AuthServer: "teleport.example.com:443",
        Onboarding: onboarding.Config{
            TokenValue: "operator-token",
            JoinMethod: types.JoinMethodKubernetes,
        },
        CredentialLifetime: bot.CredentialLifetime{
            TTL:             time.Hour,
            RenewalInterval: 30 * time.Minute,
        },
    }

    ebot, err := embeddedtbot.New(botCfg, logger)
    if err != nil {
        return nil, nil, err
    }

    // Validate the setup before starting the full operator.
    pong, err := ebot.Preflight(ctx)
    if err != nil {
        return nil, nil, fmt.Errorf("preflight failed: %w", err)
    }
    log.Printf("Connected to cluster %s (version %s)", pong.ClusterName, pong.ServerVersion)

    // Start and get a client.
    client, err := ebot.StartAndWaitForClient(ctx, 60*time.Second)
    if err != nil {
        return nil, nil, err
    }

    return client, ebot, nil
}
```

### Using Raw Credentials (No Built-In Client)

When you need to build a custom client or use credentials with a different library:

```go
ebot, err := embeddedtbot.New(botCfg, logger)
if err != nil {
    log.Fatal(err)
}

creds, err := ebot.StartAndWaitForCredentials(ctx, 30*time.Second)
if err != nil {
    log.Fatal(err)
}

// Build your own client with the credentials.
tlsCfg, err := creds.TLSConfig()
if err != nil {
    log.Fatal(err)
}
// Use tlsCfg with any TLS-aware client...
```

### Using flag.FlagSet for CLI Integration

```go
func main() {
    botCfg := &embeddedtbot.BotConfig{
        Kind: bot.KindUnspecified,
    }

    fs := flag.NewFlagSet("myapp", flag.ExitOnError)
    botCfg.BindFlags(fs)
    // Add your own flags...
    fs.Parse(os.Args[1:])

    ebot, err := embeddedtbot.New(botCfg, slog.Default())
    // ...
}
```

### Building a Custom Service with the Core bot Package

For full control, use `bot.Config` directly with custom services:

```go
import (
    "github.com/gravitational/teleport/lib/tbot/bot"
    "github.com/gravitational/teleport/lib/tbot/bot/connection"
    "github.com/gravitational/teleport/lib/tbot/bot/destination"
    "github.com/gravitational/teleport/lib/tbot/bot/onboarding"
    "github.com/gravitational/teleport/lib/tbot/services/clientcredentials"
)

cred := &clientcredentials.UnstableConfig{}

cfg := bot.Config{
    Kind: bot.KindUnspecified,
    Connection: connection.Config{
        Address:               "teleport.example.com:443",
        AddressKind:           connection.AddressKindProxy,
        AuthServerAddressMode: connection.AllowProxyAsAuthServer,
    },
    Onboarding: onboarding.Config{
        TokenValue: "my-token",
        JoinMethod: types.JoinMethodKubernetes,
    },
    InternalStorage:    destination.NewMemory(),
    CredentialLifetime: bot.DefaultCredentialLifetime,
    Logger:             slog.Default(),
    Services: []bot.ServiceBuilder{
        // Include the client credentials service for in-memory credential access.
        clientcredentials.ServiceBuilder(cred, bot.DefaultCredentialLifetime),
        // Add your own custom service:
        bot.NewServiceBuilder("my-svc", "my-instance", func(deps bot.ServiceDependencies) (bot.Service, error) {
            return &myService{client: deps.Client, log: deps.Logger}, nil
        }),
    },
}

if err := cfg.CheckAndSetDefaults(); err != nil {
    log.Fatal(err)
}

bt, err := bot.New(cfg)
if err != nil {
    log.Fatal(err)
}

// Run blocks until context canceled or error.
if err := bt.Run(ctx); err != nil {
    log.Fatal(err)
}
```

### Graceful Shutdown

The bot shuts down gracefully when the context is canceled:

```go
ctx, cancel := context.WithCancel(context.Background())

// In a signal handler or shutdown hook:
go func() {
    sigCh := make(chan os.Signal, 1)
    signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
    <-sigCh
    cancel()
}()

// This returns when the context is canceled.
err := ebot.Start(ctx)
```

### Triggering Certificate Reload

Use `ReloadCh` to force an immediate certificate renewal:

```go
reloadCh := make(chan struct{}, 1)

cfg := bot.Config{
    // ...
    ReloadCh: reloadCh,
}

// Trigger a reload:
reloadCh <- struct{}{}
```

---

## YAML Config Parsing (tbot Binary-Level)

The `config.BotConfig` struct (from `lib/tbot/config`) supports YAML parsing for the tbot binary's config format. Use this when loading tbot YAML config files programmatically:

```go
import "github.com/gravitational/teleport/lib/tbot/config"

data, _ := os.ReadFile("/etc/tbot.yaml")
var cfg config.BotConfig
if err := yaml.Unmarshal(data, &cfg); err != nil {
    log.Fatal(err)
}
if err := cfg.CheckAndSetDefaults(); err != nil {
    log.Fatal(err)
}
```

The `config.BotConfig` struct wraps `bot.Config` with YAML tags and supports the full v2 config file format including `services`, `outputs` (legacy), `proxy_server`, `auth_server`, `onboarding`, `storage`, `oneshot`, `debug`, `fips`, `diag_addr`, `credential_ttl`, `renewal_interval`, and `join_uri`.

---

## Error Handling

All errors are wrapped with `github.com/gravitational/trace`. Common patterns:

```go
import "github.com/gravitational/trace"

// Check for specific error types:
if trace.IsNotFound(err) { /* ... */ }
if trace.IsBadParameter(err) { /* ... */ }
if trace.IsAccessDenied(err) { /* ... */ }

// Credential lifetime validation returns SuboptimalCredentialTTLError
// for non-fatal issues (e.g. TTL exceeds server max):
var suboptimal bot.SuboptimalCredentialTTLError
if errors.As(err, &suboptimal) {
    log.Warn(suboptimal.Message(), suboptimal.LogLabels()...)
}
```

Common failure modes:

- **Join failure** (`access denied`): token missing/expired, join method mismatch, ServiceAccount not in token allow list.
- **Deadline exceeded on `StartAndWaitForClient`**: bot cannot reach the proxy/auth server, or certificate issuance takes longer than the deadline.
- **`bot has already been started`**: `Run`/`OneShot` called more than once on the same `Bot` instance.

---

## Package Dependency Graph

```text
embeddedtbot (high-level wrapper)
    |
    +---> bot.Config / bot.Bot (core engine)
    |         |
    |         +---> connection.Config (address, TLS)
    |         +---> onboarding.Config (token, join method)
    |         +---> destination.Destination (memory, directory)
    |         +---> bot.CredentialLifetime (TTL, renewal)
    |         +---> []bot.ServiceBuilder (services to run)
    |
    +---> clientcredentials.UnstableConfig (in-memory client.Credentials)
    |
    +---> client.Client (Teleport API client)

config.BotConfig (YAML config file parsing)
    |
    +---> bot.Config (converted internally by tbot.Bot.Run)
```
