#!/usr/bin/env nu

# RPM Packaging Script for Mechanix Terminal
# Usage: nu package-rpm.nu terminal <output-dir>

const REQUIRED_METADATA_FIELDS = ["name", "binary", "folder"]
const METADATA_FILE = "packaging-metadata.yaml"
const VERSION_RESOLVER = "utils/resolve-next-version.nu"
const INSTALL_PREFIX = "/usr"
const SHARE_BASE = "/usr/share/mechanix"
const DESKTOP_DIR = "/usr/share/applications"
const ICON_DIR = "/usr/share/icons/hicolor/48x48/apps"

# ==========================================================================
# Helpers
# ==========================================================================

def validate-metadata [app: record] {
    let app_columns = ($app | columns)
    let missing = ($REQUIRED_METADATA_FIELDS | where { |field| not ($field in $app_columns) })

    if ($missing | is-not-empty) {
        let missing_fields = ($missing | str join ", ")
        let msg = $"Missing required metadata fields: ($missing_fields)"
        error make { msg: $msg }
    }

    if not (($app.folder | path expand) | path exists) {
        let folder_path = ($app.folder | path expand)
        let msg = $"Application folder does not exist: ($folder_path)"
        error make { msg: $msg }
    }
}


def load-metadata [app_name: string] {
    if not ($METADATA_FILE | path exists) {
        let msg = $"Metadata file not found: ($METADATA_FILE)"
        error make { msg: $msg }
    }

    let metadata = open $METADATA_FILE
    let app = ($metadata.applications | where name == $app_name | first)

    if ($app | is-empty) {
        let available = ($metadata.applications | get name | str join ", ")
        let msg = $"App '($app_name)' not found. Available: ($available)"
        error make { msg: $msg }
    }

    validate-metadata $app
    $app
}


def load-pubspec [app_folder: path] {
    let pubspec_path = ($app_folder | path expand | path join "pubspec.yaml")
    if not ($pubspec_path | path exists) {
        let folder_path = ($app_folder | path expand)
        let msg = $"pubspec.yaml not found in ($folder_path)"
        error make { msg: $msg }
    }

    let pubspec = open $pubspec_path
    if not ("version" in ($pubspec | columns)) {
        error make { msg: "No version field in pubspec.yaml" }
    }

    $pubspec
}


def resolve-version [pkg_name: string, upstream_version: string] {
    let resolver_path = ($VERSION_RESOLVER | path expand)

    if not ($resolver_path | path exists) {
        print $"[WARN] Version resolver not found at: ($resolver_path)"
        print "[INFO] Falling back to release 1"
        return {
            upstream_version: $upstream_version
            next_revision: 1
            full_version: $"($upstream_version)-1"
        }
    }

    print $"[INFO] Running version resolver: ($resolver_path)"

    let result = (do -i {
        ^nu $resolver_path --format "rpm" --name $pkg_name --upstream $upstream_version | complete
    })

    if $result.exit_code != 0 {
        print $"[WARN] Version resolver failed with exit code ($result.exit_code)"
        if ($result.stderr | is-not-empty) {
            print $"[DEBUG] Resolver stderr: ($result.stderr)"
        }
        print "[INFO] Falling back to release 1"
        return {
            upstream_version: $upstream_version
            next_revision: 1
            full_version: $"($upstream_version)-1"
        }
    }

    try {
        let parsed = ($result.stdout | from json)
        print $"[INFO] Resolved package version: ($parsed.full_version)"
        $parsed
    } catch {
        print "[WARN] Version resolver returned invalid JSON"
        if ($result.stdout | is-not-empty) {
            print $"[DEBUG] Resolver stdout: ($result.stdout)"
        }
        print "[INFO] Falling back to release 1"
        {
            upstream_version: $upstream_version
            next_revision: 1
            full_version: $"($upstream_version)-1"
        }
    }
}


def resolve-build-directory [app_folder: path, pkg_arch: string] {
    let folder = ($app_folder | path expand)
    let normalized_arch = (if $pkg_arch == "x86_64" { "x86_64" } else { if $pkg_arch == "aarch64" { "aarch64" } else { $pkg_arch } })
    let alt_arch = (if $normalized_arch == "aarch64" { "arm64" } else { if $normalized_arch == "x86_64" { "x64" } else { $normalized_arch } })

    let candidates = [
        ($folder | path join "build" "elinux" $normalized_arch "release" "bundle")
        ($folder | path join "build" "elinux" $alt_arch "release" "bundle")
        ($folder | path join "build" "elinux" "bundle")
    ]

    for path in $candidates {
        if ($path | path exists) {
            let resolved = ($path | path expand)
            print $"[INFO] Using build directory: ($resolved)"
            return $resolved
        }
    }

    let tried = ($candidates | each { |p| $p | path expand })
    let tried_list = ($tried | str join "\n  ")
    let msg = $"Build directory not found. Tried:\n  ($tried_list)"
    error make { msg: $msg }
}


