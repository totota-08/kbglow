#!/usr/bin/env node
// Wire kbglow into Claude Code's hooks (~/.claude/settings.json) so the
// keyboard blinks while Claude is waiting for approval.
//
//   kbglow-setup                 add/update the hooks
//   kbglow-setup --remove        remove every kbglow hook (Claude Code + Codex)
//   kbglow-setup --done          also blink briefly when a turn COMPLETES
//                                (Claude Code Stop hook + Codex CLI notify)
//   kbglow-setup --done-remove   back to approval-only blinking
//   kbglow-setup --watch         install a launchd agent running `kbglow watch`
//                                (blink on Claude Desktop / ChatGPT notifications;
//                                needs Full Disk Access for the kbglow binary)
//   kbglow-setup --watch-remove  stop and remove the watch agent
//
// Runs automatically as npm postinstall (--postinstall: never fails the
// install, and skips silently when no Claude settings can be touched).
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const POSTINSTALL = process.argv.includes('--postinstall');
const REMOVE = process.argv.includes('--remove');
const DONE = process.argv.includes('--done');
const DONE_REMOVE = process.argv.includes('--done-remove');
const WATCH = process.argv.includes('--watch');
const WATCH_REMOVE = process.argv.includes('--watch-remove');

const settingsDir = path.join(os.homedir(), '.claude');
const settingsPath = path.join(settingsDir, 'settings.json');
const binPath = path.join(__dirname, '..', 'bin', 'kbglow');

// The Notification hook also fires for "idle for 60s" nudges; the grep keeps
// the blink to actual permission requests (hook JSON arrives on stdin).
const PULSE = `grep -qi permission && (${binPath} pulse --blink --period 2 -t 600 >/dev/null 2>&1 &) || true`;
const STOP = `${binPath} stop >/dev/null 2>&1 || true`;
// Short fast double-blink for "the turn finished" (opt-in: kbglow-setup --done).
const DONE_BLINK = `(${binPath} pulse --blink --period 0.6 -t 2.4 >/dev/null 2>&1 &) || true`;
const STOP_THEN_DONE = `${binPath} stop >/dev/null 2>&1; ${DONE_BLINK}`;

function events(done) {
  return {
    Notification: PULSE,
    PostToolUse: STOP,
    UserPromptSubmit: STOP,
    Stop: done ? STOP_THEN_DONE : STOP,
  };
}

function isKbglow(hook) {
  return hook && typeof hook.command === 'string' && hook.command.includes('kbglow');
}

// Drop kbglow commands from one event's matcher groups; prune empty groups.
function stripKbglow(groups) {
  if (!Array.isArray(groups)) return [];
  return groups
    .map((g) => ({ ...g, hooks: (g.hooks || []).filter((h) => !isKbglow(h)) }))
    .filter((g) => g.hooks.length > 0);
}

function main() {
  let settings = {};
  let backedUp = false;
  if (fs.existsSync(settingsPath)) {
    const raw = fs.readFileSync(settingsPath, 'utf8');
    try {
      settings = JSON.parse(raw);
    } catch (e) {
      throw new Error(`${settingsPath} is not valid JSON — fix it and rerun kbglow-setup`);
    }
    fs.writeFileSync(settingsPath + '.kbglow-bak', raw);
    backedUp = true;
  }

  const hooks = settings.hooks || {};
  // Keep done-mode sticky across plain re-runs unless explicitly toggled.
  const hadDone = JSON.stringify(hooks.Stop || []).includes('pulse');
  const done = DONE ? true : DONE_REMOVE ? false : hadDone;
  for (const [event, command] of Object.entries(events(done))) {
    const kept = stripKbglow(hooks[event]);
    if (!REMOVE) kept.push({ hooks: [{ type: 'command', command }] });
    if (kept.length > 0) hooks[event] = kept;
    else delete hooks[event];
  }
  if (Object.keys(hooks).length > 0) settings.hooks = hooks;
  else delete settings.hooks;

  fs.mkdirSync(settingsDir, { recursive: true });
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');

  if (REMOVE) {
    console.log(`kbglow: removed Claude Code hooks from ${settingsPath}`);
  } else {
    console.log(`kbglow: Claude Code hooks installed in ${settingsPath}`);
    console.log('kbglow: your keyboard now blinks while Claude waits for approval');
    console.log('kbglow: (undo anytime with: kbglow-setup --remove)');
    console.log('kbglow: GUI apps too (Claude Desktop / ChatGPT)? run: kbglow-setup --watch');
    if (done) {
      console.log('kbglow: turn-complete blink is ON (off with: kbglow-setup --done-remove)');
    } else if (!POSTINSTALL) {
      console.log('kbglow: want a short blink when a turn completes too? kbglow-setup --done');
    }
  }
  if (backedUp) {
    console.log(`kbglow: previous settings backed up to ${settingsPath}.kbglow-bak`);
  }
  if (POSTINSTALL && !REMOVE && fs.existsSync(plistPath)) {
    // The watch agent points at a binary this install just replaced, which
    // invalidates its signature-bound Full Disk Access grant.
    console.warn('kbglow: NOTE — the update replaced the kbglow binary, so the watch');
    console.warn('kbglow: agent lost its Full Disk Access grant. Run "kbglow-setup --watch"');
    console.warn('kbglow: to re-grant it (guided).');
  }
  return done;
}

