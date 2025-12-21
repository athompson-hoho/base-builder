/**
 * CC-Remote MCP Server
 *
 * MCP bridge for Claude Code integration.
 * Connects to the main cc-remote server via REST API.
 */

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import * as z from 'zod';

/**
 * Configuration
 */
const CONFIG = {
  serverUrl: process.env.CC_REMOTE_SERVER_URL || 'http://localhost:3000',
  name: 'cc-remote-mcp',
  version: '0.1.0',
};

/**
 * HTTP client for REST API communication
 */
async function fetchApi<T>(endpoint: string, options?: RequestInit): Promise<T> {
  const url = `${CONFIG.serverUrl}/api${endpoint}`;

  try {
    const response = await fetch(url, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...options?.headers,
      },
    });

    if (!response.ok) {
      const errorData = (await response.json().catch(() => ({}))) as { message?: string };
      throw new Error(errorData.message || `HTTP ${response.status}: ${response.statusText}`);
    }

    return (await response.json()) as T;
  } catch (error) {
    if (error instanceof TypeError && error.message.includes('fetch')) {
      throw new Error(`cc-remote server not reachable at ${CONFIG.serverUrl.replace('http://', '')}`);
    }
    throw error;
  }
}

/**
 * Machine state from REST API
 */
interface MachineDTO {
  id: string;
  label: string | null;
  type: 'turtle' | 'computer' | 'pocket';
  status: 'online' | 'offline';
  lastSeen: string;
  fuelLevel: number | null;
  fuelLimit: number | null;
}

interface MachinesResponse {
  machines: MachineDTO[];
  count: number;
}

/**
 * Create and configure the MCP server
 */
function createServer(): McpServer {
  const server = new McpServer({
    name: CONFIG.name,
    version: CONFIG.version,
  });

  // Register cc_list_machines tool
  server.registerTool(
    'cc_list_machines',
    {
      title: 'List CC Machines',
      description:
        'List all connected ComputerCraft machines (turtles, computers, pocket computers)',
      inputSchema: {
        status: z
          .enum(['online', 'offline', 'all'])
          .optional()
          .describe('Filter by machine status (default: all)'),
      },
      outputSchema: {
        machines: z.array(
          z.object({
            id: z.string(),
            label: z.string().nullable(),
            type: z.enum(['turtle', 'computer', 'pocket']),
            status: z.enum(['online', 'offline']),
            lastSeen: z.string(),
          })
        ),
        count: z.number(),
        message: z.string().optional(),
      },
    },
    async ({ status }) => {
      try {
        // Build query string
        const queryParams = status && status !== 'all' ? `?status=${status}` : '';
        const data = await fetchApi<MachinesResponse>(`/machines${queryParams}`);

        // Format machines for output
        const machines = data.machines.map((m) => ({
          id: m.id,
          label: m.label,
          type: m.type,
          status: m.status,
          lastSeen: m.lastSeen,
        }));

        // Build response
        const output: {
          machines: typeof machines;
          count: number;
          message?: string;
        } = {
          machines,
          count: machines.length,
        };

        // Add message if no machines
        if (machines.length === 0) {
          output.message = 'No machines connected';
        }

        return {
          content: [{ type: 'text', text: JSON.stringify(output, null, 2) }],
          structuredContent: output,
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Unknown error';

        // Return error in a structured way
        const output = {
          machines: [],
          count: 0,
          message: message,
        };

        return {
          content: [{ type: 'text', text: `Error: ${message}` }],
          structuredContent: output,
          isError: true,
        };
      }
    }
  );

  return server;
}

/**
 * Main entry point
 */
async function main(): Promise<void> {
  const server = createServer();

  // Connect via stdio (spawned by Claude Code)
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

// Run the server
main().catch((error) => {
  console.error('MCP server error:', error);
  process.exit(1);
});

// Export for testing
export { createServer, fetchApi, CONFIG };
