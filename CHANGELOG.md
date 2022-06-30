# Changelog

## Version 3.1.0 - 2022-06-30
### Changed
- `KILL_SWITCH` now requires `iptables` or `nftables` to be enabled. It defaults to `iptables`. See documentation for more information.

### Added
- Modified OpenVPN configuration file cleanup function.

## Version 3.0.0 - 2022-06-14
### Changed
- Refactored scripts
  - Renamed a lot of variables ([PLEASE see docs](README.md#environment-variables))
  - Updated logic used to select the OpenVPN configuration file
  - Switched to `nftables`
- Updated to Alpine 3.16
- Fixed outdated proxy configuration files

## Version 2.1.0 - 2022-03-06
### Added
- `VPN_CONFIG_PATTERN` environment variable.

## Version 2.0.0 - 2022-01-02
### Changed
- `OPENVPN_AUTH_SECRET` changed to `VPN_AUTH_SECRET` for consistency.

### Fixed
- Commented remotes are no longer processed.
