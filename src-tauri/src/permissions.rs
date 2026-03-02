extern "C" {
    fn CGRequestPostEventAccess() -> bool;
}

pub fn request_accessibility() -> bool {
    unsafe { CGRequestPostEventAccess() }
}
