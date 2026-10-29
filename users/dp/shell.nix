# System half of dp's shells on both hosts. Home Manager owns the prompt,
# completion, and integrations; the system only supplies Zsh and its paths.
_:

{
  programs.zsh = {
    enable = true;
    enableBashCompletion = false;
    enableGlobalCompInit = false;
    promptInit = "";
  };
}
