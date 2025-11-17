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
    
    # Collect all input files (go.mod, go.sum, and all transitive source files)
    input_files = [ctx.file.go_mod]
    if ctx.file.go_sum:
        input_files.append(ctx.file.go_sum)
    
    # Add all transitive source files as inputs to ensure dependency tracking
    all_input_files = depset(input_files, transitive = [all_src_files])
    
    # Create output directory
    output_dir = ctx.actions.declare_directory(ctx.attr.name)
    
    # Collect all source files into a list for the script
    src_files_list = all_src_files.to_list()
    
    # Use the external script file
    script_file = ctx.file._script
    
    # Build command arguments: output_dir, go_mod, go_sum, and file pairs
    cmd_args = [output_dir.path, ctx.file.go_mod.path]
    if ctx.file.go_sum:
        cmd_args.append(ctx.file.go_sum.path)
    else:
        cmd_args.append("")
    
    # Add file path pairs (file_path|short_path)
    for src_file in src_files_list:
        cmd_args.append("{}|{}".format(src_file.path, src_file.short_path))
    
    # Run the script
    # Include script_file and all source files in inputs
    all_script_inputs = depset([script_file], transitive = [all_input_files])
    ctx.actions.run(
        inputs = all_script_inputs,
        outputs = [output_dir],
        executable = script_file,
        arguments = cmd_args,
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

