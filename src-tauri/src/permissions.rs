extern "C" {
    fn CGPreflightPostEventAccess() -> bool;
    fn CGRequestPostEventAccess() -> bool;
}

pub fn check_accessibility() -> bool {
    unsafe { CGPreflightPostEventAccess() }
}

pub fn request_accessibility() -> bool {
    unsafe { CGRequestPostEventAccess() }
}
