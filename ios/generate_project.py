#!/usr/bin/env python3
"""Generate a valid Xcode project.pbxproj for RefPlane iOS app."""

import uuid
import os

def gen_uuid():
    return uuid.uuid4().hex[:24].upper()

# All Swift source files
BASE = "/home/runner/work/RefPlane/RefPlane/ios/RefPlane"
SWIFT_FILES = [
    ("RefPlaneApp.swift",                 "RefPlaneApp.swift"),
    ("Models/AppModels.swift",            "AppModels.swift"),
    ("Models/AppState.swift",             "AppState.swift"),
    ("Processing/OklabColorSpace.swift",  "OklabColorSpace.swift"),
    ("Processing/KMeansClusterer.swift",  "KMeansClusterer.swift"),
    ("Processing/RegionCleaner.swift",    "RegionCleaner.swift"),
    ("Processing/GrayscaleProcessor.swift","GrayscaleProcessor.swift"),
    ("Processing/ValueStudyProcessor.swift","ValueStudyProcessor.swift"),
    ("Processing/ColorRegionsProcessor.swift","ColorRegionsProcessor.swift"),
    ("Processing/ImageSimplifier.swift",  "ImageSimplifier.swift"),
    ("Processing/ImageProcessor.swift",   "ImageProcessor.swift"),
    ("Processing/UIImageExtensions.swift","UIImageExtensions.swift"),
    ("Views/ContentView.swift",           "ContentView.swift"),
    ("Views/ImageCanvasView.swift",       "ImageCanvasView.swift"),
    ("Views/ControlPanelView.swift",      "ControlPanelView.swift"),
    ("Views/ModeBarView.swift",           "ModeBarView.swift"),
    ("Views/ValueSettingsView.swift",     "ValueSettingsView.swift"),
    ("Views/ColorSettingsView.swift",     "ColorSettingsView.swift"),
    ("Views/GridSettingsView.swift",      "GridSettingsView.swift"),
    ("Views/GridOverlayView.swift",       "GridOverlayView.swift"),
    ("Views/CompareView.swift",           "CompareView.swift"),
    ("Views/CropView.swift",              "CropView.swift"),
    ("Views/PaletteView.swift",           "PaletteView.swift"),
    ("Views/ActionBarView.swift",         "ActionBarView.swift"),
    ("Views/ImagePickerView.swift",       "ImagePickerView.swift"),
    ("Views/ErrorToastView.swift",        "ErrorToastView.swift"),
    ("Views/ThresholdSliderView.swift",   "ThresholdSliderView.swift"),
]

# Assign unique IDs to everything
PROJECT_UUID       = gen_uuid()
TARGET_UUID        = gen_uuid()
BUILD_CONF_LIST_PROJ = gen_uuid()
BUILD_CONF_LIST_TGT  = gen_uuid()
DEBUG_CONF_UUID_PROJ = gen_uuid()
RELEASE_CONF_UUID_PROJ = gen_uuid()
DEBUG_CONF_UUID_TGT  = gen_uuid()
RELEASE_CONF_UUID_TGT = gen_uuid()
SOURCES_PHASE_UUID  = gen_uuid()
RESOURCES_PHASE_UUID = gen_uuid()
FRAMEWORKS_PHASE_UUID = gen_uuid()
MAIN_GROUP_UUID     = gen_uuid()
PRODUCTS_GROUP_UUID = gen_uuid()
APP_PRODUCT_UUID    = gen_uuid()
APP_REF_UUID        = gen_uuid()

# Group UUIDs
MODELS_GROUP  = gen_uuid()
PROC_GROUP    = gen_uuid()
VIEWS_GROUP   = gen_uuid()
ASSETS_FILE   = gen_uuid()
ASSETS_BUILD  = gen_uuid()
ROOT_GROUP    = gen_uuid()

# Per-file IDs
file_refs   = {}  # path -> fileRef UUID
build_files = {}  # path -> buildFile UUID

for rel_path, name in SWIFT_FILES:
    file_refs[rel_path]   = gen_uuid()
    build_files[rel_path] = gen_uuid()

# -----------------------------------------------------------------------
def pbx_file_ref(uuid, name, rel_path):
    return f'\t\t{uuid} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {name}; path = {rel_path}; sourceTree = "<group>"; }};'

def pbx_build_file(build_uuid, file_uuid, name):
    return f'\t\t{build_uuid} = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {name} */; }};'

