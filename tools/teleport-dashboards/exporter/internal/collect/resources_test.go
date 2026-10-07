package collect

import (
	"context"
	"errors"
	"testing"

	"github.com/gravitational/teleport/api/types"
)

// fakeResourceLister stands in for *client.Client. Each slice is what the
// corresponding fetch returns; each error, when non-nil, is what it fails with.
type fakeResourceLister struct {
	nodes    []types.Server
	apps     []types.AppServer
	kubes    []types.KubeServer
	dbs      []types.DatabaseServer
	desktops []types.WindowsDesktop

	nodesErr    error
	appsErr     error
	kubesErr    error
	dbsErr      error
	desktopsErr error
}

func (f *fakeResourceLister) GetNodes(_ context.Context, _ string) ([]types.Server, error) {
	return f.nodes, f.nodesErr
}

func (f *fakeResourceLister) GetApplicationServers(_ context.Context, _ string) ([]types.AppServer, error) {
	return f.apps, f.appsErr
}

func (f *fakeResourceLister) GetKubernetesServers(_ context.Context) ([]types.KubeServer, error) {
	return f.kubes, f.kubesErr
}

func (f *fakeResourceLister) GetDatabaseServers(_ context.Context, _ string) ([]types.DatabaseServer, error) {
	return f.dbs, f.dbsErr
}

func (f *fakeResourceLister) GetWindowsDesktops(_ context.Context, _ types.WindowsDesktopFilter) ([]types.WindowsDesktop, error) {
	return f.desktops, f.desktopsErr
}

func newTestNode(t *testing.T, name, hostname string) types.Server {
	t.Helper()
	s, err := types.NewServer(name, types.KindNode, types.ServerSpecV2{Hostname: hostname})
	if err != nil {
		t.Fatalf("NewServer(%q): %v", name, err)
	}
	return s
}

// newTestAppServer builds an AppServer for the named app served by hostID.
// Two agents serving the same app produce two AppServers with the same
// resource name and different host IDs — the case dedup has to collapse.
func newTestAppServer(t *testing.T, appName, hostID string) types.AppServer {
	t.Helper()
	app, err := types.NewAppV3(types.Metadata{Name: appName}, types.AppSpecV3{URI: "http://localhost:8080"})
	if err != nil {
		t.Fatalf("NewAppV3(%q): %v", appName, err)
	}
	srv, err := types.NewAppServerV3FromApp(app, hostID, hostID)
	if err != nil {
		t.Fatalf("NewAppServerV3FromApp(%q): %v", appName, err)
	}
	return srv
}

func newTestKubeServer(t *testing.T, clusterName, hostID string) types.KubeServer {
	t.Helper()
	cluster, err := types.NewKubernetesClusterV3(types.Metadata{Name: clusterName}, types.KubernetesClusterSpecV3{})
	if err != nil {
		t.Fatalf("NewKubernetesClusterV3(%q): %v", clusterName, err)
	}
	srv, err := types.NewKubernetesServerV3FromCluster(cluster, hostID, hostID)
	if err != nil {
		t.Fatalf("NewKubernetesServerV3FromCluster(%q): %v", clusterName, err)
	}
	return srv
}

func newTestDBServer(t *testing.T, dbName, hostID string) types.DatabaseServer {
	t.Helper()
	db, err := types.NewDatabaseV3(types.Metadata{Name: dbName}, types.DatabaseSpecV3{
		Protocol: "postgres",
		URI:      "localhost:5432",
	})
	if err != nil {
		t.Fatalf("NewDatabaseV3(%q): %v", dbName, err)
	}
	srv, err := types.NewDatabaseServerV3(types.Metadata{Name: dbName}, types.DatabaseServerSpecV3{
		HostID:   hostID,
		Hostname: hostID,
		Database: db,
	})
	if err != nil {
		t.Fatalf("NewDatabaseServerV3(%q): %v", dbName, err)
	}
	return srv
}

func newTestDesktop(t *testing.T, name string) types.WindowsDesktop {
	t.Helper()
	d, err := types.NewWindowsDesktopV3(name, nil, types.WindowsDesktopSpecV3{Addr: "10.0.0.1:3389"})
	if err != nil {
		t.Fatalf("NewWindowsDesktopV3(%q): %v", name, err)
	}
	return d
}

func TestCountsEachKind(t *testing.T) {
	lister := &fakeResourceLister{
		nodes:    []types.Server{newTestNode(t, "n1", "ssh-node-1"), newTestNode(t, "n2", "ssh-node-2")},
		apps:     []types.AppServer{newTestAppServer(t, "grafana", "h1"), newTestAppServer(t, "prometheus", "h2")},
		kubes:    []types.KubeServer{newTestKubeServer(t, "jturner-dev.k8s.local", "h3")},
		dbs:      []types.DatabaseServer{newTestDBServer(t, "pg", "h4"), newTestDBServer(t, "mysql", "h5"), newTestDBServer(t, "redis", "h6")},
		desktops: []types.WindowsDesktop{newTestDesktop(t, "win-1")},
	}

	got, err := collectResources(context.Background(), lister)
	if err != nil {
		t.Fatalf("collectResources returned error: %v", err)
	}

	want := map[string]int{
		KindNode:           2,
		KindApp:            2,
		KindKube:           1,
		KindDB:             3,
		KindWindowsDesktop: 1,
	}
	assertCounts(t, want, got)
}

