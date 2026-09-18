from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Contracts(unittest.TestCase):
    def test_bash_syntax(self):
        subprocess.run(["bash", "-n", str(ROOT / "install/install.sh")], check=True)

    def test_system_tool_environment_is_local(self):
        function = next(line for line in (ROOT / "install/install.sh").read_text().splitlines() if line.startswith("system_tool()"))
        result = subprocess.check_output(["bash", "-c", function + '\nexport LD_LIBRARY_PATH=/opt/mqm/lib64\nsystem_tool bash -c \'printf "%s\\n" "$LD_LIBRARY_PATH"\'\nprintf "%s\\n" "$LD_LIBRARY_PATH"'], text=True)
        self.assertEqual(result.splitlines(), ["/usr/lib64:/lib64", "/opt/mqm/lib64"])

    def test_loader_cache_is_overridden_when_environment_empty(self):
        function = next(line for line in (ROOT / "install/install.sh").read_text().splitlines() if line.startswith("system_tool()"))
        result = subprocess.check_output(["bash", "-c", function + '\nunset LD_LIBRARY_PATH\nsystem_tool bash -c \'printf "%s" "$LD_LIBRARY_PATH"\''], text=True)
        self.assertEqual(result, "/usr/lib64:/lib64")

    def test_invalid_instance_explains_that_it_is_a_local_label(self):
        result = subprocess.run(
            [
                "bash",
                str(ROOT / "install/install.sh"),
                "--version",
                "v6.0.0",
                "--instance",
                "QM1",
                "--qmgr",
                "QM1",
                "--service-user",
                "mqmon",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("local lowercase service label", result.stderr)
        self.assertIn("not an MQ identifier", result.stderr)
        self.assertIn("--instance qm1", result.stderr)

    def test_build_scripts_compile(self):
        for path in (ROOT / "build").glob("*.py"):
            compile(path.read_text(), str(path), "exec")


if __name__ == "__main__":
    unittest.main()