def pbx_group(uuid, name, children, path=None):
    children_str = "\n".join(f"\t\t\t\t{c}," for c in children)
    path_str = f'path = {path};' if path else f'name = {name};'
    return f"""\t\t{uuid} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children_str}
\t\t\t);
\t\t\t{path_str}
\t\t\tsourceTree = "<group>";
\t\t}};"""

# Collect file refs by group
model_files = [(r, n) for r, n in SWIFT_FILES if r.startswith("Models/")]
proc_files  = [(r, n) for r, n in SWIFT_FILES if r.startswith("Processing/")]
view_files  = [(r, n) for r, n in SWIFT_FILES if r.startswith("Views/")]
root_files  = [(r, n) for r, n in SWIFT_FILES if "/" not in r]

PBXPROJ = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(pbx_build_file(build_files[r], file_refs[r], n) for r, n in SWIFT_FILES)}
\t\t{ASSETS_BUILD} = {{isa = PBXBuildFile; fileRef = {ASSETS_FILE} /* Assets.xcassets */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(pbx_file_ref(file_refs[r], n, r) for r, n in SWIFT_FILES)}
\t\t{ASSETS_FILE} = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
\t\t{APP_PRODUCT_UUID} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = RefPlane.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FRAMEWORKS_PHASE_UUID} = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{pbx_group(MODELS_GROUP, "Models", [file_refs[r] for r, n in model_files])}
{pbx_group(PROC_GROUP, "Processing", [file_refs[r] for r, n in proc_files])}
{pbx_group(VIEWS_GROUP, "Views", [file_refs[r] for r, n in view_files])}
{pbx_group(PRODUCTS_GROUP_UUID, "Products", [APP_PRODUCT_UUID])}
\t\t{MAIN_GROUP_UUID} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(f"\t\t\t\t{file_refs[r]}," for r, n in root_files)}
\t\t\t\t{MODELS_GROUP},
\t\t\t\t{PROC_GROUP},
\t\t\t\t{VIEWS_GROUP},
\t\t\t\t{ASSETS_FILE},
\t\t\t\t{PRODUCTS_GROUP_UUID},
\t\t\t);
\t\t\tpath = RefPlane;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{ROOT_GROUP} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{MAIN_GROUP_UUID},
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{TARGET_UUID} = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {BUILD_CONF_LIST_TGT};
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_PHASE_UUID},
\t\t\t\t{RESOURCES_PHASE_UUID},
\t\t\t\t{FRAMEWORKS_PHASE_UUID},
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = RefPlane;
\t\t\tproductName = RefPlane;
\t\t\tproductReference = {APP_PRODUCT_UUID};
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{PROJECT_UUID} = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{TARGET_UUID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {BUILD_CONF_LIST_PROJ};
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {ROOT_GROUP};
\t\t\tproductRefGroup = {PRODUCTS_GROUP_UUID};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{TARGET_UUID},
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{RESOURCES_PHASE_UUID} = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{ASSETS_BUILD} /* Assets.xcassets */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{SOURCES_PHASE_UUID} = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(f"\t\t\t\t{build_files[r]} /* {n} */," for r, n in SWIFT_FILES)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{DEBUG_CONF_UUID_PROJ} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{RELEASE_CONF_UUID_PROJ} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{DEBUG_CONF_UUID_TGT} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_NSPhotoLibraryUsageDescription = "RefPlane needs access to your photo library to open reference images.";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLE_SWIFT_VERSION = 5.0;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.refplane.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{RELEASE_CONF_UUID_TGT} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_NSPhotoLibraryUsageDescription = "RefPlane needs access to your photo library to open reference images.";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLE_SWIFT_VERSION = 5.0;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.refplane.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{BUILD_CONF_LIST_PROJ} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{DEBUG_CONF_UUID_PROJ} /* Debug */,
\t\t\t\t{RELEASE_CONF_UUID_PROJ} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{BUILD_CONF_LIST_TGT} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{DEBUG_CONF_UUID_TGT} /* Debug */,
\t\t\t\t{RELEASE_CONF_UUID_TGT} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

\t}};
\trootObject = {PROJECT_UUID};
}}
"""

out_path = "/home/runner/work/RefPlane/RefPlane/ios/RefPlane.xcodeproj/project.pbxproj"
with open(out_path, "w") as f:
    f.write(PBXPROJ)

print(f"Generated: {out_path}")
print(f"File size: {os.path.getsize(out_path):,} bytes")
