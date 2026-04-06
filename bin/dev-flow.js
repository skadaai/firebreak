#!/usr/bin/env node

const fs = require("node:fs")
const path = require("node:path")
const { spawn, spawnSync } = require("node:child_process")

const GITHUB_FLAKE_REF = "github:skadaai/firebreak";
const LOCAL_ROOT_MARKERS = [
  ["flake.nix"],
  ["modules", "base", "host", "dev-flow.sh"]
]
const LIBEXEC_FILES = [
  "dev-flow.sh",
  "firebreak-project-config.sh"
]
const HELP_COMMANDS = new Set(["", "help", "-h", "--help"])

const args = process.argv.slice(2)
const topLevelCommand = args[0] || ""
const forcedLocalRoot = process.env.DEV_FLOW_LAUNCHER_PACKAGE_ROOT || ""
const kvmPath = process.env.DEV_FLOW_LAUNCHER_KVM_PATH || "/dev/kvm"
const launcherPlatform = process.env.DEV_FLOW_LAUNCHER_TEST_PLATFORM || process.platform
const launcherArch = process.env.DEV_FLOW_LAUNCHER_TEST_ARCH || process.arch

const fail = (message) => {
  console.error(`dev-flow launcher: ${message}`)
  process.exit(1)
}

const warn = (message) => {
  console.error(`dev-flow launcher: ${message}`)
}

const pathExists = (targetPath) => {
  try {
    fs.accessSync(targetPath)
    return true
  } catch {
    return false
  }
}

const looksLikeRoot = (candidateRoot) => (
  LOCAL_ROOT_MARKERS.every((segments) => pathExists(path.join(candidateRoot, ...segments)))
)

const looksLikeLibexecDir = (candidateDir) => (
  LIBEXEC_FILES.every((fileName) => pathExists(path.join(candidateDir, fileName)))
)

const findLocalRoot = (startDir) => {
  let currentDir = path.resolve(startDir)
  while (true) {
    if (looksLikeRoot(currentDir)) {
      return currentDir
    }
    const parentDir = path.dirname(currentDir)
    if (parentDir === currentDir) {
      return null
    }
    currentDir = parentDir
  }
}

const resolveLocalRoot = () => {
  if (!forcedLocalRoot) {
    return findLocalRoot(process.cwd())
  }

  if (!looksLikeRoot(forcedLocalRoot)) {
    fail(`DEV_FLOW_LAUNCHER_PACKAGE_ROOT does not point to a Firebreak checkout: ${forcedLocalRoot}`)
  }

  return path.resolve(forcedLocalRoot)
}

const resolveFlakeRef = (localRoot) => (localRoot ? `path:${localRoot}` : GITHUB_FLAKE_REF)

const resolveLibexecDir = (localRoot) => {
  if (localRoot) {
    const localLibexecDir = path.join(localRoot, "modules", "base", "host")
    if (looksLikeLibexecDir(localLibexecDir)) {
      return localLibexecDir
    }
  }

  const packagedLibexecDir = path.resolve(__dirname, "..", "modules", "base", "host")
  if (looksLikeLibexecDir(packagedLibexecDir)) {
    return packagedLibexecDir
  }

  fail("unable to resolve the dev-flow shell runtime")
}

const checkPlatform = () => {
  if (launcherPlatform === "linux" && (launcherArch === "x64" || launcherArch === "arm64")) {
    return
  }

  if (launcherPlatform === "darwin" && launcherArch === "arm64") {
    return
  }

  if (launcherPlatform === "darwin") {
    fail("dev-flow on macOS requires Apple Silicon (arm64). Intel Macs are not supported.")
  }

  fail("dev-flow currently targets x86_64-linux, aarch64-linux, and aarch64-darwin hosts.")
}

const checkNix = () => {
  const result = spawnSync("nix", ["--version"], { encoding: "utf8" })
  if (result.error) {
    if (result.error.code === "ENOENT") {
      fail("Nix is not installed. Install Nix first, then run `npx dev-flow` again.")
    }
    fail(`unable to execute nix: [${result.error.code || "unknown"}] ${result.error.message}`)
  }
  if (result.status !== 0) {
    fail(`Nix is installed but unavailable: ${(result.stderr || result.stdout || "").trim()}`)
  }
}

const commandRequiresNix = () => !HELP_COMMANDS.has(topLevelCommand)

const checkKvm = () => {
  if (!commandRequiresNix() || launcherPlatform !== "linux") {
    return
  }

  try {
    fs.accessSync(kvmPath, fs.constants.R_OK | fs.constants.W_OK)
  } catch (error) {
    if (!fs.existsSync(kvmPath)) {
      fail(`${kvmPath} is missing. dev-flow needs KVM access to run local validation suites on Linux.`)
    }
    if (error && error.code === "EACCES") {
      fail(`${kvmPath} is not readable and writable by the current user. dev-flow needs KVM access on Linux.`)
    }
    fail(`${kvmPath} is not usable: ${error.message}`)
  }
}

const checkWorkspacePath = () => {
  if (/\s/.test(process.cwd())) {
    warn("the current working directory contains whitespace; local validation and workspace launch may fail until you move it.")
  }
}

const runDevFlow = async () => {
  const localRoot = resolveLocalRoot()
  const flakeRef = commandRequiresNix() ? resolveFlakeRef(localRoot) : ""
  const libexecDir = resolveLibexecDir(localRoot)

  const child = spawn(
    "bash",
    [path.join(libexecDir, "dev-flow.sh"), ...args],
    {
      cwd: process.cwd(),
      env: {
        ...process.env,
        DEV_FLOW_LIBEXEC_DIR: libexecDir,
        DEV_FLOW_FLAKE_REF: flakeRef,
        DEV_FLOW_NIX_ACCEPT_FLAKE_CONFIG: commandRequiresNix() ? "1" : "",
        DEV_FLOW_NIX_EXTRA_EXPERIMENTAL_FEATURES: commandRequiresNix() ? "nix-command flakes" : ""
      },
      stdio: "inherit"
    }
  )

  child.on("error", (error) => {
    fail(`unable to launch dev-flow shell entrypoint: ${error.message}`)
  })

  child.on("exit", (status, signal) => {
    if (status === null && signal) {
      process.kill(process.pid, signal)
      return
    }
    process.exit(status === null ? 1 : status)
  })
}

checkPlatform()
if (commandRequiresNix()) {
  checkNix()
}
checkKvm()
checkWorkspacePath()
runDevFlow().catch((error) => {
  fail(`unexpected launcher error: ${error.message}`)
})
