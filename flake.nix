{
    description = "Esp32 development environment";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/release-23.05";

        # Manage rust toolchain
        fenix = {
            url = "github:nix-community/fenix";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        # Build rust packages
        crane = {
            url = "github:ipetkov/crane";
            inputs.nixpkgs.follows = "nixpkgs";
            # inputs.flake-compat.follows = "flake-compat";
            # inputs.utils.follows = "utils";
        };
    };

    outputs = { self, nixpkgs, flake-utils, fenix, crane }: let
        system = "x86_64-linux";

        pkgs = import nixpkgs {
            inherit system;
        };

        # Rust toolchain used to build tools.
        toolchain = fenix.packages.${system}.fromToolchainFile {
            file = ./cli/rust-toolchain.toml;
            sha256 = "sha256-gdYqng0y9iHYzYPAdkC/ka3DRny3La/S5G8ASj0Ayyc=";
        };

        craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;

        cargo-generate = craneLib.buildPackage {
            src = craneLib.downloadCargoPackage {
                name = "cargo-generate";
                version = "0.18.3";
                checksum = "sha256-t7L2Jzgdx1IzQMYGVZ3d9gg8suYTQ2g4HaV3hjj5Btg=";
                source = "registry+https://github.com/rust-lang/crates.io-index";         
            };

            buildInputs = with pkgs; [ openssl pkg-config ];
            doCheck = false;

            OPENSSL_NO_VENDOR=1;
        };

        ldproxy = craneLib.buildPackage {
            src = craneLib.downloadCargoPackage {
                name = "ldproxy";
                version = "0.3.3";
                checksum = "sha256-eDwS3nFpFjrAfcpplhteAH34BuI96+wOkOoaEKwsu6U=";
                source = "registry+https://github.com/rust-lang/crates.io-index";         
            };

            doCheck = false;
        };

        espflash = craneLib.buildPackage {
            src = craneLib.downloadCargoPackage {
                name = "espflash";
                version = "2.0.0";
                checksum = "sha256-S+JUVqUHgwXIc7lcy1O9NPTR9o7vv1MRHOnPPGTkRY4=";
                source = "registry+https://github.com/rust-lang/crates.io-index";         
            };

            buildInputs = with pkgs; [ udev pkg-config ]; #libudev-zero
            doCheck = false;
        };

        cargo-espflash = craneLib.buildPackage {
            src = craneLib.downloadCargoPackage {
                name = "cargo-espflash";
                version = "2.0.0";
                checksum = "sha256-duUOQk85b3I3O2aOBkQcU6ON5QSD7BeJL3NQbKBYAD4=";
                source = "registry+https://github.com/rust-lang/crates.io-index";         
            };

            buildInputs = with pkgs; [ openssl udev pkg-config ]; #libudev-zero
            doCheck = false;

            OPENSSL_NO_VENDOR=1;
        };

        esp-toolchain-bin = fetchTarball {
            url = "https://github.com/esp-rs/rust-build/releases/download/v1.70.0.1/rust-1.70.0.1-x86_64-unknown-linux-gnu.tar.xz";
            sha256 = "sha256:0bai86aqmks6k85sncbr897zw7abxl5bk7hps9bmn3i79x3jqigy";
        };

        esp-toolchain-src = fetchTarball {
            url = "https://github.com/esp-rs/rust-build/releases/download/v1.70.0.1/rust-src-1.70.0.1.tar.xz";
            sha256 = "sha256:023j8w5g1s6f4zbk0q7mn8vwkz735qvgdalxw4yrnrqxjyw5barj";
        };

        xtensa-esp32-elf-clang = fetchTarball {
            url = "https://github.com/espressif/llvm-project/releases/download/esp-16.0.0-20230516/libs_llvm-esp-16.0.0-20230516-linux-amd64.tar.xz";
            sha256 = "sha256:15zkdvn495afkk690rsxwnmjqjbpw1cjz0rbvnqqyz3r0r2h3lsg";
        };

        riscv32-esp-elf = fetchTarball {
            url = "https://github.com/espressif/crosstool-NG/releases/download/esp-12.2.0_20230208/riscv32-esp-elf-12.2.0_20230208-x86_64-linux-gnu.tar.xz";
            sha256 = "sha256:0sj6aqfxfhqrxw7zrqd866a07g91javsqbp2i6pmw3f3ybbidg6l";
        };

        xtensa-esp32s2-elf = fetchTarball {
            url = "https://github.com/espressif/crosstool-NG/releases/download/esp-12.2.0_20230208/xtensa-esp32s2-elf-12.2.0_20230208-x86_64-linux-gnu.tar.xz";
            sha256 = "sha256:0klljvqpg1p5q7dcv8sjgpqr40ccbp1gd1xpjyykf0z3k7p1bnsx";
        };

 
        # esp rustc version has additional targets in `rustc --print target-list`
        esp-toolchain = pkgs.stdenv.mkDerivation {
            name = "esp-toolchain";

            # Skip src requirement
            unpackPhase = "true";

            buildInputs = [esp-toolchain-bin esp-toolchain-src xtensa-esp32-elf-clang riscv32-esp-elf xtensa-esp32s2-elf];

            installPhase = ''
                mkdir -p $out/
                mkdir -p $out/lib/rustlib

                # somehow otherwise has no permission to copy
                touch $out/lib/rustlib/uninstall.sh

                echo "--- starting build ---"

                bash ${esp-toolchain-bin}/install.sh --destdir=$out --prefix="" --without=rust-docs-json-preview,rust-docs --disable-ldconfig
                bash ${esp-toolchain-src}/install.sh --destdir=$out --prefix="" --disable-ldconfig
            '';
        };

    in {
        # packages.${system}.test = esp-toolchain;
        devShells.${system}.default = pkgs.mkShell {
            nativeBuildInputs = [
                esp-toolchain

                cargo-generate
                ldproxy
                espflash
                cargo-espflash

                pkgs.zlib
                pkgs.libxml2
            ];

            shellHook = ''
                export LIBCLANG_PATH="${xtensa-esp32-elf-clang}/lib"
                export PATH="${xtensa-esp32s2-elf}/bin:$PATH"
                export PATH="${riscv32-esp-elf}/bin:$PATH"
                export PATH="${esp-toolchain}/bin:$PATH"
            '';

            LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.zlib}/lib:${pkgs.libxml2.out}/lib";
        };
    };

}