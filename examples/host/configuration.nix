{ pkgs, ... }:
{
  programs.orca.enable = true;

  # The always-on Orca runtime that the phone and other computers pair with.
  services.orca-server = {
    enable = true;
    user = "owner";
    mobilePairing = true;
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [ "amd_pstate=active" ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;
    graphics.enable = true;
    amdgpu.initrd.enable = true;
  };

  services = {
    fwupd.enable = true;
    tailscale.enable = true;
    power-profiles-daemon.enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  networking = {
    hostName = "matrix-mini";
    networkmanager.enable = true;
  };

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";

  users.users.owner = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "26.11";
}
