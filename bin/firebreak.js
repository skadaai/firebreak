#!/usr/bin/env node

const fs = require("node:fs")
const path = require("node:path")
const { spawn, spawnSync } = require("node:child_process")

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
const LOCAL_ONLY_COMMANDS = new Set(["", "help", "-h", "--help", "init", "doctor", "vms"])
const ORA_SPINNER_NAME = "dots"

const args = process.argv.slice(2)
const topLevelCommand = args[0] || "";
const forcedLocalRoot = process.env.FIREBREAK_LAUNCHER_PACKAGE_ROOT || "";
const kvmPath = process.env.FIREBREAK_LAUNCHER_KVM_PATH || "/dev/kvm";
const forcedIpForwardState = process.env.FIREBREAK_LAUNCHER_IP_FORWARD_STATE || "";
const forcedSudoNetworkingState = process.env.FIREBREAK_LAUNCHER_SUDO_NETWORKING_STATE || "";
const nixHelpersDisabled = process.env.FIREBREAK_LAUNCHER_DISABLE_NIX_HELPERS === "1"
const launcherPlatform = process.env.FIREBREAK_LAUNCHER_TEST_PLATFORM || process.platform
const launcherArch = process.env.FIREBREAK_LAUNCHER_TEST_ARCH || process.arch
const supportedLinuxArchitectures = new Map([
  ["x64", "x86_64-linux"],
  ["arm64", "aarch64-linux"]
])

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
  if (launcherPlatform === "linux" && supportedLinuxArchitectures.has(launcherArch)) {
    return;
  }

  if (launcherPlatform === "darwin" && launcherArch === "arm64") {
    console.warn('Support on macOS is EXPERIMENTAL! Please report issues at https://github.com/skadaai/firebreak/issues')
    return;
  }

  if (launcherPlatform === "darwin") {
    fail("Firebreak local support on macOS requires Apple Silicon (arm64). Intel Macs are not supported.")
  }

  fail(`Firebreak currently targets ${Array.from(supportedLinuxArchitectures.values()).join(", ")} and aarch64-darwin hosts.`)
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

const ipForwardFailureReason = () => {
  if (forcedIpForwardState) {
    if (forcedIpForwardState === "enabled") {
      return null;
    }
    return "net.ipv4.ip_forward is disabled";
  }

  try {
    const raw = fs.readFileSync("/proc/sys/net/ipv4/ip_forward", "utf8").trim()
    return raw === "1" ? null : "net.ipv4.ip_forward is disabled";
  } catch (error) {
    return `unable to read net.ipv4.ip_forward: ${error.message}`;
  }
}

const commandExists = (command, argsForCheck) => {
  const result = spawnSync(command, argsForCheck, {
    stdio: "ignore"
  })

  return !result.error || result.error.code !== "ENOENT"
}

