# Time: the host's time zone, chrony (client only).
{ config, ... }:
{
  time.timeZone = config.dev.host.timezone;
  services.chrony = {
    enable = true;
    servers = [
      "0.pool.ntp.org"
      "1.pool.ntp.org"
      "2.pool.ntp.org"
      "3.pool.ntp.org"
    ];
  };
}
