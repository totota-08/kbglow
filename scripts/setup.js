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
    console.log('kbglow: GUI apps too (Claude Desktop / ChatGPT)? run: kbglow-setup --watch');
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

const WATCH_LOG = '/tmp/kbglow.watch.log';

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
