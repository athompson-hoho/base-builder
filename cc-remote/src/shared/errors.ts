/**
 * CC-Remote Error Codes
 *
 * Numeric error codes organized by category for easy handling in Lua.
 * - 1xxx: Authentication errors
 * - 2xxx: Protocol errors
 * - 3xxx: Execution errors
 * - 5xxx: Server errors
 */

/**
 * Protocol error codes
 */
export enum ErrorCode {
  // Authentication errors (1xxx)
  /** Token provided is invalid or expired */
  INVALID_TOKEN = 1001,
  /** Authentication not received within timeout period */
  AUTH_TIMEOUT = 1002,
  /** Message received before authentication */
  AUTH_REQUIRED = 1003,

  // Protocol errors (2xxx)
  /** Message failed validation or is malformed */
  INVALID_MESSAGE = 2001,
  /** Message type is not recognized */
  UNKNOWN_MESSAGE_TYPE = 2002,
  /** Required field is missing from message */
  MISSING_FIELD = 2003,
  /** Message exceeds size limit (16KB) */
  MESSAGE_TOO_LARGE = 2004,

  // Execution errors (3xxx)
  /** Code execution exceeded timeout */
  EXECUTION_TIMEOUT = 3001,
  /** Code execution failed with error */
  EXECUTION_FAILED = 3002,
  /** Target machine is not connected */
  MACHINE_OFFLINE = 3003,
  /** Machine not found */
  MACHINE_NOT_FOUND = 3004,

  // Server errors (5xxx)
  /** Unexpected internal server error */
  INTERNAL_ERROR = 5001,
  /** Server is shutting down */
  SERVER_SHUTDOWN = 5002,
}

/**
 * Error code category
 */
export type ErrorCategory = 'auth' | 'protocol' | 'execution' | 'server';

/**
 * Get the category of an error code
 */
export function getErrorCategory(code: ErrorCode): ErrorCategory {
  const prefix = Math.floor(code / 1000);
  switch (prefix) {
    case 1:
      return 'auth';
    case 2:
      return 'protocol';
    case 3:
      return 'execution';
    case 5:
      return 'server';
    default:
      return 'server';
  }
}

/**
 * Human-readable error messages for each error code
 */
export const ERROR_MESSAGES: Record<ErrorCode, string> = {
  [ErrorCode.INVALID_TOKEN]: 'Invalid or expired authentication token',
  [ErrorCode.AUTH_TIMEOUT]: 'Authentication timeout - no auth message received',
  [ErrorCode.AUTH_REQUIRED]: 'Authentication required before sending messages',
  [ErrorCode.INVALID_MESSAGE]: 'Invalid message format',
  [ErrorCode.UNKNOWN_MESSAGE_TYPE]: 'Unknown message type',
  [ErrorCode.MISSING_FIELD]: 'Required field missing from message',
  [ErrorCode.MESSAGE_TOO_LARGE]: 'Message exceeds maximum size (16KB)',
  [ErrorCode.EXECUTION_TIMEOUT]: 'Code execution timed out',
  [ErrorCode.EXECUTION_FAILED]: 'Code execution failed',
  [ErrorCode.MACHINE_OFFLINE]: 'Target machine is offline',
  [ErrorCode.MACHINE_NOT_FOUND]: 'Machine not found',
  [ErrorCode.INTERNAL_ERROR]: 'Internal server error',
  [ErrorCode.SERVER_SHUTDOWN]: 'Server is shutting down',
};

/**
 * Get the human-readable message for an error code
 */
export function getErrorMessage(code: ErrorCode): string {
  return ERROR_MESSAGES[code] ?? `Unknown error (${code})`;
}

/**
 * Format an error with code and message
 */
export function formatError(
  code: ErrorCode,
  details?: string
): { code: ErrorCode; message: string } {
  const baseMessage = getErrorMessage(code);
  const message = details ? `${baseMessage}: ${details}` : baseMessage;
  return { code, message };
}

/**
 * Create a protocol error message object
 */
export function createErrorMessage(
  code: ErrorCode,
  details?: unknown
): {
  type: 'error';
  code: ErrorCode;
  message: string;
  details?: unknown;
} {
  return {
    type: 'error',
    code,
    message: getErrorMessage(code),
    ...(details !== undefined && { details }),
  };
}

/**
 * Check if an error is recoverable (can retry)
 */
export function isRecoverableError(code: ErrorCode): boolean {
  // Server errors and timeouts are potentially recoverable
  return (
    code === ErrorCode.EXECUTION_TIMEOUT ||
    code === ErrorCode.MACHINE_OFFLINE ||
    code === ErrorCode.INTERNAL_ERROR
  );
}

/**
 * Check if an error should terminate the connection
 */
export function isTerminalError(code: ErrorCode): boolean {
  return (
    code === ErrorCode.INVALID_TOKEN ||
    code === ErrorCode.AUTH_TIMEOUT ||
    code === ErrorCode.SERVER_SHUTDOWN
  );
}
