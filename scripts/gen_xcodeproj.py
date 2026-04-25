#!/usr/bin/env python3
"""
gen_xcodeproj.py — Generate TheCouncil.xcodeproj for The Council macOS app.

Produces a correct Xcode 15/16 project.pbxproj with:
  - macOS 15+ deployment, Swift 6 strict concurrency
  - App Sandbox (network.client + file read/write)
  - Two targets: TheCouncil (app) + TheCouncilTests (unit)
  - Phase-0 source stubs referenced in both targets
  - Four SPM packages on main branch: GRDB.swift, KeychainAccess, MLXSwift, swift-markdown
  - Assets.xcassets, Info.plist, TheCouncil.entitlements wired up

Run from the repo root:
    python3 scripts/gen_xcodeproj.py
"""

import hashlib
import os
import textwrap

# ─── Paths ───────────────────────────────────────────────────────────────────

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XCODEPROJ = os.path.join(REPO, "TheCouncil.xcodeproj")
SRC = os.path.join(REPO, "TheCouncil")
TESTS = os.path.join(REPO, "TheCouncilTests")

# ─── Stable UUID factory ──────────────────────────────────────────────────────

_pool: dict[str, str] = {}

def uid(name: str) -> str:
    """Return a stable 24-char uppercase hex UUID derived from *name*."""
    if name not in _pool:
        h = hashlib.sha256(name.encode()).hexdigest()[:24].upper()
        _pool[name] = h
    return _pool[name]

# ─── Source file manifest ─────────────────────────────────────────────────────
# Each entry: (uuid_key, relative_path_from_SRC_or_TESTS, target)
#   target = "app" | "test" | "resource"

APP_SOURCES = [
    # Phase 0
    ("f_app_main",              "App/TheCouncilApp.swift"),
    ("f_content_view",          "App/ContentView.swift"),
    ("f_db_manager",            "Database/DatabaseManager.swift"),
    ("f_migration001",          "Database/Migrations/Migration001_InitialSchema.swift"),
    ("f_keychain_store",        "Keychain/KeychainStore.swift"),
    ("f_model_decision",        "Models/Decision.swift"),
    ("f_model_modelrun",        "Models/ModelRun.swift"),
    ("f_model_argument",        "Models/Argument.swift"),
    ("f_model_cluster",         "Models/Cluster.swift"),
    ("f_model_verdict",         "Models/Verdict.swift"),
    ("f_model_outcome",         "Models/Outcome.swift"),
    ("f_model_appsettings",     "Models/AppSettings.swift"),
    ("f_settings_view",         "Features/Settings/SettingsView.swift"),
    ("f_thisweek_view",         "Features/ThisWeek/ThisWeekView.swift"),
    ("f_allDecisions_view",     "Features/DecisionDetail/AllDecisionsView.swift"),
    # Phase 1
    ("f_streaming_proto",       "APIClients/StreamingChatClient.swift"),
    ("f_anthropic_client",      "APIClients/AnthropicClient.swift"),
    ("f_redaction_engine",      "Features/Refinement/RedactionEngine.swift"),
    ("f_intake_vm",             "Features/Intake/IntakeViewModel.swift"),
    ("f_intake_view",           "Features/Intake/IntakeView.swift"),
    ("f_attachment_view",       "Features/Intake/AttachmentView.swift"),
    ("f_refinement_vm",         "Features/Refinement/RefinementViewModel.swift"),
    ("f_refinement_view",       "Features/Refinement/RefinementView.swift"),
    # Phase 2
    ("f_airgap_guard",          "APIClients/AirGapNetworkGuard.swift"),
    ("f_openai_client",         "APIClients/OpenAIClient.swift"),
    ("f_gemini_client",         "APIClients/GeminiClient.swift"),
    ("f_grok_client",           "APIClients/GrokClient.swift"),
    ("f_lens_template",         "Orchestration/LensTemplate.swift"),
    ("f_lens_loader",           "Orchestration/LensTemplateLoader.swift"),
    ("f_persona",               "Orchestration/Persona.swift"),
    ("f_persona_loader",        "Orchestration/PersonaLoader.swift"),
    ("f_model_spec",            "Orchestration/ModelSpec.swift"),
    ("f_cost_guardrails",       "Orchestration/CostGuardrails.swift"),
    ("f_council_orchestrator",  "Orchestration/CouncilOrchestrator.swift"),
    ("f_config_vm",             "Features/Configuration/CouncilConfigurationViewModel.swift"),
    ("f_config_view",           "Features/Configuration/CouncilConfigurationView.swift"),
    ("f_execution_vm",          "Features/Execution/ExecutionViewModel.swift"),
    ("f_execution_view",        "Features/Execution/ExecutionView.swift"),
    # Phase 3
    ("f_ollama_client",         "APIClients/OllamaClient.swift"),
    ("f_resource_gate",         "LocalInference/LocalResourceGate.swift"),
    ("f_mlx_runner",            "LocalInference/MLXRunner.swift"),
    ("f_model_downloads",       "LocalInference/ModelDownloadManager.swift"),
    # Phase 4
    ("f_debate_engine",         "Orchestration/DebateEngine.swift"),
    ("f_argument_extractor",    "Orchestration/ArgumentExtractor.swift"),
    ("f_clustering_engine",     "Orchestration/ClusteringEngine.swift"),
    # Phase 5
    ("f_force_simulation",      "ForceGraph/ForceSimulation.swift"),
    ("f_quadtree",              "ForceGraph/BarnesHutQuadtree.swift"),
    ("f_graph_vm",              "Features/SynthesisMap/GraphViewModel.swift"),
    ("f_graph_view",            "Features/SynthesisMap/GraphView.swift"),
    ("f_verdict_tray",          "Features/SynthesisMap/VerdictTray.swift"),
    # Phase 6
    ("f_verdict_capture_vm",    "Features/VerdictCapture/VerdictCaptureViewModel.swift"),
    ("f_verdict_capture_view",  "Features/VerdictCapture/VerdictCaptureView.swift"),
]

