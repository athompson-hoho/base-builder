# CC-Remote Technical Spike

This spike validates three critical CC:Tweaked assumptions before full development:

1. **WebSocket connectivity** - Can we connect from CC:Tweaked to a Node.js server?
2. **Print interception** - Can we override `_G.print` to capture output?
3. **Remote code execution** - Can we use `load()` to execute code from the server?

## Quick Start

### Step 1: Start the Server

```bash
cd cc-remote-spike
npm install
npm start
```

You should see:
```
[SPIKE] WebSocket server listening on ws://localhost:3000
[SPIKE] Waiting for CC:Tweaked connection...
```

### Step 2: Copy Agent to CC:Tweaked

**Option A: Manual copy**

1. Find your Minecraft saves folder:
   - Windows: `%appdata%\.minecraft\saves\<world>\computercraft\computer\<id>\`
2. Copy `spike-agent.lua` to that folder as `spike.lua`
3. In CC:Tweaked, run: `spike`

**Option B: Pastebin (if available)**

1. Upload `spike-agent.lua` to pastebin.com
2. In CC:Tweaked, run: `pastebin get <code> spike`
3. Run: `spike`

**Option C: HTTP whitelist (requires config)**

1. Add `localhost` to CC:Tweaked's HTTP whitelist in `config/computercraft-server.toml`
2. In CC:Tweaked, run:
   ```
   wget http://localhost:3000/spike-agent.lua spike
   spike
   ```

### Step 3: Watch the Results

The server console will show:
```
[SPIKE] Client connected
[SPIKE] Agent said hello! Machine: computer_0
[SPIKE] TEST 1 PASSED: WebSocket connectivity works!

[SPIKE] Captured print output: [...]
[SPIKE] TEST 2 PASSED: Print interception works!

[SPIKE] Execution result: { success: true, return_value: 42 }
[SPIKE] TEST 3 PASSED: Remote code execution works!

========================================
[SPIKE] ALL TESTS PASSED!
[SPIKE] Safe to proceed with full development.
========================================
```

## If Tests Fail

### WebSocket Connection Failed

- Check CC:Tweaked's HTTP config allows WebSocket connections
- Verify `localhost:3000` is reachable from Minecraft
- Check firewall settings

### Print Capture Failed

- This would be unusual - CC:Tweaked allows `_G.print` override
- Check for Lua syntax errors

### Remote Execution Failed

- Verify `load()` is available (should be in CC:Tweaked)
- Check for sandbox restrictions

## Files

- `server.js` - Node.js WebSocket server that orchestrates the tests
- `spike-agent.lua` - Lua agent that runs on CC:Tweaked
- `package.json` - Node dependencies

## Success Criteria

All three tests must pass before proceeding with full cc-remote development.
If any test fails, the architecture needs to be redesigned.
