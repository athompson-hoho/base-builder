/**
 * Message Router
 *
 * Routes incoming WebSocket messages to appropriate handlers based on type.
 * Validates messages using Zod schemas and sends error responses for invalid messages.
 */

import type { WebSocket, RawData } from 'ws';
import {
  AgentMessageSchema,
  HeartbeatMessage,
  ConsoleMessage,
  ResultMessage,
  PongMessage,
  DisconnectMessage,
} from '../../shared/protocol.js';
import { ErrorCode, createErrorMessage } from '../../shared/errors.js';
import { StateManager } from '../state-manager.js';
import { log } from '../logger.js';
import type { ZodIssue } from 'zod';

/**
 * Handler callbacks for different message types
 */
export interface MessageHandlers {
  onHeartbeat?: (machineId: string, message: HeartbeatMessage) => void;
  onConsole?: (machineId: string, message: ConsoleMessage) => void;
  onResult?: (machineId: string, message: ResultMessage) => void;
  onPong?: (machineId: string, message: PongMessage) => void;
  onDisconnect?: (machineId: string, message: DisconnectMessage) => void;
}

/**
 * Routes WebSocket messages to handlers
 */
export class MessageRouter {
  constructor(
    private stateManager: StateManager,
    private handlers: MessageHandlers = {}
  ) {}

  /**
   * Process an incoming message from an authenticated machine
   */
  handleMessage(ws: WebSocket, machineId: string, data: RawData): void {
    let parsed: unknown;
    try {
      parsed = JSON.parse(data.toString());
    } catch {
      log('warn', 'Invalid JSON from machine', { machineId });
      this.sendError(ws, ErrorCode.INVALID_MESSAGE);
      return;
    }

    // Validate message structure
    const result = AgentMessageSchema.safeParse(parsed);
    if (!result.success) {
      log('warn', 'Invalid message structure', {
        machineId,
        errors: result.error.issues.map((i: ZodIssue) => i.message),
      });
      this.sendError(ws, ErrorCode.INVALID_MESSAGE, result.error.issues[0]?.message);
      return;
    }

    const message = result.data;

    // Route to handler based on type
    switch (message.type) {
      case 'heartbeat':
        this.handleHeartbeat(machineId, message);
        break;

      case 'console':
        this.handleConsole(machineId, message);
        break;

      case 'result':
        this.handleResult(machineId, message);
        break;

      case 'pong':
        this.handlePong(machineId, message);
        break;

      case 'disconnect':
        this.handleDisconnect(machineId, message);
        break;

      case 'error':
        // Log errors from agent but don't take action
        log('warn', 'Error from agent', { machineId, code: message.code, message: message.message });
        break;

      case 'auth':
        // Auth messages should be handled by AuthHandler, not routed here
        log('warn', 'Unexpected auth message from authenticated machine', { machineId });
        break;

      default:
        log('warn', 'Unhandled message type', { machineId, type: (message as { type: string }).type });
        this.sendError(ws, ErrorCode.UNKNOWN_MESSAGE_TYPE);
    }
  }

  /**
   * Set a message handler
   */
  setHandler<K extends keyof MessageHandlers>(type: K, handler: MessageHandlers[K]): void {
    this.handlers[type] = handler;
  }

  /**
   * Handle heartbeat message
   */
  private handleHeartbeat(machineId: string, message: HeartbeatMessage): void {
    // Update last seen
    this.stateManager.updateLastSeen(machineId);

    // Update fuel level if provided
    if (message.fuel_level !== undefined) {
      this.stateManager.updateFuelLevel(machineId, message.fuel_level);
    }

    log('debug', 'Heartbeat received', { machineId, fuel: message.fuel_level });

    // Call custom handler
    this.handlers.onHeartbeat?.(machineId, message);
  }

  /**
   * Handle console message
   */
  private handleConsole(machineId: string, message: ConsoleMessage): void {
    // Add lines to buffer
    this.stateManager.addConsoleLines(
      machineId,
      message.lines.map(line => ({
        text: line.text,
        timestamp: line.timestamp,
        level: line.level,
      }))
    );

    log('debug', 'Console output received', { machineId, lines: message.lines.length });

    // Call custom handler
    this.handlers.onConsole?.(machineId, message);
  }

  /**
   * Handle result message
   */
  private handleResult(machineId: string, message: ResultMessage): void {
    log('info', 'Execution result', {
      machineId,
      id: message.id,
      success: message.success,
      duration: message.duration_ms,
    });

    // Call custom handler
    this.handlers.onResult?.(machineId, message);
  }

  /**
   * Handle pong message
   */
  private handlePong(machineId: string, message: PongMessage): void {
    const latency = message.timestamp - message.original_timestamp;
    log('debug', 'Pong received', { machineId, latency });

    // Call custom handler
    this.handlers.onPong?.(machineId, message);
  }

  /**
   * Handle disconnect message
   */
  private handleDisconnect(machineId: string, message: DisconnectMessage): void {
    log('info', 'Clean disconnect', { machineId, reason: message.reason });

    // Mark machine as offline
    this.stateManager.setMachineOffline(machineId);

    // Call custom handler
    this.handlers.onDisconnect?.(machineId, message);
  }

  /**
   * Send error response
   */
  private sendError(ws: WebSocket, code: ErrorCode, details?: string): void {
    const errorMsg = createErrorMessage(code, details);
    try {
      ws.send(JSON.stringify(errorMsg));
    } catch {
      // Ignore send errors
    }
  }
}