def validate-binary [build_dir: path, binary_name: string] {
    let binary_path = ($build_dir | path join $binary_name)
    if not ($binary_path | path exists) {
        let path_str = ($binary_path | path expand)
        let msg = $"Binary not found: ($path_str)"
        error make { msg: $msg }
    }
    $binary_path
}


def copy-artifact [src: path, dest: path] {
    if not ($src | path exists) {
        return
    }
    if not ($dest | path exists) { mkdir $dest }
    cp -r $src $dest
}


def create-launcher [dest: path, binary_name: string, pkg_name: string] {
    let launcher = $"#!/bin/sh
APPDIR=\"/usr/share/mechanix/($pkg_name)\"
export LD_LIBRARY_PATH=\"\$APPDIR/lib:\$LD_LIBRARY_PATH\"
exec \"$APPDIR/($binary_name)\" --bundle=\"$APPDIR\" \"$@\"
"
    $launcher | save -f $dest
    chmod 755 $dest
}


def collect-artifacts [app: record, build_dir: path, rpm_root: path, pkg_name: string] {
    print "[INFO] Collecting artifacts..."

    let binary_path = validate-binary $build_dir $app.binary
    let share_dest = ($rpm_root | path join "usr" "share" "mechanix" $pkg_name)
    copy-artifact $binary_path $share_dest
    chmod 755 ($share_dest | path join $app.binary)

    let bin_dest = ($rpm_root | path join "usr" "bin")
    if not ($bin_dest | path exists) { mkdir $bin_dest }
    create-launcher ($bin_dest | path join $app.binary) $app.binary $pkg_name

    let lib_src = ($build_dir | path join "lib")
    if ($lib_src | path exists) {
        copy-artifact $lib_src $share_dest
    }

    let data_src = ($build_dir | path join "data")
    if ($data_src | path exists) {
        copy-artifact $data_src $share_dest
    }

    let desktop_file = $"org.mechanix.($app.name).desktop"
    let desktop_src = (($app.folder | path expand) | path join $desktop_file)
    let desktop_installed = if ($desktop_src | path exists) {
        let desktop_dest = ($rpm_root | path join "usr" "share" "applications")
        copy-artifact $desktop_src $desktop_dest
        true
    } else {
        false
    }

    let icon_file = $"mechanix_($app.name).png"
    let icon_src = (($app.folder | path expand) | path join "assets" $icon_file)
    let icon_installed = if ($icon_src | path exists) {
        let icon_dest = ($rpm_root | path join "usr" "share" "icons" "hicolor" "48x48" "apps")
        copy-artifact $icon_src $icon_dest
        true
    } else {
        false
    }

    {
        desktop_installed: $desktop_installed,
        icon_installed: $icon_installed,
        desktop_file: $desktop_file,
        icon_file: $icon_file
    }
}


