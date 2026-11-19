package collect

import (
	"context"
	"fmt"
	"time"

	"github.com/gravitational/teleport/api/client"
	machineidv1pb "github.com/gravitational/teleport/api/gen/proto/go/teleport/machineid/v1"

	"github.com/jturner-teleport/teleport-usage/internal/exporter"
)

// mwiInterval matches the resources collector: bot fleets change on the scale
// of deployments, and two paged listings every five minutes is negligible load.
const mwiInterval = 5 * time.Minute

// maxMWIPages bounds the paging loops. A server that returns a non-empty
// next-page token forever (or the same token repeatedly) would otherwise spin
// this collector until its context expires, holding a connection open and
// blocking the next tick. Hitting the bound is an error, not a truncated
// count: an under-count published as fact is the failure mode this package
// exists to prevent.
const maxMWIPages = 10_000

// mwiLister is the slice of the Teleport API this collector uses, expressed
// without gRPC call options so it can be faked in tests. The concrete
// *client.Client is adapted to it by clientMWILister.
type mwiLister interface {
	ListBots(ctx context.Context, req *machineidv1pb.ListBotsRequest) (*machineidv1pb.ListBotsResponse, error)
	ListBotInstances(ctx context.Context, req *machineidv1pb.ListBotInstancesV2Request) (*machineidv1pb.ListBotInstancesResponse, error)
}

// clientMWILister adapts *client.Client to mwiLister.
type clientMWILister struct {
	clt *client.Client
}

func (a clientMWILister) ListBots(ctx context.Context, req *machineidv1pb.ListBotsRequest) (*machineidv1pb.ListBotsResponse, error) {
	return a.clt.BotServiceClient().ListBots(ctx, req)
}

// ListBotInstances uses ListBotInstancesV2; the v1 RPC is deprecated in the
// API this binary is built against.
func (a clientMWILister) ListBotInstances(ctx context.Context, req *machineidv1pb.ListBotInstancesV2Request) (*machineidv1pb.ListBotInstancesResponse, error) {
	return a.clt.BotInstanceServiceClient().ListBotInstancesV2(ctx, req)
}

// MWI counts Machine & Workload Identity bots and bot instances.
type MWI struct {
	reg *exporter.Registry
}

// NewMWI builds the Machine & Workload Identity collector.
func NewMWI(reg *exporter.Registry) *MWI {
	return &MWI{reg: reg}
}

// Name implements Collector.
func (c *MWI) Name() string { return exporter.CollectorMWI }

// Interval implements Collector.
func (c *MWI) Interval() time.Duration { return mwiInterval }

// Collect implements Collector. Both counts are published together or neither
// is: a bot count paired with an unknown instance count is not a snapshot of
// anything.
func (c *MWI) Collect(ctx context.Context, clt *client.Client) error {
	bots, instances, err := collectMWI(ctx, clientMWILister{clt: clt})
	if err != nil {
		return err
	}
	c.reg.SetMWI(bots, instances)
	return nil
}

// collectMWI counts bots and bot instances, following next-page tokens to the
// end of each list. Reading only the first page would under-count every
// cluster with more bots than fit in one page, and the under-count would look
// exactly like a real one.
//
// Any failure returns (0, 0, err). No partial count escapes.
func collectMWI(ctx context.Context, lister mwiLister) (bots, botInstances int, err error) {
	for pageToken, page := "", 0; ; page++ {
		if page >= maxMWIPages {
			return 0, 0, fmt.Errorf("listing bots: exceeded %d pages; the server is not terminating pagination", maxMWIPages)
		}
		resp, err := lister.ListBots(ctx, &machineidv1pb.ListBotsRequest{PageToken: pageToken})
		if err != nil {
			return 0, 0, fmt.Errorf("listing bots: %w", err)
		}
		bots += len(resp.GetBots())
		if resp.GetNextPageToken() == "" {
			break
		}
		pageToken = resp.GetNextPageToken()
	}

	for pageToken, page := "", 0; ; page++ {
		if page >= maxMWIPages {
			return 0, 0, fmt.Errorf("listing bot instances: exceeded %d pages; the server is not terminating pagination", maxMWIPages)
		}
		resp, err := lister.ListBotInstances(ctx, &machineidv1pb.ListBotInstancesV2Request{PageToken: pageToken})
		if err != nil {
			return 0, 0, fmt.Errorf("listing bot instances: %w", err)
		}
		botInstances += len(resp.GetBotInstances())
		if resp.GetNextPageToken() == "" {
			break
		}
		pageToken = resp.GetNextPageToken()
	}

	return bots, botInstances, nil
}
