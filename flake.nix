{
  description = "Bluehood — Bluetooth neighborhood monitor";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.python3Packages.buildPythonApplication {
            pname = "bluehood";
            version = "0.2.0";
            pyproject = true;

            src = pkgs.fetchFromGitHub {
              owner = "dannymcc";
              repo = "bluehood";
              rev = "d79d4940046bd134a05e0256c03871c6cffd4c31";
              hash = "sha256-G0DzFD53Cw1aUbCOg/IJZNlXDoE1+20SQiXg5Gg+v2c=";
            };

            build-system = [ pkgs.python3Packages.setuptools ];

            dependencies = with pkgs.python3Packages; [
              bleak
              aiosqlite
              aiohttp
              mac-vendor-lookup
            ];

            postInstall = ''
              wrapProgram $out/bin/bluehood \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.bluez ]}
            '';

            nativeBuildInputs = [ pkgs.makeWrapper ];

            meta = {
              description = "Monitor your local neighbourhood's Bluetooth activity";
              homepage = "https://github.com/dannymcc/bluehood";
              license = pkgs.lib.licenses.mit;
              mainProgram = "bluehood";
              platforms = pkgs.lib.platforms.linux;
            };
          };
        });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              (python3.withPackages (ps: with ps; [
                bleak
                aiosqlite
                aiohttp
                mac-vendor-lookup
                pip
              ]))
              bluez
              makeWrapper
            ];

            shellHook = ''
              echo "bluehood dev shell"
              echo "Run: sudo bluehood  (or grant caps first)"
              echo "  sudo setcap 'cap_net_admin,cap_net_raw+eip' \$(readlink -f \$(which python3))"
            '';
          };
        });

      # Home Manager module
      #
      # Usage in your home.nix / flake:
      #
      #   inputs.bluehood.url = "github:you/bluehood-flake";
      #
      #   home-manager.users.you = { imports = [ inputs.bluehood.homeManagerModules.default ]; ... };
      #
      # ⚠  Bluetooth scanning requires CAP_NET_ADMIN + CAP_NET_RAW.
      #    On NixOS, grant them at the system level:
      #
      #      security.wrappers.bluehood = {
      #        source = "${inputs.bluehood.packages.${system}.default}/bin/bluehood";
      #        capabilities = "cap_net_admin,cap_net_raw+eip";
      #        owner = "root"; group = "root";
      #      };
      #
      #    Then set `services.bluehood.package = /run/wrappers/bin/bluehood;`
      #    or just run the service as root via a NixOS systemd service instead.
      homeManagerModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.bluehood;
          defaultPkg = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        in
        {
          options.services.bluehood = {
            enable = lib.mkEnableOption "Bluehood Bluetooth neighborhood monitor";

            package = lib.mkOption {
              type = lib.types.package;
              default = defaultPkg;
              defaultText = lib.literalExpression "bluehood from this flake";
              description = "The bluehood package to use.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 8080;
              example = 9000;
              description = "Port for the web dashboard.";
            };

            adapter = lib.mkOption {
              type = lib.types.str;
              default = "auto";
              example = "hci0";
              description = "Bluetooth adapter to use (auto-detects when set to \"auto\").";
            };

            dataDir = lib.mkOption {
              type = lib.types.str;
              # %h expands to the home directory inside the unit
              default = "%h/.local/share/bluehood";
              description = "Directory for bluehood's SQLite database.";
            };

            extraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              example = [ "--no-web" ];
              description = "Additional arguments passed verbatim to bluehood.";
            };
          };

          config = lib.mkIf cfg.enable {
            systemd.user.services.bluehood = {
              Unit = {
                Description = "Bluehood Bluetooth neighborhood monitor";
                Documentation = "https://github.com/dannymcc/bluehood";
                # Start after the user's session bluetooth target if present.
                After = [ "bluetooth.target" ];
              };

              Service = {
                ExecStart = lib.escapeShellArgs (
                  [ "${cfg.package}/bin/bluehood"
                    "--port" (toString cfg.port)
                    "--adapter" cfg.adapter
                  ] ++ cfg.extraArgs
                );

                Environment = [
                  "BLUEHOOD_DATA_DIR=${cfg.dataDir}"
                ];

                Restart = "on-failure";
                RestartSec = "5s";

                # Bluetooth scanning requires these capabilities.
                # They are silently ignored if not in the user's bounding set —
                # see the module comment above for the NixOS security.wrappers approach.
                AmbientCapabilities = "CAP_NET_ADMIN CAP_NET_RAW";
                CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW";
              };

              Install = {
                WantedBy = [ "default.target" ];
              };
            };
          };
        };
    };
}
