#!/usr/bin/env nu

try { mkdir /nix } catch { |e|
  print $"Could not create /nix directory: ($e.msg)"
  exit 1
}

try {
  mkdir /var/lib/nix
} catch { |e|
  print $"Could not create /var/lib/nix directory: ($e.msg)"
  exit 1
}

try {
  mount --bind /var/lib/nix /nix
} catch { |e|
  print $"Could not bind /var/lib/nix to /nix: ($e.msg)"
  exit 1
}

dnf -y install nix
