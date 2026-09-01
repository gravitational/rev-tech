package collect

import (
	"context"
	"errors"
	"testing"

	headerv1 "github.com/gravitational/teleport/api/gen/proto/go/teleport/header/v1"
	machineidv1pb "github.com/gravitational/teleport/api/gen/proto/go/teleport/machineid/v1"
)

// fakeMWILister serves canned pages. Each page is consumed in order and hands
// out a next-page token until the last one, which returns "".
type fakeMWILister struct {
	botPages      [][]*machineidv1pb.Bot
	instancePages [][]*machineidv1pb.BotInstance

	botsErr      error
	instancesErr error

	botTokens      []string // page tokens the caller sent, in order
	instanceTokens []string
}

func (f *fakeMWILister) ListBots(_ context.Context, req *machineidv1pb.ListBotsRequest) (*machineidv1pb.ListBotsResponse, error) {
	if f.botsErr != nil {
		return nil, f.botsErr
	}
	f.botTokens = append(f.botTokens, req.GetPageToken())
	idx := pageIndex(req.GetPageToken(), len(f.botPages))
	if idx < 0 {
		return nil, errors.New("bad page token")
	}
	return &machineidv1pb.ListBotsResponse{
		Bots:          f.botPages[idx],
		NextPageToken: nextToken(idx, len(f.botPages)),
	}, nil
}

func (f *fakeMWILister) ListBotInstances(_ context.Context, req *machineidv1pb.ListBotInstancesV2Request) (*machineidv1pb.ListBotInstancesResponse, error) {
	if f.instancesErr != nil {
		return nil, f.instancesErr
	}
	f.instanceTokens = append(f.instanceTokens, req.GetPageToken())
	idx := pageIndex(req.GetPageToken(), len(f.instancePages))
	if idx < 0 {
		return nil, errors.New("bad page token")
	}
	return &machineidv1pb.ListBotInstancesResponse{
		BotInstances:  f.instancePages[idx],
		NextPageToken: nextToken(idx, len(f.instancePages)),
	}, nil
}

// pageIndex maps a token to a page. "" is the first page; "page-N" is page N.
func pageIndex(token string, pages int) int {
	if pages == 0 {
		return -1
	}
	switch token {
	case "":
		return 0
	case "page-1":
		return 1
	case "page-2":
		return 2
	default:
		return -1
	}
}

func nextToken(idx, pages int) string {
	if idx+1 >= pages {
		return ""
	}
	return []string{"page-1", "page-2"}[idx]
}

func bots(names ...string) []*machineidv1pb.Bot {
	out := make([]*machineidv1pb.Bot, 0, len(names))
	for _, n := range names {
		out = append(out, &machineidv1pb.Bot{Metadata: &headerv1.Metadata{Name: n}})
	}
	return out
}

func instances(ids ...string) []*machineidv1pb.BotInstance {
	out := make([]*machineidv1pb.BotInstance, 0, len(ids))
	for _, id := range ids {
		out = append(out, &machineidv1pb.BotInstance{Spec: &machineidv1pb.BotInstanceSpec{InstanceId: id}})
	}
	return out
}

// TestPagesAllBots proves the collector follows next-page tokens. Reading only
// the first page would silently under-count every cluster with more bots than
// fit in one page.
func TestPagesAllBots(t *testing.T) {
	f := &fakeMWILister{
		botPages: [][]*machineidv1pb.Bot{
			bots("bot-a", "bot-b"),
			bots("bot-c"),
		},
		instancePages: [][]*machineidv1pb.BotInstance{
			instances("i1", "i2"),
			instances("i3", "i4", "i5"),
		},
	}

	gotBots, gotInstances, err := collectMWI(context.Background(), f)
	if err != nil {
		t.Fatalf("collectMWI returned error: %v", err)
	}
	if gotBots != 3 {
		t.Errorf("bots = %d, want 3 (2 on page one, 1 on page two)", gotBots)
	}
	if gotInstances != 5 {
		t.Errorf("bot instances = %d, want 5 (2 on page one, 3 on page two)", gotInstances)
	}
	if len(f.botTokens) != 2 || f.botTokens[0] != "" || f.botTokens[1] != "page-1" {
		t.Errorf("bot page tokens = %v, want [\"\" \"page-1\"]", f.botTokens)
	}
	if len(f.instanceTokens) != 2 || f.instanceTokens[0] != "" || f.instanceTokens[1] != "page-1" {
		t.Errorf("instance page tokens = %v, want [\"\" \"page-1\"]", f.instanceTokens)
	}
}

func TestBotListFailureReturnsError(t *testing.T) {
	boom := errors.New("rpc error: permission denied")

	tests := []struct {
		name string
		fail func(*fakeMWILister)
	}{
		{"bots", func(f *fakeMWILister) { f.botsErr = boom }},
		{"bot instances", func(f *fakeMWILister) { f.instancesErr = boom }},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			f := &fakeMWILister{
				botPages:      [][]*machineidv1pb.Bot{bots("bot-a")},
				instancePages: [][]*machineidv1pb.BotInstance{instances("i1")},
			}
			tc.fail(f)

			gotBots, gotInstances, err := collectMWI(context.Background(), f)
			if err == nil {
				t.Fatalf("collectMWI succeeded despite a failing %s list; got %d bots / %d instances", tc.name, gotBots, gotInstances)
			}
			if !errors.Is(err, boom) {
				t.Errorf("error does not wrap the underlying failure: %v", err)
			}
			if gotBots != 0 || gotInstances != 0 {
				t.Errorf("collectMWI returned partial counts %d bots / %d instances alongside error; want 0/0", gotBots, gotInstances)
			}
		})
	}
}

// TestZeroBotsIsNotAnError guards the same distinction the resources collector
// makes: a cluster with no bots is a successful measurement of zero.
func TestZeroBotsIsNotAnError(t *testing.T) {
	f := &fakeMWILister{
		botPages:      [][]*machineidv1pb.Bot{nil},
		instancePages: [][]*machineidv1pb.BotInstance{nil},
	}

	gotBots, gotInstances, err := collectMWI(context.Background(), f)
	if err != nil {
		t.Fatalf("collectMWI returned error for an empty cluster: %v", err)
	}
	if gotBots != 0 || gotInstances != 0 {
		t.Errorf("got %d bots / %d instances, want 0/0", gotBots, gotInstances)
	}
}
