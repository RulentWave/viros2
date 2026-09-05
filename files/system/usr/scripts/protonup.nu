#!/usr/bin/env nu
def main [] {
    let release = (
		http get https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest
	)

    let latest_version = $release.tag_name
    let architecture = (uname | get machine)
    if $architecture != "x86_64" and $architecture != "aarch64" {
        error make { msg: $"Unsupported architecture: ($architecture)" }
    }

    let archive = $"($latest_version)-($architecture).tar.gz"
    let shasumfile = $"($latest_version)-($architecture).sha512sum"
    let assets = $release.assets | where {|asset|
        $asset.name == $archive or $asset.name == $shasumfile
    }
    if ($assets | length) != 2 {
        error make { msg: $"Release ($latest_version) does not contain a Proton-GE archive and checksum for ($architecture)" }
    }

    let install_dir = $nu.home-dir | path join ".steam/steam/compatibilitytools.d"
    let latest_path = $install_dir | path join $"($latest_version)-($architecture)"
    mkdir $install_dir

    if ($latest_path | path exists) {
        print $"Already installed: ($latest_version)"
        return
    }

    print $"Installing latest Proton-GE: ($latest_version)"
    notify-send "ProtonUp-nu" $"Installing latest Proton-GE: ($latest_version)"

    let working_dir = (mktemp -d)

    $assets | each {|a|
		let download = $working_dir | path join $a.name
		wget $a.browser_download_url -O $download
		if $env.LAST_EXIT_CODE != 0 {
    error make { msg: $"Download failed: ($a.browser_download_url)" }
		}
		let expected_digest = $a.digest | split row ":" | get 1 | str trim
		let actual_digest = open --raw $download | hash sha256
		if $expected_digest == $actual_digest {
			print $"SHA256 digest matches for ($download)"
		} else {
			notify-send "ProtonUp-nu" $"SHA256 digest does not match for ($download)"
			error make {
				msg: $"SHA256 mismatch for ($download)"
			}
		}
	}
    cd $working_dir
    # Check sha512sum after checking against the GitHub digest. This also verifies
    # the downloaded archive against the downloaded release checksum.
    sha512sum -c $shasumfile
    if $env.LAST_EXIT_CODE != 0 {
        notify-send "ProtonUp-nu" $"SHA512 check failed for ($archive)"
        error make {msg: $"SHA512 check failed for ($archive)"}
    }

    notify-send "ProtonUp-nu" $"Installing ($latest_version)"
    tar -xzf $archive -C $install_dir
    notify-send "ProtonUp-nu" $"($latest_version) installed"
    cd $nu.home-dir

    let install_path_latest = $install_dir | path join "GE-Proton-Latest"
    rm -rf $install_path_latest
    cp -r $latest_path $install_path_latest
    let vdf = r###'
"compatibilitytools"
{
  "compat_tools"
  {
    "GE-Proton"
    {
      "install_path" "."

      "display_name" "GE-Proton-latest"

      "from_oslist"  "windows"
      "to_oslist"    "linux"
    }
  }
}
'###
    $vdf | save -f ($install_path_latest | path join compatibilitytool.vdf)
    rm -rf $working_dir
}
