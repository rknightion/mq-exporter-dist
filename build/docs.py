"""Build only approved public Markdown into an isolated static-site payload."""
from pathlib import Path
import re
import shutil
import tempfile
import uuid

from public_check import inspect

ROOT = Path(__file__).resolve().parents[1]
PAGES = {
    "README.md": "index.md",
    "SECURITY.md": "security.md",
    **{"docs/" + name + ".md": name + ".md" for name in (
        "compatibility", "safety", "maintaining", "evidence", "candidate-notes", "release-v0.1.0", "prometheus", "otel")},
}


def render(text):
    text = text.replace("](../README.md)", "](index.md)")
    for source, destination in PAGES.items():
        text = text.replace("](" + source + ")", "](" + destination + ")")
    for directory in ("examples", "build"):
        text = text.replace("](" + directory + "/", "](https://github.com/rknightion/mq-exporter-dist/blob/main/" + directory + "/")
    return re.sub(r"^> \[!WARNING\]\n((?:>.*\n)+)",
                  lambda m: '!!! warning "Community software, no warranty"\n' +
                  "".join("    " + line.removeprefix("> ") + "\n" for line in m[1].splitlines()),
                  text, flags=re.MULTILINE)


def main():
    from mkdocs.commands.build import build
    from mkdocs.config import load_config

    work = ROOT / ".work"
    work.mkdir(exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix="docs-", dir=work))
    source = stage / "source"
    source.mkdir()
    for original, destination in PAGES.items():
        text = render((ROOT / original).read_text(encoding="utf-8"))
        inspect(text.encode(), original)
        (source / destination).write_text(text, encoding="utf-8")
    (source / "assets").mkdir()
    shutil.copyfile(ROOT / "site/style.css", source / "assets/style.css")
    output = stage / "html"
    build(load_config(config_file=str(ROOT / "mkdocs.yml"), docs_dir=str(source), site_dir=str(output)))
    for path in output.rglob("*"):
        if path.is_symlink():
            raise RuntimeError("site payload must not contain symlinks")
        if path.is_file():
            inspect(path.read_bytes(), str(path.relative_to(output)))
    target = work / "site-html"
    if target.exists():
        target.rename(work / ("site-previous-" + uuid.uuid4().hex))
    output.rename(target)
    print("Static documentation built and privacy-scanned: .work/site-html")


if __name__ == "__main__":
    main()
