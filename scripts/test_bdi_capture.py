"""Regression checks for the independent BDI evidence validator and failure state."""
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from run_bdi_capture import expected_windows, validate_capture, teacher_code
from sw.b1i_ref.prn_b1i import prn_code


class BdiEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.code = prn_code(6)

    def tearDown(self):
        self.temp.cleanup()

    def check(self, rows):
        path = self.root / 'evidence.csv'
        with path.open('w', encoding='utf-8', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(expected_windows(self.code)[0]))
            writer.writeheader(); writer.writerows(rows)
        return validate_capture(path, self.code)

    def test_correct_full_period_and_confirmations(self):
        result = self.check(expected_windows(self.code))
        self.assertEqual(result['aligned_code_samples_compared'], 49104)
        self.assertEqual(result['first_capture_window'], 11)

    def test_phase_label_is_not_sufficient(self):
        rows = expected_windows(self.code)
        rows[10]['q'] = -57287
        rows[10]['magnitude'] = 57287
        with self.assertRaises(ValueError): self.check(rows)

    def test_wrong_phase_or_sample_count_rejected(self):
        for key, value in [('phase', 11), ('accepted_samples', 180047)]:
            rows = expected_windows(self.code); rows[10][key] = value
            with self.assertRaises(ValueError): self.check(rows)

    def test_nh_sign_and_early_capture_rejected(self):
        rows = expected_windows(self.code); rows[11]['q'] = -57288
        with self.assertRaises(ValueError): self.check(rows)
        rows = expected_windows(self.code); rows[0]['capture'] = 1
        with self.assertRaises(ValueError): self.check(rows)

    def test_missing_second_confirmation_rejected(self):
        with self.assertRaises(ValueError): self.check(expected_windows(self.code)[:-1])

    def test_zero_input_is_not_success(self):
        rows = expected_windows(self.code)
        for row in rows: row.update(i=0, q=0, magnitude=0, capture=0)
        with self.assertRaises(ValueError): self.check(rows)

    def test_corrupted_teacher_code_rejected(self):
        bits = ''.join(map(str, self.code))
        bits = ('1' if bits[0] == '0' else '0') + bits[1:]
        (self.root / 'bdi_prn_code_pkg.sv').write_text("MEO6_CODE = 2046'b"+bits+';', encoding='utf-8')
        with self.assertRaises(ValueError): teacher_code(self.root)

    def test_failed_rerun_invalidates_old_pass(self):
        output = self.root / 'results'; output.mkdir()
        manifest = output / 'bdi_results.json'
        manifest.write_text(json.dumps({'passed': True, 'status': 'passed'}), encoding='utf-8')
        result = subprocess.run([sys.executable, str(Path(__file__).with_name('run_bdi_capture.py')),
                                 '--release', str(self.root / 'missing'), '--output-dir', str(output)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(manifest.read_text(encoding='utf-8'))
        self.assertFalse(data['passed']); self.assertEqual(data['status'], 'failed')


if __name__ == '__main__': unittest.main(verbosity=2)
