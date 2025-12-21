/**
 * Authentication Handler
 *
 * Handles the authentication flow for incoming WebSocket connections.
 * - Enforces 5-second auth timeout
 * - Validates tokens
 * - Registers authenticated machines in StateManager
 */

import type { WebSocket, RawData } from 'ws';
import { AuthMessageSchema, AckMessage, ErrorMessage } from '../../shared/protocol.js';
import { ErrorCode, createErrorMessage } from '../../shared/errors.js';
import { TokenManager } from '../token-manager.js';
import { StateManager } from '../state-manager.js';
import { log } from '../logger.js';

/**
 * Auth timeout in milliseconds
 */
const AUTH_TIMEOUT_MS = 5000;

/**
 * Result of authentication attempt
 */
export interface AuthResult {
  success: boolean;
  machineId?: string;
  error?: ErrorCode;
}

/**
 * Pending connection awaiting authentication
 */
interface PendingConnection {
  ws: WebSocket;
  timer: NodeJS.Timeout;
  clientIp: string;
}

/**
 * Handles authentication for WebSocket connections
 */
export class AuthHandler {
  private pending: Map<WebSocket, PendingConnection> = new Map();

  constructor(
    private tokenManager: TokenManager,
    private stateManager: StateManager
  ) {}

  /**
   * Start tracking a new connection for authentication
   */
  startAuthTimeout(ws: WebSocket, clientIp: string): void {
    const timer = setTimeout(() => {
      this.handleAuthTimeout(ws, clientIp);
    }, AUTH_TIMEOUT_MS);

    this.pending.set(ws, { ws, timer, clientIp });
  }

  /**
   * Handle incoming message on unauthenticated connection
   * Returns true if authentication succeeded
   */
  handleMessage(ws: WebSocket, data: RawData): AuthResult {
    const pending = this.pending.get(ws);
    if (!pending) {
      // Not a pending connection (shouldn't happen)
      return { success: false, error: ErrorCode.AUTH_REQUIRED };
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(data.toString());
    } catch {
      log('warn', `Invalid JSON from ${pending.clientIp}`);
      this.rejectConnection(ws, ErrorCode.INVALID_MESSAGE, pending.clientIp);
      return { success: false, error: ErrorCode.INVALID_MESSAGE };
    }

    // Validate auth message structure
    const result = AuthMessageSchema.safeParse(parsed);
    if (!result.success) {
      log('warn', `Invalid auth message from ${pending.clientIp}`, { errors: result.error.issues });
      this.rejectConnection(ws, ErrorCode.INVALID_MESSAGE, pending.clientIp);
      return { success: false, error: ErrorCode.INVALID_MESSAGE };
    }

    const authMessage = result.data;

    // Validate token
    if (!this.tokenManager.validateToken(authMessage.token)) {
      log('warn', `Invalid token from ${pending.clientIp}`);
      this.rejectConnection(ws, ErrorCode.INVALID_TOKEN, pending.clientIp);
      return { success: false, error: ErrorCode.INVALID_TOKEN };
    }

    // Clear pending state
    clearTimeout(pending.timer);
    this.pending.delete(ws);

    // Register machine
    const machineId = authMessage.machine_id;
    this.stateManager.registerMachine(machineId, authMessage.machine_type, ws, {
      label: authMessage.label,
      fuelLevel: authMessage.fuel_level,
      fuelLimit: authMessage.fuel_limit,
    });

    // Send acknowledgment
    const ack: AckMessage = {
      type: 'ack',
      message: 'Connected successfully',
    };
    ws.send(JSON.stringify(ack));

    log('info', `Machine connected: ${machineId}`, {
      type: authMessage.machine_type,
      label: authMessage.label,
      fuelLevel: authMessage.fuel_level,
      ip: pending.clientIp,
    });

    return { success: true, machineId };
  }

  /**
   * Check if a connection is pending authentication
   */
  isPending(ws: WebSocket): boolean {
    return this.pending.has(ws);
  }

  /**
   * Cancel pending authentication (e.g., on disconnect)
   */
  cancelPending(ws: WebSocket): void {
    const pending = this.pending.get(ws);
    if (pending) {
      clearTimeout(pending.timer);
      this.pending.delete(ws);
    }
  }

  /**
   * Get count of pending connections
   */
  getPendingCount(): number {
    return this.pending.size;
  }

  /**
   * Handle auth timeout
   */
  private handleAuthTimeout(ws: WebSocket, clientIp: string): void {
    log('warn', `Auth timeout from ${clientIp}`);
    this.rejectConnection(ws, ErrorCode.AUTH_TIMEOUT, clientIp);
  }

  /**
   * Reject a connection with an error
   */
  private rejectConnection(ws: WebSocket, code: ErrorCode, clientIp: string): void {
    // Send error message
    const errorMsg: ErrorMessage = createErrorMessage(code);
    try {
      ws.send(JSON.stringify(errorMsg));
    } catch {
      // Ignore send errors on rejected connection
    }

    // Close connection
    ws.close(1008, errorMsg.message); // 1008 = Policy Violation

    // Clean up
    this.cancelPending(ws);

    log('info', `Connection rejected: ${code}`, { ip: clientIp });
  }
}
