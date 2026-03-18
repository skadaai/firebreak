{ lib, pkgs, renderTemplate }:
let
  devUser = "dev";
  devHome = "/var/lib/${devUser}";
  workspaceMount = "/workspace";
  hostMetaMount = "/run/microvm-host-meta";
  startDirFile = "/run/microvm-start-dir";

  qemu9pOptions = [
    "nofail"
    "trans=virtio"
    "version=9p2000.L"
    "msize=65536"
    "x-systemd.after=systemd-modules-load.service"
  ];

  scriptVars = {
    "@BASH@" = "${pkgs.bashInteractive}/bin/bash";
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = devUser;
    "@HOST_META_MOUNT@" = hostMetaMount;
    "@START_DIR_FILE@" = startDirFile;
    "@WORKSPACE_MOUNT@" = workspaceMount;
  };

  runtimeExtraArgsScript = pkgs.writeShellScript "microvm-runtime-extra-args"
    (renderTemplate scriptVars ../scripts/runtime-extra-args.sh);

  devConsoleStartScript = pkgs.writeShellScript "dev-console-start"
    (renderTemplate scriptVars ../scripts/dev-console-start.sh);
in {
  networking.hostName = "my-microvm";
  networking.useDHCP = true;

  users.users.root.password = "";
  users.users.${devUser} = {
    isNormalUser = true;
    password = "";
    extraGroups = [ "wheel" ];
    home = devHome;
    createHome = true;
    shell = pkgs.bashInteractive;
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    bun
    git
    nodejs
  ];

  programs.bash.interactiveShellInit =
    renderTemplate scriptVars ../scripts/dev-shell-init.sh;

  systemd.services.dev-bootstrap = {
    description = "Install persistent developer tools before login";
    wantedBy = [ "multi-user.target" ];
    before = [ "getty.target" "serial-getty@ttyS0.service" ];
    after = [ "local-fs.target" "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };

    path = with pkgs; [
      bun
      coreutils
    ];

    script = renderTemplate scriptVars ../scripts/dev-bootstrap.sh;
  };

  fileSystems.${workspaceMount} = {
    device = "hostcwd";
    fsType = "9p";
    options = qemu9pOptions;
  };

  fileSystems.${hostMetaMount} = {
    device = "hostmeta";
    fsType = "9p";
    options = qemu9pOptions ++ [ "ro" ];
  };

  systemd.services.link-host-cwd = {
    description = "Bind mount /workspace at the launch-time host cwd";
    wantedBy = [ "multi-user.target" ];
    before = [ "dev-console.service" ];
    after = [ "local-fs.target" ];

    path = with pkgs; [
      coreutils
      util-linux
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };

    script = renderTemplate scriptVars ../scripts/link-host-cwd.sh;
  };

  systemd.services."serial-getty@ttyS0".enable = false;

  systemd.services.dev-console = {
    description = "Interactive dev shell on ttyS0";
    wantedBy = [ "multi-user.target" ];
    after = [ "dev-bootstrap.service" "link-host-cwd.service" ];
    requires = [ "dev-bootstrap.service" "link-host-cwd.service" ];
    conflicts = [ "serial-getty@ttyS0.service" ];

    serviceConfig = {
      User = devUser;
      WorkingDirectory = devHome;
      StandardInput = "tty-force";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/ttyS0";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
      Restart = "always";
      RestartSec = 0;
      Type = "idle";
      ExecStart = devConsoleStartScript;
    };
  };

  microvm = {
    extraArgsScript = "${runtimeExtraArgsScript}";
    interfaces = [ {
      type = "user";
      id = "vm-user";
      mac = "02:00:00:00:00:01";
    } ];
    volumes = [ {
      mountPoint = "/var";
      image = "var.img";
      size = 2048;
    } ];
    shares = [ {
      # use proto = "virtiofs" for MicroVMs that are started by systemd
      proto = "9p";
      tag = "ro-store";
      # a host's /nix/store will be picked up so that no
      # squashfs/erofs will be built for it.
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
    } ];

    # "qemu" has 9p built-in!
    hypervisor = "qemu";
    socket = "control.socket";
  };
}
