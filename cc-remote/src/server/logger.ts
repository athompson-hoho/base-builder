/**
 * Structured Logger
 *
 * Provides structured logging with ISO 8601 timestamps and JSON formatting.
 */

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

interface LogContext {
  [key: string]: unknown;
}

/**
 * Verbose mode flag
 */
let verbose = false;

/**
 * Set verbose mode
 */
export function setVerbose(enabled: boolean): void {
  verbose = enabled;
}

/**
 * Check if verbose mode is enabled
 */
export function isVerbose(): boolean {
  return verbose;
}

/**
 * Format a log message with timestamp and optional context
 */
export function formatLog(level: LogLevel, message: string, context?: LogContext): string {
  const timestamp = new Date().toISOString();
  const levelStr = level.toUpperCase().padEnd(5);

  if (context && Object.keys(context).length > 0) {
    return `[${timestamp}] [${levelStr}] ${message} ${JSON.stringify(context)}`;
  }

  return `[${timestamp}] [${levelStr}] ${message}`;
}

/**
 * Log a message at the specified level
 */
export function log(level: LogLevel, message: string, context?: LogContext): void {
  // Skip debug messages unless verbose mode is enabled
  if (level === 'debug' && !verbose) {
    return;
  }

  const formatted = formatLog(level, message, context);

  switch (level) {
    case 'error':
      console.error(formatted);
      break;
    case 'warn':
      console.warn(formatted);
      break;
    default:
      console.log(formatted);
  }
}

/**
 * Log at debug level (only shown in verbose mode)
 */
export function debug(message: string, context?: LogContext): void {
  log('debug', message, context);
}

/**
 * Log at info level
 */
export function info(message: string, context?: LogContext): void {
  log('info', message, context);
}

/**
 * Log at warn level
 */
export function warn(message: string, context?: LogContext): void {
  log('warn', message, context);
}

/**
 * Log at error level
 */
export function error(message: string, context?: LogContext): void {
  log('error', message, context);
}
