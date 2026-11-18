"""Exercise the installer mirror rewrite without sudo, apt or network access."""
import shlex
import subprocess
import unittest
from pathlib import Path


class AptMirrorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(__file__).with_name('apt-install.sh').read_text()
        command = next(shlex.split(line) for line in source.splitlines() if line.strip().startswith('sudo sed '))
        cls.sed_args = [arg for arg in command[2:-1] if arg != '-i']

    def rewrite(self, text):
        return subprocess.run(['sed', *self.sed_args], input=text, text=True, capture_output=True, check=True).stdout

    def test_cloud_mirrors_use_official_https_preserving_paths_and_priorities(self):
        mirrors = (
            'http://us-east-2.ec2.archive.ubuntu.com/ubuntu/\tpriority:1\n'
            'https://eu-west-1.ec2.archive.ubuntu.com/ubuntu/\tpriority:2\n'
            'http://azure.archive.ubuntu.com/ubuntu/\tpriority:3\n'
        )
        expected = ''.join(f'https://archive.ubuntu.com/ubuntu/\tpriority:{priority}\n' for priority in range(1, 4))

        self.assertEqual(self.rewrite(mirrors), expected)

    def test_other_hosts_are_unchanged(self):
        mirrors = (
            'https://archive.ubuntu.com/ubuntu/\tpriority:1\n'
            'https://security.ubuntu.com/ubuntu/\tpriority:2\n'
            'https://mirror.example.com/ubuntu/\tpriority:3\n'
            'https://us-east-2.ec2.archive.ubuntu.com.example.org/ubuntu/\tpriority:4\n'
        )

        self.assertEqual(self.rewrite(mirrors), mirrors)

    def test_rewrite_is_idempotent(self):
        mirrors = self.rewrite('http://us-east-2.ec2.archive.ubuntu.com/ubuntu/\tpriority:1\n')

        self.assertEqual(self.rewrite(mirrors), mirrors)


if __name__ == '__main__':
    unittest.main()
