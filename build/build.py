"""Pinned build orchestration. Build-machine Python 3.12+, never required on targets."""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import versions
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PINS = json.loads((ROOT / "build/inputs.json").read_text())
SDK_BASE = "https://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/messaging/mqdev/redist/"


def run(*args, cwd=None, env=None):
    result = subprocess.run(args, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        print(result.stdout.replace(str(ROOT), "<distribution-source>"))
        raise RuntimeError("build command failed: " + Path(args[0]).name)
    return result.stdout.strip()


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


def download(url, target, sha):
    if not target.exists():
        env = os.environ.copy()
        if os.name != "nt" and Path("/usr/lib64").is_dir():
            env["LD_LIBRARY_PATH"] = "/usr/lib64:/lib64"
        subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--proto-redir", "=https", "--retry", "3", "--max-time", "900", "-o", str(target), url], check=True, env=env)
    if digest(target) != sha:
        raise RuntimeError("build input checksum mismatch; retain failed input for inspection")


def unpack(file, dest):
    dest.mkdir(parents=True, exist_ok=True)
    if file.suffix == ".zip":
        with zipfile.ZipFile(file) as z:
            for e in z.infolist():
                if e.filename.startswith(("/", "\\")) or ".." in Path(e.filename).parts or ":" in e.filename:
                    raise ValueError("unsafe build input archive")
            z.extractall(dest)
    else:
        with tarfile.open(file) as t:
            t.extractall(dest, filter="data")


def prepare_service(work, cache):
    # The collector's pruned vendor tree lacks svc. Keep this separate from it.
    version = PINS["service_xsys_version"]
    archive = cache / "service-xsys.zip"
    download("https://proxy.golang.org/golang.org/x/sys/@v/" + version + ".zip", archive, PINS["service_xsys_zip_sha256"])
    wrapper = work / "service"
    wrapper.mkdir()
    with zipfile.ZipFile(archive) as z:
        prefix = "golang.org/x/sys@" + version + "/"
        for name in z.namelist():
            relative = name.removeprefix(prefix)
            if not name.startswith(prefix) or ".." in Path(relative).parts:
                raise RuntimeError("unexpected service module path")
            if relative.startswith("windows/") or relative in ("LICENSE", "PATENTS"):
                target = wrapper / "vendor/golang.org/x/sys" / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(z.read(name))
    (wrapper / "go.mod").write_text("module github.com/rknightion/mq-exporter-dist/service\n\ngo 1.26.0\n\nrequire golang.org/x/sys " + version + "\n")
    (wrapper / "vendor/modules.txt").write_text("# golang.org/x/sys " + version + "\n## explicit; go 1.25.0\ngolang.org/x/sys/windows\ngolang.org/x/sys/windows/svc\n")
    shutil.copyfile(ROOT / "build/service.go.txt", wrapper / "main.go")
    return wrapper


def notices(source):
    files = [source / "LICENSE"]
    files += sorted(p for p in (source / "vendor").rglob("*") if p.is_file() and p.name.upper().startswith(("LICENSE", "NOTICE", "COPYING")))
    return "\n\n".join("===== " + str(p.relative_to(source)) + " =====\n" + p.read_text(errors="replace") for p in files)


def sbom(source, version, platform, exporter="prometheus", variant="native", patches=None):
    components = []
    roots = [source]
    if platform == "windows-amd64":
        roots.append(source.parent / "service")
    seen = set()
    for root in roots:
        for line in (root / "vendor/modules.txt").read_text().splitlines():
            m = re.match(r"# (\S+) (v\S+)$", line)
            if m and (m[1], m[2]) not in seen:
                seen.add((m[1], m[2]))
                component = {"type": "library", "name": m[1], "version": m[2], "purl": "pkg:golang/" + m[1] + "@" + m[2]}
                # The custom variant's only source modification is the vendored
                # mq-golang patch; record it as CycloneDX pedigree on that component.
                if variant == "custom" and patches and m[1] == "github.com/ibm-messaging/mq-golang/v5":
                    component["pedigree"] = {"patches": [{"type": "unofficial", "diff": {"url": p["name"]}} for p in patches]}
                components.append(component)
    name = "mq-exporter-dist" if exporter == "prometheus" else "mq-otel-dist"
    if variant == "custom":
        name += "-custom"
    return {"bomFormat": "CycloneDX", "specVersion": "1.5", "version": 1, "metadata": {"component": {"type": "application", "name": name + "-" + platform, "version": version}}, "components": components}


def package(source, output, version, platform, commit, evidence, exporter="prometheus", variant="native", patches=None):
    # Exact allowlist: never package the SDK, source cache, environment or raw logs.
    windows = platform == "windows-amd64"
    ext = ".exe" if windows else ""
    binary = "mq_prometheus_custom" if variant == "custom" else "mq_" + exporter
    prefix = "mq-exporter-dist" if exporter == "prometheus" else "mq-otel-dist"
    if variant == "custom":
        prefix += "-custom"
    payload = {n + ext: (output / (n + ext)).read_bytes() for n in [binary, "mq-config-check", "mq-dist"]}
    if windows:
        payload["mq-service.exe"] = (output / "mq-service.exe").read_bytes()
    for name in (["install.ps1", "diagnose.ps1"] if windows else ["install.sh", "diagnose.sh"]):
        content = (ROOT / "install" / name).read_text()
        if name == "install.sh":
            content = content.replace("exporter=prometheus # package default", "exporter=" + exporter + " # package default")
        elif name == "install.ps1":
            content = content.replace("[string]$Exporter = 'prometheus'", "[string]$Exporter = '" + exporter + "'")
        payload[name] = content.encode()
    if not windows:
        # Every Linux archive (prometheus, otel, custom) carries the multi-instance
        # updater and the known-releases inventory it and mq-dist consult.
        update_sh = ROOT / "install/update.sh"
        if not update_sh.exists():
            raise RuntimeError("install/update.sh is missing; it must exist before packaging Linux archives")
        update_content = update_sh.read_text()
        if "exporter=prometheus # package default" in update_content:
            update_content = update_content.replace("exporter=prometheus # package default", "exporter=" + exporter + " # package default")
        payload["update.sh"] = update_content.encode()
        payload["known-releases.json"] = (ROOT / "build/known-releases.json").read_bytes()
    payload["LICENSE"] = (ROOT / "LICENSE").read_bytes()
    payload["THIRD-PARTY-NOTICES.txt"] = notices(source).encode()
    if windows:
        ccroot = source.parent / "cc"
        licenses = sorted(p for p in ccroot.rglob("*") if p.is_file() and p.name.upper().startswith(("COPYING", "LICENSE")))
        if not licenses:
            raise RuntimeError("Windows toolchain license notices missing")
        payload["THIRD-PARTY-NOTICES.txt"] += ("\n\nWindows compiler runtime notices\n" + "\n\n".join(str(p.relative_to(ccroot)) + "\n" + p.read_text(errors="replace") for p in licenses)).encode()
    payload["sbom.cdx.json"] = json.dumps(sbom(source, version, platform, exporter, variant, patches), indent=2, sort_keys=True).encode()
    metadata = {"distribution_version": version, "distribution_commit": commit, "platform": platform, "exporter": exporter, "inputs": PINS,
                "variant": variant, "track": "custom" if variant == "custom" else "native",
                "upstream_tag": PINS["upstream_tag"], "upstream_commit": PINS["upstream_commit"],
                "compatibility": "provisional; see compatibility matrix", "evidence": evidence,
                "payload_sha256": {n: hashlib.sha256(b).hexdigest() for n, b in payload.items()}}
    if variant == "custom":
        metadata["patches"] = [{"name": p["name"], "sha256": p["sha256"]} for p in patches]
    payload["build-metadata.json"] = json.dumps(metadata, indent=2, sort_keys=True).encode()
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    name = prefix + "-" + version + "-" + platform + (".zip" if windows else ".tar.gz")
    target = dist / name
    if target.exists():
        raise RuntimeError("output already exists; archive it before rebuilding")
    if windows:
        with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for n, b in sorted(payload.items()):
                info = zipfile.ZipInfo(n, (2026, 1, 1, 0, 0, 0))
                info.external_attr = 0o100644 << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, b)
    else:
        with target.open("wb") as f, gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=0) as g, tarfile.open(fileobj=g, mode="w", format=tarfile.USTAR_FORMAT) as t:
            for n, b in sorted(payload.items()):
                info = tarfile.TarInfo(n)
                info.size = len(b)
                info.mode = 0o755 if n in [binary, "mq-config-check", "mq-dist", "install.sh", "diagnose.sh", "update.sh"] else 0o644
                t.addfile(info, io.BytesIO(b))
    (dist / (name + ".sha256")).write_text(digest(target) + "  " + name + "\n")
    (dist / (name + ".metadata.json")).write_bytes(payload["build-metadata.json"])
    (dist / (name + ".sbom.cdx.json")).write_bytes(payload["sbom.cdx.json"])
    print(name + " sha256=" + digest(target))
    return target


