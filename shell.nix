{ pkgs, pre-commit-hooks, system, toolchain }:
let
  pre-commit-check = pre-commit-hooks.lib.${system}.run {
    src = ./.;
    hooks = {
      nixpkgs-fmt.enable = true;
      rustfmt = {
        enable = true;
        package = toolchain;
      };
      #      clippy = {
      #        enable = true;
      #        package = toolchain;
      #        args = [ "-- -D unused_imports" ];
      #      };
    };
  };
in
pkgs.mkShell rec {
  buildInputs = with pkgs; [
    toolchain
    xorg.libXcursor
    xorg.libXrandr
    xorg.libXi
    xorg.libX11
    libxkbcommon
    libGL
    alsa-lib
    pkg-config
    cmake
    udev
    vulkan-loader
    rustPlatform.bindgenHook
    bashInteractive
    openssl
    openssl.dev
    fontconfig

  ] ++ pre-commit-check.enabledPackages;
  LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath buildInputs}";
  RUST_SRC_PATH = "${toolchain}/lib/rustlib/src/rust/library";
  shellHook = ''
    ${pre-commit-check.shellHook}
  '';
}
