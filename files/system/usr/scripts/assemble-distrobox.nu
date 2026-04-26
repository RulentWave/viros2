#!/usr/bin/env nu

const DISTROBOX_FIELDS = [
    name additional_flags additional_packages home hostname image
    clone include init_hooks pre_init_hooks volume exported_apps
    exported_bins exported_bins_path entry start_now init nvidia
    pull root unshare_groups unshare_ipc unshare_netns
    unshare_process unshare_devsys unshare_all
]

# fields that when transpiled to distrobox ini are space-separated
const LIST_FIELDS_SPACE = [additional_flags additional_packages volume exported_apps exported_bins]
# Fields that when transpiled to distrobox ini are semicolon-separated
const LIST_FIELDS_SEMI  = [init_hooks pre_init_hooks]

let dropin_dir = ($env.XDG_CONFIG_HOME? | default ($env.HOME | path join ".config"))
	| path join "distrobox/distrobox.d"

export def "to distrobox-ini" [] {
	let input = $in

	let data = match ($input | describe -d | get type) {
		"record" => [$input]
		_        =>  $input
		}

	let ready = $data | select -o ...$DISTROBOX_FIELDS

	  # Apply `default []` for every list field
  let list_fields = ($LIST_FIELDS_SPACE | append $LIST_FIELDS_SEMI)
  let defaulted = $list_fields
		| reduce -f $ready {|field, acc| $acc | default [] $field
			}

    # Join space-separated list fields
  let joined_space = $LIST_FIELDS_SPACE | reduce -f $defaulted {|field, acc|
      $acc | update $field {|row| $row | get $field | str join " " }
    }

    # Join semicolon-separated list fields
  let joined = $LIST_FIELDS_SEMI | reduce -f $joined_space {|field, acc|
      $acc | update $field {|row| $row | get $field | str join " ; " }
    }
	$joined
	| group-by name
	| update cells {|v| $v | first | reject name}
	| to toml
	| str replace --all --regex '(?m)^(\S+)\s*=\s*' '${1}='

}

export def update-distrobox-hostnames [] {
	let hostname = (sys host).hostname
	$in | each {|d|
		let current = ($d | get -o hostname)
		let suffix = if $current == null { $d.name } else { $current }
		$d | upsert hostname $"($hostname)-($suffix)"
	}
}

# Run `distrobox assemble <action>` against each rendered INI.
export def distrobox-assemble [action: string] {
	$in | each {|y|
		let tmp = (mktemp -t 'distrobox-XXXXXX.ini' | str trim)
		try {
			$y | save -f $tmp
			distrobox assemble $action --file $tmp
		} catch {|e|
			print $"Failed to ($action) distrobox: ($e.msg)"
		}
		rm -f $tmp
	}
}

# Verify each distrobox's image against its cosign_key (if set).
# Returns only the entries that pass (or have no key configured).
export def verify-cosign-keys [] {
    $in | each {|d|
        let key = ($d | get -o cosign_key)
        if ($key | is-empty) {
            $d
        } else if not ($key | path exists) {
            print $"Skipping ($d.name): cosign key not found at ($key)"
            null
        } else {
            let result = (do { cosign verify --key $key $d.image } | complete)
            if $result.exit_code == 0 {
                $d
            } else {
                print $"Skipping ($d.name): cosign verification failed for ($d.image)"
                print $result.stderr
                null
            }
        }
    } | compact
}

# Load configs from the drop-in directory, rewrite hostnames, and render to INI strings.
def prepare-distroboxes [] {
	let dir = $dropin_dir
	let distroboxes = if ($dir | path exists) {
		ls $dir | where type == file | get name
	| each { |f| try {
	
			let data = open $f
			if ($data | describe | str starts-with "list") { $data } else { [$data] }
			} catch {|e|
					print $"Skipping ($f): ($e.msg)"
					[]
			}
      }
      | flatten
    } else {
        []
    }
	if ($distroboxes | is-empty) {
		print $"No distrobox configs found in ($dropin_dir)"
		return []
	}

	$distroboxes
	| update-distrobox-hostnames
	| verify-cosign-keys
	| each {|i| $i | to distrobox-ini }
}

def run [action: string] {
	prepare-distroboxes | distrobox-assemble $action
}

def "main create" [] { 
	run "create"
}
def "main rm"     [] { run "rm" }

def "main print" {
	prepare-distroboxes |each {|ini| print $ini; print "---"}
}

def main [] {
	print "Usage: <script> <create|rm|print>"
	exit 1
}