// ---------------------------------------------------------------------------
// Other AI CLIs. Each adapter detects its CLI by config dir and wires the
// same two signals: approval-wait -> slow pulse, turn-complete -> stop
// (+ short fast blink in done mode). All writes are idempotent: existing
// kbglow entries are stripped and re-added, other config is preserved.
// ---------------------------------------------------------------------------

const APPROVAL_PULSE = `(${binPath} pulse --blink --period 2 -t 600 >/dev/null 2>&1 &) || true`;

function home(...p) {
  return path.join(os.homedir(), ...p);
}

function readJSON(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    if (fs.existsSync(file)) throw new Error(`${file} is not valid JSON — fix it first`);
    return {};
  }
}

function writeJSON(file, obj) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(obj, null, 2) + '\n');
}

// Claude-style hooks map: { Event: [ {hooks:[{type:'command',command}]} ] }.
// `nested` wraps it under a top-level "hooks" key (Gemini/Qwen settings.json);
// Factory's hooks.json has the events at the top level.
function mergeHookEvents(file, eventCommands, { nested = true, remove = false } = {}) {
  const root = readJSON(file);
  const container = nested ? root.hooks || {} : root;
  for (const [event, command] of Object.entries(eventCommands)) {
    const kept = stripKbglow(container[event]);
    if (!remove && command) kept.push({ hooks: [{ type: 'command', command }] });
    if (kept.length > 0) container[event] = kept;
    else delete container[event];
  }
  if (nested) {
    if (Object.keys(container).length > 0) root.hooks = container;
    else delete root.hooks;
  }
  writeJSON(file, root);
}

