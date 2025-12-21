/**
 * CC-Remote Protocol Types
 *
 * All WebSocket message schemas using Zod for validation.
 * Wire format uses snake_case for Lua compatibility.
 */

import { z } from 'zod';

// =============================================================================
// Message Type Constants
// =============================================================================

export const MESSAGE_TYPES = [
  'auth',
  'ack',
  'heartbeat',
  'console',
  'execute',
  'result',
  'ping',
  'pong',
  'error',
  'disconnect',
] as const;

export type MessageType = (typeof MESSAGE_TYPES)[number];

// =============================================================================
// Machine Type
// =============================================================================

export const MachineTypeSchema = z.enum(['turtle', 'computer', 'pocket']);
export type MachineType = z.infer<typeof MachineTypeSchema>;

// =============================================================================
// Agent → Server Messages
// =============================================================================

/**
 * Authentication message - first message from agent after connection
 */
export const AuthMessageSchema = z.object({
  type: z.literal('auth'),
  token: z.string().min(1),
  machine_id: z.string().min(1),
  label: z.string().optional(),
  machine_type: MachineTypeSchema,
  fuel_level: z.number().optional(),
  fuel_limit: z.number().optional(),
});
export type AuthMessage = z.infer<typeof AuthMessageSchema>;

/**
 * Heartbeat message - periodic liveness indicator
 */
export const HeartbeatMessageSchema = z.object({
  type: z.literal('heartbeat'),
  timestamp: z.number(),
  fuel_level: z.number().optional(),
});
export type HeartbeatMessage = z.infer<typeof HeartbeatMessageSchema>;

/**
 * Console message - batched console output from agent
 */
export const ConsoleMessageSchema = z.object({
  type: z.literal('console'),
  lines: z.array(
    z.object({
      text: z.string(),
      timestamp: z.number(),
      level: z.enum(['info', 'error', 'warn']).default('info'),
    })
  ),
});
export type ConsoleMessage = z.infer<typeof ConsoleMessageSchema>;

/**
 * Result message - execution result from agent
 */
export const ResultMessageSchema = z.object({
  type: z.literal('result'),
  id: z.string(),
  success: z.boolean(),
  return_value: z.unknown().optional(),
  stdout: z.array(z.string()).optional(),
  error: z.string().optional(),
  duration_ms: z.number().optional(),
});
export type ResultMessage = z.infer<typeof ResultMessageSchema>;

/**
 * Pong message - response to server ping
 */
export const PongMessageSchema = z.object({
  type: z.literal('pong'),
  timestamp: z.number(),
  original_timestamp: z.number(),
});
export type PongMessage = z.infer<typeof PongMessageSchema>;

// =============================================================================
// Server → Agent Messages
// =============================================================================

/**
 * Acknowledgment message - confirms successful authentication
 */
export const AckMessageSchema = z.object({
  type: z.literal('ack'),
  message: z.string().optional(),
});
export type AckMessage = z.infer<typeof AckMessageSchema>;

/**
 * Execute message - remote code execution request
 */
export const ExecuteMessageSchema = z.object({
  type: z.literal('execute'),
  id: z.string(),
  code: z.string().min(1),
  timeout_ms: z.number().optional(),
});
export type ExecuteMessage = z.infer<typeof ExecuteMessageSchema>;

/**
 * Ping message - latency check from server
 */
export const PingMessageSchema = z.object({
  type: z.literal('ping'),
  timestamp: z.number(),
});
export type PingMessage = z.infer<typeof PingMessageSchema>;

// =============================================================================
// Bidirectional Messages
// =============================================================================

/**
 * Error message - protocol or execution error
 */
export const ErrorMessageSchema = z.object({
  type: z.literal('error'),
  code: z.number(),
  message: z.string(),
  details: z.unknown().optional(),
});
export type ErrorMessage = z.infer<typeof ErrorMessageSchema>;

/**
 * Disconnect message - clean disconnect notification
 */
export const DisconnectMessageSchema = z.object({
  type: z.literal('disconnect'),
  reason: z.string().optional(),
});
export type DisconnectMessage = z.infer<typeof DisconnectMessageSchema>;

// =============================================================================
// Union Types for Parsing
// =============================================================================

/**
 * All messages that can be sent from Agent to Server
 */
export const AgentMessageSchema = z.discriminatedUnion('type', [
  AuthMessageSchema,
  HeartbeatMessageSchema,
  ConsoleMessageSchema,
  ResultMessageSchema,
  PongMessageSchema,
  ErrorMessageSchema,
  DisconnectMessageSchema,
]);
export type AgentMessage = z.infer<typeof AgentMessageSchema>;

/**
 * All messages that can be sent from Server to Agent
 */
export const ServerMessageSchema = z.discriminatedUnion('type', [
  AckMessageSchema,
  ExecuteMessageSchema,
  PingMessageSchema,
  ErrorMessageSchema,
  DisconnectMessageSchema,
]);
export type ServerMessage = z.infer<typeof ServerMessageSchema>;

/**
 * Any valid protocol message
 */
export const ProtocolMessageSchema = z.discriminatedUnion('type', [
  AuthMessageSchema,
  AckMessageSchema,
  HeartbeatMessageSchema,
  ConsoleMessageSchema,
  ExecuteMessageSchema,
  ResultMessageSchema,
  PingMessageSchema,
  PongMessageSchema,
  ErrorMessageSchema,
  DisconnectMessageSchema,
]);
export type ProtocolMessage = z.infer<typeof ProtocolMessageSchema>;

// =============================================================================
// Validation Helpers
// =============================================================================

/**
 * Parse and validate an incoming message from an agent
 */
export function parseAgentMessage(data: unknown): AgentMessage {
  return AgentMessageSchema.parse(data);
}

/**
 * Parse and validate an incoming message from the server
 */
export function parseServerMessage(data: unknown): ServerMessage {
  return ServerMessageSchema.parse(data);
}

/**
 * Safely parse a message, returning null if invalid
 */
export function safeParseMessage(
  data: unknown
): ProtocolMessage | null {
  const result = ProtocolMessageSchema.safeParse(data);
  return result.success ? result.data : null;
}

/**
 * Check if a string is a valid message type
 */
export function isValidMessageType(type: string): type is MessageType {
  return MESSAGE_TYPES.includes(type as MessageType);
}
