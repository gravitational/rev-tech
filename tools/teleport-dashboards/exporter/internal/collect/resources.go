package collect

import (
	"context"
	"fmt"
	"time"

	"github.com/gravitational/teleport/api/client"
	apidefaults "github.com/gravitational/teleport/api/defaults"
	"github.com/gravitational/teleport/api/types"

	"github.com/jturner-teleport/teleport-usage/internal/exporter"
)

// Protected-resource kinds, as they appear in the `kind` label of
// teleport_usage_protected_resources. They are part of the metric contract, so
// they are constants rather than string literals scattered through the code.
const (
	KindNode           = "node"
	KindApp            = "app"
	KindKube           = "kube"
	KindDB             = "db"
	KindWindowsDesktop = "windows_desktop"
)

// resourcesInterval is how often the protected-resource inventory is
// recounted. Resources change on the scale of deployments, not seconds, and
// five listings per interval against the auth server is cheap at this cadence.
const resourcesInterval = 5 * time.Minute

// resourceLister is the slice of *client.Client this collector uses. It exists
// so the counting logic can be tested without a cluster: *client.Client is a
// concrete struct with a live gRPC connection inside it and cannot be faked.
type resourceLister interface {
	GetNodes(ctx context.Context, namespace string) ([]types.Server, error)
	GetApplicationServers(ctx context.Context, namespace string) ([]types.AppServer, error)
	GetKubernetesServers(ctx context.Context) ([]types.KubeServer, error)
	GetDatabaseServers(ctx context.Context, namespace string) ([]types.DatabaseServer, error)
	GetWindowsDesktops(ctx context.Context, filter types.WindowsDesktopFilter) ([]types.WindowsDesktop, error)
}

// Resources counts protected resources by kind.
type Resources struct {
	reg *exporter.Registry
}

// NewResources builds the protected-resources collector.
func NewResources(reg *exporter.Registry) *Resources {
	return &Resources{reg: reg}
}

// Name implements Collector.
func (c *Resources) Name() string { return exporter.CollectorResources }

// Interval implements Collector.
func (c *Resources) Interval() time.Duration { return resourcesInterval }

// Collect implements Collector. It publishes nothing unless every kind was
// counted successfully: the scheduler turns the returned error into a
// withdrawal, which is the only honest answer when part of the inventory is
// unknown.
func (c *Resources) Collect(ctx context.Context, clt *client.Client) error {
	byKind, err := collectResources(ctx, clt)
	if err != nil {
		return err
	}
	c.reg.SetResources(byKind)
	return nil
}

// collectResources counts each kind of protected resource, or returns an error
// and no counts at all.
//
// Returning partial counts is the failure this replaces. The previous tracker
// logged a failed fetch, returned early from that one fetcher, and let its
// caller write a snapshot anyway — so a broken listing and an empty cluster
// produced the same output. A month of confident zeros followed on a cluster
// that actually had four resources. Here, one failed fetch fails the whole
// collection and the counts are dropped on the floor.
func collectResources(ctx context.Context, lister resourceLister) (map[string]int, error) {
	// Dedup is per kind and keyed on the resource name. Several agents can
	// heartbeat the same logical resource — two app agents proxying "grafana"
	// yield two AppServers — and each server carries the resource's name as
	// its own (see types.NewAppServerV3FromApp). Billing counts the resource,
	// not the agents serving it, so len() over the server list over-counts.
	seen := map[string]map[string]struct{}{
		KindNode:           {},
		KindApp:            {},
		KindKube:           {},
		KindDB:             {},
		KindWindowsDesktop: {},
	}
	add := func(kind, name string) { seen[kind][name] = struct{}{} }

	nodes, err := lister.GetNodes(ctx, apidefaults.Namespace)
	if err != nil {
		return nil, fmt.Errorf("listing nodes: %w", err)
	}
	for _, n := range nodes {
		// GetName, not GetHostname: a node's name is its host UUID, and two
		// distinct machines are allowed to share a hostname. Keying on
		// hostname would silently merge them into one.
		add(KindNode, n.GetName())
	}

	apps, err := lister.GetApplicationServers(ctx, apidefaults.Namespace)
	if err != nil {
		return nil, fmt.Errorf("listing application servers: %w", err)
	}
	for _, a := range apps {
		add(KindApp, a.GetName())
	}

	kubes, err := lister.GetKubernetesServers(ctx)
	if err != nil {
		return nil, fmt.Errorf("listing kubernetes servers: %w", err)
	}
	for _, k := range kubes {
		add(KindKube, k.GetName())
	}

	dbs, err := lister.GetDatabaseServers(ctx, apidefaults.Namespace)
	if err != nil {
		return nil, fmt.Errorf("listing database servers: %w", err)
	}
	for _, d := range dbs {
		add(KindDB, d.GetName())
	}

	desktops, err := lister.GetWindowsDesktops(ctx, types.WindowsDesktopFilter{})
	if err != nil {
		return nil, fmt.Errorf("listing windows desktops: %w", err)
	}
	for _, w := range desktops {
		add(KindWindowsDesktop, w.GetName())
	}

	// Every kind is emitted, including the empty ones. On a successful
	// collection `db: 0` is a measurement worth publishing; the only way a
	// kind goes missing from /metrics is the registry withdrawing it after a
	// failure. Absence therefore means "unknown", never "none".
	byKind := make(map[string]int, len(seen))
	for kind, names := range seen {
		byKind[kind] = len(names)
	}
	return byKind, nil
}
