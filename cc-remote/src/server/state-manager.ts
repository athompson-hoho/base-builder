/**
 * State Manager
 *
 * Manages the state of all connected CC:Tweaked machines.
 * Provides methods for registering, querying, and updating machine state.
 */

import type { WebSocket } from 'ws';
import {
  MachineState,
  MachineStateDTO,
  MachineType,
  MachineStatus,
  ConsoleLine,
  createMachineState,
  toMachineStateDTO,
  DEFAULT_BUFFER_SIZE,
} from '../shared/machine-state.js';

/**
 * Event types for state changes
 */
export type StateEventType = 'machine_online' | 'machine_offline' | 'machine_updated';

/**
 * State change event
 */
export interface StateEvent {
  type: StateEventType;
  machineId: string;
  timestamp: Date;
  previousStatus?: MachineStatus;
  newStatus?: MachineStatus;
  durationMs?: number;
}

/**
 * Event listener callback
 */
export type StateEventListener = (event: StateEvent) => void;

/**
 * Manages connected machine state
 */
export class StateManager {
  private machines: Map<string, MachineState> = new Map();
  private events: StateEvent[] = [];
  private listeners: StateEventListener[] = [];
  private maxEvents: number = 1000;
  private maxConsoleLines: number = DEFAULT_BUFFER_SIZE;

  /**
   * Register a new machine or update existing connection
   */
  registerMachine(
    id: string,
    type: MachineType,
    ws: WebSocket,
    options?: {
      label?: string;
      fuelLevel?: number;
      fuelLimit?: number;
    }
  ): MachineState {
    const existing = this.machines.get(id);

    if (existing) {
      // Reconnecting - preserve console buffer
      const state: MachineState = {
        ...existing,
        type,
        label: options?.label ?? existing.label,
        fuelLevel: options?.fuelLevel ?? existing.fuelLevel,
        fuelLimit: options?.fuelLimit ?? existing.fuelLimit,
        status: 'online',
        lastSeen: new Date(),
        ws,
      };
      this.machines.set(id, state);

      // Fire online event if was offline
      if (existing.status === 'offline') {
        this.emitEvent({
          type: 'machine_online',
          machineId: id,
          timestamp: new Date(),
          previousStatus: 'offline',
          newStatus: 'online',
        });
      }

      return state;
    }

    // New machine
    const state = createMachineState(id, type, ws, options);
    this.machines.set(id, state);

    this.emitEvent({
      type: 'machine_online',
      machineId: id,
      timestamp: new Date(),
      newStatus: 'online',
    });

    return state;
  }

  /**
   * Get a machine by ID
   */
  getMachine(id: string): MachineState | undefined {
    return this.machines.get(id);
  }

  /**
   * Remove a machine completely
   */
  removeMachine(id: string): boolean {
    const machine = this.machines.get(id);
    if (!machine) {
      return false;
    }

    this.machines.delete(id);

    this.emitEvent({
      type: 'machine_offline',
      machineId: id,
      timestamp: new Date(),
      previousStatus: machine.status,
    });

    return true;
  }

  /**
   * Mark a machine as offline (preserves state)
   */
  setMachineOffline(id: string): boolean {
    const machine = this.machines.get(id);
    if (!machine) {
      return false;
    }

    const previousStatus = machine.status;
    const wasOnlineSince = machine.lastSeen;

    machine.status = 'offline';
    machine.ws = null;

    if (previousStatus === 'online') {
      const durationMs = new Date().getTime() - wasOnlineSince.getTime();
      this.emitEvent({
        type: 'machine_offline',
        machineId: id,
        timestamp: new Date(),
        previousStatus: 'online',
        newStatus: 'offline',
        durationMs,
      });
    }

    return true;
  }

  /**
   * Update machine's last seen timestamp
   */
  updateLastSeen(id: string): boolean {
    const machine = this.machines.get(id);
    if (!machine) {
      return false;
    }
    machine.lastSeen = new Date();
    return true;
  }

  /**
   * Update machine fuel level
   */
  updateFuelLevel(id: string, fuelLevel: number): boolean {
    const machine = this.machines.get(id);
    if (!machine) {
      return false;
    }
    machine.fuelLevel = fuelLevel;
    return true;
  }

  /**
   * Add console lines to a machine's buffer
   */
  addConsoleLines(id: string, lines: ConsoleLine[]): boolean {
    const machine = this.machines.get(id);
    if (!machine) {
      return false;
    }

    // Add lines and trim to max buffer size
    machine.consoleBuffer.push(...lines);
    if (machine.consoleBuffer.length > this.maxConsoleLines) {
      machine.consoleBuffer = machine.consoleBuffer.slice(-this.maxConsoleLines);
    }

    return true;
  }

  /**
   * Get console lines for a machine
   */
  getConsoleLines(id: string, limit?: number): ConsoleLine[] {
    const machine = this.machines.get(id);
    if (!machine) {
      return [];
    }

    const lines = machine.consoleBuffer;
    if (limit && limit < lines.length) {
      return lines.slice(-limit);
    }
    return [...lines];
  }

  /**
   * Get all machines
   */
  getAllMachines(): MachineState[] {
    return Array.from(this.machines.values());
  }

  /**
   * Get machines by status
   */
  getMachinesByStatus(status: MachineStatus): MachineState[] {
    return this.getAllMachines().filter(m => m.status === status);
  }

  /**
   * Get all machines as DTOs (for API responses)
   */
  toDTO(): MachineStateDTO[] {
    return this.getAllMachines().map(toMachineStateDTO);
  }

  /**
   * Get machine as DTO
   */
  getMachineDTO(id: string): MachineStateDTO | undefined {
    const machine = this.getMachine(id);
    return machine ? toMachineStateDTO(machine) : undefined;
  }

  /**
   * Get machine count
   */
  getMachineCount(): number {
    return this.machines.size;
  }

  /**
   * Get online machine count
   */
  getOnlineCount(): number {
    return this.getMachinesByStatus('online').length;
  }

  /**
   * Check if a machine exists
   */
  hasMachine(id: string): boolean {
    return this.machines.has(id);
  }

  /**
   * Add event listener
   */
  addEventListener(listener: StateEventListener): void {
    this.listeners.push(listener);
  }

  /**
   * Remove event listener
   */
  removeEventListener(listener: StateEventListener): boolean {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
      return true;
    }
    return false;
  }

  /**
   * Get recent events
   */
  getEvents(since?: Date): StateEvent[] {
    if (!since) {
      return [...this.events];
    }
    return this.events.filter(e => e.timestamp > since);
  }

  /**
   * Clear all state (for testing)
   */
  clear(): void {
    this.machines.clear();
    this.events = [];
  }

  /**
   * Emit a state event
   */
  private emitEvent(event: StateEvent): void {
    this.events.push(event);

    // Trim old events
    if (this.events.length > this.maxEvents) {
      this.events = this.events.slice(-this.maxEvents);
    }

    // Notify listeners
    for (const listener of this.listeners) {
      try {
        listener(event);
      } catch (error) {
        console.error('[StateManager] Event listener error:', error);
      }
    }
  }
}

/**
 * Singleton instance for the application
 */
let instance: StateManager | null = null;

/**
 * Get the singleton StateManager instance
 */
export function getStateManager(): StateManager {
  if (!instance) {
    instance = new StateManager();
  }
  return instance;
}

/**
 * Reset the singleton (for testing)
 */
export function resetStateManager(): void {
  if (instance) {
    instance.clear();
  }
  instance = null;
}
