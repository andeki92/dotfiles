# Homebrew Configuration

This directory contains the Homebrew configuration files used to maintain a consistent set of packages and applications across different macOS machines.

## Structure

```
config/brew/
├── .config/
│   └── brewfile/
│       └── Brewfile    # List of packages, casks, and Mac App Store apps to install
└── README.md           # This file
```

The structure follows the XDG Base Directory Specification, which will symlink to `~/.config/brewfile/Brewfile` when stowed.

## Usage

### Installation

First, ensure that this module is stowed to your home directory:

```bash
cd ~/.dotfiles
stow brew
```

This will create the XDG-compliant brewfile directory structure in your home directory.

### Installing Packages

To install all packages defined in the Brewfile:

```bash
brew bundle
```

Homebrew automatically detects the Brewfile in `~/.config/brewfile/Brewfile`, so no additional parameters are needed.

### Updating the Brewfile

To update the Brewfile with your currently installed packages:

```bash
brew bundle dump --force
```

The updated file will be saved to `~/.config/brewfile/Brewfile`. To update your dotfiles repository, copy the changes:

```bash
cp ~/.config/brewfile/Brewfile ~/.dotfiles/config/brew/.config/brewfile/
```

### Checking Status

To check which packages in the Brewfile are installed/missing:

```bash
brew bundle check
```

## Customization

The Brewfile is organized into sections:

1. **Taps** - Sources for packages
2. **Development Tools** - Programming and development utilities
3. **Shells and CLI Utilities** - Command-line tools 
4. **Language Support** - Programming language environments (commented by default)
5. **Applications** - macOS applications
6. **Fonts** - Fonts for development and UI
7. **Mac App Store** - Applications from the Mac App Store (requires `mas`)

Modify the Brewfile to add or remove packages based on your needs. 
Follow the format of the existing entries, keeping comments for readability.

## Tips

- The Language Support section is commented by default. Uncomment the languages you actually use.
- Mac App Store applications require the `mas` CLI tool. Install it with `brew install mas` if needed.
- To install only part of the Brewfile, you can edit a copy and run `brew bundle` with that specific file. 