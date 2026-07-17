#!/usr/bin/env python3
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


PROJECT_NAME = "Vokrr"
IOS_ROOT = Path("ios/Vokrr")
PROJECT_DIR = IOS_ROOT / f"{PROJECT_NAME}.xcodeproj"
WORKSPACE_DIR = PROJECT_DIR / "project.xcworkspace"
ENV_FILE = Path(".env")
EXAMPLE_ENV_FILE = Path(".env.example")
DEVELOPMENT_TEAM = "TF5TTN84RT"
DEPLOYMENT_TARGET = "17.0"
MARKETING_VERSION = "1.4.2"


@dataclass(frozen=True)
class TargetSpec:
    name: str
    root: Path
    product_name: str
    product_type: str
    bundle_identifier: str
    info_plist: str
    entitlements: str
    is_extension: bool = False


TARGETS = (
    TargetSpec(
        name="Vokrr",
        root=IOS_ROOT / "Vokrr",
        product_name="Vokrr.app",
        product_type="com.apple.product-type.application",
        bundle_identifier="com.vokrr.ios",
        info_plist="Vokrr/Info.plist",
        entitlements="Vokrr/Vokrr.entitlements",
    ),
    TargetSpec(
        name="VokrrWidgets",
        root=IOS_ROOT / "VokrrWidgets",
        product_name="VokrrWidgets.appex",
        product_type="com.apple.product-type.app-extension",
        bundle_identifier="com.vokrr.ios.widgets",
        info_plist="VokrrWidgets/Info.plist",
        entitlements="VokrrWidgets/VokrrWidgets.entitlements",
        is_extension=True,
    ),
)


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
    if path.suffix in {".plist", ".entitlements", ".xcprivacy"}:
        return "text.plist.xml"
    if path.suffix == ".xcassets":
        return "folder.assetcatalog"
    if path.suffix in {".ttf", ".otf"}:
        return "file"
    raise ValueError(f"Unsupported file type for project generation: {path}")


def collect_project_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for current_root, dirs, filenames in os.walk(root):
        current = Path(current_root)
        dirs[:] = [
            directory
            for directory in dirs
            if not directory.endswith(".appiconset")
            and not directory.endswith(".colorset")
            and not directory.endswith(".imageset")
            and not directory.endswith(".xcodeproj")
        ]
        if current.name.endswith(".xcassets"):
            files.append(current.relative_to(root))
            dirs[:] = []
            continue
        for filename in filenames:
            path = current / filename
            if path.suffix in {".swift", ".plist", ".entitlements", ".xcprivacy", ".ttf", ".otf"}:
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
    children: list[tuple[str, str]] = []
    for child_dir in sorted(subtree):
        child_path = Path(child_dir) if path is None else path / child_dir
        child_id = render_group(
            child_dir,
            child_path,
            subtree[child_dir],
            files,
            ids,
            file_refs,
            group_entries,
        )
        children.append((child_id, child_dir))
    direct_parent = path or Path(".")
    for file in (candidate for candidate in files if candidate.parent == direct_parent):
        children.append((file_refs[file], file.name))
    child_lines = "\n".join(
        f"\t\t\t\t{object_id} /* {comment} */," for object_id, comment in children
    )
    path_value = name if path is None else path.name
    group_entries.append(
        f"""\t\t{group_id} /* {name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{child_lines}
\t\t\t);
\t\t\tpath = {path_value};
\t\t\tsourceTree = "<group>";
\t\t}};"""
    )
    return group_id


def target_build_settings(spec: TargetSpec, default_server_url: str) -> str:
    settings = [
        "CODE_SIGN_STYLE = Automatic;",
        f"CODE_SIGN_ENTITLEMENTS = {spec.entitlements};",
        "CURRENT_PROJECT_VERSION = 1;",
        f"DEVELOPMENT_TEAM = {DEVELOPMENT_TEAM};",
        "GENERATE_INFOPLIST_FILE = NO;",
        f"INFOPLIST_FILE = {spec.info_plist};",
        f"IPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};",
        f"MARKETING_VERSION = {MARKETING_VERSION};",
        f"PRODUCT_BUNDLE_IDENTIFIER = {spec.bundle_identifier};",
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";',
        "SWIFT_EMIT_LOC_STRINGS = YES;",
        "SWIFT_VERSION = 5.0;",
        "TARGETED_DEVICE_FAMILY = 1;",
    ]
    if spec.is_extension:
        settings.extend(
            [
                "APPLICATION_EXTENSION_API_ONLY = YES;",
                "SKIP_INSTALL = YES;",
                "LD_RUNPATH_SEARCH_PATHS = (",
                '\t\t\t\t\t"$(inherited)",',
                '\t\t\t\t\t"@executable_path/Frameworks",',
                '\t\t\t\t\t"@executable_path/../../Frameworks",',
                "\t\t\t\t);",
            ]
        )
    else:
        escaped_url = default_server_url.replace('"', '\\"')
        settings.extend(
            [
                "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
                f'IOS_DEFAULT_SERVER_URL = "{escaped_url}";',
                "LD_RUNPATH_SEARCH_PATHS = (",
                '\t\t\t\t\t"$(inherited)",',
                '\t\t\t\t\t"@executable_path/Frameworks",',
                "\t\t\t\t);",
                "SUPPORTED_INTERFACE_ORIENTATIONS = UIInterfaceOrientationPortrait;",
            ]
        )
    return "\n".join(f"\t\t\t\t{line}" for line in settings)


