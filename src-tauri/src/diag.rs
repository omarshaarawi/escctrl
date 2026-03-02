use std::io::Write;

pub fn log(msg: &str) {
    let home = std::env::var("HOME").unwrap_or_default();
    let path = format!("{home}/Library/Logs/escctrl.log");
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
    {
        let _ = writeln!(f, "{msg}");
    }
}
