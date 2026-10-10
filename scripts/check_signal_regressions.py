"""PRN 与捕获回归检查；只输出断言结果，不生成实验报告。"""
from __future__ import annotations

import hashlib
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "sw"))
from b1i_ref import acquisition, params, prn_b1i, signal_gen  # noqa: E402
from b1i_ref import scenario  # noqa: E402
from b1i_ref.tracking_model import TrackingChannel  # noqa: E402
from run_local_chain import samples_in_blocks, track_in_blocks  # noqa: E402


class SignalRegressions(unittest.TestCase):
    def test_prn_known_sequences(self):
        # SHA256 of 2046 unpacked 0/1 bytes. Independently evaluated with an
        # integer register whose bit 0 is stage 11 and the GNSS-SDR numerical taps:
        # https://github.com/gnss-sdr/gnss-sdr/blob/main/src/algorithms/libs/beidou_b1i_signal_replica.cc
        expected = {
            1: "0d962586c5881e7cc9bc3c3f105dd37c23138b930ca79d8241a0a3fd013a9b88",
            37: "a5de9b776ddb74fb63c87f298bdd253383c0926eee5435f21bc23111b7fc843d",
            38: "c50e7ea580eb563f09606f16534026d9f36ae0e47ea640963bfd40523590ebd2",
            39: "88c99c0184db95e6a19ede26daadde06a517dd14ab1da0f74efe3c25d63fddc6",
            63: "0562eab00d06f482276997bd5ae99a515b5938b8f0c5ead6321ca2e8b9424e72",
        }
        for prn, digest in expected.items():
            with self.subTest(prn=prn):
                self.assertEqual(hashlib.sha256(bytes(prn_b1i.prn_code(prn))).hexdigest(), digest)

    def test_all_prns_and_invalid_numbers(self):
        codes = [bytes(prn_b1i.prn_code(p)) for p in range(1, 64)]
        self.assertEqual(len(set(codes)), 63)
        self.assertTrue(all(len(c) == 2046 and set(c) == {0, 1} for c in codes))
        for prn in (0, 64, -1):
            with self.subTest(prn=prn), self.assertRaises(KeyError):
                prn_b1i.prn_code(prn)
        self.assertTrue(prn_b1i.selftest()["gold_3_valued"])

    def test_acquisition_magnitude_rotation(self):
        iq = np.array([1 + 2j, -3 + 4j, 0j])
        expected = np.array([np.sqrt(5), 5, 0])
        for phase in np.linspace(0, 2 * np.pi, 16, endpoint=False):
            np.testing.assert_allclose(acquisition.magnitude(iq * np.exp(1j * phase)), expected)

    def test_c39_acquisition_at_eight_carrier_phases(self):
        code = prn_b1i.prn_code(39)
        for phase in np.linspace(0, 2 * np.pi, 8, endpoint=False):
            with self.subTest(phase=phase):
                signal = signal_gen.make_if_signal(
                    params.P.samples_per_ms, code, prn_b1i.NH20, [0], 123.125, 1500,
                    carrier_phase_rad=phase, quantize=False)
                hit = acquisition.serial_search(signal, code, range(1000, 2001, 100))[0]
                self.assertEqual(hit["doppler_hz"], 1500)
                self.assertEqual(hit["code_phase_chips"], 123.125)

    def test_block_generation_preserves_samples_and_noise(self):
        rx = scenario.geodetic_to_ecef(39.9, 116.4, 50)
        eph = scenario.make_constellation(rx, 345618, 1000, n_sats=1, seed=3)[0]
        sc = scenario.Scenario(rx, 345618, 1000, [scenario.SatConfig(eph)], seed=3)
        n = 4 * params.P.samples_per_ms + 7
        expected = sc.samples(0, n)
        np.testing.assert_array_equal(samples_in_blocks(sc, n, 1), expected)

    def test_block_tracking_preserves_window_state(self):
        code = prn_b1i.prn_code(39)
        signal = signal_gen.make_if_signal(
            12 * params.P.samples_per_ms + 7, code, prn_b1i.NH20, [0], 123.125, 1500)
        whole, blocked = TrackingChannel(code), TrackingChannel(code)
        for ch in (whole, blocked):
            ch.reset(code_phase_chips=123.125, doppler_hz=1500)
        self.assertEqual(track_in_blocks(blocked, signal, 1), whole.process(signal))
        self.assertEqual(blocked.code_phase, whole.code_phase)
        self.assertEqual(blocked.carrier_phase, whole.carrier_phase)


if __name__ == "__main__":
    unittest.main(verbosity=2)
