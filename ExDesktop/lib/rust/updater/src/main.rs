// EXpaDesktop's update helper.
//
// The in-app Updater checks GitHub and shows the changelog; this binary does
// the part that must survive the app closing: fetch, check out the chosen
// release tag or the latest main, build the Windows release, relaunch.
//
// It refuses to touch a dirty working tree unless --force is passed, so an
// update can never silently throw away local changes. `--plan` prints the
// exact commands without running them; the unit tests use that to keep the
// release/commit paths honest.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    Release,
    Commit,
}

struct Options {
    repo: PathBuf,
    mode: Mode,
    target: String,
    flutter: String,
    force: bool,
    plan: bool,
    pid: Option<u32>,
}

fn main() {
    let options = match parse_args() {
        Some(options) => options,
        None => {
            eprintln!(
                "usage: updater --repo PATH --mode release|commit --target TAG|SHA \
                 [--flutter PATH] [--pid PID] [--force] [--plan]"
            );
            std::process::exit(2);
        }
    };
    if options.plan {
        for line in plan_lines(&options) {
            println!("{line}");
        }
        return;
    }
    match run(&options) {
        Ok(()) => {}
        Err(message) => {
            eprintln!("update failed: {message}");
            append_log(
                &options.repo.join(".expa_update.log"),
                &format!("update failed: {message}"),
            );
            // The desktop already closed to let the build replace its exe.
            // If anything went wrong, bring the old build back instead of
            // leaving the user without a desktop.
            relaunch(&options.repo);
            std::process::exit(1);
        }
    }
}

fn relaunch(repo: &Path) {
    let exe = repo.join("ExDesktop/build/windows/x64/runner/Release/exp_desktop.exe");
    if exe.exists() {
        let _ = Command::new(&exe).spawn();
    }
}

fn parse_args() -> Option<Options> {
    let mut repo = None;
    let mut mode = None;
    let mut target = None;
    let mut flutter = "flutter".to_string();
    let mut force = false;
    let mut plan = false;
    let mut pid = None;
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--repo" => repo = args.next().map(PathBuf::from),
            "--mode" => {
                mode = match args.next().as_deref() {
                    Some("release") => Some(Mode::Release),
                    Some("commit") => Some(Mode::Commit),
                    _ => None,
                }
            }
            "--target" => target = args.next(),
            "--flutter" => {
                if let Some(value) = args.next() {
                    flutter = value;
                }
            }
            "--force" => force = true,
            "--plan" => plan = true,
            "--pid" => pid = args.next().and_then(|value| value.parse().ok()),
            _ => {}
        }
    }
    Some(Options {
        repo: repo?,
        mode: mode?,
        target: target?,
        flutter,
        force,
        plan,
        pid,
    })
}

fn plan_lines(options: &Options) -> Vec<String> {
    let mut lines = vec![
        format!("cd {}", options.repo.display()),
        "git fetch --all --tags --prune".to_string(),
    ];
    match options.mode {
        Mode::Release => lines.push(format!("git checkout tags/{}", options.target)),
        Mode::Commit => {
            lines.push("git checkout main".to_string());
            lines.push("git pull --ff-only origin main".to_string());
        }
    }
    lines.push(format!(
        "cd {}",
        options.repo.join("ExDesktop").display()
    ));
    lines.push(format!("{} build windows --release", options.flutter));
    lines
}

fn run(options: &Options) -> Result<(), String> {
    if !options.repo.join(".git").exists() {
        return Err(format!(
            "{} is not a git checkout",
            options.repo.display()
        ));
    }
    let version_file = find_version_file(&options.repo)?;
    let current = parse_version_file(&version_file)
        .ok_or_else(|| "cannot parse the local version file".to_string())?;
    if options.mode == Mode::Release {
        let target = parse_version(&options.target)
            .ok_or_else(|| format!("cannot parse the target tag {}", options.target))?;
        if is_newer(current, target) && !options.force {
            return Err(format!(
                "refusing to downgrade {} to {} (pass --force to override)",
                format_version(current),
                options.target
            ));
        }
    }
    if !options.force {
        let status = Command::new("git")
            .arg("-C")
            .arg(&options.repo)
            .args(["status", "--porcelain"])
            .output()
            .map_err(|error| format!("cannot run git: {error}"))?;
        if !status.stdout.is_empty() {
            return Err(
                "the working tree has uncommitted changes; commit or stash them first \
                 (or pass --force)"
                    .to_string(),
            );
        }
    }

    if options.pid.is_some() {
        // The desktop asked us to wait for it to close before the build
        // replaces the exe.
        thread::sleep(Duration::from_millis(2200));
    }

    let log_path = options.repo.join(".expa_update.log");
    for line in plan_lines(options) {
        append_log(&log_path, &format!("> {line}"));
    }

    run_command(
        Command::new("git")
            .arg("-C")
            .arg(&options.repo)
            .args(["fetch", "--all", "--tags", "--prune"]),
        &log_path,
    )?;
    match options.mode {
        Mode::Release => {
            run_command(
                Command::new("git")
                    .arg("-C")
                    .arg(&options.repo)
                    .args(["checkout", &format!("tags/{}", options.target)]),
                &log_path,
            )?;
        }
        Mode::Commit => {
            run_command(
                Command::new("git")
                    .arg("-C")
                    .arg(&options.repo)
                    .args(["checkout", "main"]),
                &log_path,
            )?;
            run_command(
                Command::new("git")
                    .arg("-C")
                    .arg(&options.repo)
                    .args(["pull", "--ff-only", "origin", "main"]),
                &log_path,
            )?;
        }
    }
    run_command(
        Command::new(&options.flutter)
            .current_dir(options.repo.join("ExDesktop"))
            .args(["build", "windows", "--release"]),
        &log_path,
    )?;

    let exe = options
        .repo
        .join("ExDesktop/build/windows/x64/runner/Release/exp_desktop.exe");
    if !exe.exists() {
        return Err("the build finished but the exe is missing".to_string());
    }
    Command::new(&exe)
        .spawn()
        .map_err(|error| format!("cannot relaunch the app: {error}"))?;
    append_log(&log_path, &format!("launched {}", exe.display()));
    Ok(())
}

