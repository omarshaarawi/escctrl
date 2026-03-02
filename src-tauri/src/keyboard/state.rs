use std::time::Instant;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CapsState {
    Idle,
    Pressed(Instant),
    HeldAsCtrl,
}

pub struct CapsLockTracker {
    state: CapsState,
    tap_threshold_ms: u64,
    interrupted: bool,
}

impl CapsLockTracker {
    pub fn new(tap_threshold_ms: u64) -> Self {
        Self {
            state: CapsState::Idle,
            tap_threshold_ms,
            interrupted: false,
        }
    }

    pub fn press(&mut self) {
        self.state = CapsState::Pressed(Instant::now());
        self.interrupted = false;
    }

    pub fn interrupt(&mut self) {
        if matches!(self.state, CapsState::Pressed(_)) {
            self.state = CapsState::HeldAsCtrl;
        }
        self.interrupted = true;
    }

    pub fn release(&mut self) -> bool {
        let was_tap = match self.state {
            CapsState::Pressed(t) => {
                t.elapsed().as_millis() < self.tap_threshold_ms as u128 && !self.interrupted
            }
            _ => false,
        };
        self.state = CapsState::Idle;
        self.interrupted = false;
        was_tap
    }

    pub fn is_held(&self) -> bool {
        matches!(self.state, CapsState::Pressed(_) | CapsState::HeldAsCtrl)
    }

    pub fn set_threshold(&mut self, ms: u64) {
        self.tap_threshold_ms = ms;
    }
}