TEST_SOURCES = [
    # Phase 0
    ("f_test_migrations",       "Database/DatabaseMigrationTests.swift"),
    ("f_test_keychain",         "Keychain/KeychainStoreTests.swift"),
    ("f_test_forcegraph",       "ForceGraph/ForceSimulationTests.swift"),
    # Phase 1
    ("f_test_intake",           "Intake/IntakeValidationTests.swift"),
    ("f_test_redaction",        "Refinement/RedactionEngineTests.swift"),
    ("f_test_anthropic",        "APIClients/AnthropicClientTests.swift"),
    # Phase 2
    ("f_test_openai",           "APIClients/OpenAIClientTests.swift"),
    ("f_test_gemini",           "APIClients/GeminiClientTests.swift"),
    ("f_test_grok",             "APIClients/GrokClientTests.swift"),
    ("f_test_lens_loader",      "Orchestration/LensTemplateLoaderTests.swift"),
    ("f_test_persona_loader",   "Orchestration/PersonaLoaderTests.swift"),
    ("f_test_cost",             "Orchestration/CostGuardrailTests.swift"),
    ("f_test_orchestrator",     "Orchestration/CouncilOrchestratorTests.swift"),
    # Phase 3
    ("f_test_airgap",           "APIClients/AirGapNetworkGuardTests.swift"),
    ("f_test_ollama",           "APIClients/OllamaClientTests.swift"),
    ("f_test_resource_gate",    "LocalInference/LocalResourceGateTests.swift"),
    ("f_test_mlx_runner",       "LocalInference/MLXRunnerTests.swift"),
    ("f_test_model_downloads",  "LocalInference/ModelDownloadManagerTests.swift"),
    # Phase 4
    ("f_test_debate",           "Orchestration/DebateEngineTests.swift"),
    ("f_test_extractor",        "Orchestration/ArgumentExtractorTests.swift"),
    ("f_test_clustering",       "Orchestration/ClusteringEngineTests.swift"),
    # Phase 5
    ("f_test_quadtree",         "ForceGraph/BarnesHutQuadtreeTests.swift"),
    ("f_test_graph_vm",         "SynthesisMap/GraphViewModelTests.swift"),
    # Phase 6
    ("f_test_verdict_capture",  "VerdictCapture/VerdictCaptureTests.swift"),
    # Diagnostics (opt-in, gated by RUN_DIAGNOSTICS env var)
    ("f_test_diagnostics",      "Diagnostics/APIConnectivityDiagnostic.swift"),
]

SPM_PACKAGES = [
    # (pkg_uid_key, prod_uid_key, bf_uid_key, repo_url, product_name, branch)
    ("pkg_grdb",      "prod_grdb",      "bf_grdb",      "https://github.com/groue/GRDB.swift",        "GRDB",           "master"),
    ("pkg_keychain",  "prod_keychain",  "bf_keychain",  "https://github.com/kishikawakatsumi/KeychainAccess", "KeychainAccess", "master"),
    ("pkg_mlx",       "prod_mlx",       "bf_mlx",       "https://github.com/ml-explore/mlx-swift",    "MLX",            "main"),
    ("pkg_markdown",  "prod_markdown",  "bf_markdown",  "https://github.com/apple/swift-markdown",    "Markdown",       "main"),
]

# ─── pbxproj generator ───────────────────────────────────────────────────────

