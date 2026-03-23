#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const packageRoot =
  process.env.FIREBREAK_LAUNCHER_PACKAGE_ROOT ||
  path.resolve(__dirname, "..");
const kvmPath = process.env.FIREBREAK_LAUNCHER_KVM_PATH || "/dev/kvm";
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
    topLevelCommand === "doctor"
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
  const flakeRef = `path:${packageRoot}#firebreak`;
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

  process.exit(result.status === null ? 1 : result.status);
}

checkPlatform();
checkNix();
checkKvm();
checkWorkspacePath();
runFirebreak();
