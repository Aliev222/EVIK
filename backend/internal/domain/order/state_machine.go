package order

type State string

const (
	StateCreated        State = "created"
	StateSearching      State = "searching"
	StateAccepted       State = "accepted"
	StateArrived        State = "arrived"
	StateInProgress     State = "in_progress"
	StateAwaitingPayment State = "awaiting_payment"
	StateCompleted      State = "completed"
	StateCancelled      State = "cancelled"
)

// Status is kept for backward compatibility with current use cases and transport contracts.
type Status = State

const (
	StatusCreated        Status = StateCreated
	StatusSearching      Status = StateSearching
	StatusAccepted       Status = StateAccepted
	StatusArrived        Status = StateArrived
	StatusInProgress     Status = StateInProgress
	StatusAwaitingPayment Status = StateAwaitingPayment
	StatusCompleted      Status = StateCompleted
	StatusCancelled      Status = StateCancelled
	StatusNoDriverFound  Status = StateNoDriverFound
)

var allowedTransitions = map[State]map[State]struct{}{
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
	StateCompleted: {},
	StateCancelled: {},
	StateNoDriverFound: {},
}

type StateMachine struct {
	current State
}

func NewStateMachine(current State) *StateMachine {
	return &StateMachine{current: current}
}

func (sm *StateMachine) Transition(to State) error {
	allowed, ok := allowedTransitions[sm.current]
	if !ok {
		return ErrInvalidTransition
	}

	if _, ok := allowed[to]; !ok {
		return ErrInvalidTransition
	}
	sm.current = to
	return nil
}

func (sm *StateMachine) Current() State {
	return sm.current
}
