#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const GITHUB_FLAKE_REF = "github:skadaai/firebreak#firebreak";
const LOCAL_ROOT_MARKERS = [
  ["flake.nix"],
  ["modules", "base", "host", "firebreak.sh"]
];

const kvmPath = process.env.FIREBREAK_LAUNCHER_KVM_PATH || "/dev/kvm";
const forcedLocalRoot = process.env.FIREBREAK_LAUNCHER_PACKAGE_ROOT || "";
const args = process.argv.slice(2);
const topLevelCommand = args[0] || "";

function fail(message) {
  console.error(`firebreak launcher: ${message}`);
  process.exit(1);
}

function warn(message) {
  console.error(`firebreak launcher: ${message}`);
}

function checkPlatform() {
  if (process.platform !== "linux") {
    fail("Firebreak currently requires a Linux host.");
  }

  if (process.arch !== "x64") {
    fail("Firebreak currently targets x86_64 Linux hosts.");
  }
}

function checkNix() {
  const result = spawnSync("nix", ["--version"], {
    encoding: "utf8"
  });

  if (result.error && result.error.code === "ENOENT") {
    fail("Nix is not installed. Install Nix first, then run `npx firebreak` again.");
  }

  if (result.status !== 0) {
    fail(`Nix is installed but unavailable: ${(result.stderr || result.stdout || "").trim()}`);
  }
}

function pathExists(targetPath) {
  try {
    fs.accessSync(targetPath);
    return true;
  } catch {
    return false;
  }
}

function looksLikeFirebreakRoot(candidateRoot) {
  return LOCAL_ROOT_MARKERS.every((segments) =>
    pathExists(path.join(candidateRoot, ...segments))
  );
}

function findLocalFirebreakRoot(startDir) {
  let currentDir = path.resolve(startDir);

  while (true) {
    if (looksLikeFirebreakRoot(currentDir)) {
      return currentDir;
    }

    const parentDir = path.dirname(currentDir);
    if (parentDir === currentDir) {
      return null;
    }
    currentDir = parentDir;
  }
}

function resolveFlakeRef() {
  if (forcedLocalRoot) {
    if (!looksLikeFirebreakRoot(forcedLocalRoot)) {
      fail(`FIREBREAK_LAUNCHER_PACKAGE_ROOT does not point to a Firebreak checkout: ${forcedLocalRoot}`);
    }
    return `path:${path.resolve(forcedLocalRoot)}#firebreak`;
  }

  const localRoot = findLocalFirebreakRoot(process.cwd());
  if (localRoot) {
    return `path:${localRoot}#firebreak`;
  }

  return GITHUB_FLAKE_REF;
}

function kvmFailureReason() {
  try {
    fs.accessSync(kvmPath, fs.constants.R_OK | fs.constants.W_OK);
    return null;
  } catch (error) {
    if (!fs.existsSync(kvmPath)) {
      return `${kvmPath} is missing`;
    }

    if (error && error.code === "EACCES") {
      return `${kvmPath} is not readable and writable by the current user`;
    }

    return `${kvmPath} is not usable: ${error.message}`;
  }
}

function commandAllowsMissingKvm() {
  return (
    topLevelCommand === "" ||
    topLevelCommand === "help" ||
    topLevelCommand === "-h" ||
    topLevelCommand === "--help" ||
    topLevelCommand === "init" ||
    topLevelCommand === "doctor" ||
    topLevelCommand === "vms"
  );
}

function checkKvm() {
  const failure = kvmFailureReason();
  if (!failure) {
    return;
  }

  if (commandAllowsMissingKvm()) {
    warn(`${failure}. Continuing because this command can still provide setup or diagnostics help.`);
    return;
  }

  fail(`${failure}. Firebreak needs KVM access to run local MicroVM workloads.`);
}

function checkWorkspacePath() {
  if (/\s/.test(process.cwd())) {
    warn("the current working directory contains whitespace; local VM launch will fail until you move it.");
  }
}

function runFirebreak() {
  const flakeRef = resolveFlakeRef();
  const result = spawnSync(
    "nix",
    [
      "--accept-flake-config",
      "--extra-experimental-features",
      "nix-command flakes",
      "run",
      flakeRef,
      "--",
      ...args
    ],
    {
      cwd: process.cwd(),
      env: process.env,
      stdio: "inherit"
    }
  );

  if (result.error) {
    fail(`unable to launch Firebreak through Nix: ${result.error.message}`);
  }

  if (result.status === null && result.signal) {
    process.kill(process.pid, result.signal);
    return;
  }

  process.exit(result.status === null ? 1 : result.status);
}

checkPlatform();
checkNix();
checkKvm();
checkWorkspacePath();
runFirebreak();