def generate_project() -> None:
    generate_app_environment()
    default_server_url = load_env_value("IOS_DEFAULT_SERVER_URL", "https://api.vokrr.com")
    ids = IDPool()
    file_ref_entries: list[str] = []
    build_file_entries: list[str] = []
    group_entries: list[str] = []
    target_files: dict[str, list[Path]] = {}
    target_file_refs: dict[str, dict[Path, str]] = {}
    source_build_ids: dict[str, list[tuple[str, str]]] = {}
    resource_build_ids: dict[str, list[tuple[str, str]]] = {}

    for spec in TARGETS:
        files = collect_project_files(spec.root)
        target_files[spec.name] = files
        refs: dict[Path, str] = {}
        source_build_ids[spec.name] = []
        resource_build_ids[spec.name] = []
        for file in files:
            file_id = ids.next()
            refs[file] = file_id
            file_ref_entries.append(
                f'\t\t{file_id} /* {file.name} */ = {{isa = PBXFileReference; lastKnownFileType = {pbx_file_type(file)}; path = {file.name}; sourceTree = "<group>"; }};'
            )
            phase: str | None = None
            if file.suffix == ".swift":
                phase = "Sources"
            elif file.suffix in {".xcassets", ".xcprivacy", ".ttf", ".otf"}:
                phase = "Resources"
            if phase:
                build_id = ids.next()
                build_file_entries.append(
                    f"\t\t{build_id} /* {file.name} in {phase} */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {file.name} */; }};"
                )
                destination = source_build_ids if phase == "Sources" else resource_build_ids
                destination[spec.name].append((build_id, f"{file.name} in {phase}"))
        target_file_refs[spec.name] = refs

    group_ids: dict[str, str] = {}
    for spec in TARGETS:
        group_ids[spec.name] = render_group(
            spec.name,
            None,
            build_group_tree(target_files[spec.name]),
            target_files[spec.name],
            ids,
            target_file_refs[spec.name],
            group_entries,
        )

    products_group_id = ids.next()
    product_ids = {spec.name: ids.next() for spec in TARGETS}
    product_children = "\n".join(
        f"\t\t\t\t{product_ids[spec.name]} /* {spec.product_name} */," for spec in TARGETS
    )
    group_entries.append(
        f"""\t\t{products_group_id} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{product_children}
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};"""
    )
    root_group_id = ids.next()
    root_children = "\n".join(
        [f"\t\t\t\t{group_ids[spec.name]} /* {spec.name} */," for spec in TARGETS]
        + [f"\t\t\t\t{products_group_id} /* Products */,"]
    )
    group_entries.append(
        f"""\t\t{root_group_id} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{root_children}
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};"""
    )

    phase_ids = {
        spec.name: {"frameworks": ids.next(), "resources": ids.next(), "sources": ids.next()}
        for spec in TARGETS
    }
    embed_phase_id = ids.next()
    target_ids = {spec.name: ids.next() for spec in TARGETS}
    proxy_id = ids.next()
    dependency_id = ids.next()
    embed_build_id = ids.next()
    build_file_entries.append(
        f"\t\t{embed_build_id} /* VokrrWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {product_ids['VokrrWidgets']} /* VokrrWidgets.appex */; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};"
    )
    project_id = ids.next()
    project_config_list_id = ids.next()
    target_config_list_ids = {spec.name: ids.next() for spec in TARGETS}
    project_debug_id, project_release_id = ids.next(), ids.next()
    target_config_ids = {
        spec.name: {"Debug": ids.next(), "Release": ids.next()} for spec in TARGETS
    }

    def phase_lines(entries: list[tuple[str, str]]) -> str:
        return "\n".join(
            f"\t\t\t\t{build_id} /* {comment} */," for build_id, comment in entries
        )

    frameworks_sections: list[str] = []
    resources_sections: list[str] = []
    sources_sections: list[str] = []
    for spec in TARGETS:
        frameworks_sections.append(
            f"""\t\t{phase_ids[spec.name]['frameworks']} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ();
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};"""
        )
        resources_sections.append(
            f"""\t\t{phase_ids[spec.name]['resources']} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{phase_lines(resource_build_ids[spec.name])}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};"""
        )
        sources_sections.append(
            f"""\t\t{phase_ids[spec.name]['sources']} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{phase_lines(source_build_ids[spec.name])}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};"""
        )

    native_targets: list[str] = []
    for spec in TARGETS:
        phases = [
            f"\t\t\t\t{phase_ids[spec.name]['sources']} /* Sources */,",
            f"\t\t\t\t{phase_ids[spec.name]['frameworks']} /* Frameworks */,",
            f"\t\t\t\t{phase_ids[spec.name]['resources']} /* Resources */,",
        ]
        dependencies: list[str] = []
        if not spec.is_extension:
            phases.append(f"\t\t\t\t{embed_phase_id} /* Embed Foundation Extensions */,")
            dependencies.append(f"\t\t\t\t{dependency_id} /* PBXTargetDependency */,")
        native_targets.append(
            f"""\t\t{target_ids[spec.name]} /* {spec.name} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_config_list_ids[spec.name]} /* Build configuration list for PBXNativeTarget "{spec.name}" */;
\t\t\tbuildPhases = (
{chr(10).join(phases)}
\t\t\t);
\t\t\tbuildRules = ();
\t\t\tdependencies = (
{chr(10).join(dependencies)}
\t\t\t);
\t\t\tname = {spec.name};
\t\t\tproductName = {spec.name};
\t\t\tproductReference = {product_ids[spec.name]} /* {spec.product_name} */;
\t\t\tproductType = "{spec.product_type}";
\t\t}};"""
        )

    target_attributes = "\n".join(
        f"\t\t\t\t\t{target_ids[spec.name]} = {{ CreatedOnToolsVersion = 26.3; }};"
        for spec in TARGETS
    )
    project_target_lines = "\n".join(
        f"\t\t\t\t{target_ids[spec.name]} /* {spec.name} */," for spec in TARGETS
    )

    config_entries = [
        f"""\t\t{project_debug_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};""",
        f"""\t\t{project_release_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t}};
\t\t\tname = Release;
\t\t}};""",
    ]
    for spec in TARGETS:
        settings = target_build_settings(spec, default_server_url)
        for configuration in ("Debug", "Release"):
            config_entries.append(
                f"""\t\t{target_config_ids[spec.name][configuration]} /* {configuration} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{settings}
\t\t\t}};
\t\t\tname = {configuration};
\t\t}};"""
            )

    config_lists = [
        f"""\t\t{project_config_list_id} /* Build configuration list for PBXProject "{PROJECT_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{project_debug_id} /* Debug */,
\t\t\t\t{project_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};"""
    ]
    for spec in TARGETS:
        config_lists.append(
            f"""\t\t{target_config_list_ids[spec.name]} /* Build configuration list for PBXNativeTarget "{spec.name}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{target_config_ids[spec.name]['Debug']} /* Debug */,
\t\t\t\t{target_config_ids[spec.name]['Release']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};"""
        )

    product_refs = "\n".join(
        f'\t\t{product_ids[spec.name]} /* {spec.product_name} */ = {{isa = PBXFileReference; explicitFileType = {"wrapper.application" if not spec.is_extension else "wrapper.app-extension"}; includeInIndex = 0; path = {spec.product_name}; sourceTree = BUILT_PRODUCTS_DIR; }};'
        for spec in TARGETS
    )

    pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_entries)}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t{proxy_id} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {project_id} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {target_ids['VokrrWidgets']};
\t\t\tremoteInfo = VokrrWidgets;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t{embed_phase_id} /* Embed Foundation Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{embed_build_id} /* VokrrWidgets.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
{chr(10).join(file_ref_entries)}
{product_refs}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
{chr(10).join(frameworks_sections)}
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{chr(10).join(group_entries)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
{chr(10).join(native_targets)}
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2630;
\t\t\t\tLastUpgradeCheck = 2630;
\t\t\t\tTargetAttributes = {{
{target_attributes}
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_config_list_id} /* Build configuration list for PBXProject "{PROJECT_NAME}" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (en, Base, );
\t\t\tmainGroup = {root_group_id};
\t\t\tproductRefGroup = {products_group_id} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
{project_target_lines}
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{chr(10).join(resources_sections)}
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{chr(10).join(sources_sections)}
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{dependency_id} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {target_ids['VokrrWidgets']} /* VokrrWidgets */;
\t\t\ttargetProxy = {proxy_id} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{chr(10).join(config_entries)}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{chr(10).join(config_lists)}
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
<Workspace version="1.0">
   <FileRef location="self:"></FileRef>
</Workspace>
"""
    )


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
    config_dir = TARGETS[0].root / "Config"
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
