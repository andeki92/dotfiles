# Ghostty Terminal Emulator Configuration

## Overview
This directory contains the configuration for Ghostty, a modern GPU-accelerated terminal emulator with excellent performance and aesthetics.

## Structure
- `.config/ghostty/config` - Main configuration file
- `.config/ghostty/themes/` - Theme files
  - `catppuccin-latte.conf` - Light theme variant
  - `catppuccin-frappe.conf` - Medium-dark theme variant
  - `catppuccin-macchiato.conf` - Dark theme variant
  - `catppuccin-mocha.conf` - Darker theme variant

## Features
- **Automatic Theme Switching:** Follows system light/dark preferences
- **Catppuccin Theme Variants:** Multiple aesthetic color schemes
- **Enhanced Font Rendering:** Optimized for readability with JetBrains Mono Nerd Font
- **Modern Interface:** Background blur and subtle transparency
- **Window Padding:** Balanced padding for better visual appearance
- **Intuitive Keybindings:** Easy tab navigation and management
- **Shell Integration:** Automatically detects and integrates with the shell

## Installation
Stow this module to create the symlinks:

```bash
stow ghostty
```

## Customization
You can modify the theme by changing the `theme` setting in the config file. 
For light/dark theme switching, use the format:

```
theme = light:catppuccin-latte,dark:catppuccin-macchiato
```

## Key Decisions
- Using Catppuccin themes for beautiful, consistent aesthetics
- Font thickening enabled for improved readability (macOS style)
- Background blur for modern appearance
- Automatic light/dark theme integration with system settings
- Hidden titlebar for cleaner appearance

## Resources
- [Ghostty Documentation](https://ghostty.org/docs/)
- [Catppuccin Theme Project](https://github.com/catppuccin/ghostty)
- [JetBrains Mono Nerd Font](https://www.nerdfonts.com/font-downloads) 
