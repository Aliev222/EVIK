package order

import (
	"errors"
	"testing"
	"time"
)

// Full square-matrix coverage of the order state machine in
// state_machine.go. The allowed map below is the TEST's independent copy of
// the contract: every pair (from,to) is either an allowed transition or must
// produce ErrInvalidTransition. This covers all valid transitions, all
// forbidden pairs (including the terminal states completed/cancelled and the
// probing-stage shortcuts like searching→completed, created→accepted,
// awaiting_payment→accepted) in one exhaustive pass.

var validatedTransitions = map[State]map[State]struct{}{
	StateCreated: {
		StateSearching: {},
		StateCancelled: {},
	},
	StateSearching: {
		StateAccepted:      {},
		StateCancelled:     {},
		StateNoDriverFound: {},
	},
	StateAccepted: {
		StateArrived:   {},
		StateCancelled: {},
	},
	StateArrived: {
		StateInProgress: {},
		StateCancelled:  {},
	},
	StateInProgress: {
		StateAwaitingPayment: {},
		StateCancelled:       {},
	},
	StateAwaitingPayment: {
		StateCompleted: {},
		StateCancelled: {},
	},
	StateCompleted:     {},
	StateCancelled:     {},
	StateNoDriverFound: {
		StateCancelled: {},
	},
}

var allStates = []State{
	StateCreated,
	StateSearching,
	StateAccepted,
	StateArrived,
	StateInProgress,
	StateAwaitingPayment,
	StateCompleted,
	StateCancelled,
	StateNoDriverFound,
}

// TestStateMachine_TransitionMatrix exhaustively checks all 9×9 (from, to)
// pairs: allowed pairs must succeed and move the machine, forbidden pairs
// must fail with ErrInvalidTransition and leave the machine untouched.
func TestStateMachine_TransitionMatrix(t *testing.T) {
	for _, from := range allStates {
		for _, to := range allStates {
			name := string(from) + "->" + string(to)
			_, allowed := validatedTransitions[from][to]
			t.Run(name, func(t *testing.T) {
				sm := NewStateMachine(from)
				err := sm.Transition(to)
				if allowed {
					if err != nil {
						t.Fatalf("Transition(%q) from %q: unexpected error %v", to, from, err)
					}
					if sm.Current() != to {
						t.Fatalf("Current() = %q, want %q", sm.Current(), to)
					}
					return
				}
				if !errors.Is(err, ErrInvalidTransition) {
					t.Fatalf("Transition(%q) from %q: err = %v, want ErrInvalidTransition", to, from, err)
				}
				if sm.Current() != from {
					t.Fatalf("failed transition mutated state: Current() = %q, want %q", sm.Current(), from)
				}
			})
		}
	}
}

// TestStateMachine_TerminalStates locks the invariant that completed and
// cancelled are absorbing: no outgoing transition exists at all, including
// back to themselves.
func TestStateMachine_TerminalStates(t *testing.T) {
	for _, terminal := range []State{StateCompleted, StateCancelled} {
		t.Run(string(terminal), func(t *testing.T) {
			for _, to := range allStates {
				sm := NewStateMachine(terminal)
				if err := sm.Transition(to); !errors.Is(err, ErrInvalidTransition) {
					t.Fatalf("Transition(%q) from terminal %q: err = %v, want ErrInvalidTransition", to, terminal, err)
				}
				if sm.Current() != terminal {
					t.Fatalf("Current() = %q, want %q", sm.Current(), terminal)
				}
			}
		})
	}
}