def resolve_track(version_text, platform, exporter):
    """Parse and validate a distribution version string against the pinned
    upstream tag and the custom track's platform/exporter restriction.
    Raises ValueError on any violation; never touches the filesystem or network."""
    version = versions.parse(version_text)
    if version.upstream_tag != PINS["upstream_tag"]:
        raise ValueError("distribution version's upstream part " + version.upstream_tag + " does not match the pinned upstream_tag " + PINS["upstream_tag"])
    if version.track == "custom" and (platform != "linux" or exporter != "prometheus"):
        raise ValueError("the custom track only supports linux + prometheus")
    return version


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=["linux", "windows"])
    parser.add_argument("version")
    parser.add_argument("--exporter", choices=["prometheus", "otel"], default="prometheus")
    args = parser.parse_args()
    config_args = [] if args.exporter == "prometheus" else ["--exporter", "otel", "--otlp-endpoint", "https://otel.example.com:4318"]
    if run("just", "--evaluate", "go_version", cwd=ROOT).strip('"') != PINS["go_version"]:
        raise RuntimeError("Go build input and task-interface versions differ")
    version = resolve_track(args.version, args.platform, args.exporter)
    track = version.track
    source_binary = "mq_" + args.exporter
    binary = "mq_prometheus_custom" if track == "custom" else source_binary
    # Release automation must operate on committed source, including all packaging files.
    if run("git", "status", "--porcelain", cwd=ROOT):
        raise RuntimeError("commit and review distribution changes before building release bytes")
    commit = run("git", "rev-parse", "HEAD", cwd=ROOT)
    workroot = ROOT / ".work"
    workroot.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="build-", dir=workroot))
    cache = workroot / "downloads"
    cache.mkdir(exist_ok=True)
    source = work / "upstream"
    env = os.environ.copy()
    if Path("/usr/lib64").is_dir():
        env["LD_LIBRARY_PATH"] = "/usr/lib64:/lib64"
    run("git", "clone", "--quiet", "--depth", "1", "--branch", PINS["upstream_tag"], "https://github.com/ibm-messaging/mq-metric-samples.git", str(source), env=env)
    if run("git", "rev-parse", "HEAD", cwd=source) != PINS["upstream_commit"]:
        raise RuntimeError("upstream tag changed")
    patches = None
    if track == "custom":
        # Only reviewed patches touch the custom track; the native track builds
        # upstream unchanged.
        patch_path = ROOT / "build/patches/qdepthhi.patch"
        run("git", "apply", "--check", str(patch_path), cwd=source)
        run("git", "apply", str(patch_path), cwd=source)
        patches = [{"name": patch_path.name, "sha256": digest(patch_path)}]
    output = work / "output"
    output.mkdir()
    check = source / "dist-check"
    check.mkdir()
    shutil.copyfile(source / "cmd" / source_binary / "config.go", check / "config.go")
    shutil.copyfile(ROOT / "build/configcheck.go.txt", check / "main.go")
    if args.platform == "linux":
        go = cache / "go-linux.tar.gz"
        mq = cache / "mq-linux.tar.gz"
        download("https://go.dev/dl/go" + PINS["go_version"] + ".linux-amd64.tar.gz", go, PINS["go_linux_sha256"])
        download(SDK_BASE + PINS["mq_sdk_version"] + "-IBM-MQC-Redist-LinuxX64.tar.gz", mq, PINS["mq_linux_sha256"])
        unpack(go, work / "toolchain")
        unpack(mq, work / "mq")
        subprocess.run(["docker", "build", "--platform", "linux/amd64", "-f", str(ROOT / "build/linux.Dockerfile"), "-t", "mq-exporter-dist-builder:local", str(ROOT)], check=True)
        image = run("docker", "image", "inspect", "mq-exporter-dist-builder:local", "--format", "{{.Id}}")
        base = ["docker", "run", "--rm", "--network", "none", "--platform", "linux/amd64", "-v", str(work) + ":/work", "-v", str(ROOT) + ":/project:ro", "-v", str(work / "toolchain/go") + ":/opt/go:ro", "-v", str(work / "mq") + ":/opt/mqm:ro", image]
        def container(*cmd):
            return run(*(base + list(cmd)))
        flags = ["-mod=vendor", "-trimpath", "-buildvcs=false", "-ldflags=-buildid="]
        container("go", "build", *flags, "-o", "/work/output/" + binary, "./cmd/" + source_binary)
        contains_metric = b"attribute_depth_high_limit" in (output / binary).read_bytes()
        if track == "custom" and not contains_metric:
            raise RuntimeError("custom binary is missing the attribute_depth_high_limit metric string")
        if track != "custom" and contains_metric:
            raise RuntimeError("native binary unexpectedly contains the custom attribute_depth_high_limit metric string")
        container("go", "build", *flags, "-o", "/work/output/mq-config-check", "./dist-check")
        container("bash", "-c", "cd /project && CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags=-buildid= -o /work/output/mq-dist ./cmd/mq-dist")
        if track == "custom":
            # Prove the DEPTH_HIGH_LIMIT test actually exercises the emission
            # guard: it must pass against the applied patch, and a variant
            # with the guard's Set=true path reverted must make it fail.
            test_pkg = "./vendor/github.com/ibm-messaging/mq-golang/v5/mqmetric/"
            test_dest = source / "vendor/github.com/ibm-messaging/mq-golang/v5/mqmetric/qdepthhi_test.go"
            shutil.copyfile(ROOT / "tests/qdepthhi_test.go.txt", test_dest)
            container("go", "test", "-mod=vendor", test_pkg, "-run", "TestQDepthHighLimit")
            negative_patch = ROOT / "build/patches/qdepthhi-negative.patch"
            run("git", "apply", "--check", str(negative_patch), cwd=source)
            run("git", "apply", str(negative_patch), cwd=source)
            negative_result = subprocess.run(base + ["go", "test", "-mod=vendor", test_pkg, "-run", "TestQDepthHighLimit"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            run("git", "apply", "-R", str(negative_patch), cwd=source)
            if negative_result.returncode == 0:
                raise RuntimeError("qdepthhi-negative.patch did not make TestQDepthHighLimit fail; the emission guard is not proven under test:\n" + negative_result.stdout)
            test_dest.unlink()
        for executable in (binary, "mq-config-check", "mq-dist"):
            container("/work/output/mq-dist", "inspect", "/work/output/" + executable)
        container("env", "LD_BIND_NOW=1", "/work/output/" + binary, "--help")
        (output / "config.json").write_text(container("/work/output/mq-dist", "config", "--qmgr", "QM1", *config_args), encoding="utf-8")
        container("/work/output/mq-config-check", "-f", "/work/output/config.json")
        exit_code = "10" if args.exporter == "prometheus" else "1"
        container("bash", "-c", "/work/output/" + binary + " -f /work/output/config.json >/work/output/startup.log 2>&1; test $? -eq " + exit_code)
        container("bash", "-c", "mkdir /tmp/mq-conflict; ln -s /opt/mqm/lib64/libcurl.so /tmp/mq-conflict/libcurl.so.4; ! LD_LIBRARY_PATH=/tmp/mq-conflict curl --version | grep '^Protocols:.*https'; LD_LIBRARY_PATH=/usr/lib64:/lib64 curl --version | grep '^Protocols:.*https'")
        validation = ["docker", "run", "--rm", "--network", "none", "--platform", "linux/amd64", "-v", str(output) + ":/output:ro", "-v", str(work / "mq") + ":/opt/mqm:ro", "-e", "LD_BIND_NOW=1", "-e", "LD_LIBRARY_PATH=/opt/mqm/lib64:/usr/lib64:/lib64", PINS["linux_validation_image"]]
        run(*validation, "/output/" + binary, "--help")
        run(*validation, "/output/mq-config-check", "-f", "/output/config.json")
        evidence = {"compiled": True, "loader_smoke": "EL8 build container, MQ client runtime", "config_reader": "PASS: actual upstream initConfig", "local_bindings": "unavailable", "live_mq": "unavailable", "kernel_4_18": "unavailable", "service_lifecycle": "unavailable", "build_image": image,
                    "el9_userspace": "PASS: eager native loading and actual upstream config reader; host kernel shared",
                    "go": container("go", "version"), "compiler": container("gcc", "--version").splitlines()[0], "linker": container("ld", "--version").splitlines()[0], "rpm_inventory": container("rpm", "-qa", "--qf", "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n").splitlines(),
                    "elf": container("readelf", "-h", "-l", "-d", "--version-info", "/work/output/" + binary), "mq_imports": container("bash", "-c", "nm -D --undefined-only /work/output/" + binary + " | grep MQ")}
    else:
        if os.name != "nt":
            raise RuntimeError("Windows build requires a Windows build host (Server 2022 CI is build-only evidence)")
        go = cache / "go-windows.zip"
        mq = cache / "mq-windows.zip"
        cc = cache / "gcc-windows.zip"
        download("https://go.dev/dl/go" + PINS["go_version"] + ".windows-amd64.zip", go, PINS["go_windows_sha256"])
        download(SDK_BASE + PINS["mq_sdk_version"] + "-IBM-MQC-Redist-Win64.zip", mq, PINS["mq_windows_sha256"])
        download(PINS["windows_toolchain_url"], cc, PINS["windows_toolchain_sha256"])
        unpack(go, work / "toolchain")
        unpack(mq, work / "mq")
        unpack(cc, work / "cc")
        env = os.environ.copy()
        env.update(GOTOOLCHAIN="local", GOPROXY="off", GOSUMDB="off", GOOS="windows", GOARCH="amd64", GOAMD64="v1", CGO_ENABLED="1",
                   CC=str(work / "cc/mingw64/bin/gcc.exe"), CGO_CFLAGS='-O2 -march=x86-64 -mtune=generic -D_WIN64 "-I' + (work / "mq/Tools/c/include").as_posix() + '"',
                   CGO_LDFLAGS='"-L' + (work / "mq/bin64").as_posix() + '" -static-libgcc')
        gobin = work / "toolchain/go/bin/go.exe"
        env["PATH"] = str(work / "cc/mingw64/bin") + ";" + env["PATH"]
        linker = run(str(work / "cc/mingw64/bin/ld.exe"), "--version", env=env).splitlines()[0]
        match = re.search(r"(\d+)\.(\d+)(?:\.\d+)?$", linker)
        if not match or tuple(map(int, match.groups())) < (2, 37):
            raise RuntimeError("Windows GCC requires binutils >= 2.37 (DWARF 5)")
        flags = ["-mod=vendor", "-trimpath", "-buildvcs=false", "-ldflags=-buildid="]
        for name, pkg in [(binary, "./cmd/" + source_binary), ("mq-config-check", "./dist-check")]:
            run(str(gobin), "build", *flags, "-o", str(output / (name + ".exe")), pkg, cwd=source, env=env)
        if b"attribute_depth_high_limit" in (output / (binary + ".exe")).read_bytes():
            raise RuntimeError("native Windows binary unexpectedly contains the custom attribute_depth_high_limit metric string")
        env["CGO_ENABLED"] = "0"
        run(str(gobin), "build", "-trimpath", "-buildvcs=false", "-ldflags=-buildid=", "-o", str(output / "mq-dist.exe"), "./cmd/mq-dist", cwd=ROOT, env=env)
        wrapper = prepare_service(work, cache)
        run(str(gobin), "build", *flags, "-o", str(output / "mq-service.exe"), ".", cwd=wrapper, env=env)
        shutil.copyfile(ROOT / "tests/service-child.go.txt", source / "dist-child.go")
        run(str(gobin), "build", *flags, "-o", str(output / "service-child.exe"), "dist-child.go", cwd=source, env=env)
        imports = run(str(work / "cc/mingw64/bin/objdump.exe"), "-p", str(output / (binary + ".exe")), env=env)
        dlls = re.findall(r"DLL Name:\s*(\S+)", imports)
        allowed = {"mqm.dll", "kernel32.dll", "msvcrt.dll", "ucrtbase.dll", "advapi32.dll", "ws2_32.dll", "ntdll.dll"}
        if any(d.lower() not in allowed and not d.lower().startswith("api-ms-win-") for d in dlls):
            raise RuntimeError("undeclared PE DLL import")
        env["PATH"] = str(work / "mq/bin64") + ";" + os.environ["SystemRoot"] + "\\System32"
        run(str(output / (binary + ".exe")), "--help", env=env)
        config = run(str(output / "mq-dist.exe"), "config", "--qmgr", "QM1", *config_args, env=env)
        (output / "config.json").write_text(config, encoding="utf-8")
        run(str(output / "mq-config-check.exe"), "-f", str(output / "config.json"), env=env)
        run(str(Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"), "-NoProfile", "-File", str(ROOT / "tests/windows-runtime.ps1"), "-Output", str(output), "-MQPath", str(work / "mq"), "-Exporter", args.exporter, env=env)
        evidence = {"compiled": True, "loader_smoke": "Windows build host; NOT Server 2019 proof", "config_reader": "PASS: actual upstream initConfig", "service_lifecycle": "unavailable", "live_mq": "unavailable", "server_2019": "unavailable", "build_image": "windows-2022 hosted runner; toolchain archives pinned", "go": run(str(gobin), "version", env=env), "linker": linker, "compiler": run(str(work / "cc/mingw64/bin/gcc.exe"), "--version").splitlines()[0], "dll_imports": dlls}
    target = package(source, output, args.version, args.platform + "-amd64", commit, evidence, args.exporter, track, patches)
    if args.platform == "linux":
        subprocess.run(["docker", "run", "--rm", "--platform", "linux/amd64", "-v", str(ROOT) + ":/project:ro", "-v", str(ROOT / "dist") + ":/artifacts:ro", "-v", str(work / "mq") + ":/sdk-input:ro", image,
                        "bash", "/project/tests/linux-install.sh", "/artifacts/" + target.name, args.version, args.exporter], check=True)
    # Preserve evidence and licensed inputs instead of deleting them. Failed builds
    # remain at build-*; successful ones are clearly archived and never re-used.
    completed = workroot / "completed"
    completed.mkdir(exist_ok=True)
    work.rename(completed / work.name)


if __name__ == "__main__":
    main()
