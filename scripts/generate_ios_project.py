#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path


PROJECT_NAME = "Vokrr"
IOS_ROOT = Path("ios/Vokrr")
APP_ROOT = IOS_ROOT / PROJECT_NAME
PROJECT_DIR = IOS_ROOT / f"{PROJECT_NAME}.xcodeproj"
WORKSPACE_DIR = PROJECT_DIR / "project.xcworkspace"
ENV_FILE = Path(".env")
EXAMPLE_ENV_FILE = Path(".env.example")


def make_id(counter: int) -> str:
    return f"AA{counter:022X}"


class IDPool:
    def __init__(self) -> None:
        self.value = 1

    def next(self) -> str:
        current = make_id(self.value)
        self.value += 1
        return current


def pbx_file_type(path: Path) -> str:
    if path.suffix == ".swift":
        return "sourcecode.swift"
    if path.suffix == ".plist":
        return "text.plist.xml"
    if path.suffix == ".xcassets":
        return "folder.assetcatalog"
    raise ValueError(f"Unsupported file type for project generation: {path}")


def collect_project_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for current_root, dirs, filenames in __import__("os").walk(root):
        current = Path(current_root)
        dirs[:] = [
            directory
            for directory in dirs
            if not directory.endswith(".appiconset")
            and not directory.endswith(".colorset")
            and not directory.endswith(".xcodeproj")
        ]

        if current.name.endswith(".xcassets"):
            files.append(current.relative_to(root))
            dirs[:] = []
            continue

        for filename in filenames:
            path = current / filename
            if path.suffix not in {".swift", ".plist"}:
                continue
            files.append(path.relative_to(root))

    return sorted(files)


def build_group_tree(files: list[Path]) -> dict[str, dict]:
    tree: dict[str, dict] = {}
    for path in files:
        cursor = tree
        for part in path.parts[:-1]:
            cursor = cursor.setdefault(part, {})
    return tree


def render_group(
    name: str,
    path: Path | None,
    subtree: dict[str, dict],
    files: list[Path],
    ids: IDPool,
    file_refs: dict[Path, str],
    group_entries: list[str],
) -> str:
    group_id = ids.next()
    child_ids: list[str] = []

    child_dirs = sorted(subtree.keys())
    for child_dir in child_dirs:
        child_path = Path(child_dir) if path is None else path / child_dir
        child_subtree = subtree[child_dir]
        child_id = render_group(
            child_dir,
            child_path,
            child_subtree,
            files,
            ids,
            file_refs,
            group_entries,
        )
        child_ids.append(child_id)

    direct_files = [file for file in files if file.parent == (path or Path("."))]
    for file in direct_files:
        file_id = file_refs[file]
        child_ids.append(file_id)

    comments = "\n".join(f"\t\t\t\t{child_id} /* {resolve_comment(child_id, file_refs, files)} */," for child_id in child_ids)
    path_line = ""
    if path is not None:
        path_line = f"\n\t\t\tpath = {path.name};"
    elif name == PROJECT_NAME:
        path_line = f"\n\t\t\tpath = {PROJECT_NAME};"

    display_name = name
    group_entries.append(
        f"""\t\t{group_id} /* {display_name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{comments}
\t\t\t);{path_line}
\t\t\tsourceTree = "<group>";
\t\t}};"""
    )
    return group_id


def resolve_comment(object_id: str, file_refs: dict[Path, str], files: list[Path]) -> str:
    inverse_files = {value: path.name for path, value in file_refs.items()}
    return inverse_files.get(object_id, "Group")


