{
  lib,
  pkgs,
  personalProjects,
  ...
}:

let
  mark = pkgs.rustPlatform.buildRustPackage {
    pname = "mark";
    src = personalProjects.mark;
    version =
      (builtins.fromTOML (builtins.readFile "${personalProjects.mark}/Cargo.toml"))
      .workspace.package.version;
    cargoLock.lockFile = "${personalProjects.mark}/Cargo.lock";
    cargoBuildFlags = [
      "-p"
      "mark-cli"
    ];
    cargoTestFlags = [
      "-p"
      "mark-cli"
    ];
    nativeCheckInputs = [ pkgs.git ];
    meta.mainProgram = "mark";
  };

  hz = personalProjects.hz.packages.${pkgs.stdenv.hostPlatform.system}.default;
  hzZshInit = pkgs.runCommand "hz-zsh-init" { } ''
    ${lib.getExe hz} shell zsh > "$out"
    # Completion initialization belongs to the shared shell's lazy loader.
    substituteInPlace "$out" --replace-fail 'autoload -Uz compinit && compinit' ':'
  '';
  hzBashInit = pkgs.runCommand "hz-bash-init" { } ''
    ${lib.getExe hz} shell bash > "$out"
  '';
in
{
  home.packages = [
    mark
    hz
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    personalProjects.leetvim.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  programs.zsh.initContent = lib.mkAfter ''
    source ${hzZshInit}
  '';
  programs.bash.initExtra = lib.mkAfter ''
    source ${hzBashInit}
  '';
}
