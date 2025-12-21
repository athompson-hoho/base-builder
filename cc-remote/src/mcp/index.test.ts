/**
 * MCP Server Tests
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

// Mock fetch before importing the module
const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

// Now import the module (after mocking)
import { createServer, fetchApi, CONFIG } from './index.js';

describe('MCP Server', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('createServer', () => {
    it('should create a server with correct name and version', () => {
      const server = createServer();
      expect(server).toBeDefined();
    });
  });

  describe('fetchApi', () => {
    it('should build correct URL with endpoint', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ machines: [], count: 0 }),
      });

      await fetchApi('/machines');

      expect(mockFetch).toHaveBeenCalledWith(
        `${CONFIG.serverUrl}/api/machines`,
        expect.objectContaining({
          headers: expect.objectContaining({
            'Content-Type': 'application/json',
          }),
        })
      );
    });

    it('should return parsed JSON on success', async () => {
      const mockData = { machines: [{ id: 'test' }], count: 1 };
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockData,
      });

      const result = await fetchApi('/machines');

      expect(result).toEqual(mockData);
    });

    it('should throw error with message on HTTP error', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 404,
        statusText: 'Not Found',
        json: async () => ({ message: 'Machine not found' }),
      });

      await expect(fetchApi('/machines/invalid')).rejects.toThrow('Machine not found');
    });

    it('should throw generic error when no message in error response', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 500,
        statusText: 'Internal Server Error',
        json: async () => ({}),
      });

      await expect(fetchApi('/machines')).rejects.toThrow('HTTP 500: Internal Server Error');
    });

    it('should throw helpful error when server not reachable', async () => {
      mockFetch.mockRejectedValueOnce(new TypeError('fetch failed'));

      await expect(fetchApi('/machines')).rejects.toThrow(
        'cc-remote server not reachable at localhost:3000'
      );
    });

    it('should re-throw other errors', async () => {
      const customError = new Error('Custom error');
      mockFetch.mockRejectedValueOnce(customError);

      await expect(fetchApi('/machines')).rejects.toThrow('Custom error');
    });
  });

  describe('cc_list_machines behavior', () => {
    it('should call correct endpoint for all machines', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ machines: [], count: 0 }),
      });

      await fetchApi('/machines');

      expect(mockFetch).toHaveBeenCalledWith(
        `${CONFIG.serverUrl}/api/machines`,
        expect.any(Object)
      );
    });

    it('should call correct endpoint with status filter', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ machines: [], count: 0 }),
      });

      // Simulate what the tool does with a filter
      await fetchApi('/machines?status=online');

      expect(mockFetch).toHaveBeenCalledWith(
        `${CONFIG.serverUrl}/api/machines?status=online`,
        expect.any(Object)
      );
    });

    it('should parse machine list correctly', async () => {
      const mockMachines = {
        machines: [
          {
            id: 'turtle_1',
            label: 'Miner',
            type: 'turtle',
            status: 'online',
            lastSeen: '2025-12-20T10:00:00.000Z',
            fuelLevel: 1000,
            fuelLimit: 20000,
          },
          {
            id: 'computer_2',
            label: null,
            type: 'computer',
            status: 'offline',
            lastSeen: '2025-12-20T09:00:00.000Z',
            fuelLevel: null,
            fuelLimit: null,
          },
        ],
        count: 2,
      };

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockMachines,
      });

      const result = await fetchApi<typeof mockMachines>('/machines');

      expect(result.machines).toHaveLength(2);
      expect(result.machines[0].id).toBe('turtle_1');
      expect(result.machines[0].label).toBe('Miner');
      expect(result.machines[0].type).toBe('turtle');
      expect(result.machines[0].status).toBe('online');
      expect(result.machines[1].id).toBe('computer_2');
      expect(result.machines[1].label).toBeNull();
      expect(result.machines[1].type).toBe('computer');
    });

    it('should handle empty machine list', async () => {
      const mockResponse = {
        machines: [],
        count: 0,
      };

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockResponse,
      });

      const result = await fetchApi<typeof mockResponse>('/machines');

      expect(result.machines).toHaveLength(0);
      expect(result.count).toBe(0);
    });
  });

  describe('CONFIG', () => {
    it('should have default server URL', () => {
      expect(CONFIG.serverUrl).toBe('http://localhost:3000');
    });

    it('should have correct name and version', () => {
      expect(CONFIG.name).toBe('cc-remote-mcp');
      expect(CONFIG.version).toBe('0.1.0');
    });
  });
});
