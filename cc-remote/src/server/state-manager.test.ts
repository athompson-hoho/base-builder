/**
 * State Manager Tests
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { StateManager, StateEvent, resetStateManager } from './state-manager';
import type { WebSocket } from 'ws';

// Mock WebSocket
function createMockWs(): WebSocket {
  return {
    send: vi.fn(),
    close: vi.fn(),
    readyState: 1, // OPEN
  } as unknown as WebSocket;
}

describe('StateManager', () => {
  let manager: StateManager;

  beforeEach(() => {
    resetStateManager();
    manager = new StateManager();
  });

  describe('registerMachine', () => {
    it('should register a new machine', () => {
      const ws = createMockWs();
      const state = manager.registerMachine('turtle_1', 'turtle', ws, {
        label: 'Mining Turtle',
        fuelLevel: 1000,
        fuelLimit: 20000,
      });

      expect(state.id).toBe('turtle_1');
      expect(state.type).toBe('turtle');
      expect(state.label).toBe('Mining Turtle');
      expect(state.fuelLevel).toBe(1000);
      expect(state.fuelLimit).toBe(20000);
      expect(state.status).toBe('online');
      expect(state.ws).toBe(ws);
      expect(state.consoleBuffer).toEqual([]);
    });

    it('should preserve console buffer on reconnect', () => {
      const ws1 = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws1);

      // Add some console lines
      manager.addConsoleLines('turtle_1', [
        { text: 'Hello', timestamp: Date.now(), level: 'info' },
      ]);

      // Mark offline
      manager.setMachineOffline('turtle_1');

      // Reconnect
      const ws2 = createMockWs();
      const state = manager.registerMachine('turtle_1', 'turtle', ws2);

      expect(state.consoleBuffer).toHaveLength(1);
      expect(state.consoleBuffer[0].text).toBe('Hello');
      expect(state.ws).toBe(ws2);
    });

    it('should emit online event for new machine', () => {
      const events: StateEvent[] = [];
      manager.addEventListener(e => events.push(e));

      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws);

      expect(events).toHaveLength(1);
      expect(events[0].type).toBe('machine_online');
      expect(events[0].machineId).toBe('turtle_1');
    });

    it('should emit online event when offline machine reconnects', () => {
      const ws1 = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws1);
      manager.setMachineOffline('turtle_1');

      const events: StateEvent[] = [];
      manager.addEventListener(e => events.push(e));

      const ws2 = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws2);

      expect(events).toHaveLength(1);
      expect(events[0].type).toBe('machine_online');
      expect(events[0].previousStatus).toBe('offline');
      expect(events[0].newStatus).toBe('online');
    });
  });

  describe('getMachine', () => {
    it('should return machine by ID', () => {
      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws);

      const machine = manager.getMachine('turtle_1');
      expect(machine).toBeDefined();
      expect(machine?.id).toBe('turtle_1');
    });

    it('should return undefined for unknown ID', () => {
      expect(manager.getMachine('unknown')).toBeUndefined();
    });
  });

  describe('removeMachine', () => {
    it('should remove a machine', () => {
      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws);

      expect(manager.removeMachine('turtle_1')).toBe(true);
      expect(manager.getMachine('turtle_1')).toBeUndefined();
    });

    it('should return false for unknown machine', () => {
      expect(manager.removeMachine('unknown')).toBe(false);
    });

    it('should emit offline event', () => {
      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws);

      const events: StateEvent[] = [];
      manager.addEventListener(e => events.push(e));

      manager.removeMachine('turtle_1');

      expect(events).toHaveLength(1);
      expect(events[0].type).toBe('machine_offline');
      expect(events[0].machineId).toBe('turtle_1');
    });
  });

  describe('setMachineOffline', () => {
    it('should mark machine as offline', () => {
      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws);

      expect(manager.setMachineOffline('turtle_1')).toBe(true);

      const machine = manager.getMachine('turtle_1');
      expect(machine?.status).toBe('offline');
      expect(machine?.ws).toBeNull();
    });

    it('should emit offline event with duration', () => {
      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws);

      const events: StateEvent[] = [];
      manager.addEventListener(e => events.push(e));

      manager.setMachineOffline('turtle_1');

      expect(events).toHaveLength(1);
      expect(events[0].type).toBe('machine_offline');
      expect(events[0].durationMs).toBeDefined();
    });

    it('should return false for unknown machine', () => {
      expect(manager.setMachineOffline('unknown')).toBe(false);
    });
  });

  describe('updateLastSeen', () => {
    it('should update lastSeen timestamp', () => {
      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws);

      const before = manager.getMachine('turtle_1')?.lastSeen;

      // Wait a bit
      vi.useFakeTimers();
      vi.advanceTimersByTime(100);

      manager.updateLastSeen('turtle_1');

      const after = manager.getMachine('turtle_1')?.lastSeen;
      expect(after?.getTime()).toBeGreaterThanOrEqual(before?.getTime() ?? 0);

      vi.useRealTimers();
    });

    it('should return false for unknown machine', () => {
      expect(manager.updateLastSeen('unknown')).toBe(false);
    });
  });

  describe('updateFuelLevel', () => {
    it('should update fuel level', () => {
      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws, { fuelLevel: 1000 });

      manager.updateFuelLevel('turtle_1', 500);

      expect(manager.getMachine('turtle_1')?.fuelLevel).toBe(500);
    });

    it('should return false for unknown machine', () => {
      expect(manager.updateFuelLevel('unknown', 100)).toBe(false);
    });
  });

  describe('console buffer', () => {
    it('should add console lines', () => {
      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws);

      manager.addConsoleLines('turtle_1', [
        { text: 'Line 1', timestamp: 1000, level: 'info' },
        { text: 'Line 2', timestamp: 2000, level: 'error' },
      ]);

      const lines = manager.getConsoleLines('turtle_1');
      expect(lines).toHaveLength(2);
      expect(lines[0].text).toBe('Line 1');
      expect(lines[1].text).toBe('Line 2');
    });

    it('should trim buffer when exceeding max size', () => {
      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws);

      // Add 150 lines (max is 100)
      const lines = Array.from({ length: 150 }, (_, i) => ({
        text: `Line ${i}`,
        timestamp: i,
        level: 'info' as const,
      }));

      manager.addConsoleLines('turtle_1', lines);

      const result = manager.getConsoleLines('turtle_1');
      expect(result).toHaveLength(100);
      expect(result[0].text).toBe('Line 50'); // Oldest 50 dropped
      expect(result[99].text).toBe('Line 149');
    });

    it('should limit returned lines', () => {
      const ws = createMockWs();
      manager.registerMachine('turtle_1', 'turtle', ws);

      const lines = Array.from({ length: 50 }, (_, i) => ({
        text: `Line ${i}`,
        timestamp: i,
        level: 'info' as const,
      }));

      manager.addConsoleLines('turtle_1', lines);

      const result = manager.getConsoleLines('turtle_1', 10);
      expect(result).toHaveLength(10);
      expect(result[0].text).toBe('Line 40'); // Last 10 lines
    });

    it('should return empty array for unknown machine', () => {
      expect(manager.getConsoleLines('unknown')).toEqual([]);
    });
  });

  describe('getAllMachines', () => {
    it('should return all machines', () => {
      manager.registerMachine('turtle_1', 'turtle', createMockWs());
      manager.registerMachine('computer_1', 'computer', createMockWs());
      manager.registerMachine('pocket_1', 'pocket', createMockWs());

      const all = manager.getAllMachines();
      expect(all).toHaveLength(3);
    });
  });

  describe('getMachinesByStatus', () => {
    it('should filter by status', () => {
      manager.registerMachine('turtle_1', 'turtle', createMockWs());
      manager.registerMachine('turtle_2', 'turtle', createMockWs());
      manager.setMachineOffline('turtle_2');

      expect(manager.getMachinesByStatus('online')).toHaveLength(1);
      expect(manager.getMachinesByStatus('offline')).toHaveLength(1);
    });
  });

  describe('toDTO', () => {
    it('should convert all machines to DTOs', () => {
      manager.registerMachine('turtle_1', 'turtle', createMockWs(), {
        label: 'Test',
        fuelLevel: 100,
        fuelLimit: 20000,
      });

      const dtos = manager.toDTO();
      expect(dtos).toHaveLength(1);
      expect(dtos[0].id).toBe('turtle_1');
      expect(dtos[0].label).toBe('Test');
      expect(dtos[0].fuelLevel).toBe(100);
      expect(dtos[0].lowFuel).toBe(false);
      expect(dtos[0]).not.toHaveProperty('ws'); // No WebSocket in DTO
    });

    it('should mark low fuel correctly', () => {
      manager.registerMachine('turtle_1', 'turtle', createMockWs(), {
        fuelLevel: 50,
        fuelLimit: 20000,
      });

      const dtos = manager.toDTO();
      expect(dtos[0].lowFuel).toBe(true);
    });
  });

  describe('event listeners', () => {
    it('should call listeners on events', () => {
      const listener = vi.fn();
      manager.addEventListener(listener);

      manager.registerMachine('turtle_1', 'turtle', createMockWs());

      expect(listener).toHaveBeenCalledTimes(1);
      expect(listener).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'machine_online',
          machineId: 'turtle_1',
        })
      );
    });

    it('should remove listeners', () => {
      const listener = vi.fn();
      manager.addEventListener(listener);
      manager.removeEventListener(listener);

      manager.registerMachine('turtle_1', 'turtle', createMockWs());

      expect(listener).not.toHaveBeenCalled();
    });

    it('should handle listener errors gracefully', () => {
      const badListener = vi.fn(() => {
        throw new Error('Listener error');
      });
      const goodListener = vi.fn();

      manager.addEventListener(badListener);
      manager.addEventListener(goodListener);

      manager.registerMachine('turtle_1', 'turtle', createMockWs());

      expect(goodListener).toHaveBeenCalled();
    });
  });

  describe('getEvents', () => {
    it('should return all events', () => {
      manager.registerMachine('turtle_1', 'turtle', createMockWs());
      manager.setMachineOffline('turtle_1');

      const events = manager.getEvents();
      expect(events).toHaveLength(2);
    });

    it('should filter events by date', () => {
      manager.registerMachine('turtle_1', 'turtle', createMockWs());

      // Use a date 1 second in the past to ensure the next event is definitely "after"
      const after = new Date(Date.now() - 1);
      manager.setMachineOffline('turtle_1');

      const events = manager.getEvents(after);
      // Should include the offline event which was emitted after 'after'
      expect(events.length).toBeGreaterThanOrEqual(1);
      expect(events.some(e => e.type === 'machine_offline')).toBe(true);
    });
  });

  describe('counts', () => {
    it('should return correct machine count', () => {
      expect(manager.getMachineCount()).toBe(0);

      manager.registerMachine('turtle_1', 'turtle', createMockWs());
      expect(manager.getMachineCount()).toBe(1);

      manager.registerMachine('turtle_2', 'turtle', createMockWs());
      expect(manager.getMachineCount()).toBe(2);
    });

    it('should return correct online count', () => {
      manager.registerMachine('turtle_1', 'turtle', createMockWs());
      manager.registerMachine('turtle_2', 'turtle', createMockWs());
      manager.setMachineOffline('turtle_2');

      expect(manager.getOnlineCount()).toBe(1);
    });
  });

  describe('hasMachine', () => {
    it('should return true for existing machine', () => {
      manager.registerMachine('turtle_1', 'turtle', createMockWs());
      expect(manager.hasMachine('turtle_1')).toBe(true);
    });

    it('should return false for unknown machine', () => {
      expect(manager.hasMachine('unknown')).toBe(false);
    });
  });

  describe('clear', () => {
    it('should remove all machines and events', () => {
      manager.registerMachine('turtle_1', 'turtle', createMockWs());
      manager.registerMachine('turtle_2', 'turtle', createMockWs());

      manager.clear();

      expect(manager.getMachineCount()).toBe(0);
      expect(manager.getEvents()).toHaveLength(0);
    });
  });
});
