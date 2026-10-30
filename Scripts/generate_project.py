#!/usr/bin/env python3
"""Deterministic Xcode project with local Swift Package, no external generator."""
import hashlib, json
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
project = ROOT / "ChaiAIStory.xcodeproj"
project.mkdir(exist_ok=True)
objects = {}
def oid(key): return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
def add(key, value):
    objects[oid(key)] = value
    return oid(key)
def q(value): return json.dumps(str(value), ensure_ascii=False)
files, builds = [], []
for path in sorted((ROOT / "ChaiAIStory").glob("*.swift")):
    rel = path.relative_to(ROOT).as_posix()
    ref = add(rel, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+q(rel)+'; sourceTree = "<group>"; }')
    files.append(ref)
    builds.append(add("build:"+rel, "{isa = PBXBuildFile; fileRef = "+ref+"; }"))
assets = add("assets", '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Resources/Assets.xcassets; sourceTree = "<group>"; }')
assetbuild = add("assetbuild", "{isa = PBXBuildFile; fileRef = "+assets+"; }")
privacy = add("privacy", '{isa = PBXFileReference; lastKnownFileType = text.xml; path = Resources/PrivacyInfo.xcprivacy; sourceTree = "<group>"; }')
privacybuild = add("privacybuild", "{isa = PBXBuildFile; fileRef = "+privacy+"; }")
product = add("product", '{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ChaiAIStory.app; sourceTree = BUILT_PRODUCTS_DIR; }')
package = add("package", '{isa = XCLocalSwiftPackageReference; relativePath = "."; }')
dependency = add("dependency", '{isa = XCSwiftPackageProductDependency; productName = StoryCore; }')
framework = add("framework", "{isa = PBXBuildFile; productRef = "+dependency+"; }")
sources = add("sources", "{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ("+",".join(builds)+"); runOnlyForDeploymentPostprocessing = 0; }")
resources = add("resources", "{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ("+assetbuild+","+privacybuild+"); runOnlyForDeploymentPostprocessing = 0; }")
frameworks = add("frameworks", "{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ("+framework+"); runOnlyForDeploymentPostprocessing = 0; }")
products = add("products", "{isa = PBXGroup; children = ("+product+"); name = Products; sourceTree = \"<group>\"; }")
group = add("group", "{isa = PBXGroup; children = ("+",".join(files+[assets,privacy,products])+"); sourceTree = \"<group>\"; }")
common = {"SWIFT_VERSION":"5.0", "IPHONEOS_DEPLOYMENT_TARGET":"17.0", "SDKROOT":"iphoneos",
 "CODE_SIGNING_ALLOWED":"NO", "CODE_SIGNING_REQUIRED":"NO", "CODE_SIGN_IDENTITY":"",
 "ENABLE_USER_SCRIPT_SANDBOXING":"YES", "CLANG_ENABLE_MODULES":"YES",
 "TARGETED_DEVICE_FAMILY":"1", "PRODUCT_BUNDLE_IDENTIFIER":"com.kongdean.ChaiAIStory",
 "PRODUCT_NAME":"$(TARGET_NAME)", "INFOPLIST_FILE":"Resources/Info.plist",
 "ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon", "GENERATE_INFOPLIST_FILE":"NO",
 "MARKETING_VERSION":"1.0", "CURRENT_PROJECT_VERSION":"1",
 "LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/Frameworks",
 "SUPPORTED_PLATFORMS":"iphoneos iphonesimulator", "SWIFT_EMIT_LOC_STRINGS":"YES"}
configs=[]
for name in ["Debug","Release"]:
    settings = dict(common, SWIFT_OPTIMIZATION_LEVEL="-Onone" if name=="Debug" else "-O",
                    DEBUG_INFORMATION_FORMAT="dwarf" if name=="Debug" else "dwarf-with-dsym")
    if name=="Debug":
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]="DEBUG"
        settings["ENABLE_TESTABILITY"]="YES"
        settings["ONLY_ACTIVE_ARCH"]="YES"
    configs.append(add(name, "{isa = XCBuildConfiguration; name = "+name+"; buildSettings = {"+"".join(k+" = "+q(v)+";" for k,v in settings.items())+"}; }"))
