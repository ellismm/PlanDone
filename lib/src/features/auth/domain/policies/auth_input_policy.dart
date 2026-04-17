class AuthInputPolicy {
  static String normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  static String? validateEmail(String email) {
    final normalized = normalizeEmail(email);
    if (normalized.isEmpty) {
      return 'Email is required.';
    }
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(normalized)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? validateDisplayName(String displayName) {
    if (displayName.trim().isEmpty) {
      return 'Display name is required.';
    }
    return null;
  }

  static String? validatePassword(String password) {
    if (password.isEmpty) {
      return 'Password is required.';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must include an uppercase letter.';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must include a lowercase letter.';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Password must include a number.';
    }
    return null;
  }

  static String? validateSignInPassword(String password) {
    if (password.isEmpty) {
      return 'Password is required.';
    }
    return null;
  }

  static String? validatePasswordConfirmation({
    required String password,
    required String confirmPassword,
  }) {
    if (confirmPassword.isEmpty) {
      return 'Confirm your password.';
    }
    if (password != confirmPassword) {
      return 'Passwords do not match.';
    }
    return null;
  }
}