const sudoNetworkingFailureReason = () => {
  if (forcedSudoNetworkingState) {
    switch (forcedSudoNetworkingState) {
      case "enabled":
        return null
      case "missing-tools":
        return "host networking tools ip and iptables are required"
      case "missing-sudo":
        return "passwordless sudo is required for Firebreak host networking commands"
      case "networking-denied":
        return "passwordless sudo is required for Firebreak host networking commands"
      case "firewall-denied":
        return "passwordless sudo is required for Firebreak host firewall commands"
      default:
        return `invalid FIREBREAK_LAUNCHER_SUDO_NETWORKING_STATE: ${forcedSudoNetworkingState}`
    }
  }

  if (!commandExists("ip", ["link", "show"]) || !commandExists("iptables", ["--version"])) {
    return "host networking tools ip and iptables are required"
  }

  if (!commandExists("sudo", ["-n", "true"])) {
    return "passwordless sudo is required for Firebreak host networking commands"
  }

  const sudoIp = spawnSync("sudo", ["-n", "ip", "link", "show"], {
    stdio: "ignore"
  })
  if (sudoIp.status !== 0) {
    return "passwordless sudo is required for Firebreak host networking commands"
  }

  const sudoIptables = spawnSync("sudo", ["-n", "iptables", "-w", "-L"], {
    stdio: "ignore"
  })
  if (sudoIptables.status !== 0) {
    return "passwordless sudo is required for Firebreak host firewall commands"
  }

  return null
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

const commandRequiresNix = () => {
  if (LOCAL_ONLY_COMMANDS.has(topLevelCommand)) {
    return false
  }

  if (topLevelCommand === "run") {
    return runCommandRequiresNix()
  }

  if (topLevelCommand === "internal") {
    return internalCommandRequiresNix()
  }

  return true
}

const needsNix = commandRequiresNix()
const commandUsesOra = () => runCommandRequiresNix()

const checkLinuxLocalHost = () => {
  if (launcherPlatform !== "linux") {
    return;
  }

  const failure = kvmFailureReason() || ipForwardFailureReason() || sudoNetworkingFailureReason()
  if (!failure) {
    return;
  }

  if (!commandRequiresNix()) {
    warn(`${failure}. Continuing because this command can still provide setup or diagnostics help.`)
    return;
  }

  fail(`${failure}. Firebreak local Linux workloads require KVM access, net.ipv4.ip_forward=1, and passwordless sudo for host networking commands.`)
}

const checkWorkspacePath = () => {
  if (/\s/.test(process.cwd())) {
    warn("the current working directory contains whitespace; local VM launch will fail until you move it.")
  }
}

const formatElapsed = (elapsedMs) => `${(elapsedMs / 1000).toFixed(1)}s`;

const interpolate = (start, end, progress) => start + (end - start) * progress
const easeOutCubic = (progress) => 1 - Math.pow(1 - progress, 3)
const easeInOutQuad = (progress) => (
  progress < 0.5
    ? 2 * progress * progress
    : 1 - Math.pow(-2 * progress + 2, 2) / 2
)

const estimateProgress = (elapsedMs) => {
  if (elapsedMs <= 5000) {
    return Math.round(interpolate(4, 18, easeOutCubic(elapsedMs / 5000)))
  }

  if (elapsedMs <= 15000) {
    return Math.round(interpolate(18, 42, easeOutCubic((elapsedMs - 5000) / 10000)))
  }

  if (elapsedMs <= 35000) {
    return Math.round(interpolate(42, 72, easeInOutQuad((elapsedMs - 15000) / 20000)))
  }

  if (elapsedMs <= 90000) {
    return Math.round(interpolate(72, 92, easeInOutQuad((elapsedMs - 35000) / 55000)))
  }

  const tailProgress = 92 + Math.log1p((elapsedMs - 90000) / 30000) * 2
  return Math.min(98, Math.round(tailProgress))
}

const createFallbackReporter = (flakeRef) => {
  if (!needsNix) {
    return null
  }

  const startMs = Date.now()
  const flakeSource = flakeRef.startsWith("path:") ? "local checkout" : "GitHub";

  if (!commandUsesOra()) {
    return {
      start() {
        process.stderr.write(`firebreak launcher: loading Firebreak via ${flakeSource}...\n`)
      },
      clear() {
      },
      stop(success) {
        process.stderr.write(
          `firebreak launcher: ${success ? "ready" : "stopped"} after ${formatElapsed(Date.now() - startMs)}.\n`
        )
      }
    }
  }

  let spinnerIndex = 0
  let progressTimer = null
  let reminderVisible = false
  let reminderTimer = null
  const spinnerFrames = ["|", "/", "-", "\\"]

  const spinnerText = () => {
    const elapsedMs = Date.now() - startMs
    const progress = estimateProgress(elapsedMs)
    const reminder = reminderVisible ? " • warming caches on first run" : ""
    return `firebreak launcher: ${spinnerFrames[spinnerIndex % spinnerFrames.length]} Preparing Firebreak VM via ${flakeSource} (${progress}% • ${formatElapsed(elapsedMs)}${reminder})`
  }

  return {
    start() {
      if (!process.stderr.isTTY) {
        process.stderr.write(`firebreak launcher: loading Firebreak via ${flakeSource}...\n`)
        return
      }

      process.stderr.write(`${spinnerText()}\r`)
      progressTimer = setInterval(() => {
        spinnerIndex += 1
        process.stderr.write(`${spinnerText()}\r`)
      }, 120)
      reminderTimer = setTimeout(() => {
        reminderVisible = true
      }, 4000)
    },
    clear() {
      if (progressTimer) {
        clearInterval(progressTimer)
        progressTimer = null
      }
      if (reminderTimer) {
        clearTimeout(reminderTimer)
        reminderTimer = null
      }

      if (process.stderr.isTTY) {
        process.stderr.write("\r")
      }
    },
    stop(success) {
      if (progressTimer) {
        clearInterval(progressTimer)
        progressTimer = null
      }
      if (reminderTimer) {
        clearTimeout(reminderTimer)
        reminderTimer = null
      }

      if (process.stderr.isTTY) {
        process.stderr.write("\n")
      }
      process.stderr.write(
        `firebreak launcher: ${success ? "ready" : "stopped"} after ${formatElapsed(Date.now() - startMs)}.\n`
      )
    }
  }
}

const createReporter = async (flakeRef) => {
  const fallbackReporter = createFallbackReporter(flakeRef)
  if (!commandUsesOra()) {
    return fallbackReporter
  }

  try {
    const oraModule = await import("ora")
    const ora = oraModule.default
    const startMs = Date.now()
    const flakeSource = flakeRef.startsWith("path:") ? "local checkout" : "GitHub"
    const spinner = ora({
      text: "",
      stream: process.stderr,
      discardStdin: false,
      spinner: ORA_SPINNER_NAME
    })
    let reminderVisible = false
    let progressTimer = null
    let reminderTimer = null

    const spinnerText = () => {
      const elapsedMs = Date.now() - startMs
      const progress = estimateProgress(elapsedMs)
      const reminder = reminderVisible ? " • warming caches on first run" : ""
      return `Preparing Firebreak VM via ${flakeSource} (${progress}% • ${formatElapsed(elapsedMs)}${reminder})`
    }

    return {
      start() {
        if (!process.stderr.isTTY) {
          fallbackReporter?.start()
          return
        }

        spinner.text = spinnerText()
        spinner.start()
        progressTimer = setInterval(() => {
          spinner.text = spinnerText()
        }, 120)
        reminderTimer = setTimeout(() => {
          reminderVisible = true
          spinner.text = spinnerText()
        }, 4000)
      },
      clear() {
        if (!process.stderr.isTTY) {
          fallbackReporter?.clear?.()
          return
        }

        if (progressTimer) {
          clearInterval(progressTimer)
          progressTimer = null
        }
        if (reminderTimer) {
          clearTimeout(reminderTimer)
          reminderTimer = null
        }

        if (spinner.isSpinning) {
          spinner.stop()
        }
      },
      stop(success) {
        if (!process.stderr.isTTY) {
          fallbackReporter?.stop(success)
          return
        }

        if (progressTimer) {
          clearInterval(progressTimer)
          progressTimer = null
        }
        if (reminderTimer) {
          clearTimeout(reminderTimer)
          reminderTimer = null
        }

        const elapsed = formatElapsed(Date.now() - startMs)
        if (success) {
          spinner.succeed(`Firebreak ready after ${elapsed}`)
        } else {
          spinner.fail(`Firebreak stopped after ${elapsed}`)
        }
      }
    }
  } catch {
    return fallbackReporter
  }
}

const runFirebreak = async () => {
  const localRoot = resolveLocalRoot()
  const flakeRef = needsNix ? resolveFlakeRef(localRoot) : ""
  const firebreakLibexecDir = resolveLibexecDir(localRoot)
  const reporter = await createReporter(flakeRef)

  if (reporter) {
    reporter.start()
  }

  let result
  try {
    result = await new Promise((resolve, reject) => {
      const child = spawn(
        "bash",
        [path.join(firebreakLibexecDir, "firebreak.sh"), ...args],
        {
          cwd: process.cwd(),
          env: {
            ...process.env,
            FIREBREAK_LIBEXEC_DIR: firebreakLibexecDir,
            FIREBREAK_FLAKE_REF: flakeRef,
            FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG: needsNix && !nixHelpersDisabled ? "1" : "",
            FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES: needsNix && !nixHelpersDisabled ? "nix-command flakes" : ""
          },
          stdio: "inherit"
        }
      )

      child.on("error", reject)
      child.on("exit", (status, signal) => {
        resolve({ status, signal })
      })
    })
  } catch (error) {
    reporter?.stop(false)
    fail(`unable to launch Firebreak shell entrypoint: ${error.message}`)
  }

  if (reporter) {
    reporter.stop(result.status === 0)
  }

  if (result.status === null && result.signal) {
    process.kill(process.pid, result.signal)
    return
  }

  process.exit(result.status === null ? 1 : result.status)
}

checkPlatform()
if (needsNix) {
  checkNix()
}
checkLinuxLocalHost()
checkWorkspacePath()
runFirebreak().catch((error) => {
  fail(`unexpected launcher error: ${error.message}`)
})