def generate-spec [pkg_name: string, version: string, release: string, arch: string, app: record, pubspec: record, artifacts: record] {
    print "[INFO] Generating RPM spec file..."
    let dependencies = ($app.dependencies? | default [])
    let description = ($pubspec.description? | default "Mechanix application")
    let maintainer = ($app.maintainer? | default "Mechanix Team <team@mecha.so>")
    let summary = ($app.description? | default description)

    let base_lines = [
        $"Name: ($pkg_name)"
        $"Version: ($version)"
        $"Release: ($release)"
        $"Summary: ($summary)"
        "License: BSD"
        $"Packager: ($maintainer)"
        "URL: https://github.com/mineshp-mecha/mechanix-terminal"
        $"BuildArch: ($arch)"
        "AutoReqProv: no"
    ]

    let dependency_lines = if ($dependencies | is-not-empty) {
        $dependencies | each { |dep| $"Requires: ($dep)" }
    } else {
        []
    }

    let footer_lines = [
        ""
        "%description"
        $description
        ""
        "%post"
        "/usr/bin/update-desktop-database &> /dev/null || :"
        "touch --no-create /usr/share/icons/hicolor &>/dev/null || :"
        "gtk-update-icon-cache /usr/share/icons/hicolor &>/dev/null || :"
        ""
        "%postun"
        "/usr/bin/update-desktop-database &> /dev/null || :"
        "if [ $1 -eq 0 ] ; then"
        "    touch --no-create /usr/share/icons/hicolor &>/dev/null || :"
        "    gtk-update-icon-cache /usr/share/icons/hicolor &>/dev/null || :"
        "fi"
        ""
        "%files"
        $"($INSTALL_PREFIX)/bin/($app.binary)"
        $"%dir ($SHARE_BASE)/($pkg_name)"
        $"($SHARE_BASE)/($pkg_name)/*"
    ]

    let spec_lines = ($base_lines | append $dependency_lines | append $footer_lines)

    let spec_lines = if $artifacts.desktop_installed {
        ($spec_lines | append $"($DESKTOP_DIR)/($artifacts.desktop_file)")
    } else {
        $spec_lines
    }

    let spec_lines = if $artifacts.icon_installed {
        ($spec_lines | append $"($ICON_DIR)/($artifacts.icon_file)")
    } else {
        $spec_lines
    }

    $spec_lines | str join "\n"
}


def build-rpm [rpmbuild_root: path, rpm_root: path, pkg_name: string, spec_file: path] {
    print "[INFO] Building RPM package..."

    let topdir_def = $"_topdir ($rpmbuild_root | path expand)"
    let result = (^rpmbuild -ba --define $topdir_def --buildroot ($rpm_root | path expand) $spec_file | complete)
    if $result.exit_code != 0 {
        print "[ERROR] RPM build failed"
        print $result.stderr
        error make { msg: "RPM build failed" }
    }

    print $result.stdout
}


def export-rpms [rpmbuild_root: path, output_dir: path] {
    let out = ($output_dir | path expand)
    if not ($out | path exists) { mkdir $out }

    let rpm_files = (glob ($rpmbuild_root | path expand | path join "RPMS/**/*.rpm"))
    if ($rpm_files | is-empty) {
        error make { msg: "No RPM files found after build" }
    }

    for f in $rpm_files {
        cp $f $out
        print $"[SUCCESS] Created: ($f | path basename)"
        ^rpm -qlp $f
    }
}

# ==========================================================================
# Main
# ==========================================================================

def main [app_name: string, output_dir: string] {
    print $"[INFO] Starting RPM packaging for ($app_name)"

    let app = load-metadata $app_name
    let pubspec = load-pubspec $app.folder
    let upstream_version = ($pubspec.version | split row "+" | first)
    let pkg_name = $"mechanix-($app.name)"
    let pkg_arch = (^uname -m | str trim)
    let version_data = resolve-version $pkg_name $upstream_version
    let release = ($version_data.next_revision | into string)
    let build_dir = resolve-build-directory $app.folder $pkg_arch

    print $"[INFO] Package name: ($pkg_name)"
    print $"[INFO] Version: ($upstream_version)"
    print $"[INFO] Release: ($release)"
    print $"[INFO] Architecture: ($pkg_arch)"

    let rpmbuild_root = ($env.PWD | path join "rpmbuild")
    let rpm_root = ($rpmbuild_root | path join "BUILDROOT" ($pkg_name + "-" + $upstream_version + "-" + $release + "." + $pkg_arch))

    rm -rf $rpmbuild_root
    mkdir $rpmbuild_root
    mkdir ($rpmbuild_root | path join "SPECS")
    mkdir ($rpmbuild_root | path join "BUILD")
    mkdir ($rpmbuild_root | path join "RPMS")
    mkdir ($rpmbuild_root | path join "SRPMS")

    let artifacts = collect-artifacts $app $build_dir $rpm_root $pkg_name
    let spec_content = generate-spec $pkg_name $upstream_version $release $pkg_arch $app $pubspec $artifacts

    let spec_file = ($rpmbuild_root | path join "SPECS" ($pkg_name + ".spec"))
    $spec_content | save -f $spec_file

    build-rpm $rpmbuild_root $rpm_root $pkg_name $spec_file
    export-rpms $rpmbuild_root $output_dir

    print "[INFO] Cleaning up build artifacts..."
    rm -rf $rpmbuild_root
    print "[SUCCESS] RPM packaging complete"
}
