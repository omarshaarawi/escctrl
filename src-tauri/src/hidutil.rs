use std::process::Command;

const CAPS_LOCK_HID: u64 = 0x700000039;
const F18_HID: u64 = 0x70000006D;

pub fn remap_capslock() -> Result<(), String> {
    let mapping = format!(
        r#"{{"UserKeyMapping":[{{"HIDKeyboardModifierMappingSrc":{CAPS_LOCK_HID},"HIDKeyboardModifierMappingDst":{F18_HID}}}]}}"#
    );
    run_hidutil(&["property", "--set", &mapping])
}

pub fn restore_capslock() -> Result<(), String> {
    run_hidutil(&["property", "--set", r#"{"UserKeyMapping":[]}"#])
}

fn run_hidutil(args: &[&str]) -> Result<(), String> {
    let output = Command::new("hidutil")
        .args(args)
        .output()
        .map_err(|e| format!("hidutil: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "hidutil: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    Ok(())
}
