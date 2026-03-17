{
  description = "NixOS in MicroVMs";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [ "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" ];
  };

  inputs.microvm = {
    url = "github:microvm-nix/microvm.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages.${system} = {
        default = self.packages.${system}.my-microvm;
        my-microvm-runner = self.nixosConfigurations.my-microvm.config.microvm.declaredRunner;
        my-microvm = pkgs.writeShellApplication {
          name = "my-microvm";
          runtimeInputs = with pkgs; [ coreutils ];
          text = ''
            set -eu

            host_cwd=$PWD
            case "$host_cwd" in
              *[[:space:]]*)
                echo "current working directory contains whitespace, which microvm runtime share injection does not support: $host_cwd" >&2
                exit 1
                ;;
            esac

            host_meta_dir=$(mktemp -d)
            trap 'rm -rf "$host_meta_dir"' EXIT INT TERM

            printf '%s\n' "$host_cwd" > "$host_meta_dir/mount-path"

            exec env \
              MICROVM_HOST_CWD="$host_cwd" \
              MICROVM_HOST_META_DIR="$host_meta_dir" \
              ${self.packages.${system}.my-microvm-runner}/bin/microvm-run "$@"
          '';
        };
      };

      nixosConfigurations = {
        my-microvm = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            microvm.nixosModules.microvm
            {
              networking.hostName = "my-microvm";
              networking.useDHCP = true;
              users.users.root.password = "";
              users.users.dev = {
                isNormalUser = true;
                password = "";
                extraGroups = [ "wheel" ];
                home = "/var/lib/dev";
                createHome = true;
                shell = nixpkgs.legacyPackages.${system}.bashInteractive;
              };

              security.sudo.wheelNeedsPassword = false;

              environment.systemPackages = with nixpkgs.legacyPackages.${system}; [
                bun
                git
                nodejs
              ];

              programs.bash.interactiveShellInit = ''
                if [ "$USER" = "dev" ]; then
                  export BUN_INSTALL=/var/lib/dev/.bun
                  export XDG_CONFIG_HOME=/var/lib/dev/.config
                  export XDG_CACHE_HOME=/var/lib/dev/.cache
                  export XDG_STATE_HOME=/var/lib/dev/.local/state
                  export PATH="$BUN_INSTALL/bin:$PATH"
                  cdw() {
                    target=/workspace
                    if [ -r /run/microvm-start-dir ]; then
                      target=$(cat /run/microvm-start-dir)
                    fi
                    cd "$target"
                  }
                fi
              '';

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

                path = with nixpkgs.legacyPackages.${system}; [
                  bun
                  coreutils
                ];

                script = ''
                  set -eu

                  export DEV_HOME=/var/lib/dev
                  export HOME="$DEV_HOME"
                  export BUN_INSTALL="$DEV_HOME/.bun"
                  export XDG_CONFIG_HOME="$DEV_HOME/.config"
                  export XDG_CACHE_HOME="$DEV_HOME/.cache"
                  export XDG_STATE_HOME="$DEV_HOME/.local/state"
                  export PATH="$BUN_INSTALL/bin:$PATH"

                  echo "Preparing persistent development tools..."

                  mkdir -p \
                    "$BUN_INSTALL/bin" \
                    "$XDG_CONFIG_HOME" \
                    "$XDG_CACHE_HOME" \
                    "$XDG_STATE_HOME"
                  chown -R dev:users "$DEV_HOME"

                  if ! [ -x "$BUN_INSTALL/bin/codex" ]; then
                    echo "Installing Codex CLI into persistent storage..."
                    bun install --global @openai/codex
                    chown -R dev:users "$DEV_HOME"
                  else
                    echo "Codex CLI already present."
                  fi
                '';
              };

              fileSystems."/workspace" = {
                device = "hostcwd";
                fsType = "9p";
                options = [
                  "nofail"
                  "trans=virtio"
                  "version=9p2000.L"
                  "msize=65536"
                  "x-systemd.after=systemd-modules-load.service"
                ];
              };

              fileSystems."/run/microvm-host-meta" = {
                device = "hostmeta";
                fsType = "9p";
                options = [
                  "nofail"
                  "ro"
                  "trans=virtio"
                  "version=9p2000.L"
                  "msize=65536"
                  "x-systemd.after=systemd-modules-load.service"
                ];
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

                script = ''
                  set -eu

                  metadata=/run/microvm-host-meta/mount-path
                  for _ in $(seq 1 50); do
                    if [ -d /workspace ] && [ -r "$metadata" ]; then
                      break
                    fi
                    sleep 0.1
                  done

                  if ! [ -d /workspace ] || ! [ -r "$metadata" ]; then
                    echo "workspace or host cwd metadata not ready; continuing without dynamic bind mount"
                    exit 0
                  fi

                  target=$(cat "$metadata")
                  if [ -z "$target" ]; then
                    exit 0
                  fi

                  printf '%s\n' "$target" > /run/microvm-start-dir
                  chmod 0644 /run/microvm-start-dir

                  if [ "$target" = "/workspace" ]; then
                    exit 0
                  fi

                  if [ -L "$target" ]; then
                    rm -f "$target"
                  fi

                  if mountpoint -q "$target"; then
                    exit 0
                  fi

                  parent=$(dirname "$target")
                  mkdir -p "$parent" "$target"

                  if [ -e "$target" ] && ! [ -d "$target" ]; then
                    echo "refusing to replace existing non-directory path: $target"
                    exit 0
                  fi

                  mount --bind /workspace "$target"
                '';
              };

              systemd.services."serial-getty@ttyS0".enable = false;

              systemd.services.dev-console = {
                description = "Interactive dev shell on ttyS0";
                wantedBy = [ "multi-user.target" ];
                after = [ "dev-bootstrap.service" "link-host-cwd.service" ];
                requires = [ "dev-bootstrap.service" "link-host-cwd.service" ];
                conflicts = [ "serial-getty@ttyS0.service" ];

                serviceConfig = {
                  User = "dev";
                  WorkingDirectory = "/var/lib/dev";
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
                  ExecStart = "${pkgs.bashInteractive}/bin/bash -lc 'target=/workspace; if [ -r /run/microvm-start-dir ]; then target=$(cat /run/microvm-start-dir); fi; if [ ! -d \"$target\" ]; then target=/workspace; fi; cd \"$target\"; exec ${pkgs.bashInteractive}/bin/bash -i'";
                };
              };

              microvm = {
                extraArgsScript = "${pkgs.writeShellScript "microvm-runtime-extra-args" ''
                  set -eu

                  if [ -z "''${MICROVM_HOST_CWD:-}" ]; then
                    exit 0
                  fi

                  printf '%s\n' \
                    -fsdev "local,id=fs-hostcwd,path=$MICROVM_HOST_CWD,security_model=none,readonly=false" \
                    -device "virtio-9p-pci,fsdev=fs-hostcwd,mount_tag=hostcwd"

                  if [ -n "''${MICROVM_HOST_META_DIR:-}" ]; then
                    printf '%s\n' \
                      -fsdev "local,id=fs-hostmeta,path=$MICROVM_HOST_META_DIR,security_model=none,readonly=true" \
                      -device "virtio-9p-pci,fsdev=fs-hostmeta,mount_tag=hostmeta"
                  fi
                ''}";
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
          ];
        };
      };
    };
}
