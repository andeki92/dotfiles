# Dotfiles

My personal dotfiles, managed with GNU Stow.

## Structure

The repository follows a modular structure to allow for easy management of different tools and environments:

```
.dotfiles/               # Root directory
├── .stowrc              # Stow configuration 
├── scripts/             # Helper scripts
└── config/              # All configuration files
    ├── zsh/             # Zsh configuration
    │   ├── .config/     # Goes to ~/.config
    │   │   └── zsh/     # Goes to ~/.config/zsh
    │   └── .zshrc       # Goes to ~/.zshrc
    └── git/             # Git configuration
        └── .config/     # Goes to ~/.config
            └── git/     # Goes to ~/.config/git
```

## Aliases

This repository includes various aliases to improve productivity across different tools.

### Kubernetes Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `k` | `kubectl` | Main kubectl shorthand |
| `kg` | `kubectl get` | Get resources |
| `kgp` | `kubectl get pods` | Get pods |
| `kd` | `kubectl describe` | Describe resources |
| `kl` | `kubectl logs` | View logs |
| `kaf` | `kubectl apply -f` | Apply a YAML file |
| `kx` | `kubectx` | Switch between clusters |
| `kn` | `kubens` | Switch between namespaces |

#### Helper Functions

- `kns <namespace>`: Switch to namespace with feedback
- `klp <pattern>`: Follow logs of pod matching pattern
- `kep <pattern> [command]`: Execute command in pod matching pattern

### Git Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `g` | `git` | Main git shorthand |
| `ga` | `git add` | Stage changes |
| `gc` | `git commit` | Commit changes |
| `gp` | `git push` | Push changes |
| `gl` | `git pull` | Pull changes |
| `gs` | `git status` | Check status |

### Directory Navigation

| Alias | Command | Description |
|-------|---------|-------------|
| `..` | `cd ..` | Move up one directory |
| `...` | `cd ../..` | Move up two directories |
| `l` | `ls -lah` | List all files with details |
| `ll` | `ls -lh` | List files with details |

## Performance Monitoring

This repository includes tooling to monitor zsh startup performance over time.

### Running Benchmarks

To measure zsh startup time:

```bash
# Run a benchmark
./scripts/benchmark.sh

# Save benchmark results to docs/benchmarks.md
./scripts/benchmark.sh --save
```

### Automated Benchmarks

Pull requests that modify zsh configurations will automatically trigger benchmark tests through GitHub Actions. The action will:

1. Run benchmarks on both the PR branch and main branch
2. Compare the results
3. Comment on the PR with performance impact

This helps ensure that changes don't negatively impact shell startup time.

## Usage

```bash
# Clone the repository
git clone https://github.com/username/dotfiles.git ~/.dotfiles

# Navigate to the repository
cd ~/.dotfiles

# Stow everything
stow .

# Stow specific applications
stow zsh git 

# Update after changes
stow -R .
``` 