configlist = add("configlist", "{isa = XCConfigurationList; buildConfigurations = ("+",".join(configs)+"); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }")
target = add("target", "{isa = PBXNativeTarget; buildConfigurationList = "+configlist+"; buildPhases = ("+",".join([sources,frameworks,resources])+"); buildRules = (); dependencies = (); name = ChaiAIStory; packageProductDependencies = ("+dependency+"); productName = ChaiAIStory; productReference = "+product+"; productType = \"com.apple.product-type.application\"; }")
uitestfile = add("uitestfile", '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UITests/ChaiAIStoryUITests.swift; sourceTree = SOURCE_ROOT; }')
uitestbuild = add("uitestbuild", "{isa = PBXBuildFile; fileRef = "+uitestfile+"; }")
uisources = add("uisources", "{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ("+uitestbuild+"); runOnlyForDeploymentPostprocessing = 0; }")
uiproduct = add("uiproduct", '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = ChaiAIStoryUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }')
uiconfigs=[]
for name in ["Debug", "Release"]:
    settings = {"SWIFT_VERSION":"5.0", "IPHONEOS_DEPLOYMENT_TARGET":"17.0", "SDKROOT":"iphoneos", "PRODUCT_BUNDLE_IDENTIFIER":"com.kongdean.ChaiAIStory.UITests", "PRODUCT_NAME":"$(TARGET_NAME)", "TEST_TARGET_NAME":"ChaiAIStory", "GENERATE_INFOPLIST_FILE":"YES", "CODE_SIGNING_ALLOWED":"NO", "TARGETED_DEVICE_FAMILY":"1"}
    uiconfigs.append(add("ui"+name, "{isa = XCBuildConfiguration; name = "+name+"; buildSettings = {"+"".join(k+" = "+q(v)+";" for k,v in settings.items())+"}; }"))
uiconfiglist=add("uiconfiglist","{isa = XCConfigurationList; buildConfigurations = ("+",".join(uiconfigs)+"); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }")
proxy=add("uiproxy","{isa = PBXContainerItemProxy; containerPortal = "+oid("project")+"; proxyType = 1; remoteGlobalIDString = "+target+"; remoteInfo = ChaiAIStory; }")
uidependency=add("uitargetdep","{isa = PBXTargetDependency; target = "+target+"; targetProxy = "+proxy+"; }")
uitarget=add("uitarget", "{isa = PBXNativeTarget; buildConfigurationList = "+uiconfiglist+"; buildPhases = ("+uisources+"); buildRules = (); dependencies = ("+uidependency+"); name = ChaiAIStoryUITests; productName = ChaiAIStoryUITests; productReference = "+uiproduct+"; productType = "+q("com.apple.product-type.bundle.ui-testing")+"; }")
objects[group]=objects[group].replace(products+");",products+","+uitestfile+");")
objects[products]=objects[products].replace(product+");",product+","+uiproduct+");")
projectconfigs=[]
for name in ["Debug","Release"]:
    projectconfigs.append(add("project"+name, "{isa = XCBuildConfiguration; name = "+name+"; buildSettings = {SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; }; }"))
projectconfiglist=add("projectconfiglist", "{isa = XCConfigurationList; buildConfigurations = ("+",".join(projectconfigs)+"); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }")
root = add("project", "{isa = PBXProject; attributes = {LastUpgradeCheck = 1600; }; buildConfigurationList = "+projectconfiglist+"; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = \"zh-Hant\"; hasScannedForEncodings = 0; knownRegions = (\"zh-Hant\",en,Base); mainGroup = "+group+"; packageReferences = ("+package+"); productRefGroup = "+products+"; projectDirPath = \"\"; projectRoot = \"\"; targets = ("+target+","+uitarget+"); }")
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"+"\n".join(k+" = "+v+";" for k,v in objects.items())+"\n}; rootObject = "+root+"; }\n")
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes/"ChaiAIStory.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="ChaiAIStory.app" BlueprintName="ChaiAIStory" ReferencedContainer="container:ChaiAIStory.xcodeproj"/>
</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uitarget}" BuildableName="ChaiAIStoryUITests.xctest" BlueprintName="ChaiAIStoryUITests" ReferencedContainer="container:ChaiAIStory.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES">
<BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="ChaiAIStory.app" BlueprintName="ChaiAIStory" ReferencedContainer="container:ChaiAIStory.xcodeproj"/></BuildableProductRunnable>
</LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print("Generated ChaiAIStory.xcodeproj")
