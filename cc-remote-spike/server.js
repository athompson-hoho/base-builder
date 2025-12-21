/**
 * CC-Remote Technical Spike - WebSocket Server
 *
 * Tests:
 * 1. WebSocket connectivity with CC:Tweaked
 * 2. Sending execute commands to the agent
 * 3. Receiving results back
 *
 * Run: npm start
 * Connect from CC:Tweaked and observe console output
 */

import { WebSocketServer } from 'ws';
import express from 'express';
import { createServer } from 'http';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PORT = 3000;

// Create Express app for HTTP file serving
const app = express();
const server = createServer(app);

// Serve the Lua agent file
app.get('/spike-agent.lua', (req, res) => {
  console.log('[SPIKE] Agent file requested from:', req.ip);
  const luaPath = join(__dirname, 'spike-agent.lua');
  res.type('text/plain').send(readFileSync(luaPath, 'utf8'));
});

// Health check
app.get('/', (req, res) => {
  res.send('CC-Remote Spike Server - Use ws://localhost:3000 for WebSocket');
});

// Create WebSocket server attached to HTTP server
const wss = new WebSocketServer({ server });

console.log(`[SPIKE] Server listening on port ${PORT}`);
console.log(`[SPIKE] WebSocket: ws://localhost:${PORT}`);
console.log(`[SPIKE] Lua agent: http://localhost:${PORT}/spike-agent.lua`);
console.log('[SPIKE] Waiting for CC:Tweaked connection...');
console.log('');

wss.on('connection', (ws, req) => {
  console.log('[SPIKE] Client connected from:', req.socket.remoteAddress);

  // Send welcome message
  ws.send(JSON.stringify({
    type: 'welcome',
    message: 'Connected to cc-remote spike server'
  }));

  ws.on('message', (data) => {
    const raw = data.toString();
    console.log('[SPIKE] Received:', raw);

    try {
      const msg = JSON.parse(raw);

      switch (msg.type) {
        case 'hello':
          console.log('[SPIKE] Agent said hello! Machine:', msg.machine_id);
          console.log('[SPIKE] TEST 1 PASSED: WebSocket connectivity works!');
          console.log('');

          // Test 2: Send a print capture test
          console.log('[SPIKE] Sending print capture test...');
          ws.send(JSON.stringify({
            type: 'test_print',
            message: 'Please print something and send it back'
          }));
          break;

        case 'print_captured':
          console.log('[SPIKE] Captured print output:', msg.lines);
          console.log('[SPIKE] TEST 2 PASSED: Print interception works!');
          console.log('');

          // Test 3: Send code to execute
          console.log('[SPIKE] Sending remote code execution test...');
          ws.send(JSON.stringify({
            type: 'execute',
            id: 'test_1',
            code: 'return 40 + 2'
          }));
          break;

        case 'result':
          console.log('[SPIKE] Execution result:', msg);
          if (msg.success && msg.return_value === 42) {
            console.log('[SPIKE] TEST 3 PASSED: Remote code execution works!');
            console.log('');
            console.log('========================================');
            console.log('[SPIKE] ALL TESTS PASSED!');
            console.log('[SPIKE] CC:Tweaked assumptions validated.');
            console.log('[SPIKE] Safe to proceed with full development.');
            console.log('========================================');
          } else {
            console.log('[SPIKE] TEST 3 FAILED: Unexpected result');
            console.log('[SPIKE] Expected return_value: 42, got:', msg.return_value);
          }
          break;

        case 'error':
          console.log('[SPIKE] Error from agent:', msg.message);
          break;

        default:
          console.log('[SPIKE] Unknown message type:', msg.type);
          // Echo it back
          ws.send(JSON.stringify({ type: 'echo', original: msg }));
      }
    } catch (e) {
      console.log('[SPIKE] Failed to parse JSON:', e.message);
      // Echo raw message back
      ws.send(JSON.stringify({ type: 'echo', raw: raw }));
    }
  });

  ws.on('close', () => {
    console.log('[SPIKE] Client disconnected');
  });

  ws.on('error', (err) => {
    console.log('[SPIKE] WebSocket error:', err.message);
  });
});

// Handle server errors
wss.on('error', (err) => {
  console.error('[SPIKE] Server error:', err.message);
});

// Start HTTP + WebSocket server
server.listen(PORT, () => {
  console.log('');
  console.log('Instructions:');
  console.log('1. In CC:Tweaked config, whitelist localhost or your IP');
  console.log('2. In CC:Tweaked, run:');
  console.log(`   wget http://localhost:${PORT}/spike-agent.lua spike`);
  console.log('   spike');
  console.log('3. Watch this console for test results');
  console.log('');
});