// TestAnyFetchFailureReturnsErrorAndNoCounts is the regression test for the bug
// this package exists to prevent: the old tracker logged a failed fetch and
// carried on, writing a snapshot whose zeros were indistinguishable from a real
// decline in resources. A partial count is never returned.
func TestAnyFetchFailureReturnsErrorAndNoCounts(t *testing.T) {
	boom := errors.New("rpc error: connection refused")

	// A fully-populated cluster, so a partial result would be conspicuous:
	// any successful fetch has something to (wrongly) report.
	populate := func(f *fakeResourceLister) {
		f.nodes = []types.Server{newTestNode(t, "n1", "ssh-node-1")}
		f.apps = []types.AppServer{newTestAppServer(t, "grafana", "h1")}
		f.kubes = []types.KubeServer{newTestKubeServer(t, "kube-1", "h2")}
		f.dbs = []types.DatabaseServer{newTestDBServer(t, "pg", "h3")}
		f.desktops = []types.WindowsDesktop{newTestDesktop(t, "win-1")}
	}

	tests := []struct {
		name string
		fail func(*fakeResourceLister)
	}{
		{"nodes", func(f *fakeResourceLister) { f.nodesErr = boom }},
		{"apps", func(f *fakeResourceLister) { f.appsErr = boom }},
		{"kubes", func(f *fakeResourceLister) { f.kubesErr = boom }},
		{"databases", func(f *fakeResourceLister) { f.dbsErr = boom }},
		{"desktops", func(f *fakeResourceLister) { f.desktopsErr = boom }},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			f := &fakeResourceLister{}
			populate(f)
			tc.fail(f)

			got, err := collectResources(context.Background(), f)
			if err == nil {
				t.Fatalf("collectResources succeeded despite a failing %s fetch; got counts %v", tc.name, got)
			}
			if !errors.Is(err, boom) {
				t.Errorf("error does not wrap the underlying failure: %v", err)
			}
			// No partial counts: the caller must have nothing it could
			// mistake for a measurement.
			if got != nil {
				t.Errorf("collectResources returned partial counts %v alongside error %v; want nil", got, err)
			}
		})
	}
}

func TestDeduplicatesMultipleServersForOneResource(t *testing.T) {
	// Two agents advertising the same logical app. That is one protected
	// resource, not two — a naive len() over AppServers over-counts.
	lister := &fakeResourceLister{
		apps: []types.AppServer{
			newTestAppServer(t, "grafana", "agent-a"),
			newTestAppServer(t, "grafana", "agent-b"),
		},
		kubes: []types.KubeServer{
			newTestKubeServer(t, "jturner-dev.k8s.local", "agent-a"),
			newTestKubeServer(t, "jturner-dev.k8s.local", "agent-b"),
		},
		dbs: []types.DatabaseServer{
			newTestDBServer(t, "pg", "agent-a"),
			newTestDBServer(t, "pg", "agent-b"),
		},
	}

	got, err := collectResources(context.Background(), lister)
	if err != nil {
		t.Fatalf("collectResources returned error: %v", err)
	}

	want := map[string]int{
		KindNode:           0,
		KindApp:            1,
		KindKube:           1,
		KindDB:             1,
		KindWindowsDesktop: 0,
	}
	assertCounts(t, want, got)
}

// TestZeroOfAKindIsReportedNotOmitted pins the other half of the contract:
// a successful collection reports zero explicitly. Absence of a kind means
// "not measured" (the registry withdrew it), so a real zero must be present.
func TestZeroOfAKindIsReportedNotOmitted(t *testing.T) {
	lister := &fakeResourceLister{
		nodes: []types.Server{newTestNode(t, "n1", "ssh-node-1")},
		apps:  []types.AppServer{newTestAppServer(t, "grafana", "h1"), newTestAppServer(t, "prometheus", "h2")},
		kubes: []types.KubeServer{newTestKubeServer(t, "jturner-dev.k8s.local", "h3")},
		// No databases and no desktops on this cluster.
	}

	got, err := collectResources(context.Background(), lister)
	if err != nil {
		t.Fatalf("collectResources returned error: %v", err)
	}

	for _, kind := range []string{KindDB, KindWindowsDesktop} {
		n, ok := got[kind]
		if !ok {
			t.Errorf("kind %q missing from a successful collection; a real zero must be reported, not omitted", kind)
			continue
		}
		if n != 0 {
			t.Errorf("kind %q = %d, want 0", kind, n)
		}
	}

	// This mirrors the live cluster: node 1, app 2, kube 1, db 0,
	// windows_desktop 0 — total 4.
	total := 0
	for _, n := range got {
		total += n
	}
	if total != 4 {
		t.Errorf("total protected resources = %d, want 4", total)
	}
}

func assertCounts(t *testing.T, want, got map[string]int) {
	t.Helper()
	if len(got) != len(want) {
		t.Errorf("got %d kinds %v, want %d kinds %v", len(got), got, len(want), want)
	}
	for kind, n := range want {
		g, ok := got[kind]
		if !ok {
			t.Errorf("kind %q missing from result %v", kind, got)
			continue
		}
		if g != n {
			t.Errorf("kind %q = %d, want %d", kind, g, n)
		}
	}
	for kind := range got {
		if _, ok := want[kind]; !ok {
			t.Errorf("unexpected kind %q in result", kind)
		}
	}
}
