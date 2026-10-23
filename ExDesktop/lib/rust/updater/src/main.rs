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

fn release_archive_url(tag: &str) -> String {
    format!(
        "https://github.com/krutkrutaya/EXpaDesktop/archive/refs/tags/{tag}.zip"
    )
}

fn ps_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

fn plan_lines(options: &Options) -> Vec<String> {
    let mut lines = vec![
        format!("cd {}", options.repo.display()),
        "git fetch --all --tags --prune".to_string(),
    ];
    match options.mode {
        Mode::Release => {
            lines.push(format!(
                "powershell Invoke-WebRequest {} -OutFile .release.zip",
                release_archive_url(&options.target)
            ));
            lines.push(
                "powershell Expand-Archive .release.zip .release-src".to_string(),
            );
            lines.push(
                "robocopy .release-src/* . /MIR /XD .git build .dart_tool target"
                    .to_string(),
            );
            lines.push(format!("git reset --hard tags/{}", options.target));
        }
        Mode::Commit => {
            lines.push("git fetch origin main".to_string());
            // A hard reset applies modified and new files **and removes files
            // the target commit deleted**; `pull` alone can leave stale files
            // behind when the history was rewritten or the tree diverged.
            lines.push("git reset --hard origin/main".to_string());
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
            // A release is downloaded as a whole archive and mirrored into the
            // checkout. Robocopy /MIR adds changed/new files and deletes files
            // the release no longer has; .git/build caches stay untouched.
            let zip = options.repo.join(".release.zip");
            let extract = options.repo.join(".release-src");
            let script = format!(
                "Invoke-WebRequest -Uri {} -OutFile {}\n\
                 if (Test-Path -LiteralPath {}) {{ Remove-Item -LiteralPath {} -Recurse -Force }}\n\
                 Expand-Archive -LiteralPath {} -DestinationPath {} -Force\n\
                 $root = (Get-ChildItem -LiteralPath {} -Directory | Select-Object -First 1).FullName\n\
                 robocopy $root {} /MIR /XD .git build .dart_tool target /NFL /NDL /NJH /NJS\n\
                 if ($LASTEXITCODE -ge 8) {{ exit 1 }}\n\
                 Remove-Item -LiteralPath {} -Recurse -Force\n\
                 Remove-Item -LiteralPath {} -Force\n\
                 exit 0",
                ps_quote(&release_archive_url(&options.target)),
                ps_quote(&zip.to_string_lossy()),
                ps_quote(&extract.to_string_lossy()),
                ps_quote(&extract.to_string_lossy()),
                ps_quote(&zip.to_string_lossy()),
                ps_quote(&extract.to_string_lossy()),
                ps_quote(&extract.to_string_lossy()),
                ps_quote(&options.repo.to_string_lossy()),
                ps_quote(&extract.to_string_lossy()),
                ps_quote(&zip.to_string_lossy()),
            );
            run_command(
                Command::new("powershell")
                    .args(["-NoProfile", "-NonInteractive", "-Command", &script]),
                &log_path,
            )?;
            // The archive installed the whole release; the reset moves HEAD to
            // the tag so future checks compare against the release commit.
            run_command(
                Command::new("git")
                    .arg("-C")
                    .arg(&options.repo)
                    .args(["reset", "--hard", &format!("tags/{}", options.target)]),
                &log_path,
            )?;
        }
        Mode::Commit => {
            run_command(
                Command::new("git")
                    .arg("-C")
                    .arg(&options.repo)
                    .args(["fetch", "origin", "main"]),
                &log_path,
            )?;
            run_command(
                Command::new("git")
                    .arg("-C")
                    .arg(&options.repo)
                    .args(["reset", "--hard", "origin/main"]),
                &log_path,
            )?;
        }
    }
    let head = git_head(&options.repo)?;
    // The checkout may have renamed the version file, so find it again.
    let build_version_file = find_version_file(&options.repo)?;
    let original = version_text(&build_version_file)?;
    rewrite_version_commit(&build_version_file, &head)?;
    let build = run_command(
        Command::new(&options.flutter)
            .current_dir(options.repo.join("ExDesktop"))
            .args(["build", "windows", "--release"]),
        &log_path,
    );
    // The built asset keeps the rewritten commit; the checkout stays clean.
    let _ = fs::write(&build_version_file, original);
    build?;

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

fn git_head(repo: &Path) -> Result<String, String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(["rev-parse", "HEAD"])
        .output()
        .map_err(|error| format!("cannot read HEAD: {error}"))?;
    if !output.status.success() {
        return Err("git rev-parse HEAD failed".to_string());
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Writes `commit=<head>` into the version file. The caller restores the
/// original bytes after the build, so the checkout remains clean while the
/// built asset reports the right commit.
fn rewrite_version_commit(path: &Path, head: &str) -> Result<(), String> {
    let text = version_text(path)?;
    let mut lines: Vec<String> = text.lines().map(|line| line.to_string()).collect();
    let mut found = false;
    for line in &mut lines {
        if line.trim_start().starts_with("commit=") {
            *line = format!("commit={head}");
            found = true;
        }
    }
    if !found {
        lines.push(format!("commit={head}"));
    }
    fs::write(path, lines.join("\n") + "\n")
        .map_err(|error| format!("cannot rewrite {}: {error}", path.display()))
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
    let mut found = Vec::new();
    for dir in [repo.to_path_buf(), repo.join("ExDesktop")] {
        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.starts_with("version_") && name.ends_with(".txt") {
                    found.push(entry.path());
                }
            }
        }
    }
    found.sort();
    found.dedup();
    match found.len() {
        0 => Err("no version_x.y.z.txt in the repository".to_string()),
        1 => Ok(found.remove(0)),
        _ => Err(format!(
            "multiple version files found ({}); keep exactly one",
            found
                .iter()
                .map(|path| path.file_name().unwrap_or_default().to_string_lossy())
                .collect::<Vec<_>>()
                .join(", ")
        )),
    }
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
    fn release_plan_downloads_the_whole_archive() {
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
        assert!(lines
            .iter()
            .any(|line| line.contains("Invoke-WebRequest https://github.com/")));
        assert!(lines.iter().any(|line| line.contains("Expand-Archive")));
        assert!(lines.iter().any(|line| line.contains("robocopy .release-src/* . /MIR")));
        assert!(lines
            .iter()
            .any(|line| line.contains("git reset --hard tags/v1.2.0")));
        assert!(lines
            .iter()
            .any(|line| line.contains("flutter build windows --release")));
    }

    #[test]
    fn commit_plan_resets_to_origin_main() {
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
        assert!(lines.iter().any(|line| line.contains("git reset --hard origin/main")));
        assert!(lines
            .iter()
            .any(|line| line.contains("C:/flutter/bin/flutter.bat build")));
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

    #[test]
    fn multiple_version_files_are_refused() {
        let temp = std::env::temp_dir().join("expa_updater_ambiguous");
        let _ = fs::remove_dir_all(&temp);
        let _ = fs::create_dir_all(&temp);
        fs::write(temp.join("version_1.0.0.txt"), "version=1.0.0\n").unwrap();
        fs::write(temp.join("version_1.1.0.txt"), "version=1.1.0\n").unwrap();
        let error = find_version_file(&temp).unwrap_err();
        assert!(error.contains("multiple version files"));
        let _ = fs::remove_dir_all(&temp);
    }

    #[test]
    fn the_built_asset_records_the_checked_out_commit() {
        let temp = std::env::temp_dir().join("expa_updater_commit");
        let _ = fs::remove_dir_all(&temp);
        let _ = fs::create_dir_all(&temp);
        let file = temp.join("version_1.3.0.txt");
        fs::write(&file, "version=1.3.0\ncommit=old1234\n").unwrap();
        rewrite_version_commit(&file, "new5678").unwrap();
        let text = version_text(&file).unwrap();
        assert!(text.contains("commit=new5678"));
        assert!(text.contains("version=1.3.0"));
        let _ = fs::remove_dir_all(&temp);
    }
}