/**
 * CC-Remote Machine State Types
 *
 * Interfaces for tracking connected CC:Tweaked machines.
 */

import type { WebSocket } from 'ws';

/**
 * Type of CC:Tweaked machine
 */
export type MachineType = 'turtle' | 'computer' | 'pocket';

/**
 * Online/offline status of a machine
 */
export type MachineStatus = 'online' | 'offline';

/**
 * Console output line
 */
export interface ConsoleLine {
  text: string;
  timestamp: number;
  level: 'info' | 'error' | 'warn';
}

/**
 * State of a connected CC:Tweaked machine
 */
export interface MachineState {
  /** Unique identifier: {type}_{computerID} (e.g., "turtle_1") */
  id: string;

  /** Optional user-defined label */
  label?: string;

  /** Machine type */
  type: MachineType;

  /** Current fuel level (turtles only) */
  fuelLevel?: number;

  /** Maximum fuel capacity (turtles only) */
  fuelLimit?: number;

  /** Online/offline status */
  status: MachineStatus;

  /** Last heartbeat timestamp */
  lastSeen: Date;

  /** Console output ring buffer */
  consoleBuffer: ConsoleLine[];

  /** Active WebSocket connection (null if offline) */
  ws: WebSocket | null;
}

/**
 * Machine state for API responses (without WebSocket reference)
 */
export interface MachineStateDTO {
  id: string;
  label?: string;
  type: MachineType;
  fuelLevel?: number;
  fuelLimit?: number;
  status: MachineStatus;
  lastSeen: string; // ISO 8601 string
  lowFuel?: boolean;
}

/**
 * Convert MachineState to DTO for API responses
 */
export function toMachineStateDTO(state: MachineState): MachineStateDTO {
  const dto: MachineStateDTO = {
    id: state.id,
    type: state.type,
    status: state.status,
    lastSeen: state.lastSeen.toISOString(),
  };

  if (state.label !== undefined) {
    dto.label = state.label;
  }

  if (state.fuelLevel !== undefined) {
    dto.fuelLevel = state.fuelLevel;
    dto.fuelLimit = state.fuelLimit;
    // Flag low fuel if below 100
    dto.lowFuel = state.fuelLevel < 100;
  }

  return dto;
}

/**
 * Default console buffer size
 */
export const DEFAULT_BUFFER_SIZE = 100;

/**
 * Create an initial machine state from auth data
 */
export function createMachineState(
  id: string,
  type: MachineType,
  ws: WebSocket,
  options?: {
    label?: string;
    fuelLevel?: number;
    fuelLimit?: number;
  }
): MachineState {
  return {
    id,
    type,
    label: options?.label,
    fuelLevel: options?.fuelLevel,
    fuelLimit: options?.fuelLimit,
    status: 'online',
    lastSeen: new Date(),
    consoleBuffer: [],
    ws,
  };
}

/**
 * Parse machine ID into components
 */
export function parseMachineId(id: string): {
  type: MachineType;
  computerId: number;
} | null {
  const match = id.match(/^(turtle|computer|pocket)_(\d+)$/);
  if (!match) {
    return null;
  }
  return {
    type: match[1] as MachineType,
    computerId: parseInt(match[2], 10),
  };
}

/**
 * Create a machine ID from type and computer ID
 */
export function createMachineId(type: MachineType, computerId: number): string {
  return `${type}_${computerId}`;
}
