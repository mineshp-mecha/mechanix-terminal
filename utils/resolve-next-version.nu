#!/usr/bin/env nu

def main [
    --format: string
    --name: string
    --upstream: string
    --base-url: string = "http://pkg.mecha.so"
] {
    if $format not-in ["deb", "rpm"] {
        error make { msg: "format must be 'deb' or 'rpm'" }
    }

    let username = ($env.MECHA_PULP_USERNAME? | default "")
    let password = ($env.MECHA_PULP_PASSWORD? | default "")
    let safe_upstream = if $upstream == "" { "1.0.0" } else { $upstream }

    let endpoint = if $format == "deb" {
        $"($base_url)/pulp/api/v3/content/deb/packages/?package=($name)"
    } else {
        $"($base_url)/pulp/api/v3/content/rpm/packages/?name=($name)"
    }

    let basic_token = if ($username != "" and $password != "") {
        ($username + ":" + $password) | encode base64
    } else {
        ""
    }

    let headers = if $basic_token != "" {
        {
            Authorization: $"Basic ($basic_token)"
            Accept: "application/json"
        }
    } else {
        { Accept: "application/json" }
    }

    let response = (http get --headers $headers $endpoint)
    let results = ($response.results? | default [])

    let versions = (
        $results
        | each { |pkg|
            if $format == "deb" {
                $pkg.version
            } else {
                $"($pkg.version)-($pkg.release)"
            }
        }
    )

    let revisions = (
        $versions
        | where { |v| $v | str starts-with $"($safe_upstream)-" }
        | each { |v|
            let parts = ($v | split row "-")
            if ($parts | length) >= 2 {
                $parts | last | into int
            } else {
                0
            }
        }
    )

    let current_max_rev = if ($revisions | is-empty) { 0 } else { $revisions | math max }
    let next_rev = $current_max_rev + 1

    {
        package_name: $name
        format: $format
        upstream_version: $safe_upstream
        current_revision: $current_max_rev
        next_revision: $next_rev
        full_version: $"($safe_upstream)-($next_rev)"
    } | to json
}
