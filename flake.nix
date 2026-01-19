{
  description = "Motion Planning Research - Headless 3D Generation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    pre-commit-hooks = { url = "github:cachix/pre-commit-hooks.nix"; };
    rust-overlay = { url = "github:oxalica/rust-overlay"; };
    crane = { url = "github:ipetkov/crane"; };
  };

  outputs = { self, nixpkgs, pre-commit-hooks, rust-overlay, crane }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ rust-overlay.overlays.default ];
      };

      rustToolchainFor = system: (pkgsFor system).rust-bin.stable.latest.default.override {
        extensions = [ "rust-src" "rustfmt" "clippy" ];
      };
    in
    {
      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);

      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          toolchain = rustToolchainFor system;
          craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;

          shaderFilter = path: type:
            (builtins.match ".*\\.frag$" path != null) ||
            (builtins.match ".*\\.vert$" path != null) ||
            (builtins.match ".*\\.glsl$" path != null) ||
            (craneLib.filterCargoSources path type);

          # These are the critical dependencies for modern Headless EGL
          runtimeDeps = with pkgs; [
            libglvnd # Provides libEGL and the dispatch layer
            mesa.drivers # Provides the llvmpipe (software) driver
            libxkbcommon # Often required by glutin/winit even in headless mode
            openssl
            cmake
            fontconfig
            xorg.libX11
            xorg.libXcursor
            xorg.libXi
            xorg.libXrandr
          ];
        in
        {
          # The package that builds the lib and runs the headless example
          headless-example = craneLib.buildPackage {
            src = craneLib.path ./.;
            strictDeps = true;

            nativeBuildInputs = with pkgs; [
              pkg-config
              cmake # <--- Added this to fix the "No such file or directory" error
              openssl.dev # Ensures headers and pkg-config files are available
            ];
            buildInputs = runtimeDeps;

            # We execute the example during the build process.
            # This ensures the output PNGs are part of the Nix store result.
            postBuild = ''
              export HOME=$TMPDIR
              export XDG_RUNTIME_DIR=$TMPDIR/runtime
              mkdir -p $XDG_RUNTIME_DIR
              chmod 0700 $XDG_RUNTIME_DIR

              # 1. Setup the EGL Surfaceless environment
              # This bypasses the need for X11, Wayland, or OSMesa
              export LD_LIBRARY_PATH="${pkgs.libglvnd}/lib:${pkgs.mesa.drivers}/lib:${pkgs.libxkbcommon}/lib:$LD_LIBRARY_PATH"
              export EGL_VENDOR_CONFIG_DIRS=${pkgs.mesa.drivers}/share/glvnd/egl_vendor.d
              export LIBGL_DRIVERS_PATH=${pkgs.mesa.drivers}/lib/dri

              # 2. Force the software rasterizer
              export GALLIUM_DRIVER=llvmpipe
              export LIBGL_ALWAYS_SOFTWARE=1
              export EGL_PLATFORM=surfaceless

              echo "Verified EGL Driver Configs:"
              ls $EGL_VENDOR_CONFIG_DIRS

              echo "Running three-d headless example..."
              # Running through cargo to ensure example-specific dependencies are handled
              cargo run --example headless --release --features="headless"
            '';

            installPhase = ''
              mkdir -p $out/bin
              mkdir -p $out/share/images

              # Copy any generated images to a share directory
              cp *.png $out/share/images/ 2>/dev/null || true

              # Copy the compiled example binary
              cp target/release/examples/headless $out/bin/
            '';
          };

          default = self.packages.${system}.headless-example;
        });

      devShells = forAllSystems (system: {
        default = (pkgsFor system).callPackage ./shell.nix {
          inherit pre-commit-hooks;
          inherit system;
          toolchain = rustToolchainFor system;
        };
      });
    };
}
