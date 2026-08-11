#!/usr/bin/env node
// Wire kbglow into Claude Code's hooks (~/.claude/settings.json) so the
// keyboard blinks while Claude is waiting for approval.
//
//   kbglow-setup                 add/update the hooks
//   kbglow-setup --remove        remove every kbglow hook
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
const WATCH = process.argv.includes('--watch');
const WATCH_REMOVE = process.argv.includes('--watch-remove');

const settingsDir = path.join(os.homedir(), '.claude');
const settingsPath = path.join(settingsDir, 'settings.json');
const binPath = path.join(__dirname, '..', 'bin', 'kbglow');

// The Notification hook also fires for "idle for 60s" nudges; the grep keeps
// the blink to actual permission requests (hook JSON arrives on stdin).
const PULSE = `grep -qi permission && (${binPath} pulse --blink --period 2 -t 600 >/dev/null 2>&1 &) || true`;
const STOP = `${binPath} stop >/dev/null 2>&1 || true`;
const EVENTS = {
  Notification: PULSE,
  PostToolUse: STOP,
  UserPromptSubmit: STOP,
  Stop: STOP,
};

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
  for (const [event, command] of Object.entries(EVENTS)) {
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
  }
  if (backedUp) {
    console.log(`kbglow: previous settings backed up to ${settingsPath}.kbglow-bak`);
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
	<key>StandardErrorPath</key><string>/tmp/kbglow.watch.log</string>
</dict>
</plist>
`;
  fs.mkdirSync(path.dirname(plistPath), { recursive: true });
  fs.writeFileSync(plistPath, plist);
  const uid = process.getuid();
  launchctl(`bootout gui/${uid} ${plistPath}`);
  launchctl(`bootstrap gui/${uid} ${plistPath}`);
  console.log('kbglow: watch agent installed (blinks on Claude Desktop / ChatGPT notifications)');
  console.log('kbglow: IMPORTANT — grant Full Disk Access to this binary, or it cannot');
  console.log('kbglow: read the Notification Center database:');
  console.log(`kbglow:   System Settings > Privacy & Security > Full Disk Access > + >`);
  console.log(`kbglow:   ${binPath}`);
  console.log('kbglow: progress/errors are logged to /tmp/kbglow.watch.log');
  console.log('kbglow: (undo anytime with: kbglow-setup --watch-remove)');
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
    main();
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
