/**
 * CC-Remote Server Entry Point
 *
 * WebSocket server for CC:Tweaked machine connectivity with REST API for MCP integration.
 */

import { createServer } from 'http';
import express, { Request, Response, NextFunction } from 'express';
import { WebSocketServer, WebSocket } from 'ws';
import { TokenManager } from './token-manager.js';
import { StateManager, getStateManager } from './state-manager.js';
import { AuthHandler } from './handlers/auth-handler.js';
import { MessageRouter } from './handlers/message-router.js';
import { HeartbeatMonitor } from './heartbeat-monitor.js';
import { log, info, error, setVerbose } from './logger.js';
import { ErrorCode, getErrorMessage } from '../shared/errors.js';
import type { MachineStateDTO } from '../shared/machine-state.js';
import fs from 'fs';
import path from 'path';

/**
 * Server configuration
 */
interface ServerConfig {
  port: number;
  tokenFile?: string;
  verbose: boolean;
}

/**
 * Parse command line arguments
 */
function parseArgs(): ServerConfig {
  const args = process.argv.slice(2);
  const config: ServerConfig = {
    port: 3000,
    verbose: false,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    const next = args[i + 1];

    switch (arg) {
      case '--port':
      case '-p':
        if (next) {
          const port = parseInt(next, 10);
          if (!isNaN(port) && port > 0 && port < 65536) {
            config.port = port;
            i++;
          }
        }
        break;

      case '--token-file':
      case '-t':
        if (next) {
          config.tokenFile = next;
          i++;
        }
        break;

      case '--verbose':
      case '-v':
        config.verbose = true;
        break;

      case '--help':
      case '-h':
        console.log(`
cc-remote-server - Remote debugging server for CC:Tweaked

Usage: npm start -- [options]

Options:
  -p, --port <port>       Port to listen on (default: 3000)
  -t, --token-file <path> Path to token file
  -v, --verbose           Enable verbose logging
  -h, --help              Show this help message
`);
        process.exit(0);
    }
  }

  return config;
}

/**
 * Map of authenticated WebSocket connections to machine IDs
 */
const wsToMachineId = new Map<WebSocket, string>();

/**
 * Main server startup
 */
async function main(): Promise<void> {
  const config = parseArgs();
  setVerbose(config.verbose);

  info('Server starting...');

  // Initialize managers
  const tokenManager = new TokenManager();
  const stateManager = getStateManager();

  // Load tokens from file if specified
  if (config.tokenFile) {
    const loaded = tokenManager.loadFromFile(config.tokenFile);
    if (loaded > 0) {
      info(`Loaded ${loaded} tokens from ${config.tokenFile}`);
    }
  }

  // Generate a token if none exist
  if (tokenManager.getTokenCount() === 0) {
    const token = tokenManager.generateToken();
    info('Generated new token', { token });

    // Save to file if specified
    if (config.tokenFile) {
      tokenManager.saveToFile(config.tokenFile);
      info(`Token saved to ${config.tokenFile}`);
    }
  }

  // Create Express app for REST API
  const app = express();
  app.use(express.json());

  // REST API endpoints
  setupRestApi(app, stateManager, tokenManager);

  // Create HTTP server
  const server = createServer(app);

  // Create WebSocket server
  const wss = new WebSocketServer({ server });

  // Initialize handlers
  const authHandler = new AuthHandler(tokenManager, stateManager);
  const messageRouter = new MessageRouter(stateManager);

  // Start heartbeat monitor
  const heartbeatMonitor = new HeartbeatMonitor(stateManager);
  heartbeatMonitor.start();

  // WebSocket connection handler
  wss.on('connection', (ws: WebSocket, req) => {
    const clientIp = req.socket.remoteAddress ?? 'unknown';
    log('debug', 'New connection', { ip: clientIp });

    // Start auth timeout
    authHandler.startAuthTimeout(ws, clientIp);

    // Message handler
    ws.on('message', (data) => {
      if (authHandler.isPending(ws)) {
        // Unauthenticated - try to authenticate
        const result = authHandler.handleMessage(ws, data);
        if (result.success && result.machineId) {
          wsToMachineId.set(ws, result.machineId);
        }
      } else {
        // Authenticated - route message
        const machineId = wsToMachineId.get(ws);
        if (machineId) {
          messageRouter.handleMessage(ws, machineId, data);
        }
      }
    });

    // Close handler
    ws.on('close', (code, reason) => {
      authHandler.cancelPending(ws);
      const machineId = wsToMachineId.get(ws);
      if (machineId) {
        const reasonStr = reason?.toString() || '';
        if (code === 1000 || code === 1001) {
          info(`Agent disconnected: ${machineId} (clean)`, { code, reason: reasonStr });
        } else {
          info(`Agent disconnected: ${machineId} (unexpected)`, { code, reason: reasonStr });
        }
        stateManager.setMachineOffline(machineId);
        wsToMachineId.delete(ws);
      }
    });

    // Error handler
    ws.on('error', (err) => {
      const machineId = wsToMachineId.get(ws);
      error('WebSocket error', { machineId, error: err.message });
    });
  });

  // Start server
  server.listen(config.port, () => {
    info(`WebSocket: ws://localhost:${config.port}`);

    // Display all tokens for install URLs
    const tokens = tokenManager.getAllTokens();
    for (const token of tokens) {
      info(`Install URL: http://localhost:${config.port}/install/${token}`);
    }

    info('Waiting for connections...');
  });

  // Graceful shutdown
  process.on('SIGINT', () => {
    info('Shutting down...');

    // Stop heartbeat monitor
    heartbeatMonitor.stop();

    // Close all connections
    wss.clients.forEach((ws) => {
      ws.close(1001, 'Server shutting down');
    });

    server.close(() => {
      info('Server stopped');
      process.exit(0);
    });
  });
}