def pbxproj() -> str:
    lines = []

    def w(s=""):
        lines.append(s)

    # Header
    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 77;")
    w("\tobjects = {")
    w()

    # ── PBXBuildFile ─────────────────────────────────────────────────────────
    w("/* Begin PBXBuildFile section */")

    # App source build files
    for key, path in APP_SOURCES:
        name = os.path.basename(path)
        w(f"\t\t{uid('bf_'+key)} /* {name} in Sources */ = "
          f"{{isa = PBXBuildFile; fileRef = {uid(key)} /* {name} */; }};")

    # Asset catalog build file
    w(f"\t\t{uid('bf_assets')} /* Assets.xcassets in Resources */ = "
      f"{{isa = PBXBuildFile; fileRef = {uid('f_assets')} /* Assets.xcassets */; }};")

    # Folder reference build files (lens templates + personas)
    w(f"\t\t{uid('bf_lens_folder')} /* LensTemplates in Resources */ = "
      f"{{isa = PBXBuildFile; fileRef = {uid('f_lens_folder')} /* LensTemplates */; }};")
    w(f"\t\t{uid('bf_persona_folder')} /* Personas in Resources */ = "
      f"{{isa = PBXBuildFile; fileRef = {uid('f_persona_folder')} /* Personas */; }};")

    # Test source build files
    for key, path in TEST_SOURCES:
        name = os.path.basename(path)
        w(f"\t\t{uid('bf_'+key)} /* {name} in Sources */ = "
          f"{{isa = PBXBuildFile; fileRef = {uid(key)} /* {name} */; }};")

    # SPM product build files
    for pkg_key, prod_key, bf_key, _, product, _branch in SPM_PACKAGES:
        w(f"\t\t{uid(bf_key)} /* {product} in Frameworks */ = "
          f"{{isa = PBXBuildFile; productRef = {uid(prod_key)} /* {product} */; }};")

    w("/* End PBXBuildFile section */")

    # ── PBXFileReference ─────────────────────────────────────────────────────
    w("/* Begin PBXFileReference section */")

    # App product
    w(f"\t\t{uid('f_app_product')} /* TheCouncil.app */ = "
      f"{{isa = PBXFileReference; explicitFileType = wrapper.application; "
      f"includeInIndex = 0; path = TheCouncil.app; sourceTree = BUILT_PRODUCTS_DIR; }};")

    # Test product
    w(f"\t\t{uid('f_test_product')} /* TheCouncilTests.xctest */ = "
      f"{{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; "
      f"includeInIndex = 0; path = TheCouncilTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")

    # Entitlements
    w(f"\t\t{uid('f_entitlements')} /* TheCouncil.entitlements */ = "
      f"{{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; "
      f"path = TheCouncil.entitlements; sourceTree = \"<group>\"; }};")

    # Info.plist
    w(f"\t\t{uid('f_infoplist')} /* Info.plist */ = "
      f"{{isa = PBXFileReference; lastKnownFileType = text.plist.xml; "
      f"path = Info.plist; sourceTree = \"<group>\"; }};")

    # Assets
    w(f"\t\t{uid('f_assets')} /* Assets.xcassets */ = "
      f"{{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; "
      f"path = Assets.xcassets; sourceTree = \"<group>\"; }};")

    # Resource folder references (blue folders — recursive, preserve structure)
    w(f"\t\t{uid('f_lens_folder')} /* LensTemplates */ = "
      f"{{isa = PBXFileReference; lastKnownFileType = folder; "
      f"path = LensTemplates; sourceTree = \"<group>\"; }};")
    w(f"\t\t{uid('f_persona_folder')} /* Personas */ = "
      f"{{isa = PBXFileReference; lastKnownFileType = folder; "
      f"path = Personas; sourceTree = \"<group>\"; }};")

    # App sources
    for key, path in APP_SOURCES:
        name = os.path.basename(path)
        w(f"\t\t{uid(key)} /* {name} */ = "
          f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
          f"path = {name}; sourceTree = \"<group>\"; }};")

    # Test sources
    for key, path in TEST_SOURCES:
        name = os.path.basename(path)
        w(f"\t\t{uid(key)} /* {name} */ = "
          f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
          f"path = {name}; sourceTree = \"<group>\"; }};")

    w("/* End PBXFileReference section */")

    # ── PBXFrameworksBuildPhase ───────────────────────────────────────────────
    w("/* Begin PBXFrameworksBuildPhase section */")

    # App frameworks phase
    w(f"\t\t{uid('app_frameworks_phase')} /* Frameworks */ = {{")
    w(f"\t\t\tisa = PBXFrameworksBuildPhase;")
    w(f"\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = (")
    for _, _, bf_key, _, product, _ in SPM_PACKAGES:
        w(f"\t\t\t\t{uid(bf_key)} /* {product} in Frameworks */,")
    w(f"\t\t\t);")
    w(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w(f"\t\t}};")

    # Test frameworks phase (empty — tests import via @testable import)
    w(f"\t\t{uid('test_frameworks_phase')} /* Frameworks */ = {{")
    w(f"\t\t\tisa = PBXFrameworksBuildPhase;")
    w(f"\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = (")
    w(f"\t\t\t);")
    w(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w(f"\t\t}};")

    w("/* End PBXFrameworksBuildPhase section */")

    # ── PBXGroup ─────────────────────────────────────────────────────────────
    w("/* Begin PBXGroup section */")

    # Main group (root)
    w(f"\t\t{uid('main_group')} = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('grp_thecouncil')} /* TheCouncil */,")
    w(f"\t\t\t\t{uid('grp_tests_root')} /* TheCouncilTests */,")
    w(f"\t\t\t\t{uid('products_group')} /* Products */,")
    w(f"\t\t\t\t{uid('frameworks_group')} /* Frameworks */,")
    w(f"\t\t\t);")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Products group
    w(f"\t\t{uid('products_group')} /* Products */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_app_product')} /* TheCouncil.app */,")
    w(f"\t\t\t\t{uid('f_test_product')} /* TheCouncilTests.xctest */,")
    w(f"\t\t\t);")
    w(f"\t\t\tname = Products;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Frameworks group (SPM)
    w(f"\t\t{uid('frameworks_group')} /* Frameworks */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t);")
    w(f"\t\t\tname = Frameworks;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # TheCouncil source group
    w(f"\t\t{uid('grp_thecouncil')} /* TheCouncil */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('grp_app')} /* App */,")
    w(f"\t\t\t\t{uid('grp_database')} /* Database */,")
    w(f"\t\t\t\t{uid('grp_keychain')} /* Keychain */,")
    w(f"\t\t\t\t{uid('grp_models')} /* Models */,")
    w(f"\t\t\t\t{uid('grp_api_clients')} /* APIClients */,")
    w(f"\t\t\t\t{uid('grp_local_inference')} /* LocalInference */,")
    w(f"\t\t\t\t{uid('grp_orchestration')} /* Orchestration */,")
    w(f"\t\t\t\t{uid('grp_features')} /* Features */,")
    w(f"\t\t\t\t{uid('grp_forcegraph')} /* ForceGraph */,")
    w(f"\t\t\t\t{uid('grp_resources')} /* Resources */,")
    w(f"\t\t\t\t{uid('f_assets')} /* Assets.xcassets */,")
    w(f"\t\t\t\t{uid('f_entitlements')} /* TheCouncil.entitlements */,")
    w(f"\t\t\t\t{uid('f_infoplist')} /* Info.plist */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = TheCouncil;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # App sub-group
    w(f"\t\t{uid('grp_app')} /* App */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_app_main')} /* TheCouncilApp.swift */,")
    w(f"\t\t\t\t{uid('f_content_view')} /* ContentView.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = App;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Database sub-group
    w(f"\t\t{uid('grp_database')} /* Database */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_db_manager')} /* DatabaseManager.swift */,")
    w(f"\t\t\t\t{uid('grp_migrations')} /* Migrations */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Database;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Migrations sub-group
    w(f"\t\t{uid('grp_migrations')} /* Migrations */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_migration001')} /* Migration001_InitialSchema.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Migrations;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Keychain sub-group
    w(f"\t\t{uid('grp_keychain')} /* Keychain */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_keychain_store')} /* KeychainStore.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Keychain;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Models sub-group
    w(f"\t\t{uid('grp_models')} /* Models */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_model_decision')} /* Decision.swift */,")
    w(f"\t\t\t\t{uid('f_model_modelrun')} /* ModelRun.swift */,")
    w(f"\t\t\t\t{uid('f_model_argument')} /* Argument.swift */,")
    w(f"\t\t\t\t{uid('f_model_cluster')} /* Cluster.swift */,")
    w(f"\t\t\t\t{uid('f_model_verdict')} /* Verdict.swift */,")
    w(f"\t\t\t\t{uid('f_model_outcome')} /* Outcome.swift */,")
    w(f"\t\t\t\t{uid('f_model_appsettings')} /* AppSettings.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Models;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # APIClients group (Phase 1+)
    w(f"\t\t{uid('grp_api_clients')} /* APIClients */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_streaming_proto')} /* StreamingChatClient.swift */,")
    w(f"\t\t\t\t{uid('f_anthropic_client')} /* AnthropicClient.swift */,")
    w(f"\t\t\t\t{uid('f_airgap_guard')} /* AirGapNetworkGuard.swift */,")
    w(f"\t\t\t\t{uid('f_openai_client')} /* OpenAIClient.swift */,")
    w(f"\t\t\t\t{uid('f_gemini_client')} /* GeminiClient.swift */,")
    w(f"\t\t\t\t{uid('f_grok_client')} /* GrokClient.swift */,")
    w(f"\t\t\t\t{uid('f_ollama_client')} /* OllamaClient.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = APIClients;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # LocalInference group (Phase 3)
    w(f"\t\t{uid('grp_local_inference')} /* LocalInference */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_resource_gate')} /* LocalResourceGate.swift */,")
    w(f"\t\t\t\t{uid('f_mlx_runner')} /* MLXRunner.swift */,")
    w(f"\t\t\t\t{uid('f_model_downloads')} /* ModelDownloadManager.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = LocalInference;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Orchestration group (Phase 2)
    w(f"\t\t{uid('grp_orchestration')} /* Orchestration */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_lens_template')} /* LensTemplate.swift */,")
    w(f"\t\t\t\t{uid('f_lens_loader')} /* LensTemplateLoader.swift */,")
    w(f"\t\t\t\t{uid('f_persona')} /* Persona.swift */,")
    w(f"\t\t\t\t{uid('f_persona_loader')} /* PersonaLoader.swift */,")
    w(f"\t\t\t\t{uid('f_model_spec')} /* ModelSpec.swift */,")
    w(f"\t\t\t\t{uid('f_cost_guardrails')} /* CostGuardrails.swift */,")
    w(f"\t\t\t\t{uid('f_council_orchestrator')} /* CouncilOrchestrator.swift */,")
    w(f"\t\t\t\t{uid('f_debate_engine')} /* DebateEngine.swift */,")
    w(f"\t\t\t\t{uid('f_argument_extractor')} /* ArgumentExtractor.swift */,")
    w(f"\t\t\t\t{uid('f_clustering_engine')} /* ClusteringEngine.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Orchestration;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # ForceGraph group (Phase 5)
    w(f"\t\t{uid('grp_forcegraph')} /* ForceGraph */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_force_simulation')} /* ForceSimulation.swift */,")
    w(f"\t\t\t\t{uid('f_quadtree')} /* BarnesHutQuadtree.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = ForceGraph;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Features sub-group
    w(f"\t\t{uid('grp_features')} /* Features */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('grp_feat_intake')} /* Intake */,")
    w(f"\t\t\t\t{uid('grp_feat_refinement')} /* Refinement */,")
    w(f"\t\t\t\t{uid('grp_feat_config')} /* Configuration */,")
    w(f"\t\t\t\t{uid('grp_feat_execution')} /* Execution */,")
    w(f"\t\t\t\t{uid('grp_feat_settings')} /* Settings */,")
    w(f"\t\t\t\t{uid('grp_feat_thisweek')} /* ThisWeek */,")
    w(f"\t\t\t\t{uid('grp_feat_alldecisions')} /* DecisionDetail */,")
    w(f"\t\t\t\t{uid('grp_feat_synthesis')} /* SynthesisMap */,")
    w(f"\t\t\t\t{uid('grp_feat_verdict')} /* VerdictCapture */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Features;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Configuration feature group (Phase 2)
    w(f"\t\t{uid('grp_feat_config')} /* Configuration */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_config_vm')} /* CouncilConfigurationViewModel.swift */,")
    w(f"\t\t\t\t{uid('f_config_view')} /* CouncilConfigurationView.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Configuration;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Execution feature group (Phase 2)
    w(f"\t\t{uid('grp_feat_execution')} /* Execution */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_execution_vm')} /* ExecutionViewModel.swift */,")
    w(f"\t\t\t\t{uid('f_execution_view')} /* ExecutionView.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Execution;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Resources group (Phase 2)
    w(f"\t\t{uid('grp_resources')} /* Resources */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_lens_folder')} /* LensTemplates */,")
    w(f"\t\t\t\t{uid('f_persona_folder')} /* Personas */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Resources;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Intake feature group (Phase 1)
    w(f"\t\t{uid('grp_feat_intake')} /* Intake */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_intake_vm')} /* IntakeViewModel.swift */,")
    w(f"\t\t\t\t{uid('f_intake_view')} /* IntakeView.swift */,")
    w(f"\t\t\t\t{uid('f_attachment_view')} /* AttachmentView.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Intake;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Refinement feature group (Phase 1)
    w(f"\t\t{uid('grp_feat_refinement')} /* Refinement */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_redaction_engine')} /* RedactionEngine.swift */,")
    w(f"\t\t\t\t{uid('f_refinement_vm')} /* RefinementViewModel.swift */,")
    w(f"\t\t\t\t{uid('f_refinement_view')} /* RefinementView.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Refinement;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Settings feature group
    w(f"\t\t{uid('grp_feat_settings')} /* Settings */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_settings_view')} /* SettingsView.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Settings;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # ThisWeek feature group
    w(f"\t\t{uid('grp_feat_thisweek')} /* ThisWeek */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_thisweek_view')} /* ThisWeekView.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = ThisWeek;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # AllDecisions feature group
    w(f"\t\t{uid('grp_feat_alldecisions')} /* DecisionDetail */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_allDecisions_view')} /* AllDecisionsView.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = DecisionDetail;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # SynthesisMap feature group (Phase 5)
    w(f"\t\t{uid('grp_feat_synthesis')} /* SynthesisMap */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_graph_vm')} /* GraphViewModel.swift */,")
    w(f"\t\t\t\t{uid('f_graph_view')} /* GraphView.swift */,")
    w(f"\t\t\t\t{uid('f_verdict_tray')} /* VerdictTray.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = SynthesisMap;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # VerdictCapture feature group (Phase 6)
    w(f"\t\t{uid('grp_feat_verdict')} /* VerdictCapture */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_verdict_capture_vm')} /* VerdictCaptureViewModel.swift */,")
    w(f"\t\t\t\t{uid('f_verdict_capture_view')} /* VerdictCaptureView.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = VerdictCapture;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Tests root group
    w(f"\t\t{uid('grp_tests_root')} /* TheCouncilTests */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('grp_tests_db')} /* Database */,")
    w(f"\t\t\t\t{uid('grp_tests_keychain')} /* Keychain */,")
    w(f"\t\t\t\t{uid('grp_tests_fg')} /* ForceGraph */,")
    w(f"\t\t\t\t{uid('grp_tests_intake')} /* Intake */,")
    w(f"\t\t\t\t{uid('grp_tests_refinement')} /* Refinement */,")
    w(f"\t\t\t\t{uid('grp_tests_api')} /* APIClients */,")
    w(f"\t\t\t\t{uid('grp_tests_orch')} /* Orchestration */,")
    w(f"\t\t\t\t{uid('grp_tests_local')} /* LocalInference */,")
    w(f"\t\t\t\t{uid('grp_tests_synthesis')} /* SynthesisMap */,")
    w(f"\t\t\t\t{uid('grp_tests_verdict')} /* VerdictCapture */,")
    w(f"\t\t\t\t{uid('grp_tests_diagnostics')} /* Diagnostics */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = TheCouncilTests;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    w(f"\t\t{uid('grp_tests_db')} /* Database */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_migrations')} /* DatabaseMigrationTests.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Database;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    w(f"\t\t{uid('grp_tests_keychain')} /* Keychain */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_keychain')} /* KeychainStoreTests.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Keychain;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    w(f"\t\t{uid('grp_tests_fg')} /* ForceGraph */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_forcegraph')} /* ForceSimulationTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_quadtree')} /* BarnesHutQuadtreeTests.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = ForceGraph;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    w(f"\t\t{uid('grp_tests_intake')} /* Intake */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_intake')} /* IntakeValidationTests.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Intake;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    w(f"\t\t{uid('grp_tests_refinement')} /* Refinement */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_redaction')} /* RedactionEngineTests.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Refinement;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    w(f"\t\t{uid('grp_tests_api')} /* APIClients */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_anthropic')} /* AnthropicClientTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_openai')} /* OpenAIClientTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_gemini')} /* GeminiClientTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_grok')} /* GrokClientTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_airgap')} /* AirGapNetworkGuardTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_ollama')} /* OllamaClientTests.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = APIClients;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    w(f"\t\t{uid('grp_tests_orch')} /* Orchestration */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_lens_loader')} /* LensTemplateLoaderTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_persona_loader')} /* PersonaLoaderTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_cost')} /* CostGuardrailTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_orchestrator')} /* CouncilOrchestratorTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_debate')} /* DebateEngineTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_extractor')} /* ArgumentExtractorTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_clustering')} /* ClusteringEngineTests.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Orchestration;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # LocalInference tests group (Phase 3)
    w(f"\t\t{uid('grp_tests_local')} /* LocalInference */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_resource_gate')} /* LocalResourceGateTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_mlx_runner')} /* MLXRunnerTests.swift */,")
    w(f"\t\t\t\t{uid('f_test_model_downloads')} /* ModelDownloadManagerTests.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = LocalInference;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")


    # SynthesisMap tests group (Phase 5)
    w(f"\t\t{uid('grp_tests_synthesis')} /* SynthesisMap */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_graph_vm')} /* GraphViewModelTests.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = SynthesisMap;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # VerdictCapture tests group (Phase 6)
    w(f"\t\t{uid('grp_tests_verdict')} /* VerdictCapture */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_verdict_capture')} /* VerdictCaptureTests.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = VerdictCapture;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Diagnostics tests group (opt-in)
    w(f"\t\t{uid('grp_tests_diagnostics')} /* Diagnostics */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{uid('f_test_diagnostics')} /* APIConnectivityDiagnostic.swift */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Diagnostics;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")
    w("/* End PBXGroup section */")

    # ── PBXNativeTarget ───────────────────────────────────────────────────────
    w("/* Begin PBXNativeTarget section */")

    # App target
    w(f"\t\t{uid('app_target')} /* TheCouncil */ = {{")
    w(f"\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {uid('app_config_list')} /* Build configuration list for PBXNativeTarget \"TheCouncil\" */;")
    w(f"\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{uid('app_sources_phase')} /* Sources */,")
    w(f"\t\t\t\t{uid('app_frameworks_phase')} /* Frameworks */,")
    w(f"\t\t\t\t{uid('app_resources_phase')} /* Resources */,")
    w(f"\t\t\t);")
    w(f"\t\t\tbuildRules = (")
    w(f"\t\t\t);")
    w(f"\t\t\tdependencies = (")
    w(f"\t\t\t);")
    w(f"\t\t\tname = TheCouncil;")
    w(f"\t\t\tpackageProductDependencies = (")
    for _, prod_key, _, _, product, _branch in SPM_PACKAGES:
        w(f"\t\t\t\t{uid(prod_key)} /* {product} */,")
    w(f"\t\t\t);")
    w(f"\t\t\tproductName = TheCouncil;")
    w(f"\t\t\tproductReference = {uid('f_app_product')} /* TheCouncil.app */;")
    w(f"\t\t\tproductType = \"com.apple.product-type.application\";")
    w(f"\t\t}};")

    # Test target
    w(f"\t\t{uid('test_target')} /* TheCouncilTests */ = {{")
    w(f"\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {uid('test_config_list')} /* Build configuration list for PBXNativeTarget \"TheCouncilTests\" */;")
    w(f"\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{uid('test_sources_phase')} /* Sources */,")
    w(f"\t\t\t\t{uid('test_frameworks_phase')} /* Frameworks */,")
    w(f"\t\t\t);")
    w(f"\t\t\tbuildRules = (")
    w(f"\t\t\t);")
    w(f"\t\t\tdependencies = (")
    w(f"\t\t\t\t{uid('test_dep_on_app')} /* PBXTargetDependency */,")
    w(f"\t\t\t);")
    w(f"\t\t\tname = TheCouncilTests;")
    w(f"\t\t\tpackageProductDependencies = (")
    w(f"\t\t\t);")
    w(f"\t\t\tproductName = TheCouncilTests;")
    w(f"\t\t\tproductReference = {uid('f_test_product')} /* TheCouncilTests.xctest */;")
    w(f"\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    w(f"\t\t}};")

    w("/* End PBXNativeTarget section */")

    # ── PBXProject ────────────────────────────────────────────────────────────
    w("/* Begin PBXProject section */")
    w(f"\t\t{uid('project')} /* Project object */ = {{")
    w(f"\t\t\tisa = PBXProject;")
    w(f"\t\t\tattributes = {{")
    w(f"\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w(f"\t\t\t\tLastSwiftUpdateCheck = 2600;")
    w(f"\t\t\t\tLastUpgradeCheck = 2600;")
    w(f"\t\t\t\tTargetAttributes = {{")
    w(f"\t\t\t\t\t{uid('app_target')} = {{")
    w(f"\t\t\t\t\t\tCreatedOnToolsVersion = 16.1;")
    w(f"\t\t\t\t\t}};")
    w(f"\t\t\t\t\t{uid('test_target')} = {{")
    w(f"\t\t\t\t\t\tCreatedOnToolsVersion = 16.1;")
    w(f"\t\t\t\t\t\tTestTargetID = {uid('app_target')};")
    w(f"\t\t\t\t\t}};")
    w(f"\t\t\t\t}};")
    w(f"\t\t\t}};")
    w(f"\t\t\tbuildConfigurationList = {uid('proj_config_list')} /* Build configuration list for PBXProject \"TheCouncil\" */;")
    w(f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    w(f"\t\t\tdevelopmentRegion = en;")
    w(f"\t\t\thasScannedForEncodings = 0;")
    w(f"\t\t\tknownRegions = (")
    w(f"\t\t\t\ten,")
    w(f"\t\t\t\tBase,")
    w(f"\t\t\t);")
    w(f"\t\t\tmainGroup = {uid('main_group')};")
    w(f"\t\t\tpackageReferences = (")
    for pkg_key, _, _, repo, product, _branch in SPM_PACKAGES:
        w(f"\t\t\t\t{uid(pkg_key)} /* XCRemoteSwiftPackageReference \"{product}\" */,")
    w(f"\t\t\t);")
    w(f"\t\t\tproductRefGroup = {uid('products_group')} /* Products */;")
    w(f"\t\t\tprojectDirPath = \"\";")
    w(f"\t\t\tprojectRoot = \"\";")
    w(f"\t\t\ttargets = (")
    w(f"\t\t\t\t{uid('app_target')} /* TheCouncil */,")
    w(f"\t\t\t\t{uid('test_target')} /* TheCouncilTests */,")
    w(f"\t\t\t);")
    w(f"\t\t}};")
    w("/* End PBXProject section */")

    # ── PBXResourcesBuildPhase ────────────────────────────────────────────────
    w("/* Begin PBXResourcesBuildPhase section */")
    w(f"\t\t{uid('app_resources_phase')} /* Resources */ = {{")
    w(f"\t\t\tisa = PBXResourcesBuildPhase;")
    w(f"\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = (")
    w(f"\t\t\t\t{uid('bf_assets')} /* Assets.xcassets in Resources */,")
    w(f"\t\t\t\t{uid('bf_lens_folder')} /* LensTemplates in Resources */,")
    w(f"\t\t\t\t{uid('bf_persona_folder')} /* Personas in Resources */,")
    w(f"\t\t\t);")
    w(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w(f"\t\t}};")
    w("/* End PBXResourcesBuildPhase section */")

    # ── PBXSourcesBuildPhase ──────────────────────────────────────────────────
    w("/* Begin PBXSourcesBuildPhase section */")

    w(f"\t\t{uid('app_sources_phase')} /* Sources */ = {{")
    w(f"\t\t\tisa = PBXSourcesBuildPhase;")
    w(f"\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = (")
    for key, path in APP_SOURCES:
        name = os.path.basename(path)
        w(f"\t\t\t\t{uid('bf_'+key)} /* {name} in Sources */,")
    w(f"\t\t\t);")
    w(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w(f"\t\t}};")

    w(f"\t\t{uid('test_sources_phase')} /* Sources */ = {{")
    w(f"\t\t\tisa = PBXSourcesBuildPhase;")
    w(f"\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = (")
    for key, path in TEST_SOURCES:
        name = os.path.basename(path)
        w(f"\t\t\t\t{uid('bf_'+key)} /* {name} in Sources */,")
    w(f"\t\t\t);")
    w(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w(f"\t\t}};")

    w("/* End PBXSourcesBuildPhase section */")

    # ── PBXTargetDependency ───────────────────────────────────────────────────
    w("/* Begin PBXTargetDependency section */")
    w(f"\t\t{uid('test_dep_on_app')} /* PBXTargetDependency */ = {{")
    w(f"\t\t\tisa = PBXTargetDependency;")
    w(f"\t\t\ttarget = {uid('app_target')} /* TheCouncil */;")
    w(f"\t\t\ttargetProxy = {uid('test_proxy')} /* PBXContainerItemProxy */;")
    w(f"\t\t}};")
    w("/* End PBXTargetDependency section */")

    # ── PBXContainerItemProxy ─────────────────────────────────────────────────
    w("/* Begin PBXContainerItemProxy section */")
    w(f"\t\t{uid('test_proxy')} /* PBXContainerItemProxy */ = {{")
    w(f"\t\t\tisa = PBXContainerItemProxy;")
    w(f"\t\t\tcontainerPortal = {uid('project')} /* Project object */;")
    w(f"\t\t\tproxyType = 1;")
    w(f"\t\t\tremoteGlobalIDString = {uid('app_target')};")
    w(f"\t\t\tremoteInfo = TheCouncil;")
    w(f"\t\t}};")
    w("/* End PBXContainerItemProxy section */")

    # ── XCBuildConfiguration ──────────────────────────────────────────────────
    w("/* Begin XCBuildConfiguration section */")

    # Project-level Debug
    w(f"\t\t{uid('proj_debug')} /* Debug */ = {{")
    w(f"\t\t\tisa = XCBuildConfiguration;")
    w(f"\t\t\tbuildSettings = {{")
    w(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    w(f"\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    w(f"\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;")
    w(f"\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    w(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    w(f"\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    w(f"\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;")
    w(f"\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;")
    w(f"\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_COMMA = YES;")
    w(f"\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;")
    w(f"\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;")
    w(f"\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;")
    w(f"\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;")
    w(f"\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;")
    w(f"\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;")
    w(f"\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;")
    w(f"\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;")
    w(f"\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;")
    w(f"\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;")
    w(f"\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;")
    w(f"\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;")
    w(f"\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;")
    w(f"\t\t\t\tCOPY_PHASE_STRIP = NO;")
    w(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
    w(f"\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    w(f"\t\t\t\tENABLE_TESTABILITY = YES;")
    w(f"\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;")
    w(f"\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
    w(f"\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
    w(f"\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    w(f"\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
    w(f"\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (")
    w(f"\t\t\t\t\t\"DEBUG=1\",")
    w(f"\t\t\t\t\t\"$(inherited)\",")
    w(f"\t\t\t\t);")
    w(f"\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
    w(f"\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
    w(f"\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
    w(f"\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
    w(f"\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
    w(f"\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
    w(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;")
    w(f"\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
    w(f"\t\t\t\tMTL_FAST_MATH = YES;")
    w(f"\t\t\t\tONLY_ACTIVE_ARCH = YES;")
    w(f"\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
    w(f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    w(f"\t\t\t}};")
    w(f"\t\t\tname = Debug;")
    w(f"\t\t}};")

    # Project-level Release
    w(f"\t\t{uid('proj_release')} /* Release */ = {{")
    w(f"\t\t\tisa = XCBuildConfiguration;")
    w(f"\t\t\tbuildSettings = {{")
    w(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    w(f"\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    w(f"\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;")
    w(f"\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    w(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    w(f"\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    w(f"\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;")
    w(f"\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;")
    w(f"\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_COMMA = YES;")
    w(f"\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;")
    w(f"\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;")
    w(f"\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;")
    w(f"\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;")
    w(f"\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;")
    w(f"\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;")
    w(f"\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;")
    w(f"\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;")
    w(f"\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;")
    w(f"\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;")
    w(f"\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;")
    w(f"\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;")
    w(f"\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;")
    w(f"\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;")
    w(f"\t\t\t\tCOPY_PHASE_STRIP = NO;")
    w(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
    w(f"\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
    w(f"\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    w(f"\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;")
    w(f"\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
    w(f"\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    w(f"\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
    w(f"\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
    w(f"\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
    w(f"\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
    w(f"\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
    w(f"\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
    w(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;")
    w(f"\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;")
    w(f"\t\t\t\tMTL_FAST_MATH = YES;")
    w(f"\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    w(f"\t\t\t}};")
    w(f"\t\t\tname = Release;")
    w(f"\t\t}};")

    def app_build_settings(config_name: str) -> list[str]:
        is_debug = config_name == "Debug"
        s = [
            "\t\t\t\tCODE_SIGN_ENTITLEMENTS = TheCouncil/TheCouncil.entitlements;",
            "\t\t\t\tCODE_SIGN_STYLE = Automatic;",
            "\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;",
            "\t\t\t\tCURRENT_PROJECT_VERSION = 1;",
            "\t\t\t\tENABLE_HARDENED_RUNTIME = YES;",
            "\t\t\t\tINFOPLIST_FILE = TheCouncil/Info.plist;",
            "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (",
            "\t\t\t\t\t\"$(inherited)\",",
            "\t\t\t\t\t\"@executable_path/../Frameworks\",",
            "\t\t\t\t);",
            "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;",
            "\t\t\t\tMARKETING_VERSION = 1.0;",
            "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.benpodbielski.thecouncil;",
            "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";",
            "\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;",
            "\t\t\t\tSWIFT_VERSION = 6.0;",
        ]
        if is_debug:
            s += [
                "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
                "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
                "\t\t\t\tDEAD_CODE_STRIPPING = NO;",
            ]
        else:
            s += [
                "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";",
                "\t\t\t\tDEAD_CODE_STRIPPING = YES;",
            ]
        return s

    def test_build_settings(config_name: str) -> list[str]:
        s = [
            f"\t\t\t\tBUNDLE_LOADER = \"$(BUILT_PRODUCTS_DIR)/TheCouncil.app/Contents/MacOS/TheCouncil\";",
            "\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;",
            "\t\t\t\tCURRENT_PROJECT_VERSION = 1;",
            "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;",
            "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;",
            "\t\t\t\tMARKETING_VERSION = 1.0;",
            "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.benpodbielski.thecouncil.tests;",
            "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";",
            "\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;",
            "\t\t\t\tSWIFT_VERSION = 6.0;",
            f"\t\t\t\tTEST_HOST = \"$(BUILT_PRODUCTS_DIR)/TheCouncil.app/Contents/MacOS/TheCouncil\";",
        ]
        if config_name == "Debug":
            s += [
                "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
                "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
            ]
        return s

    for cfg_uid, cfg_name, settings_fn in [
        (uid('app_debug'),   "Debug",   app_build_settings),
        (uid('app_release'), "Release", app_build_settings),
    ]:
        w(f"\t\t{cfg_uid} /* {cfg_name} */ = {{")
        w(f"\t\t\tisa = XCBuildConfiguration;")
        w(f"\t\t\tbuildSettings = {{")
        for line in settings_fn(cfg_name):
            w(line)
        w(f"\t\t\t}};")
        w(f"\t\t\tname = {cfg_name};")
        w(f"\t\t}};")

    for cfg_uid, cfg_name, settings_fn in [
        (uid('test_debug'),   "Debug",   test_build_settings),
        (uid('test_release'), "Release", test_build_settings),
    ]:
        w(f"\t\t{cfg_uid} /* {cfg_name} */ = {{")
        w(f"\t\t\tisa = XCBuildConfiguration;")
        w(f"\t\t\tbuildSettings = {{")
        for line in settings_fn(cfg_name):
            w(line)
        w(f"\t\t\t}};")
        w(f"\t\t\tname = {cfg_name};")
        w(f"\t\t}};")

    w("/* End XCBuildConfiguration section */")

    # ── XCConfigurationList ───────────────────────────────────────────────────
    w("/* Begin XCConfigurationList section */")

    w(f"\t\t{uid('proj_config_list')} /* Build configuration list for PBXProject \"TheCouncil\" */ = {{")
    w(f"\t\t\tisa = XCConfigurationList;")
    w(f"\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{uid('proj_debug')} /* Debug */,")
    w(f"\t\t\t\t{uid('proj_release')} /* Release */,")
    w(f"\t\t\t);")
    w(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    w(f"\t\t\tdefaultConfigurationName = Release;")
    w(f"\t\t}};")

    w(f"\t\t{uid('app_config_list')} /* Build configuration list for PBXNativeTarget \"TheCouncil\" */ = {{")
    w(f"\t\t\tisa = XCConfigurationList;")
    w(f"\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{uid('app_debug')} /* Debug */,")
    w(f"\t\t\t\t{uid('app_release')} /* Release */,")
    w(f"\t\t\t);")
    w(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    w(f"\t\t\tdefaultConfigurationName = Release;")
    w(f"\t\t}};")

    w(f"\t\t{uid('test_config_list')} /* Build configuration list for PBXNativeTarget \"TheCouncilTests\" */ = {{")
    w(f"\t\t\tisa = XCConfigurationList;")
    w(f"\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{uid('test_debug')} /* Debug */,")
    w(f"\t\t\t\t{uid('test_release')} /* Release */,")
    w(f"\t\t\t);")
    w(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    w(f"\t\t\tdefaultConfigurationName = Release;")
    w(f"\t\t}};")

    w("/* End XCConfigurationList section */")

    # ── XCRemoteSwiftPackageReference ─────────────────────────────────────────
    w("/* Begin XCRemoteSwiftPackageReference section */")
    for pkg_key, _, _, repo, product, branch in SPM_PACKAGES:
        w(f"\t\t{uid(pkg_key)} /* XCRemoteSwiftPackageReference \"{product}\" */ = {{")
        w(f"\t\t\tisa = XCRemoteSwiftPackageReference;")
        w(f"\t\t\trepositoryURL = \"{repo}\";")
        w(f"\t\t\trequirement = {{")
        w(f"\t\t\t\tbranch = {branch};")
        w(f"\t\t\t\tkind = branch;")
        w(f"\t\t\t}};")
        w(f"\t\t}};")
    w("/* End XCRemoteSwiftPackageReference section */")

    # ── XCSwiftPackageProductDependency ───────────────────────────────────────
    w("/* Begin XCSwiftPackageProductDependency section */")
    for pkg_key, prod_key, _, _, product, _branch in SPM_PACKAGES:
        w(f"\t\t{uid(prod_key)} /* {product} */ = {{")
        w(f"\t\t\tisa = XCSwiftPackageProductDependency;")
        w(f"\t\t\tpackage = {uid(pkg_key)} /* XCRemoteSwiftPackageReference \"{product}\" */;")
        w(f"\t\t\tproductName = {product};")
        w(f"\t\t}};")
    w("/* End XCSwiftPackageProductDependency section */")

    # ── Close ─────────────────────────────────────────────────────────────────
    w("\t};")
    w(f"\trootObject = {uid('project')} /* Project object */;")
    w("}")

    return "\n".join(lines)


# ─── Support file creators ────────────────────────────────────────────────────

def write_entitlements():
    path = os.path.join(SRC, "TheCouncil.entitlements")
    content = textwrap.dedent("""\
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.security.app-sandbox</key>
            <true/>
            <key>com.apple.security.network.client</key>
            <true/>
            <key>com.apple.security.files.user-selected.read-write</key>
            <true/>
        </dict>
        </plist>
    """)
    with open(path, "w") as f:
        f.write(content)
    print(f"  wrote {os.path.relpath(path, REPO)}")


def write_infoplist():
    path = os.path.join(SRC, "Info.plist")
    content = textwrap.dedent("""\
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>$(DEVELOPMENT_LANGUAGE)</string>
            <key>CFBundleExecutable</key>
            <string>$(EXECUTABLE_NAME)</string>
            <key>CFBundleIdentifier</key>
            <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>$(PRODUCT_NAME)</string>
            <key>CFBundlePackageType</key>
            <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
            <key>CFBundleShortVersionString</key>
            <string>$(MARKETING_VERSION)</string>
            <key>CFBundleVersion</key>
            <string>$(CURRENT_PROJECT_VERSION)</string>
            <key>LSMinimumSystemVersion</key>
            <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
            <key>NSHumanReadableCopyright</key>
            <string>Copyright © 2026 Ben Podbielski. All rights reserved.</string>
            <key>NSPrincipalClass</key>
            <string>NSApplication</string>
        </dict>
        </plist>
    """)
    with open(path, "w") as f:
        f.write(content)
    print(f"  wrote {os.path.relpath(path, REPO)}")


def write_assets():
    catalog = os.path.join(SRC, "Assets.xcassets")
    os.makedirs(catalog, exist_ok=True)
    contents_path = os.path.join(catalog, "Contents.json")
    if not os.path.exists(contents_path):
        with open(contents_path, "w") as f:
            f.write('{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    print(f"  wrote {os.path.relpath(catalog, REPO)}/Contents.json")


def write_workspace():
    ws = os.path.join(XCODEPROJ, "project.xcworkspace")
    os.makedirs(ws, exist_ok=True)
    contents = os.path.join(ws, "contents.xcworkspacedata")
    with open(contents, "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<Workspace version = "1.0">\n'
                '   <FileRef location = "self:"></FileRef>\n'
                '</Workspace>\n')
    print(f"  wrote {os.path.relpath(contents, REPO)}")


# ─── Swift stub creator ───────────────────────────────────────────────────────

def stub(rel_src_path: str, content: str, base: str = SRC):
    abs_path = os.path.join(base, rel_src_path)
    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    if not os.path.exists(abs_path):
        with open(abs_path, "w") as f:
            f.write(content)
        print(f"  stub  {os.path.relpath(abs_path, REPO)}")
    else:
        print(f"  skip  {os.path.relpath(abs_path, REPO)} (exists)")


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    print(f"\n=== Generating TheCouncil.xcodeproj ===\n")

    # 1. Create directory structure
    os.makedirs(XCODEPROJ, exist_ok=True)
    os.makedirs(SRC, exist_ok=True)
    os.makedirs(TESTS, exist_ok=True)

    # 2. Write project.pbxproj
    pbxproj_path = os.path.join(XCODEPROJ, "project.pbxproj")
    with open(pbxproj_path, "w") as f:
        f.write(pbxproj())
    print(f"  wrote TheCouncil.xcodeproj/project.pbxproj")

    # 3. Workspace stub
    write_workspace()

    # 4. Support files
    write_entitlements()
    write_infoplist()
    write_assets()

    # 5. Swift stubs — app target
    stub("App/TheCouncilApp.swift",
         "import SwiftUI\n\n@main\nstruct TheCouncilApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}\n")

    stub("App/ContentView.swift",
         "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"The Council\")\n    }\n}\n")

    for key, rel_path in APP_SOURCES:
        if rel_path in ("App/TheCouncilApp.swift", "App/ContentView.swift"):
            continue
        name = os.path.splitext(os.path.basename(rel_path))[0]
        stub(rel_path, f"// {name}.swift — stub\nimport Foundation\n")

    # 6. Swift stubs — test target
    for key, rel_path in TEST_SOURCES:
        name = os.path.splitext(os.path.basename(rel_path))[0]
        stub(rel_path,
             f"import XCTest\n@testable import TheCouncil\n\nfinal class {name}: XCTestCase {{\n}}\n",
             base=TESTS)

    print(f"\n=== Done ===\n")
    print("Next: open TheCouncil.xcodeproj in Xcode and resolve SPM packages,")
    print("  or run: xcodebuild -resolvePackageDependencies -project TheCouncil.xcodeproj\n")


if __name__ == "__main__":
    main()
