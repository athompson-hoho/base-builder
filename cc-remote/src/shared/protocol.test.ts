/**
 * Protocol Schema Tests
 */

import { describe, it, expect } from 'vitest';
import {
  AuthMessageSchema,
  HeartbeatMessageSchema,
  ConsoleMessageSchema,
  ExecuteMessageSchema,
  ResultMessageSchema,
  PingMessageSchema,
  PongMessageSchema,
  AckMessageSchema,
  ErrorMessageSchema,
  DisconnectMessageSchema,
  parseAgentMessage,
  parseServerMessage,
  safeParseMessage,
  isValidMessageType,
  MESSAGE_TYPES,
} from './protocol.js';

describe('Protocol Message Schemas', () => {
  describe('AuthMessageSchema', () => {
    it('should validate a valid auth message', () => {
      const msg = {
        type: 'auth',
        token: 'abc123def456',
        machine_id: 'turtle_1',
        machine_type: 'turtle',
      };
      expect(AuthMessageSchema.parse(msg)).toEqual(msg);
    });

    it('should validate auth message with optional fields', () => {
      const msg = {
        type: 'auth',
        token: 'abc123def456',
        machine_id: 'turtle_1',
        label: 'Excavator Alpha',
        machine_type: 'turtle',
        fuel_level: 2847,
        fuel_limit: 100000,
      };
      expect(AuthMessageSchema.parse(msg)).toEqual(msg);
    });

    it('should reject auth message with missing token', () => {
      const msg = {
        type: 'auth',
        machine_id: 'turtle_1',
        machine_type: 'turtle',
      };
      expect(() => AuthMessageSchema.parse(msg)).toThrow();
    });

    it('should reject auth message with invalid machine_type', () => {
      const msg = {
        type: 'auth',
        token: 'abc123',
        machine_id: 'turtle_1',
        machine_type: 'invalid',
      };
      expect(() => AuthMessageSchema.parse(msg)).toThrow();
    });
  });

  describe('HeartbeatMessageSchema', () => {
    it('should validate a valid heartbeat', () => {
      const msg = {
        type: 'heartbeat',
        timestamp: 1703062800,
      };
      expect(HeartbeatMessageSchema.parse(msg)).toEqual(msg);
    });

    it('should validate heartbeat with fuel_level', () => {
      const msg = {
        type: 'heartbeat',
        timestamp: 1703062800,
        fuel_level: 5000,
      };
      expect(HeartbeatMessageSchema.parse(msg)).toEqual(msg);
    });
  });

  describe('ConsoleMessageSchema', () => {
    it('should validate console message with lines', () => {
      const msg = {
        type: 'console',
        lines: [
          { text: 'Hello world', timestamp: 1703062800, level: 'info' },
          { text: 'Error occurred', timestamp: 1703062801, level: 'error' },
        ],
      };
      expect(ConsoleMessageSchema.parse(msg)).toEqual(msg);
    });

    it('should default level to info', () => {
      const msg = {
        type: 'console',
        lines: [{ text: 'Hello', timestamp: 1703062800 }],
      };
      const parsed = ConsoleMessageSchema.parse(msg);
      expect(parsed.lines[0].level).toBe('info');
    });
  });

  describe('ExecuteMessageSchema', () => {
    it('should validate execute message', () => {
      const msg = {
        type: 'execute',
        id: 'req_abc123',
        code: 'return 42',
      };
      expect(ExecuteMessageSchema.parse(msg)).toEqual(msg);
    });

    it('should validate execute message with timeout', () => {
      const msg = {
        type: 'execute',
        id: 'req_abc123',
        code: 'return turtle.forward()',
        timeout_ms: 30000,
      };
      expect(ExecuteMessageSchema.parse(msg)).toEqual(msg);
    });

    it('should reject empty code', () => {
      const msg = {
        type: 'execute',
        id: 'req_abc123',
        code: '',
      };
      expect(() => ExecuteMessageSchema.parse(msg)).toThrow();
    });
  });

  describe('ResultMessageSchema', () => {
    it('should validate successful result', () => {
      const msg = {
        type: 'result',
        id: 'req_abc123',
        success: true,
        return_value: 42,
        stdout: ['Moved forward'],
        duration_ms: 150,
      };
      expect(ResultMessageSchema.parse(msg)).toEqual(msg);
    });

    it('should validate failed result', () => {
      const msg = {
        type: 'result',
        id: 'req_abc123',
        success: false,
        error: 'attempt to index nil value',
        stdout: [],
      };
      expect(ResultMessageSchema.parse(msg)).toEqual(msg);
    });
  });

  describe('PingMessageSchema', () => {
    it('should validate ping message', () => {
      const msg = {
        type: 'ping',
        timestamp: 1703062800,
      };
      expect(PingMessageSchema.parse(msg)).toEqual(msg);
    });
  });

  describe('PongMessageSchema', () => {
    it('should validate pong message', () => {
      const msg = {
        type: 'pong',
        timestamp: 1703062801,
        original_timestamp: 1703062800,
      };
      expect(PongMessageSchema.parse(msg)).toEqual(msg);
    });
  });

  describe('AckMessageSchema', () => {
    it('should validate ack message', () => {
      const msg = {
        type: 'ack',
        message: 'Authentication successful',
      };
      expect(AckMessageSchema.parse(msg)).toEqual(msg);
    });

    it('should validate ack without message', () => {
      const msg = { type: 'ack' };
      expect(AckMessageSchema.parse(msg)).toEqual(msg);
    });
  });

  describe('ErrorMessageSchema', () => {
    it('should validate error message', () => {
      const msg = {
        type: 'error',
        code: 1001,
        message: 'Invalid token',
      };
      expect(ErrorMessageSchema.parse(msg)).toEqual(msg);
    });

    it('should validate error with details', () => {
      const msg = {
        type: 'error',
        code: 3001,
        message: 'Execution timeout',
        details: { machine_id: 'turtle_1', timeout_ms: 30000 },
      };
      expect(ErrorMessageSchema.parse(msg)).toEqual(msg);
    });
  });

  describe('DisconnectMessageSchema', () => {
    it('should validate disconnect message', () => {
      const msg = {
        type: 'disconnect',
        reason: 'User terminated',
      };
      expect(DisconnectMessageSchema.parse(msg)).toEqual(msg);
    });

    it('should validate disconnect without reason', () => {
      const msg = { type: 'disconnect' };
      expect(DisconnectMessageSchema.parse(msg)).toEqual(msg);
    });
  });
});

