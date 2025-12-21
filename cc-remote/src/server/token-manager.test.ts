/**
 * Token Manager Tests
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { TokenManager, generateToken } from './token-manager';

describe('TokenManager', () => {
  let manager: TokenManager;

  beforeEach(() => {
    manager = new TokenManager();
  });

  describe('generateToken', () => {
    it('should generate a 32-character hex string', () => {
      const token = manager.generateToken();
      expect(token).toHaveLength(32);
      expect(token).toMatch(/^[a-f0-9]{32}$/);
    });

    it('should generate unique tokens', () => {
      const tokens = new Set<string>();
      for (let i = 0; i < 100; i++) {
        tokens.add(manager.generateToken());
      }
      expect(tokens.size).toBe(100);
    });

    it('should automatically add generated token to valid set', () => {
      const token = manager.generateToken();
      expect(manager.validateToken(token)).toBe(true);
    });
  });

  describe('validateToken', () => {
    it('should return true for valid token', () => {
      const token = manager.generateToken();
      expect(manager.validateToken(token)).toBe(true);
    });

    it('should return false for unknown token', () => {
      expect(manager.validateToken('abcd1234abcd1234abcd1234abcd1234')).toBe(false);
    });

    it('should return false for removed token', () => {
      const token = manager.generateToken();
      manager.removeToken(token);
      expect(manager.validateToken(token)).toBe(false);
    });
  });

  describe('addToken', () => {
    it('should add a valid token', () => {
      const token = 'abcd1234abcd1234abcd1234abcd1234';
      manager.addToken(token);
      expect(manager.validateToken(token)).toBe(true);
    });

    it('should not add invalid format tokens', () => {
      manager.addToken('too-short');
      manager.addToken('not-hex-gggggggggggggggggggggggg');
      expect(manager.getTokenCount()).toBe(0);
    });
  });

  describe('removeToken', () => {
    it('should remove an existing token', () => {
      const token = manager.generateToken();
      expect(manager.removeToken(token)).toBe(true);
      expect(manager.validateToken(token)).toBe(false);
    });

    it('should return false for non-existent token', () => {
      expect(manager.removeToken('nonexistent')).toBe(false);
    });
  });

  describe('isValidTokenFormat', () => {
    it('should accept valid 32-char hex strings', () => {
      expect(manager.isValidTokenFormat('abcd1234abcd1234abcd1234abcd1234')).toBe(true);
      expect(manager.isValidTokenFormat('ABCD1234ABCD1234ABCD1234ABCD1234')).toBe(true);
      expect(manager.isValidTokenFormat('0000000000000000ffffffffffffffff')).toBe(true);
    });

    it('should reject invalid formats', () => {
      expect(manager.isValidTokenFormat('')).toBe(false);
      expect(manager.isValidTokenFormat('too-short')).toBe(false);
      expect(manager.isValidTokenFormat('abcd1234abcd1234abcd1234abcd123')).toBe(false); // 31 chars
      expect(manager.isValidTokenFormat('abcd1234abcd1234abcd1234abcd12345')).toBe(false); // 33 chars
      expect(manager.isValidTokenFormat('gggggggggggggggggggggggggggggggg')).toBe(false); // invalid hex
    });
  });

  describe('getAllTokens', () => {
    it('should return all tokens', () => {
      const t1 = manager.generateToken();
      const t2 = manager.generateToken();
      const t3 = manager.generateToken();

      const all = manager.getAllTokens();
      expect(all).toContain(t1);
      expect(all).toContain(t2);
      expect(all).toContain(t3);
      expect(all).toHaveLength(3);
    });
  });

  describe('getTokenCount', () => {
    it('should return correct count', () => {
      expect(manager.getTokenCount()).toBe(0);
      manager.generateToken();
      expect(manager.getTokenCount()).toBe(1);
      manager.generateToken();
      expect(manager.getTokenCount()).toBe(2);
    });
  });

  describe('clear', () => {
    it('should remove all tokens', () => {
      manager.generateToken();
      manager.generateToken();
      manager.generateToken();
      expect(manager.getTokenCount()).toBe(3);

      manager.clear();
      expect(manager.getTokenCount()).toBe(0);
    });
  });

  describe('file operations', () => {
    const testDir = path.join(process.cwd(), 'test-tokens');
    const testFile = path.join(testDir, 'tokens.txt');

    afterEach(() => {
      if (fs.existsSync(testDir)) {
        fs.rmSync(testDir, { recursive: true });
      }
    });

    it('should save and load tokens from file', () => {
      const t1 = manager.generateToken();
      const t2 = manager.generateToken();

      manager.saveToFile(testFile);

      const newManager = new TokenManager();
      const loaded = newManager.loadFromFile(testFile);

      expect(loaded).toBe(2);
      expect(newManager.validateToken(t1)).toBe(true);
      expect(newManager.validateToken(t2)).toBe(true);
    });

    it('should handle non-existent file', () => {
      const loaded = manager.loadFromFile('/nonexistent/path/tokens.txt');
      expect(loaded).toBe(0);
    });

    it('should skip comments and empty lines', () => {
      fs.mkdirSync(testDir, { recursive: true });
      fs.writeFileSync(testFile, [
        '# This is a comment',
        '',
        'abcd1234abcd1234abcd1234abcd1234',
        '# Another comment',
        '1234abcd1234abcd1234abcd1234abcd',
        '',
      ].join('\n'));

      const loaded = manager.loadFromFile(testFile);
      expect(loaded).toBe(2);
    });

    it('should skip invalid tokens in file', () => {
      fs.mkdirSync(testDir, { recursive: true });
      fs.writeFileSync(testFile, [
        'abcd1234abcd1234abcd1234abcd1234',
        'invalid',
        '1234abcd1234abcd1234abcd1234abcd',
      ].join('\n'));

      const loaded = manager.loadFromFile(testFile);
      expect(loaded).toBe(2);
    });
  });
});

describe('generateToken (standalone)', () => {
  it('should generate a 32-character hex string', () => {
    const token = generateToken();
    expect(token).toHaveLength(32);
    expect(token).toMatch(/^[a-f0-9]{32}$/);
  });
});
