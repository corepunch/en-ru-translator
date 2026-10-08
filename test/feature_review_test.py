"""The oracle runner must not turn unreviewed drift or errors into a pass."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from ltpro_feature_review import classify


class FeatureReviewTest(unittest.TestCase):
    def test_exact_and_unreviewed_results(self):
        self.assertEqual(classify('OK', 'oracle', 'oracle'), 'exact')
        self.assertEqual(classify('OK', 'changed', 'oracle'), 'unexpected')

    def test_reviews_pin_the_exact_lua_output(self):
        for category in ('intentional_difference', 'known_limitation'):
            review = dict(expected_lua='reviewed', classification=category)
            self.assertEqual(classify('OK', 'reviewed', 'oracle', review), category)
            self.assertEqual(classify('OK', 'new drift', 'oracle', review), 'unexpected')
            self.assertEqual(classify('OK', 'oracle', 'oracle', review), 'unexpected')

    def test_errors_cannot_be_accepted_as_output(self):
        review = dict(expected_lua='error message', classification='known_limitation')
        self.assertEqual(classify('ERROR', 'error message', 'oracle', review), 'errors')
        self.assertEqual(classify('ERROR', 'oracle', 'oracle'), 'errors')


if __name__ == '__main__':
    unittest.main()