def generate_project() -> None:
    generate_app_environment()
    default_server_url = load_env_value("IOS_DEFAULT_SERVER_URL", "https://api.vokrr.com")
    files = collect_project_files(APP_ROOT)
    ids = IDPool()

    file_ref_entries: list[str] = []
    build_file_entries: list[str] = []
    source_build_ids: list[str] = []
    resource_build_ids: list[str] = []
    file_refs: dict[Path, str] = {}

    for file in files:
        file_id = ids.next()
        file_refs[file] = file_id
        last_known = pbx_file_type(file)
        file_ref_entries.append(
            f'\t\t{file_id} /* {file.name} */ = {{isa = PBXFileReference; lastKnownFileType = {last_known}; path = {file.name}; sourceTree = "<group>"; }};'
        )
        if file.suffix == ".swift" or file.suffix == ".xcassets":
            build_id = ids.next()
            build_file_entries.append(
                f"\t\t{build_id} /* {file.name} in {'Sources' if file.suffix == '.swift' else 'Resources'} */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {file.name} */; }};"
            )
            if file.suffix == ".swift":
                source_build_ids.append(build_id)
            else:
                resource_build_ids.append(build_id)

    tree = build_group_tree(files)
    group_entries: list[str] = []
    app_group_id = render_group(PROJECT_NAME, None, tree, files, ids, file_refs, group_entries)
    products_group_id = ids.next()
    app_product_id = ids.next()

    group_entries.append(
        f"""\t\t{products_group_id} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_product_id} /* {PROJECT_NAME}.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};"""
    )

    root_group_id = ids.next()
    group_entries.append(
        f"""\t\t{root_group_id} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_group_id} /* {PROJECT_NAME} */,
\t\t\t\t{products_group_id} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};"""
    )

    frameworks_phase_id = ids.next()
    resources_phase_id = ids.next()
    sources_phase_id = ids.next()
    target_id = ids.next()
    project_id = ids.next()
    project_config_list_id = ids.next()
    target_config_list_id = ids.next()
    project_debug_id = ids.next()
    project_release_id = ids.next()
    target_debug_id = ids.next()
    target_release_id = ids.next()

    source_lines = "\n".join(
        f"\t\t\t\t{build_id} /* {build_name(files, build_id, build_file_entries)} */," for build_id in source_build_ids
    )
    resource_lines = "\n".join(
        f"\t\t\t\t{build_id} /* {build_name(files, build_id, build_file_entries)} */," for build_id in resource_build_ids
    )

    pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_entries)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_ref_entries)}
\t\t{app_product_id} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase_id} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{chr(10).join(group_entries)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target_id} /* {PROJECT_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_config_list_id} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase_id} /* Sources */,
\t\t\t\t{frameworks_phase_id} /* Frameworks */,
\t\t\t\t{resources_phase_id} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {PROJECT_NAME};
\t\t\tproductName = {PROJECT_NAME};
\t\t\tproductReference = {app_product_id} /* {PROJECT_NAME}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2630;
\t\t\t\tLastUpgradeCheck = 2630;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.3;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_config_list_id} /* Build configuration list for PBXProject "{PROJECT_NAME}" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {root_group_id};
\t\t\tproductRefGroup = {products_group_id} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target_id} /* {PROJECT_NAME} */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase_id} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{resource_lines}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase_id} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{source_lines}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{project_debug_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{project_release_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{target_debug_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = {PROJECT_NAME}/Info.plist;
\t\t\t\tIOS_DEFAULT_SERVER_URL = {default_server_url};
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.vokrr.ios;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTED_INTERFACE_ORIENTATIONS = UIInterfaceOrientationPortrait;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{target_release_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = {PROJECT_NAME}/Info.plist;
\t\t\t\tIOS_DEFAULT_SERVER_URL = {default_server_url};
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.vokrr.ios;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTED_INTERFACE_ORIENTATIONS = UIInterfaceOrientationPortrait;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{project_config_list_id} /* Build configuration list for PBXProject "{PROJECT_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{project_debug_id} /* Debug */,
\t\t\t\t{project_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{target_config_list_id} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{target_debug_id} /* Debug */,
\t\t\t\t{target_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project_id} /* Project object */;
}}
"""

    PROJECT_DIR.mkdir(parents=True, exist_ok=True)
    WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)
    (PROJECT_DIR / "project.pbxproj").write_text(pbxproj)
    (WORKSPACE_DIR / "contents.xcworkspacedata").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""
    )


def build_name(files: list[Path], build_id: str, build_file_entries: list[str]) -> str:
    for entry in build_file_entries:
        if build_id not in entry:
            continue
        return entry.split("/* ", 1)[1].split(" */", 1)[0]
    return "BuildFile"


def load_env_value(key: str, default: str) -> str:
    for candidate in (ENV_FILE, EXAMPLE_ENV_FILE):
        if not candidate.exists():
            continue
        for line in candidate.read_text().splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            name, value = stripped.split("=", 1)
            if name.strip() == key:
                return value.strip()
    return default


def generate_app_environment() -> None:
    config_dir = APP_ROOT / "Config"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "AppEnvironment.swift").write_text(
        '''import Foundation

enum AppEnvironment {
    static let defaultServerURL = Bundle.main.object(forInfoDictionaryKey: "VokrrDefaultServerURL") as? String
        ?? "https://api.vokrr.com"
}
'''
    )


if __name__ == "__main__":
    generate_project()
