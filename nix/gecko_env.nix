{ releng_pkgs }:

let
  inherit (releng_pkgs.lib) mkRustPlatform ;
  inherit (releng_pkgs.pkgs) rustChannelOf bash autoconf213 clang_4 llvm_4 llvmPackages_4 gcc-unwrapped glibc fetchFromGitHub unzip zip openjdk python2Packages sqlite zlib;
  inherit (releng_pkgs.pkgs.devEnv) gecko;

  # Rust 1.30.0
  rustChannel' = rustChannelOf { date = "2018-10-25"; channel = "stable"; };
  rustChannel = { inherit (rustChannel') cargo; rust = rustChannel'.rust.override { targets=["armv7-linux-androideabi"]; }; };

  # Add missing gcc libraries needed by clang (see https://github.com/mozilla/release-services/issues/1256)
  gcc_libs = builtins.concatStringsSep ":" [
    "${gcc-unwrapped}/include/c++/${gcc-unwrapped.version}"
    "${gcc-unwrapped}/include/c++/${gcc-unwrapped.version}/backward"
    "${gcc-unwrapped}/include/c++/${gcc-unwrapped.version}/x86_64-unknown-linux-gnu"
    "${glibc.dev}/include"
  ];

  # Mach needs 0.6.7 at least
  # From https://github.com/NixOS/nixpkgs/blob/cdf90258e6bf911db2b56280301014a88c91be65/pkgs/development/tools/rust/cbindgen/default.nix
  rustPlatform = mkRustPlatform {
    rust = {
      cargo = rustChannel.cargo;
      rustc = rustChannel.rust;
    };
  };
  rust-cbindgen =  rustPlatform.buildRustPackage rec {
    name = "rust-cbindgen-${version}";
    version = "0.6.7";

    src = fetchFromGitHub {
      owner = "eqrion";
      repo = "cbindgen";
      rev = "v${version}";
      sha256 = "0sgkgvkqrc6l46fvk6d9hsy0xrjpl2ix47f3cv5bi74dv8i4y2b4";
    };

    cargoSha256 = "137dqj1sp02dh0dz9psf8i8q57gmz3rfgmwk073k7x5zzkgvj21c";
  };

in gecko.overrideDerivation (old: {
  # Dummy src, cannot be null
  src = ./.;
  configurePhase = ''
    mkdir -p $out/bin
    mkdir -p $out/conf
  '';
  buildPhase = ''

    # Gecko build environment
    geckoenv=$out/bin/gecko-env

    echo "#!${bash}/bin/sh" > $geckoenv
    echo "export SHELL=xterm" >> $geckoenv
    env | grep -E '^(PATH|PKG_CONFIG_PATH|CMAKE_INCLUDE_PATH)='| sed 's/^/export /' >> $geckoenv
    echo "export CPLUS_INCLUDE_PATH=$CMAKE_INCLUDE_PATH:${gcc_libs}:\$EXTRAS_INCLUDE_PATH" >> $geckoenv
    echo "export C_INCLUDE_PATH=$CMAKE_INCLUDE_PATH:${gcc_libs}:\$EXTRAS_INCLUDE_PATH" >> $geckoenv
    echo "export INCLUDE_PATH=$CMAKE_INCLUDE_PATH:${gcc_libs}:\$EXTRAS_INCLUDE_PATH" >> $geckoenv

    # Add self in PATH, needed to exec
    echo "export PATH=$out/bin:\$PATH" >> $geckoenv

    # Clean python environment
    echo "export PYTHONPATH=" >> $geckoenv

    # Build LDFLAGS and LIBRARY_PATH
    echo "export LDFLAGS=\"$NIX_LDFLAGS\"" >> $geckoenv
    echo "export LIBRARY_PATH=${zlib}/lib/:${sqlite.out}/lib/:\$CMAKE_LIBRARY_PATH" >> $geckoenv
    echo "export LD_LIBRARY_PATH=${gcc-unwrapped.lib}/lib:${zlib}/lib/:${sqlite.out}/lib/:\$CMAKE_LIBRARY_PATH" >> $geckoenv

    # queried by the static-analysis bot
    echo "export JAVA_HOME=${openjdk}" >> $geckoenv

    # Setup Clang & Autoconf
    echo "export CC=${clang_4}/bin/clang" >> $geckoenv
    echo "export CXX=${clang_4}/bin/clang++" >> $geckoenv
    echo "export LD=${clang_4}/bin/ld" >> $geckoenv
    echo "export LLVM_CONFIG=${llvm_4}/bin/llvm-config" >> $geckoenv
    echo "export LLVMCONFIG=${llvm_4}/bin/llvm-config" >> $geckoenv # we need both
    echo "export AUTOCONF=${autoconf213}/bin/autoconf" >> $geckoenv

    # Build custom mozconfig
    mozconfig=$out/conf/mozconfig
    echo > $mozconfig "
    ac_add_options --enable-debug
    ac_add_options --with-clang-path=${clang_4}/bin/clang
    ac_add_options --with-libclang-path=${llvmPackages_4.libclang}/lib
    mk_add_options AUTOCLOBBER=1
    "

    # Use updated rust version
    echo "export PATH=${rust-cbindgen}/bin:${rustChannel.rust}/bin:${rustChannel.cargo}/bin:\$PATH" >> $geckoenv
  '';
  installPhase = ''
    geckoenv=$out/bin/gecko-env

    # Exec command line from arguments
    echo "set -x" >> $geckoenv
    echo "exec \$@" >> $geckoenv

    chmod +x $geckoenv
  '';
  propagatedBuildInputs = old.propagatedBuildInputs
    ++ [
      # Update rust to latest stable
      rustChannel.rust
      rustChannel.cargo
      rust-cbindgen
      unzip
      zip
      openjdk
      python2Packages.pyyaml
      sqlite
      zlib
    ];
})
