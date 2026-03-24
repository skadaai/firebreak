#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");

const GITHUB_FLAKE_REF = "github:skadaai/firebreak#firebreak";
const LOCAL_ROOT_MARKERS = [
  ["flake.nix"],
  ["modules", "base", "host", "firebreak.sh"]
];

const kvmPath = process.env.FIREBREAK_LAUNCHER_KVM_PATH || "/dev/kvm";
const forcedLocalRoot = process.env.FIREBREAK_LAUNCHER_PACKAGE_ROOT || "";
const args = process.argv.slice(2);
const topLevelCommand = args[0] || "";
const HELP_COMMANDS = new Set(["", "help", "-h", "--help"]);

const fail = (message) => {
  console.error(`firebreak launcher: ${message}`);
  process.exit(1);
}

const warn = (message) => {
  console.error(`firebreak launcher: ${message}`);
}

const checkPlatform = () => {
  if (process.platform !== "linux") {
    fail("Firebreak currently requires a Linux host.");
  }

  if (process.arch !== "x64") {
    fail("Firebreak currently targets x86_64 Linux hosts.");
  }
}

const checkNix = () => {
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

const pathExists = (targetPath) => {
  try {
    fs.accessSync(targetPath);
    return true;
  } catch {
    return false;
  }
}

const looksLikeFirebreakRoot = (candidateRoot) => {
  return LOCAL_ROOT_MARKERS.every((segments) =>
    pathExists(path.join(candidateRoot, ...segments))
  );
}

const findLocalFirebreakRoot = (startDir) => {
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

const resolveFlakeRef = () => {
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

const kvmFailureReason = () => {
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

const commandAllowsMissingKvm = () => (
  HELP_COMMANDS.has(topLevelCommand) ||
  topLevelCommand === "init" ||
  topLevelCommand === "doctor" ||
  topLevelCommand === "vms"
);

const checkKvm = () => {
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

const checkWorkspacePath = () => {
  if (/\s/.test(process.cwd())) {
    warn("the current working directory contains whitespace; local VM launch will fail until you move it.");
  }
}

const describeLaunch = () => {
  switch (topLevelCommand) {
    case "init":
      return "Loading Firebreak project setup";
    case "doctor":
      return "Loading Firebreak diagnostics";
    case "vms":
      return "Loading Firebreak VM catalog";
    case "run":
      return `Preparing Firebreak VM${args[1] ? ` '${args[1]}'` : ""}`;
    case "internal":
      return "Loading Firebreak internal command";
    case "":
    case "help":
    case "-h":
    case "--help":
      return "Loading Firebreak help";
    default:
      return "Loading Firebreak CLI";
  }
}

const describeFlakeSource = (flakeRef) => (
  flakeRef.startsWith("path:") ? "local checkout" : "GitHub"
);

const formatElapsed = (elapsedMs) => `${(elapsedMs / 1000).toFixed(1)}s`;
const interpolate = (start, end, progress) => start + (end - start) * progress;
const easeOutCubic = (progress) => 1 - Math.pow(1 - progress, 3);

const easeInOutQuad = (progress) => {
  if (progress < 0.5) {
    return 2 * progress * progress;
  }

  return 1 - Math.pow(-2 * progress + 2, 2) / 2;
}

const estimateProgress = (elapsedMs) => {
  if (elapsedMs <= 5000) {
    return Math.round(interpolate(4, 18, easeOutCubic(elapsedMs / 5000)));
  }

  if (elapsedMs <= 15000) {
    return Math.round(interpolate(18, 42, easeOutCubic((elapsedMs - 5000) / 10000)));
  }

  if (elapsedMs <= 35000) {
    return Math.round(interpolate(42, 72, easeInOutQuad((elapsedMs - 15000) / 20000)));
  }

  if (elapsedMs <= 90000) {
    return Math.round(interpolate(72, 92, easeInOutQuad((elapsedMs - 35000) / 55000)));
  }

  const tailProgress = 92 + Math.log1p((elapsedMs - 90000) / 30000) * 2;
  return Math.min(98, Math.round(tailProgress));
}

const createFallbackReporter = (label, flakeRef) => {
  const startMs = Date.now();
  const flakeSource = describeFlakeSource(flakeRef);

  return {
    start() {
      process.stderr.write(`firebreak launcher: ${label} via ${flakeSource}...\n`);
    },
    stop(success) {
      const elapsed = formatElapsed(Date.now() - startMs);
      process.stderr.write(`firebreak launcher: ${success ? "ready" : "stopped"} after ${elapsed}.\n`);
    }
  }
}

const createLoadingReporter = async (label, flakeRef) => {
  const fallbackReporter = createFallbackReporter(label, flakeRef);

  try {
    const oraModule = await import("ora");
    const ora = oraModule.default;
    const startMs = Date.now();
    const flakeSource = describeFlakeSource(flakeRef);
    let reminderVisible = false;
    const spinner = ora({
      text: `${label} via ${flakeSource}`,
      stream: process.stderr,
      discardStdin: false
    });
    let progressTimer = null;
    let reminderTimer = null;

    const spinnerText = () => {
      const elapsedMs = Date.now() - startMs;
      const progress = estimateProgress(elapsedMs);
      const reminder = reminderVisible ? " • warming caches on first run" : "";
      return `${label} via ${flakeSource} (${progress}% • ${formatElapsed(elapsedMs)}${reminder})`;
    }

    return {
      start() {
        if (!process.stderr.isTTY) {
          fallbackReporter.start();
          return;
        }

        spinner.text = spinnerText();
        spinner.start();
        progressTimer = setInterval(() => {
          spinner.text = spinnerText();
        }, 120);
        reminderTimer = setTimeout(() => {
          reminderVisible = true;
          spinner.text = spinnerText();
        }, 4000);
      },
      stop(success) {
        if (!process.stderr.isTTY) {
          fallbackReporter.stop(success);
          return;
        }

        if (progressTimer) {
          clearInterval(progressTimer);
        }
        if (reminderTimer) {
          clearTimeout(reminderTimer);
        }

        const elapsed = formatElapsed(Date.now() - startMs);
        if (success) {
          spinner.succeed(`Firebreak ready after ${elapsed}`);
        } else {
          spinner.fail(`Firebreak stopped after ${elapsed}`);
        }
      }
    }
  } catch {
    return fallbackReporter;
  }
}

const runFirebreak = async () => {
  const flakeRef = resolveFlakeRef();
  const reporter = await createLoadingReporter(describeLaunch(), flakeRef);
  reporter.start();

  const child = spawn(
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

  child.on("error", (error) => {
    reporter.stop(false);
    fail(`unable to launch Firebreak through Nix: ${error.message}`);
  });

  child.on("exit", (status, signal) => {
    reporter.stop(status === 0);

    if (status === null && signal) {
      process.kill(process.pid, signal);
      return;
    }

    process.exit(status === null ? 1 : status);
  });
}

const main = async () => {
  checkPlatform();
  checkNix();
  checkKvm();
  checkWorkspacePath();
  await runFirebreak();
}

main().catch((error) => {
  fail(`unexpected launcher error: ${error.message}`);
});
