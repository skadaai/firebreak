#!/usr/bin/env node

const fs = require("node:fs")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

const GITHUB_FLAKE_REF = "github:skadaai/firebreak";
const LOCAL_ROOT_MARKERS = [
  ["flake.nix"],
  ["modules", "base", "host", "firebreak.sh"]
]
const LIBEXEC_FILES = [
  "firebreak.sh",
  "firebreak-init.sh",
  "firebreak-doctor.sh",
  "firebreak-project-config.sh"
]
const HELP_COMMANDS = new Set(["", "help", "-h", "--help"])

const args = process.argv.slice(2)
const topLevelCommand = args[0] || "";
const forcedLocalRoot = process.env.FIREBREAK_LAUNCHER_PACKAGE_ROOT || "";
const kvmPath = process.env.FIREBREAK_LAUNCHER_KVM_PATH || "/dev/kvm";

const fail = (message) => {
  console.error(`firebreak launcher: ${message}`)
  process.exit(1)
}

const warn = (message) => {
  console.error(`firebreak launcher: ${message}`)
}

const pathExists = (targetPath) => {
  try {
    fs.accessSync(targetPath)
    return true;
  } catch {
    return false;
  }
}

const looksLikeFirebreakRoot = (candidateRoot) => (
  LOCAL_ROOT_MARKERS.every((segments) => pathExists(path.join(candidateRoot, ...segments)))
)

const looksLikeLibexecDir = (candidateDir) => (
  LIBEXEC_FILES.every((fileName) => pathExists(path.join(candidateDir, fileName)))
)

const findLocalFirebreakRoot = (startDir) => {
  let currentDir = path.resolve(startDir)

  while (true) {
    if (looksLikeFirebreakRoot(currentDir)) {
      return currentDir;
    }

    const parentDir = path.dirname(currentDir)
    if (parentDir === currentDir) {
      return null;
    }

    currentDir = parentDir;
  }
}

const resolveLocalRoot = () => {
  if (!forcedLocalRoot) {
    return findLocalFirebreakRoot(process.cwd())
  }

  if (!looksLikeFirebreakRoot(forcedLocalRoot)) {
    fail(`FIREBREAK_LAUNCHER_PACKAGE_ROOT does not point to a Firebreak checkout: ${forcedLocalRoot}`)
  }

  return path.resolve(forcedLocalRoot)
}

const resolveFlakeRef = (localRoot) => (
  localRoot ? `path:${localRoot}` : GITHUB_FLAKE_REF
)

const resolveLibexecDir = (localRoot) => {
  if (localRoot) {
    const localLibexecDir = path.join(localRoot, "modules", "base", "host")
    if (looksLikeLibexecDir(localLibexecDir)) {
      return localLibexecDir;
    }
  }

  const packagedLibexecDir = path.resolve(__dirname, "..", "modules", "base", "host")
  if (looksLikeLibexecDir(packagedLibexecDir)) {
    return packagedLibexecDir;
  }

  fail("unable to resolve the Firebreak shell runtime")
}

const checkPlatform = () => {
  if (process.platform !== "linux") {
    fail("Firebreak currently requires a Linux host.")
  }

  if (process.arch !== "x64") {
    fail("Firebreak currently targets x86_64 Linux hosts.")
  }
}

const checkNix = () => {
  const result = spawnSync("nix", ["--version"], {
    encoding: "utf8"
  })

  if (result.error) {
    if (result.error.code === "ENOENT") {
      fail("Nix is not installed. Install Nix first, then run `npx firebreak` again.")
    }

    fail(`unable to execute nix: [${result.error.code || "unknown"}] ${result.error.message}`)
  }

  if (result.status !== 0) {
    fail(`Nix is installed but unavailable: ${(result.stderr || result.stdout || "").trim()}`)
  }
}

const kvmFailureReason = () => {
  try {
    fs.accessSync(kvmPath, fs.constants.R_OK | fs.constants.W_OK)
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

const runCommandRequiresNix = () => {
  if (topLevelCommand !== "run") {
    return false;
  }

  const runArgs = args.slice(1)
  if (runArgs.length === 0 || HELP_COMMANDS.has(runArgs[0])) {
    return false;
  }

  for (const arg of runArgs.slice(1)) {
    if (arg === "--") {
      break;
    }

    if (HELP_COMMANDS.has(arg)) {
      return false;
    }
  }

  return true;
}

const internalCommandRequiresNix = () => (
  topLevelCommand === "internal" &&
  !HELP_COMMANDS.has(args[1] || "") &&
  (args[1] || "") !== ""
)

const commandRequiresNix = () => (
  runCommandRequiresNix() || internalCommandRequiresNix()
)

const checkKvm = () => {
  const failure = kvmFailureReason()
  if (!failure) {
    return;
  }

  if (!commandRequiresNix()) {
    warn(`${failure}. Continuing because this command can still provide setup or diagnostics help.`)
    return;
  }

  fail(`${failure}. Firebreak needs KVM access to run local MicroVM workloads.`)
}

const checkWorkspacePath = () => {
  if (/\s/.test(process.cwd())) {
    warn("the current working directory contains whitespace; local VM launch will fail until you move it.")
  }
}

const formatElapsed = (elapsedMs) => `${(elapsedMs / 1000).toFixed(1)}s`;

const createReporter = (flakeRef) => {
  if (!commandRequiresNix()) {
    return null;
  }

  const startMs = Date.now()
  const flakeSource = flakeRef.startsWith("path:") ? "local checkout" : "GitHub";
  return {
    start() {
      process.stderr.write(`firebreak launcher: loading Firebreak via ${flakeSource}...\n`)
    },
    stop(success) {
      process.stderr.write(
        `firebreak launcher: ${success ? "ready" : "stopped"} after ${formatElapsed(Date.now() - startMs)}.\n`
      )
    }
  }
}

const runFirebreak = () => {
  const localRoot = resolveLocalRoot()
  const flakeRef = resolveFlakeRef(localRoot)
  const firebreakLibexecDir = resolveLibexecDir(localRoot)
  const reporter = createReporter(flakeRef)

  if (reporter) {
    reporter.start()
  }

  const result = spawnSync(
    "bash",
    [path.join(firebreakLibexecDir, "firebreak.sh"), ...args],
    {
      cwd: process.cwd(),
      env: {
        ...process.env,
        FIREBREAK_FLAKE_REF: flakeRef,
        FIREBREAK_LIBEXEC_DIR: firebreakLibexecDir
      },
      stdio: "inherit"
    }
  )

  if (reporter) {
    reporter.stop(result.status === 0)
  }

  if (result.error) {
    fail(`unable to launch Firebreak shell entrypoint: ${result.error.message}`)
  }

  if (result.status === null && result.signal) {
    process.kill(process.pid, result.signal)
    return;
  }

  process.exit(result.status === null ? 1 : result.status)
}

checkPlatform()
if (commandRequiresNix()) {
  checkNix()
}
checkKvm()
checkWorkspacePath()
runFirebreak()
