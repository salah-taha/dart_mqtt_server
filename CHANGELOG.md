# Changelog

All notable changes to the MQTT Server package will be documented in this file.

## 1.0.0 - 2025-05-14

### Added
- Initial release of the MQTT Server package
- MQTT 3.1.1 protocol implementation
- Support for QoS levels 0, 1, and 2
- Session persistence functionality
- Authentication system with username/password support
- SSL/TLS secure connection support
- Will message handling
- Retained message support
- Topic wildcards support (+ and #)
- Centralized packet parsing with MqttPacketParser
- Manual JSON serialization for session persistence

### Changed
- Updated Dart SDK requirement to ^3.0.0 to support records

### Fixed
- Initial implementation, no fixes yet
