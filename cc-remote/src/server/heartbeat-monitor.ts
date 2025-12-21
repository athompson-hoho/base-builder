/**
 * Heartbeat Monitor
 *
 * Monitors connected machines for heartbeat timeouts and marks them offline
 * when they miss too many consecutive heartbeats.
 */

import { StateManager } from './state-manager.js';
import { log } from './logger.js';

/**
 * Configuration for heartbeat monitoring
 */
export interface HeartbeatMonitorConfig {
  /** How often to check for timeouts (ms) */
  checkInterval: number;
  /** How long before a machine is considered offline (ms) */
  timeoutThreshold: number;
}

/**
 * Default configuration
 * - Check every 5 seconds
 * - Timeout after 30 seconds (3 missed 10-second heartbeats)
 */
export const DEFAULT_CONFIG: HeartbeatMonitorConfig = {
  checkInterval: 5000,
  timeoutThreshold: 30000,
};

/**
 * Monitors machine heartbeats and marks offline when timeout is exceeded
 */
export class HeartbeatMonitor {
  private interval: NodeJS.Timeout | null = null;
  private config: HeartbeatMonitorConfig;

  constructor(
    private stateManager: StateManager,
    config?: Partial<HeartbeatMonitorConfig>
  ) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  /**
   * Start the heartbeat monitor
   */
  start(): void {
    if (this.interval) {
      return; // Already running
    }

    log('debug', 'Heartbeat monitor started', {
      checkInterval: this.config.checkInterval,
      timeoutThreshold: this.config.timeoutThreshold,
    });

    this.interval = setInterval(() => {
      this.checkHeartbeats();
    }, this.config.checkInterval);
  }

  /**
   * Stop the heartbeat monitor
   */
  stop(): void {
    if (this.interval) {
      clearInterval(this.interval);
      this.interval = null;
      log('debug', 'Heartbeat monitor stopped');
    }
  }

  /**
   * Check all online machines for heartbeat timeout
   */
  private checkHeartbeats(): void {
    const now = Date.now();
    const machines = this.stateManager.getMachinesByStatus('online');

    for (const machine of machines) {
      const lastSeen = machine.lastSeen.getTime();
      const elapsed = now - lastSeen;

      if (elapsed > this.config.timeoutThreshold) {
        log('info', `Machine offline: ${machine.id} (heartbeat timeout)`, {
          elapsed: Math.round(elapsed / 1000),
          threshold: Math.round(this.config.timeoutThreshold / 1000),
        });

        this.stateManager.setMachineOffline(machine.id);
      }
    }
  }

  /**
   * Get the current configuration
   */
  getConfig(): HeartbeatMonitorConfig {
    return { ...this.config };
  }

  /**
   * Check if the monitor is running
   */
  isRunning(): boolean {
    return this.interval !== null;
  }
}
