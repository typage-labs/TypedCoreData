#!/usr/bin/env python3
"""Regression tests for verification decisions; no SDK or build is required.

The main verifier additionally compiles an actual mutated Swift client to confirm
that the original missing-symbol false positive is rejected by this same matcher.
"""

from pathlib import Path
import importlib.util
import sys
import unittest


SCRIPT = Path(__file__).with_name("verify-advanced-apis.py")
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("verify_advanced_apis", SCRIPT)
VERIFIER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VERIFIER
SPEC.loader.exec_module(VERIFIER)

ID_ERROR = (
    "cannot assign value of type '[ManagedID<CompileContact>]' "
    "to type '[ManagedID<CompileCompany>]'"
)


def diagnostic(message):
    return f"/tmp/AdvancedAPIs.swift:29:54: error: {message}\n"


class CompilerDiagnosticTests(unittest.TestCase):
    def test_accepts_the_intended_type_mismatch(self):
        self.assertTrue(VERIFIER.NEGATIVE_CASES["WRONG_ID_RESULT"].matches(1, diagnostic(ID_ERROR)))

    def test_ambiguity_is_not_evidence_of_any_intended_rejection(self):
        output = diagnostic("type of expression is ambiguous without a type annotation")
        for flag, rejection in VERIFIER.NEGATIVE_CASES.items():
            with self.subTest(flag=flag):
                self.assertFalse(rejection.matches(1, output))
        # Even an intended mismatch must not conceal an additional ambiguity.
        self.assertFalse(VERIFIER.NEGATIVE_CASES["WRONG_ID_RESULT"].matches(
            1, diagnostic(ID_ERROR) + output))

    def test_id_mismatch_requires_the_expected_specializations(self):
        for wrong_error in [
            ID_ERROR.replace("CompileContact", "NSManagedObject"),
            ID_ERROR.replace("CompileCompany", "NSManagedObject"),
            ID_ERROR.replace("ManagedID<CompileContact>", "CompileContact"),
        ]:
            with self.subTest(error=wrong_error):
                self.assertFalse(VERIFIER.NEGATIVE_CASES["WRONG_ID_RESULT"].matches(
                    1, diagnostic(wrong_error)))

    def test_prior_missing_symbol_mutation_is_not_a_type_safety_success(self):
        output = diagnostic("cannot find 'unrelatedMissingSymbol' in scope") + (
            "28 | #if WRONG_ID_RESULT\n"
            "29 | let _: [ManagedID<CompileCompany>] = unrelatedMissingSymbol()\n"
            "   |                                       `- error: cannot find 'unrelatedMissingSymbol' in scope\n"
        )
        # This is exactly why the former substring-only rule accepted this case.
        self.assertTrue("error:" in output and "CompileCompany" in output)
        self.assertFalse(VERIFIER.NEGATIVE_CASES["WRONG_ID_RESULT"].matches(1, output))
        self.assertTrue(VERIFIER.MISSING_SYMBOL_REJECTION.matches(1, output))

    def test_rejects_an_additional_unrelated_compiler_error(self):
        output = diagnostic(ID_ERROR) + diagnostic("cannot find 'otherFailure' in scope")
        self.assertFalse(VERIFIER.NEGATIVE_CASES["WRONG_ID_RESULT"].matches(1, output))

    def test_diagnostic_category_must_not_be_quoted_inside_another_error(self):
        output = diagnostic(f"compiler plugin failed while reporting: {ID_ERROR}")
        self.assertFalse(VERIFIER.NEGATIVE_CASES["WRONG_ID_RESULT"].matches(1, output))

    def test_source_echo_and_notes_are_not_error_messages(self):
        output = (
            f"29 | // error: {ID_ERROR}\n"
            f"   | `- error: {ID_ERROR}\n"
            f"/tmp/AdvancedAPIs.swift:29:54: note: {ID_ERROR}\n"
        )
        self.assertEqual(VERIFIER.compiler_error_messages(output), [])
        self.assertFalse(VERIFIER.NEGATIVE_CASES["WRONG_ID_RESULT"].matches(1, output))

    def test_requires_an_ordinary_compiler_error_exit(self):
        for status in [0, 2, -4, -5, -11]:
            with self.subTest(status=status):
                self.assertFalse(VERIFIER.NEGATIVE_CASES["WRONG_ID_RESULT"].matches(
                    status, diagnostic(ID_ERROR)))

    def test_unlocated_compiler_errors_cannot_hide_behind_expected_errors(self):
        output = diagnostic(ID_ERROR) + "error: unable to load standard library\n"
        self.assertFalse(VERIFIER.NEGATIVE_CASES["WRONG_ID_RESULT"].matches(1, output))

    def test_requires_the_function_availability_diagnostic(self):
        output = diagnostic("'Predicate' is only available in macOS 14 or newer")
        self.assertFalse(VERIFIER.NEGATIVE_CASES["UNGUARDED_PREDICATE_API"].matches(1, output))

    def test_accepts_only_the_known_availability_companion(self):
        for operating_system in ["macOS 14", "iOS 17.0"]:
            with self.subTest(operating_system=operating_system):
                output = diagnostic(
                    f"'setPredicate(_:on:)' is only available in {operating_system} or newer"
                ) + diagnostic(f"'Predicate' is only available in {operating_system} or newer")
                self.assertTrue(VERIFIER.NEGATIVE_CASES["UNGUARDED_PREDICATE_API"].matches(1, output))
                self.assertFalse(VERIFIER.NEGATIVE_CASES["UNGUARDED_PREDICATE_API"].matches(
                    1, output + diagnostic("cannot find 'unrelatedMissingSymbol' in scope")))

    def test_other_expected_diagnostic_categories(self):
        messages = {
            "WRONG_SECTION_RESULT": "cannot assign value of type '[CompileContact]?' to type '[CompileCompany]?'",
            "UNCHECKED_ID_INITIALIZER": "missing argument label 'validating:' in call",
            "WRONG_PREDICATE_ROOT": (
                "cannot convert value of type 'NSFetchRequest<CompileContact>' "
                "to expected argument type 'NSFetchRequest<CompileCompany>'"
            ),
            "WRONG_PREDICATE_VALUE": "binary operator '==' cannot be applied to operands of type 'Int64' and 'String'",
        }
        for flag, message in messages.items():
            with self.subTest(flag=flag):
                self.assertTrue(VERIFIER.NEGATIVE_CASES[flag].matches(1, diagnostic(message)))
                self.assertFalse(VERIFIER.NEGATIVE_CASES[flag].matches(
                    1, diagnostic("cannot find 'unrelatedMissingSymbol' in scope")))
        self.assertTrue(VERIFIER.OBJC_GENERIC_REJECTION.matches(1, diagnostic(
            "extension of a generic Objective-C class cannot access the class's generic parameters at runtime")))


class HostArchitectureTests(unittest.TestCase):
    def test_selects_a_runnable_target_for_both_supported_hosts(self):
        self.assertEqual(VERIFIER.native_target_label("arm64"), "macos-arm64")
        self.assertEqual(VERIFIER.native_target_label("x86_64"), "macos-minimum")

    def test_unknown_architectures_fail_explicitly(self):
        with self.assertRaisesRegex(ValueError, "Unsupported native probe architecture"):
            VERIFIER.native_target_label("unknown-architecture")


if __name__ == "__main__":
    unittest.main(verbosity=2)
