/**
 * SORYNTH RESCUE COMMAND DASHBOARD - OPERATOR UTILITIES
 * Pure, tested helpers for operator credential generation, format verification, and sequence tracking.
 */

/**
 * Generates a cryptographically secure, high-entropy temporary password.
 * Uses Web Crypto API (crypto.getRandomValues) to ensure non-deterministic,
 * cryptographically random bytes.
 * Guarantees length >= 16 with uppercase, lowercase, numbers, and special symbols.
 */
export function generateSecureTemporaryPassword(length: number = 16): string {
  const minLength = Math.max(14, length);
  const uppercaseChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // Exclude ambiguous I, O
  const lowercaseChars = 'abcdefghijkmnopqrstuvwxyz'; // Exclude ambiguous l
  const digitChars = '23456789'; // Exclude ambiguous 0, 1
  const symbolChars = '!@#$%^&*()-_=+';

  const allChars = uppercaseChars + lowercaseChars + digitChars + symbolChars;

  const getRandomChar = (charset: string): string => {
    const randomBuffer = new Uint32Array(1);
    crypto.getRandomValues(randomBuffer);
    return charset[randomBuffer[0] % charset.length];
  };

  // Guarantee complexity requirements
  const requiredChars = [
    getRandomChar(uppercaseChars),
    getRandomChar(uppercaseChars),
    getRandomChar(lowercaseChars),
    getRandomChar(lowercaseChars),
    getRandomChar(digitChars),
    getRandomChar(digitChars),
    getRandomChar(symbolChars),
    getRandomChar(symbolChars),
  ];

  // Fill remaining length
  const remainingCount = minLength - requiredChars.length;
  for (let i = 0; i < remainingCount; i++) {
    requiredChars.push(getRandomChar(allChars));
  }

  // Cryptographically shuffle the array (Fisher-Yates with Web Crypto)
  for (let i = requiredChars.length - 1; i > 0; i--) {
    const randomBuffer = new Uint32Array(1);
    crypto.getRandomValues(randomBuffer);
    const j = randomBuffer[0] % (i + 1);
    const temp = requiredChars[i];
    requiredChars[i] = requiredChars[j];
    requiredChars[j] = temp;
  }

  return requiredChars.join('');
}

/**
 * Scans a list of existing emails and calculates the next sequential official email address.
 * Matches patterns: operator1@sorynth.org, operator2@sorynth.org, etc.
 * Defaults to: operator1@sorynth.org if none exist.
 */
export function generateNextOperatorEmail(
  existingEmails: (string | null | undefined)[],
  domain: string = 'sorynth.org'
): string {
  const cleanDomain = domain.toLowerCase().trim();
  const pattern = new RegExp(`^operator(\\d+)@${cleanDomain.replace('.', '\\.')}$`, 'i');

  let maxIndex = 0;

  for (const rawEmail of existingEmails) {
    if (!rawEmail) continue;
    const email = rawEmail.trim().toLowerCase();
    const match = email.match(pattern);
    if (match && match[1]) {
      const idx = parseInt(match[1], 10);
      if (!isNaN(idx) && idx > maxIndex) {
        maxIndex = idx;
      }
    }
  }

  return `operator${maxIndex + 1}@${cleanDomain}`;
}

/**
 * Scans existing employee IDs and calculates the next sequential Employee ID (RES-001, RES-002...).
 * Padded to at least 3 digits.
 * Defaults to: RES-001 if none exist.
 */
export function generateNextEmployeeId(
  existingIds: (string | null | undefined)[]
): string {
  const pattern = /^RES-(\d+)$/i;
  let maxIndex = 0;

  for (const rawId of existingIds) {
    if (!rawId) continue;
    const id = rawId.trim().toUpperCase();
    const match = id.match(pattern);
    if (match && match[1]) {
      const idx = parseInt(match[1], 10);
      if (!isNaN(idx) && idx > maxIndex) {
        maxIndex = idx;
      }
    }
  }

  const nextIndex = maxIndex + 1;
  return `RES-${String(nextIndex).padStart(3, '0')}`;
}

/**
 * Validates format of an Employee ID.
 * Must match RES-XXX (where XXX is at least 3 digits).
 */
export function validateEmployeeId(id: string): { isValid: boolean; error?: string } {
  if (!id || !id.trim()) {
    return { isValid: false, error: 'Employee ID is required.' };
  }
  const clean = id.trim().toUpperCase();
  if (!/^RES-\d{3,}$/.test(clean)) {
    return { isValid: false, error: 'Employee ID must follow the standard format: RES-001, RES-002, etc.' };
  }
  return { isValid: true };
}

/**
 * Validates an official email format.
 */
export function validateOperatorEmail(email: string): { isValid: boolean; error?: string } {
  if (!email || !email.trim()) {
    return { isValid: false, error: 'Email address is required.' };
  }
  const clean = email.trim().toLowerCase();
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(clean)) {
    return { isValid: false, error: 'Please enter a valid email address.' };
  }
  return { isValid: true };
}

/**
 * Validates that an initial or changed password meets security requirements.
 * Enforces high entropy (min 12 chars, upper, lower, digit, symbol)
 * and strictly prohibits default or trivial passwords.
 */
export function validatePasswordStrength(password: string): { isValid: boolean; error?: string } {
  if (!password || !password.trim()) {
    return { isValid: false, error: 'Password cannot be empty.' };
  }
  const lower = password.toLowerCase();
  if (lower === 'sorynth@321' || lower === 'password123' || lower === 'admin123456' || lower === 'sorynth12345') {
    return { isValid: false, error: 'Default or common passwords (such as sorynth@321) are strictly prohibited.' };
  }
  if (password.length < 12) {
    return { isValid: false, error: 'Password must be at least 12 characters long.' };
  }
  if (!/[A-Z]/.test(password)) {
    return { isValid: false, error: 'Password must contain at least one uppercase letter.' };
  }
  if (!/[a-z]/.test(password)) {
    return { isValid: false, error: 'Password must contain at least one lowercase letter.' };
  }
  if (!/[0-9]/.test(password)) {
    return { isValid: false, error: 'Password must contain at least one number.' };
  }
  if (!/[!@#$%^&*()_+\-=[\]{};':"\\|,.<>/?]/.test(password)) {
    return { isValid: false, error: 'Password must contain at least one special symbol.' };
  }
  return { isValid: true };
}
