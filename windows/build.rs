//! sherpa-onnx's C API DLL is delay-loaded so `asr::prefer_bundled_runtime` can load the
//! bundled onnxruntime.dll before it; loaded at start-up, it bound to the older copy Windows
//! keeps in System32 and every model load failed.

fn main() {
    let target = std::env::var("TARGET").unwrap_or_default();
    if target.ends_with("windows-msvc") {
        println!("cargo:rustc-link-arg-bins=/DELAYLOAD:sherpa-onnx-c-api.dll");
        println!("cargo:rustc-link-lib=delayimp");
    }
}