describe('Message Parsing Helpers', () => {
  describe('parseAgentMessage', () => {
    it('should parse valid agent messages', () => {
      const auth = { type: 'auth', token: 'abc', machine_id: '1', machine_type: 'turtle' };
      expect(parseAgentMessage(auth)).toEqual(auth);

      const heartbeat = { type: 'heartbeat', timestamp: 123 };
      expect(parseAgentMessage(heartbeat)).toEqual(heartbeat);
    });

    it('should throw on server-only messages', () => {
      const execute = { type: 'execute', id: '1', code: 'test' };
      expect(() => parseAgentMessage(execute)).toThrow();
    });
  });

  describe('parseServerMessage', () => {
    it('should parse valid server messages', () => {
      const ack = { type: 'ack' };
      expect(parseServerMessage(ack)).toEqual(ack);

      const execute = { type: 'execute', id: '1', code: 'return 1' };
      expect(parseServerMessage(execute)).toEqual(execute);
    });

    it('should throw on agent-only messages', () => {
      const auth = { type: 'auth', token: 'abc', machine_id: '1', machine_type: 'turtle' };
      expect(() => parseServerMessage(auth)).toThrow();
    });
  });

  describe('safeParseMessage', () => {
    it('should return message on valid input', () => {
      const msg = { type: 'ping', timestamp: 123 };
      expect(safeParseMessage(msg)).toEqual(msg);
    });

    it('should return null on invalid input', () => {
      expect(safeParseMessage({ type: 'invalid' })).toBeNull();
      expect(safeParseMessage(null)).toBeNull();
      expect(safeParseMessage('not an object')).toBeNull();
    });
  });

  describe('isValidMessageType', () => {
    it('should return true for valid types', () => {
      MESSAGE_TYPES.forEach((type) => {
        expect(isValidMessageType(type)).toBe(true);
      });
    });

    it('should return false for invalid types', () => {
      expect(isValidMessageType('invalid')).toBe(false);
      expect(isValidMessageType('')).toBe(false);
    });
  });
});
