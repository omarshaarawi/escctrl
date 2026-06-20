import CoreGraphics

/// Virtual keycodes and HID usage codes used by the remapper.
enum Keycodes {
    /// kVK_Escape
    static let escape: CGKeyCode = 0x35
    /// kVK_F18 — Caps Lock is remapped to this at the HID layer via hidutil.
    static let f18: CGKeyCode = 0x4F

    /// HID usage for the physical Caps Lock key.
    static let capsLockHID: UInt64 = 0x700000039
    /// HID usage for F18.
    static let f18HID: UInt64 = 0x70000006D

    /// A press shorter than this (with no other key in between) counts as a tap → Escape.
    static let defaultTapThresholdMs: UInt64 = 200
}