const ADAPTERS = [
  {
    name: 'Gemini CLI',
    dir: home('.gemini'),
    apply(done, remove) {
      mergeHookEvents(home('.gemini', 'settings.json'), {
        Notification: APPROVAL_PULSE,
        AfterAgent: done ? STOP_THEN_DONE : STOP,
      }, { remove });
    },
  },
  {
    name: 'Qwen Code',
    dir: home('.qwen'),
    apply(done, remove) {
      mergeHookEvents(home('.qwen', 'settings.json'), {
        PermissionRequest: APPROVAL_PULSE,
        Stop: done ? STOP_THEN_DONE : STOP,
      }, { remove });
    },
  },
  {
    name: 'Factory Droid',
    dir: home('.factory'),
    apply(done, remove) {
      mergeHookEvents(home('.factory', 'hooks.json'), {
        Notification: `grep -qi permission && ${APPROVAL_PULSE}`,
        Stop: done ? STOP_THEN_DONE : STOP,
      }, { nested: false, remove });
    },
  },
  {
    name: 'GitHub Copilot CLI',
    dir: home('.copilot'),
    apply(done, remove) {
      // Copilot loads every *.json in ~/.copilot/hooks/ — we own our own file.
      const file = home('.copilot', 'hooks', 'kbglow.json');
      if (remove) {
        try {
          fs.unlinkSync(file);
        } catch (e) {
          /* already gone */
        }
        return;
      }
      writeJSON(file, {
        version: 1,
        hooks: {
          permissionRequest: [{ type: 'command', bash: APPROVAL_PULSE, timeoutSec: 30 }],
          agentStop: [{ type: 'command', bash: done ? STOP_THEN_DONE : STOP, timeoutSec: 30 }],
        },
      });
    },
  },
  {
    name: 'Cursor CLI',
    dir: home('.cursor'),
    apply(done, remove) {
      // Cursor may exec the hook command without a shell, so it points at a
      // small script of ours. Turn-complete only (no approval event).
      const script = home('.cursor', 'kbglow-stop.sh');
      const file = home('.cursor', 'hooks.json');
      const root = readJSON(file);
      root.version = root.version || 1;
      root.hooks = root.hooks || {};
      const kept = (root.hooks.stop || []).filter(
        (h) => !(h && typeof h.command === 'string' && h.command.includes('kbglow')));
      if (remove) {
        try {
          fs.unlinkSync(script);
        } catch (e) {
          /* already gone */
        }
      } else {
        fs.writeFileSync(script, `#!/bin/sh\n${done ? STOP_THEN_DONE : STOP}\n`, { mode: 0o755 });
        kept.push({ command: script });
      }
      if (kept.length > 0) root.hooks.stop = kept;
      else delete root.hooks.stop;
      writeJSON(file, root);
    },
  },
  {
    name: 'opencode',
    dir: home('.config', 'opencode'),
    apply(done, remove) {
      const file = home('.config', 'opencode', 'plugins', 'kbglow.js');
      if (remove) {
        try {
          fs.unlinkSync(file);
        } catch (e) {
          /* already gone */
        }
        return;
      }
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, `// kbglow: blink while opencode waits for approval; stop when the turn ends.
// Generated by kbglow-setup — safe to delete (or run: kbglow-setup --remove).
const PULSE = ${JSON.stringify(APPROVAL_PULSE)}
const STOP = ${JSON.stringify(done ? STOP_THEN_DONE : STOP)}
export const KbglowPlugin = async ({ $ }) => ({
  event: async ({ event }) => {
    if (event.type === "permission.asked") await $\`sh -c \${PULSE}\`
    if (event.type === "session.idle") await $\`sh -c \${STOP}\`
  },
})
`);
    },
  },
];

function configureAdapters(done, remove) {
  const wired = [];
  for (const a of ADAPTERS) {
    if (!fs.existsSync(a.dir)) continue;
    try {
      a.apply(done, remove);
      wired.push(a.name);
    } catch (e) {
      console.warn(`kbglow: ${a.name}: skipped (${e.message})`);
    }
  }
  if (wired.length > 0) {
    console.log(`kbglow: ${remove ? 'removed from' : 'wired up'}: ${wired.join(', ')}`);
  }
  return wired;
}

const WATCH_LOG = '/tmp/kbglow.watch.log';

const codexConfigPath = path.join(os.homedir(), '.codex', 'config.toml');

/// Wire the turn-complete blink into Codex CLI via its `notify` option
/// (fires on agent-turn-complete). Top-level TOML keys must sit before the
/// first [table] header, so the entry is inserted, not appended.
function configureCodex(enable) {
  if (!fs.existsSync(path.dirname(codexConfigPath))) {
    if (enable) console.log('kbglow: Codex CLI not found (~/.codex) — skipped');
    return;
  }
  let text = '';
  try {
    text = fs.readFileSync(codexConfigPath, 'utf8');
  } catch (e) {
    /* no config yet — we'll create one */
  }
  const lines = text.split('\n').filter((l) => !l.includes('kbglow'));
  if (enable) {
    if (lines.some((l) => /^\s*notify\s*=/.test(l))) {
      console.warn('kbglow: ~/.codex/config.toml already defines notify — left untouched');
      return;
    }
    const entry = [
      '# kbglow: blink when a Codex turn completes (kbglow-setup --done)',
      `notify = ["sh", "-c", "(${binPath} pulse --blink --period 0.6 -t 2.4 >/dev/null 2>&1 &) || true # kbglow"]`,
    ];
    let at = lines.findIndex((l) => l.trim().startsWith('['));
    if (at === -1) at = lines.length;
    lines.splice(at, 0, ...entry);
    fs.writeFileSync(codexConfigPath, lines.join('\n'));
    console.log('kbglow: Codex CLI turn-complete blink configured (~/.codex/config.toml)');
  } else if (text.includes('kbglow')) {
    fs.writeFileSync(codexConfigPath, lines.join('\n'));
    console.log('kbglow: removed the Codex CLI notify entry');
  }
}

