import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/auth/domain/policies/auth_input_policy.dart';

void main() {
  test('normalizes email to lowercase and trims whitespace', () {
    expect(
      AuthInputPolicy.normalizeEmail('  User@PlanDone.dev '),
      'user@plandone.dev',
    );
  });

  test('rejects passwords without mixed-case and number requirements', () {
    expect(
      AuthInputPolicy.validatePassword('alllowercase'),
      'Password must include an uppercase letter.',
    );
    expect(
      AuthInputPolicy.validatePassword('ALLUPPERCASE'),
      'Password must include a lowercase letter.',
    );
    expect(
      AuthInputPolicy.validatePassword('PasswordOnly'),
      'Password must include a number.',
    );
  });

  test('accepts balanced passwords', () {
    expect(
      AuthInputPolicy.validatePassword('PlanDone123'),
      isNull,
    );
  });

  test('sign-in password validation only requires a value', () {
    expect(
      AuthInputPolicy.validateSignInPassword(''),
      'Password is required.',
    );
    expect(
      AuthInputPolicy.validateSignInPassword('short'),
      isNull,
    );
  });
}
