/**
 * Heartbeat Monitor Tests
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { HeartbeatMonitor, DEFAULT_CONFIG } from './heartbeat-monitor';
import { StateManager, resetStateManager } from './state-manager';
import type { WebSocket } from 'ws';

// Mock WebSocket
function createMockWs(): WebSocket {
  return {
    send: vi.fn(),
    close: vi.fn(),
    readyState: 1,
  } as unknown as WebSocket;
}

describe('HeartbeatMonitor', () => {
  let stateManager: StateManager;
  let monitor: HeartbeatMonitor;

  beforeEach(() => {
    vi.useFakeTimers();
    resetStateManager();
    stateManager = new StateManager();
    monitor = new HeartbeatMonitor(stateManager, {
      checkInterval: 1000,
      timeoutThreshold: 3000,
    });
  });

  afterEach(() => {
    monitor.stop();
    vi.useRealTimers();
  });

  describe('configuration', () => {
    it('should use default config when none provided', () => {
      const defaultMonitor = new HeartbeatMonitor(stateManager);
      const config = defaultMonitor.getConfig();
      expect(config.checkInterval).toBe(DEFAULT_CONFIG.checkInterval);
      expect(config.timeoutThreshold).toBe(DEFAULT_CONFIG.timeoutThreshold);
    });

    it('should accept custom config', () => {
      const config = monitor.getConfig();
      expect(config.checkInterval).toBe(1000);
      expect(config.timeoutThreshold).toBe(3000);
    });
  });

  describe('start/stop', () => {
    it('should track running state', () => {
      expect(monitor.isRunning()).toBe(false);
      monitor.start();
      expect(monitor.isRunning()).toBe(true);
      monitor.stop();
      expect(monitor.isRunning()).toBe(false);
    });

    it('should not start multiple times', () => {
      monitor.start();
      monitor.start();
      expect(monitor.isRunning()).toBe(true);
      monitor.stop();
      expect(monitor.isRunning()).toBe(false);
    });
  });

  describe('heartbeat timeout detection', () => {
    it('should mark machine offline after timeout', () => {
      // Register a machine
      stateManager.registerMachine('turtle_1', 'turtle', createMockWs());
      expect(stateManager.getMachine('turtle_1')?.status).toBe('online');

      // Start monitor
      monitor.start();

      // Advance time past timeout threshold
      vi.advanceTimersByTime(4000);

      // Machine should be offline
      expect(stateManager.getMachine('turtle_1')?.status).toBe('offline');
    });

    it('should not mark machine offline before timeout', () => {
      // Register a machine
      stateManager.registerMachine('turtle_1', 'turtle', createMockWs());

      // Start monitor
      monitor.start();

      // Advance time but not past threshold
      vi.advanceTimersByTime(2000);

      // Machine should still be online
      expect(stateManager.getMachine('turtle_1')?.status).toBe('online');
    });

    it('should keep machine online if lastSeen is updated', () => {
      // Register a machine
      stateManager.registerMachine('turtle_1', 'turtle', createMockWs());

      // Start monitor
      monitor.start();

      // Advance time
      vi.advanceTimersByTime(2000);

      // Update lastSeen (simulating heartbeat)
      stateManager.updateLastSeen('turtle_1');

      // Advance time more
      vi.advanceTimersByTime(2000);

      // Machine should still be online because lastSeen was updated
      expect(stateManager.getMachine('turtle_1')?.status).toBe('online');
    });

    it('should not check already offline machines', () => {
      // Register a machine and set it offline
      stateManager.registerMachine('turtle_1', 'turtle', createMockWs());
      stateManager.setMachineOffline('turtle_1');

      // Count events
      const events: unknown[] = [];
      stateManager.addEventListener(e => events.push(e));

      // Start monitor
      monitor.start();

      // Advance time
      vi.advanceTimersByTime(4000);

      // No new offline events should be emitted
      expect(events.filter(e => (e as { type: string }).type === 'machine_offline')).toHaveLength(0);
    });

    it('should handle multiple machines independently', () => {
      // Register two machines
      stateManager.registerMachine('turtle_1', 'turtle', createMockWs());
      stateManager.registerMachine('turtle_2', 'turtle', createMockWs());

      // Start monitor
      monitor.start();

      // Advance time a bit
      vi.advanceTimersByTime(2000);

      // Update only turtle_1's lastSeen
      stateManager.updateLastSeen('turtle_1');

      // Advance time past threshold
      vi.advanceTimersByTime(2000);

      // turtle_1 should be online (was updated), turtle_2 should be offline
      expect(stateManager.getMachine('turtle_1')?.status).toBe('online');
      expect(stateManager.getMachine('turtle_2')?.status).toBe('offline');
    });
  });

  describe('reconnection', () => {
    it('should allow offline machine to come back online', () => {
      // Register and timeout a machine
      stateManager.registerMachine('turtle_1', 'turtle', createMockWs());
      monitor.start();
      vi.advanceTimersByTime(4000);
      expect(stateManager.getMachine('turtle_1')?.status).toBe('offline');

      // Machine reconnects
      stateManager.registerMachine('turtle_1', 'turtle', createMockWs());
      expect(stateManager.getMachine('turtle_1')?.status).toBe('online');

      // Keep sending heartbeats
      stateManager.updateLastSeen('turtle_1');
      vi.advanceTimersByTime(2000);

      // Should still be online
      expect(stateManager.getMachine('turtle_1')?.status).toBe('online');
    });
  });
});
