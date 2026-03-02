use core_foundation::runloop::{kCFRunLoopCommonModes, CFRunLoop};
use core_graphics::event::{
    CGEvent, CGEventFlags, CGEventTap, CGEventTapLocation, CGEventTapOptions,
    CGEventTapPlacement, CGEventType, CallbackResult, EventField,
};
use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::thread;

use super::keycodes::{DEFAULT_TAP_THRESHOLD_MS, ESCAPE, F18};
use super::state::CapsLockTracker;

pub struct KeyboardEngine {
    enabled: Arc<AtomicBool>,
    escape_on_tap: Arc<AtomicBool>,
    tracker: Arc<Mutex<CapsLockTracker>>,
    thread_handle: Option<thread::JoinHandle<()>>,
}

impl KeyboardEngine {
    pub fn new() -> Self {
        Self {
            enabled: Arc::new(AtomicBool::new(true)),
            escape_on_tap: Arc::new(AtomicBool::new(true)),
            tracker: Arc::new(Mutex::new(CapsLockTracker::new(DEFAULT_TAP_THRESHOLD_MS))),
            thread_handle: None,
        }
    }

    pub fn start(&mut self) -> Result<(), String> {
        if self.thread_handle.is_some() {
            return Err("engine already running".into());
        }

        let enabled = self.enabled.clone();
        let escape_on_tap = self.escape_on_tap.clone();
        let tracker = self.tracker.clone();

        let handle = thread::spawn(move || {
            let tap = CGEventTap::new(
                CGEventTapLocation::HID,
                CGEventTapPlacement::HeadInsertEventTap,
                CGEventTapOptions::Default,
                vec![
                    CGEventType::KeyDown,
                    CGEventType::KeyUp,
                    CGEventType::FlagsChanged,
                ],
                move |_proxy, event_type, event| {
                    if !enabled.load(Ordering::Relaxed) {
                        return CallbackResult::Keep;
                    }
                    handle_event(event_type, event, &tracker, &escape_on_tap)
                },
            );

            let tap = match tap {
                Ok(tap) => tap,
                Err(()) => {
                    log::error!(
                        "Failed to create CGEventTap. Grant Accessibility permission."
                    );
                    return;
                }
            };

            unsafe {
                let source = tap
                    .mach_port()
                    .create_runloop_source(0)
                    .expect("failed to create runloop source");
                CFRunLoop::get_current().add_source(&source, kCFRunLoopCommonModes);
            }

            tap.enable();
            CFRunLoop::run_current();
        });

        self.thread_handle = Some(handle);
        Ok(())
    }

    pub fn set_enabled(&self, val: bool) {
        self.enabled.store(val, Ordering::Relaxed);
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    pub fn set_escape_on_tap(&self, val: bool) {
        self.escape_on_tap.store(val, Ordering::Relaxed);
    }

    pub fn is_escape_on_tap(&self) -> bool {
        self.escape_on_tap.load(Ordering::Relaxed)
    }

    pub fn set_threshold(&self, ms: u64) {
        if let Ok(mut t) = self.tracker.lock() {
            t.set_threshold(ms);
        }
    }
}

fn handle_event(
    event_type: CGEventType,
    event: &CGEvent,
    tracker: &Arc<Mutex<CapsLockTracker>>,
    escape_on_tap: &Arc<AtomicBool>,
) -> CallbackResult {
    let keycode = event.get_integer_value_field(EventField::KEYBOARD_EVENT_KEYCODE) as u16;

    match event_type {
        CGEventType::KeyDown => {
            if keycode == F18 {
                let mut t = tracker.lock().unwrap();
                if !t.is_held() {
                    t.press();
                }
                return CallbackResult::Drop;
            }

            let mut t = tracker.lock().unwrap();
            if t.is_held() {
                t.interrupt();
                let mut flags = event.get_flags();
                flags.insert(CGEventFlags::CGEventFlagControl);
                event.set_flags(flags);
            }
            CallbackResult::Keep
        }

        CGEventType::KeyUp => {
            if keycode == F18 {
                let mut t = tracker.lock().unwrap();
                let was_tap = t.release();
                if was_tap && escape_on_tap.load(Ordering::Relaxed) {
                    post_escape();
                }
                return CallbackResult::Drop;
            }

            let t = tracker.lock().unwrap();
            if t.is_held() {
                let mut flags = event.get_flags();
                flags.insert(CGEventFlags::CGEventFlagControl);
                event.set_flags(flags);
            }
            CallbackResult::Keep
        }

        CGEventType::FlagsChanged => {
            let flags = event.get_flags();
            if flags.contains(CGEventFlags::CGEventFlagAlphaShift) {
                return CallbackResult::Drop;
            }
            CallbackResult::Keep
        }

        CGEventType::TapDisabledByTimeout => {
            log::warn!("event tap disabled by timeout");
            CallbackResult::Keep
        }

        _ => CallbackResult::Keep,
    }
}

fn post_escape() {
    let source = match CGEventSource::new(CGEventSourceStateID::Private) {
        Ok(s) => s,
        Err(()) => return,
    };
    if let Ok(down) = CGEvent::new_keyboard_event(source.clone(), ESCAPE, true) {
        down.post(CGEventTapLocation::HID);
    }
    let source = match CGEventSource::new(CGEventSourceStateID::Private) {
        Ok(s) => s,
        Err(()) => return,
    };
    if let Ok(up) = CGEvent::new_keyboard_event(source, ESCAPE, false) {
        up.post(CGEventTapLocation::HID);
    }
}