/**
 * Set up REST API endpoints
 */
function setupRestApi(
  app: express.Application,
  stateManager: StateManager,
  tokenManager: TokenManager
): void {
  // Health check
  app.get('/api/health', (_req: Request, res: Response) => {
    res.json({ status: 'ok', machines: stateManager.getMachineCount() });
  });

  // List all machines
  app.get('/api/machines', (req: Request, res: Response) => {
    let machines = stateManager.toDTO();

    // Filter by status if requested
    const status = req.query.status as string;
    if (status === 'online' || status === 'offline') {
      machines = machines.filter((m: MachineStateDTO) => m.status === status);
    }

    res.json({
      machines,
      count: machines.length,
    });
  });

  // Get single machine
  app.get('/api/machines/:id', (req: Request, res: Response) => {
    const machine = stateManager.getMachineDTO(req.params.id);
    if (!machine) {
      res.status(404).json({
        error: true,
        code: ErrorCode.MACHINE_NOT_FOUND,
        message: getErrorMessage(ErrorCode.MACHINE_NOT_FOUND),
      });
      return;
    }
    res.json(machine);
  });

  // Get machine console
  app.get('/api/machines/:id/console', (req: Request, res: Response) => {
    const machine = stateManager.getMachine(req.params.id);
    if (!machine) {
      res.status(404).json({
        error: true,
        code: ErrorCode.MACHINE_NOT_FOUND,
        message: getErrorMessage(ErrorCode.MACHINE_NOT_FOUND),
      });
      return;
    }

    const limit = parseInt(req.query.lines as string) || 50;
    const lines = stateManager.getConsoleLines(req.params.id, limit);

    res.json({
      machineId: req.params.id,
      lines,
      count: lines.length,
    });
  });

  // Get recent events
  app.get('/api/events', (req: Request, res: Response) => {
    const since = req.query.since ? new Date(req.query.since as string) : undefined;
    const events = stateManager.getEvents(since);
    res.json({
      events,
      count: events.length,
    });
  });

  // Install endpoint - serves agent with embedded config
  app.get('/install/:token', (req: Request, res: Response) => {
    const token = req.params.token;

    if (!tokenManager.validateToken(token)) {
      res.status(404).send('-- Invalid token');
      return;
    }

    // Read agent template
    const agentPath = path.join(__dirname, '../../agent/agent.lua');
    let agentCode: string;

    try {
      agentCode = fs.readFileSync(agentPath, 'utf-8');
    } catch {
      error('Failed to read agent.lua', { path: agentPath });
      res.status(500).send('-- Server error: agent.lua not found');
      return;
    }

    // Get server URL from request
    const host = req.get('host') || `localhost:${req.socket.localPort}`;
    const protocol = req.protocol === 'https' ? 'wss' : 'ws';
    const serverUrl = `${protocol}://${host}`;

    // Embed configuration
    const configuredAgent = agentCode
      .replace('server_url = "ws://localhost:3000"', `server_url = "${serverUrl}"`)
      .replace('token = "YOUR_TOKEN_HERE"', `token = "${token}"`);

    res.setHeader('Content-Type', 'text/x-lua');
    res.setHeader('Content-Disposition', 'attachment; filename="agent.lua"');
    res.send(configuredAgent);
  });

  // Error handling middleware
  app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
    error('REST API error', { error: err.message });
    res.status(500).json({
      error: true,
      code: ErrorCode.INTERNAL_ERROR,
      message: getErrorMessage(ErrorCode.INTERNAL_ERROR),
    });
  });
}

// Run the server
main().catch((err) => {
  error('Server failed to start', { error: err.message });
  process.exit(1);
});
