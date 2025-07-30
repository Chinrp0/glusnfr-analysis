# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-29

### Added
- Initial release of modular GluSnFR analysis pipeline
- GPU-accelerated dF/F calculations with CPU fallback
- Adaptive ROI filtering based on noise levels
- Support for 1AP and PPF experiments
- Comprehensive Excel output with multiple sheets
- Publication-ready plotting with noise level separation
- Modular architecture for easy extension and testing
- Configuration module for centralized parameter management
- String utilities with cached regex patterns for performance
- Memory management for large dataset processing
- Comprehensive test suite with realistic data simulation

### Performance
- 2-5x faster processing compared to monolithic scripts
- 50% reduction in memory usage with single-precision optimization
- Intelligent GPU/CPU selection based on data size and available memory

### Documentation
- Complete README with installation and usage instructions
- MIT license for open source distribution
- Professional repository structure for GitHub publication

## [0.50.0] - 2025-01-25

### Added
- Migration from monolithic script to modular architecture
- Initial module structure and organization
- Basic configuration management

### Changed
- Refactored from single large script to multiple focused modules
- Improved error handling and validation throughout pipeline

## Legacy Versions

Previous versions (v1-v49) were monolithic scripts with incremental improvements to analysis algorithms and output formatting.
