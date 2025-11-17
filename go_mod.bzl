"""Custom rule to generate go.mod and go.sum from Bazel dependencies."""

load("@rules_go//go:def.bzl", "GoInfo")

def _collect_srcs(srcs):
    """Convert srcs to depset, handling both list and depset types."""
    if type(srcs) == type([]):
        return depset(srcs)
    return srcs

def _go_mod_aspect_impl(target, ctx):
    """Aspect to collect all transitive source files (.go, .h, .s/.asm, and go:embed files)."""
    src_files = depset()
    
    # Collect source files from this target
    if GoInfo in target:
        go_info = target[GoInfo]
        
        # Collect .go source files (srcs is a list of File objects)
        if hasattr(go_info, "srcs"):
            src_files = depset(transitive = [src_files, depset(go_info.srcs)])
        
        # Collect CGO header files (.h) - check embedsrcs which may contain embedded files
        if hasattr(go_info, "embedsrcs"):
            src_files = depset(transitive = [src_files, _collect_srcs(go_info.embedsrcs)])
    
    # Collect from dependencies (aspect will be applied transitively)
    if hasattr(ctx.rule.attr, "deps"):
        for dep in ctx.rule.attr.deps:
            if hasattr(dep, "go_mod_sources"):
                src_files = depset(transitive = [src_files, dep.go_mod_sources])
    
    # Also collect embedded libraries
    if hasattr(ctx.rule.attr, "embed"):
        for embed in ctx.rule.attr.embed:
            if hasattr(embed, "go_mod_sources"):
                src_files = depset(transitive = [src_files, embed.go_mod_sources])
    
    return struct(go_mod_sources = src_files)

_go_mod_aspect = aspect(
    implementation = _go_mod_aspect_impl,
    attr_aspects = ["deps", "embed"],
)

def _go_mod_impl(ctx):
    """Implementation of the go_mod rule."""
    
    # Collect all transitive source files using the aspect
    all_src_files = depset()
    for dep in ctx.attr.deps:
        if hasattr(dep, "go_mod_sources"):
            all_src_files = depset(transitive = [all_src_files, dep.go_mod_sources])
        # Also collect direct source files from GoInfo (all file types)
        if GoInfo in dep:
            go_info = dep[GoInfo]
            # Collect .go source files (srcs is a list of File objects)
            if hasattr(go_info, "srcs"):
                all_src_files = depset(transitive = [all_src_files, depset(go_info.srcs)])
            # Collect go:embed files (embedsrcs)
            if hasattr(go_info, "embedsrcs"):
                all_src_files = depset(transitive = [all_src_files, _collect_srcs(go_info.embedsrcs)])
    
    # Create output directory
    output_dir = ctx.actions.declare_directory(ctx.attr.name)
    
    # Ensure go.sum exists - create empty file if not provided
    go_sum_file = ctx.file.go_sum
    if not go_sum_file:
        go_sum_file = ctx.actions.declare_file(ctx.attr.name + "_empty.sum")
        ctx.actions.write(
            output = go_sum_file,
            content = "",
        )
    
    # Collect all input files
    input_files = [ctx.file.go_mod, go_sum_file]
    
    # Map files to their importpaths by tracking which GoInfo they come from
    file_to_importpath = {}
    for dep in ctx.attr.deps:
        if GoInfo in dep:
            go_info = dep[GoInfo]
            importpath = go_info.importpath
            if hasattr(go_info, "srcs"):
                for src_file in go_info.srcs:
                    # Check if file is from external repository
                    owner = src_file.owner
                    if owner and owner.workspace_name:
                        continue
                    if src_file.short_path.startswith("external/"):
                        continue
                    file_to_importpath[src_file] = importpath
            if hasattr(go_info, "embedsrcs"):
                for embed_file in go_info.embedsrcs:
                    owner = embed_file.owner
                    if owner and owner.workspace_name:
                        continue
                    if embed_file.short_path.startswith("external/"):
                        continue
                    file_to_importpath[embed_file] = importpath
    
    # Add all source files to inputs
    workspace_files_list = list(file_to_importpath.keys())
    all_input_files = depset(input_files + workspace_files_list, transitive = [all_src_files])
    
    # Use the external script file
    script_file = ctx.file._script
    
    # Build command arguments: src_file importpath pairs
    cmd_args = []
    for src_file, importpath in file_to_importpath.items():
        cmd_args.append(src_file.path)
        cmd_args.append(importpath)
    
    # Run the script with environment variables
    all_script_inputs = depset([script_file], transitive = [all_input_files])
    ctx.actions.run(
        inputs = all_script_inputs,
        outputs = [output_dir],
        executable = script_file,
        arguments = cmd_args,
        env = {
            "OUT_DIR": output_dir.path,
            "GO_MOD": ctx.file.go_mod.path,
            "GO_SUM": go_sum_file.path,
            "MODULE_PATH": ctx.attr.importpath,
        },
        mnemonic = "GoModDirectory",
    )
    
    return [
        DefaultInfo(
            files = depset([output_dir]),
            runfiles = ctx.runfiles(
                files = [output_dir],
                transitive_files = all_src_files,
            ),
        ),
    ]

go_mod = rule(
    implementation = _go_mod_impl,
    attrs = {
        "importpath": attr.string(
            mandatory = True,
            doc = "The Go module import path (e.g., example.com/my/module)",
        ),
        "go_mod": attr.label(
            mandatory = True,
            allow_single_file = [".mod"],
            doc = "The go.mod file to use as a template",
        ),
        "go_sum": attr.label(
            allow_single_file = [".sum"],
            doc = "Optional go.sum file",
        ),
        "deps": attr.label_list(
            providers = [GoInfo],
            aspects = [_go_mod_aspect],
            doc = "List of Go library or deps targets to include in the module",
        ),
        "_script": attr.label(
            default = "//:go_mod_script.sh",
            allow_single_file = True,
            doc = "The shell script to copy files",
        ),
    },
    doc = "Generates go.mod and go.sum files from Bazel Go dependencies. Depends transitively on all source files.",
)

