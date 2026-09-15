_:

{
  users.users.z = {
    isNormalUser = true;
    # Start user services at boot and keep the local proxy alive after SSH logout.
    linger = true;
    description = "phony";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII7YFAmCVuAcrXuYzE/A47ceCoW8ZflRM/qpUK1nU+oT phongndo69@gmail.com"
    ];
  };
}
