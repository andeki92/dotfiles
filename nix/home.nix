{ pkgs, ... }: {
   programs.home-manager.enable = true;

   home.packages = with pkgs; [
    mise
    sshs
    glow
  ];

  programs.git = {
    enable = true;
  };
}