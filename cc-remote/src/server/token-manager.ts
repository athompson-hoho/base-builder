/**
 * Token Manager
 *
 * Generates and validates authentication tokens for agent connections.
 * Tokens are 32-character hex strings generated from 16 random bytes.
 */

import crypto from 'crypto';
import fs from 'fs';
import path from 'path';

/**
 * Token length in bytes (produces 32-char hex string)
 */
const TOKEN_BYTES = 16;

/**
 * Manages authentication tokens for agent connections
 */
export class TokenManager {
  private tokens: Set<string> = new Set();

  /**
   * Generate a new random token
   */
  generateToken(): string {
    const token = crypto.randomBytes(TOKEN_BYTES).toString('hex');
    this.tokens.add(token);
    return token;
  }

  /**
   * Validate a token
   */
  validateToken(token: string): boolean {
    return this.tokens.has(token);
  }

  /**
   * Add an existing token (e.g., loaded from file)
   */
  addToken(token: string): void {
    if (this.isValidTokenFormat(token)) {
      this.tokens.add(token);
    }
  }

  /**
   * Remove a token
   */
  removeToken(token: string): boolean {
    return this.tokens.delete(token);
  }

  /**
   * Get all tokens (for saving to file)
   */
  getAllTokens(): string[] {
    return Array.from(this.tokens);
  }

  /**
   * Get the number of registered tokens
   */
  getTokenCount(): number {
    return this.tokens.size;
  }

  /**
   * Check if a string is a valid token format (32 hex chars)
   */
  isValidTokenFormat(token: string): boolean {
    return /^[a-f0-9]{32}$/i.test(token);
  }

  /**
   * Load tokens from a file (one token per line)
   */
  loadFromFile(filepath: string): number {
    if (!fs.existsSync(filepath)) {
      return 0;
    }

    const content = fs.readFileSync(filepath, 'utf-8');
    const lines = content.split('\n').map(line => line.trim()).filter(Boolean);

    let loaded = 0;
    for (const line of lines) {
      // Skip comments
      if (line.startsWith('#')) {
        continue;
      }
      if (this.isValidTokenFormat(line)) {
        this.tokens.add(line);
        loaded++;
      }
    }

    return loaded;
  }

  /**
   * Save tokens to a file (one token per line)
   */
  saveToFile(filepath: string): void {
    const dir = path.dirname(filepath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    const content = [
      '# CC-Remote Authentication Tokens',
      '# One token per line. Lines starting with # are comments.',
      '',
      ...this.getAllTokens(),
      '',
    ].join('\n');

    fs.writeFileSync(filepath, content, 'utf-8');
  }

  /**
   * Clear all tokens
   */
  clear(): void {
    this.tokens.clear();
  }
}

/**
 * Generate a standalone token (utility function)
 */
export function generateToken(): string {
  return crypto.randomBytes(TOKEN_BYTES).toString('hex');
}