// TestOrder_FullHappyPathTransitions walks the entire client lifecycle
// created→searching→accepted→arrived→in_progress→awaiting_payment→completed
// through the entity API and asserts UpdatedAt advances on each step while
// CancelledAt stays nil.
func TestOrder_FullHappyPathTransitions(t *testing.T) {
	start := time.Date(2026, 8, 1, 10, 0, 0, 0, time.UTC)
	ord, err := NewOrder("order-1", "client-1",
		Coordinate{Lat: 55.75, Lng: 37.62},
		Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckWinch, start)
	if err != nil {
		t.Fatalf("NewOrder: %v", err)
	}

	steps := []struct {
		next Status
		at   time.Time
	}{
		{StatusSearching, start.Add(1 * time.Second)},
		{StatusAccepted, start.Add(2 * time.Second)},
		{StatusArrived, start.Add(3 * time.Second)},
		{StatusInProgress, start.Add(4 * time.Second)},
		{StatusAwaitingPayment, start.Add(5 * time.Second)},
		{StatusCompleted, start.Add(6 * time.Second)},
	}
	for _, step := range steps {
		if err := ord.TransitionTo(step.next, step.at); err != nil {
			t.Fatalf("TransitionTo(%q): %v", step.next, err)
		}
		if ord.Status != step.next {
			t.Fatalf("Status = %q, want %q", ord.Status, step.next)
		}
		if !ord.UpdatedAt.Equal(step.at) {
			t.Fatalf("UpdatedAt = %v, want %v", ord.UpdatedAt, step.at)
		}
	}
	if ord.CancelledAt != nil {
		t.Fatalf("CancelledAt = %v, want nil for a non-cancelled lifecycle", *ord.CancelledAt)
	}
}

// TestOrder_TransitionToCancelledSetsCancelledAt verifies CancelledAt is
// stamped exactly when the order enters cancelled and UpdatedAt advances.
func TestOrder_TransitionToCancelledSetsCancelledAt(t *testing.T) {
	start := time.Date(2026, 8, 1, 10, 0, 0, 0, time.UTC)
	cancelAt := start.Add(30 * time.Minute)

	ord, err := NewOrder("order-1", "client-1",
		Coordinate{Lat: 55.75, Lng: 37.62},
		Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckWinch, start)
	if err != nil {
		t.Fatalf("NewOrder: %v", err)
	}
	if err := ord.TransitionTo(StatusSearching, start.Add(1*time.Second)); err != nil {
		t.Fatalf("to searching: %v", err)
	}

	if err := ord.TransitionTo(StatusCancelled, cancelAt); err != nil {
		t.Fatalf("TransitionTo(cancelled): %v", err)
	}
	if ord.Status != StatusCancelled {
		t.Fatalf("Status = %q, want cancelled", ord.Status)
	}
	if ord.CancelledAt == nil || !ord.CancelledAt.Equal(cancelAt) {
		t.Fatalf("CancelledAt = %v, want %v", ord.CancelledAt, cancelAt)
	}
	if !ord.UpdatedAt.Equal(cancelAt) {
		t.Fatalf("UpdatedAt = %v, want %v", ord.UpdatedAt, cancelAt)
	}
}

// TestOrder_FailedTransitionLeavesStateUntouched verifies that a rejected
// transition (e.g. completed→cancelled) mutates nothing: status, UpdatedAt
// and CancelledAt all keep their previous values.
func TestOrder_FailedTransitionLeavesStateUntouched(t *testing.T) {
	start := time.Date(2026, 8, 1, 10, 0, 0, 0, time.UTC)
	completedAt := start.Add(1 * time.Minute)

	ord, err := NewOrder("order-1", "client-1",
		Coordinate{Lat: 55.75, Lng: 37.62},
		Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckWinch, start)
	if err != nil {
		t.Fatalf("NewOrder: %v", err)
	}
	// completed terminates the order via the legit longest path.
	if err := ord.TransitionTo(StatusSearching, completedAt); err != nil {
		t.Fatalf("to searching: %v", err)
	}

	err = ord.TransitionTo(StatusCompleted, completedAt.Add(10*time.Second))
	if !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("TransitionTo(completed) from searching: err = %v, want ErrInvalidTransition", err)
	}
	if ord.Status != StatusSearching {
		t.Fatalf("Status = %q after failed transition, want searching", ord.Status)
	}
	if !ord.UpdatedAt.Equal(completedAt) {
		t.Fatalf("UpdatedAt = %v after failed transition, want unchanged %v", ord.UpdatedAt, completedAt)
	}
	if ord.CancelledAt != nil {
		t.Fatalf("CancelledAt = %v, want nil after failed transition", *ord.CancelledAt)
	}

	// From cancelled no transition is possible: completed→cancelled and
	// cancelled→completed both must fail.
	if err := ord.TransitionTo(StatusCancelled, completedAt.Add(20*time.Second)); err != nil {
		t.Fatalf("TransitionTo(cancelled) from searching: %v", err)
	}
	if err := ord.TransitionTo(StatusCompleted, completedAt.Add(30*time.Second)); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("TransitionTo(completed) from cancelled: err = %v, want ErrInvalidTransition", err)
	}
}