const agentLabel = 'dev.totota08.kbglow.watch';
const plistPath = path.join(os.homedir(), 'Library', 'LaunchAgents', `${agentLabel}.plist`);

function launchctl(cmd) {
  try {
    execSync(`launchctl ${cmd}`, { stdio: 'ignore' });
  } catch (e) {
    /* bootout of a non-loaded agent etc. — fine */
  }
}

function sleep(seconds) {
  execSync(`sleep ${seconds}`);
}

/// Walk the user to the one step we cannot do for them: Finder opens with the
/// binary pre-selected, the Full Disk Access pane opens next to it, the path
/// is on the clipboard — then we watch the agent's log and confirm the moment
/// the grant lands.
function guideFullDiskAccess() {
  try {
    execSync('pbcopy', { input: binPath });
    execSync(`open -R "${binPath}"`);
    execSync('open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"');
  } catch (e) {
    /* headless / non-GUI session — the printed instructions still apply */
  }
  console.log('');
  console.log('kbglow: two windows just opened. In System Settings > Full Disk Access:');
  console.log('kbglow:   1. drag the highlighted "kbglow" file from Finder into the list');
  console.log('kbglow:      (its path is also on your clipboard for the "+" > Cmd+Shift+G route)');
  console.log('kbglow:   2. turn its toggle ON');
  console.log('kbglow: waiting for the grant (Ctrl-C to skip — the watcher keeps retrying anyway)...');
  for (let i = 0; i < 90; i++) {
    sleep(2);
    try {
      const log = fs.readFileSync(WATCH_LOG, 'utf8');
      if (log.includes('watching notifications')) {
        console.log('kbglow: ✓ granted — now watching for Claude Desktop / ChatGPT notifications');
        return;
      }
    } catch (e) {
      /* log not written yet */
    }
  }
  console.log('kbglow: no grant detected yet — the watcher keeps retrying every 30s,');
  console.log(`kbglow: so finishing the steps above later is fine (log: ${WATCH_LOG})`);
}


function installWatchAgent() {
  const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>${agentLabel}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${binPath}</string>
		<string>watch</string>
	</array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>ThrottleInterval</key><integer>30</integer>
	<key>StandardErrorPath</key><string>${WATCH_LOG}</string>
</dict>
</plist>
`;
  fs.mkdirSync(path.dirname(plistPath), { recursive: true });
  fs.writeFileSync(plistPath, plist);
  const uid = process.getuid();
  launchctl(`bootout gui/${uid} ${plistPath}`);
  try {
    fs.unlinkSync(WATCH_LOG); // stale success lines would fool the grant detection
  } catch (e) {
    /* no old log */
  }
  launchctl(`bootstrap gui/${uid} ${plistPath}`);
  console.log('kbglow: watch agent installed (blinks on Claude Desktop / ChatGPT notifications)');
  console.log('kbglow: (undo anytime with: kbglow-setup --watch-remove)');
  guideFullDiskAccess();
}

function removeWatchAgent() {
  launchctl(`bootout gui/${process.getuid()} ${plistPath}`);
  try {
    fs.unlinkSync(plistPath);
  } catch (e) {
    /* already gone */
  }
  console.log('kbglow: watch agent removed');
}

try {
  if (WATCH) {
    installWatchAgent();
  } else if (WATCH_REMOVE) {
    removeWatchAgent();
  } else {
    const done = main();
    configureAdapters(done, REMOVE);
    if (DONE || DONE_REMOVE || REMOVE) configureCodex(DONE);
  }
} catch (e) {
  if (POSTINSTALL) {
    console.warn(`kbglow: could not configure Claude Code hooks automatically (${e.message})`);
    console.warn('kbglow: run "kbglow-setup" later to finish setup');
    process.exit(0);
  }
  console.error(`kbglow-setup: ${e.message}`);
  process.exit(1);
}