fn run_command(command: &mut Command, log_path: &Path) -> Result<(), String> {
    let output = command
        .output()
        .map_err(|error| format!("cannot start command: {error}"))?;
    append_log(log_path, &String::from_utf8_lossy(&output.stdout));
    append_log(log_path, &String::from_utf8_lossy(&output.stderr));
    if output.status.success() {
        Ok(())
    } else {
        Err(format!("command exited with {}", output.status))
    }
}

fn append_log(path: &Path, text: &str) {
    if text.trim().is_empty() {
        return;
    }
    use std::io::Write;
    if let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{text}");
    }
}

fn find_version_file(repo: &Path) -> Result<PathBuf, String> {
    for dir in [repo.to_path_buf(), repo.join("ExDesktop")] {
        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.starts_with("version_") && name.ends_with(".txt") {
                    return Ok(entry.path());
                }
            }
        }
    }
    Err("no version_x.y.z.txt in the repository".to_string())
}

fn version_text(path: &Path) -> Result<String, String> {
    fs::read_to_string(path).map_err(|error| format!("cannot read {}: {error}", path.display()))
}

/// The file name is authoritative: version_2.3.4.txt. The body is a fallback.
fn parse_version_file(path: &Path) -> Option<(u32, u32, u32)> {
    let name = path.file_name()?.to_string_lossy();
    let stem = name.strip_prefix("version_")?.strip_suffix(".txt")?;
    parse_version(stem).or_else(|| {
        version_text(path).ok().and_then(|text| {
            text.lines()
                .find_map(|line| line.trim().strip_prefix("version="))
                .and_then(parse_version)
        })
    })
}

fn parse_version(value: &str) -> Option<(u32, u32, u32)> {
    let trimmed = value.trim();
    let without_v = trimmed.strip_prefix('v').unwrap_or(trimmed);
    let mut parts = without_v.split('.');
    let major = parts.next()?.parse().ok()?;
    let minor = parts.next()?.parse().ok()?;
    let patch = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some((major, minor, patch))
}

fn is_newer(current: (u32, u32, u32), target: (u32, u32, u32)) -> bool {
    target > current
}

fn format_version(value: (u32, u32, u32)) -> String {
    format!("{}.{}.{}", value.0, value.1, value.2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_parse_with_or_without_v() {
        assert_eq!(parse_version("1.2.3"), Some((1, 2, 3)));
        assert_eq!(parse_version("v0.9.12"), Some((0, 9, 12)));
        assert_eq!(parse_version("1.0"), None);
        assert_eq!(parse_version("x.y.z"), None);
    }

    #[test]
    fn comparison_is_lexicographic() {
        assert!(is_newer((1, 0, 0), (1, 0, 1)));
        assert!(is_newer((1, 0, 9), (1, 1, 0)));
        assert!(is_newer((0, 9, 9), (1, 0, 0)));
        assert!(!is_newer((1, 1, 0), (1, 0, 9)));
        assert!(!is_newer((1, 0, 0), (1, 0, 0)));
    }

    #[test]
    fn release_plan_checks_out_the_tag() {
        let options = Options {
            repo: PathBuf::from("C:/repo"),
            mode: Mode::Release,
            target: "v1.2.0".to_string(),
            flutter: "flutter".to_string(),
            force: false,
            plan: true,
            pid: None,
        };
        let lines = plan_lines(&options);
        assert!(lines.iter().any(|line| line.contains("git checkout tags/v1.2.0")));
        assert!(lines.iter().any(|line| line.contains("flutter build windows --release")));
    }

    #[test]
    fn commit_plan_pulls_main() {
        let options = Options {
            repo: PathBuf::from("C:/repo"),
            mode: Mode::Commit,
            target: "abc1234".to_string(),
            flutter: "C:/flutter/bin/flutter.bat".to_string(),
            force: false,
            plan: true,
            pid: None,
        };
        let lines = plan_lines(&options);
        assert!(lines.iter().any(|line| line.contains("git pull --ff-only origin main")));
        assert!(lines.iter().any(|line| line.contains("C:/flutter/bin/flutter.bat build")));
    }

    #[test]
    fn the_version_file_name_carries_the_semver() {
        let temp = std::env::temp_dir().join("expa_updater_test");
        let _ = fs::create_dir_all(&temp);
        fs::write(
            temp.join("version_2.3.4.txt"),
            "version=2.3.4\ncommit=abc1234\n",
        )
        .unwrap();
        let file = find_version_file(&temp).unwrap();
        let version = parse_version_file(&file).unwrap();
        assert_eq!(version, (2, 3, 4));
        let _ = fs::remove_dir_all(&temp);
    }
}