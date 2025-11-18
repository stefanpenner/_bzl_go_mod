"""Custom rule to generate go.mod and go.sum from Bazel dependencies."""

load("@rules_go//go:def.bzl", "GoInfo")

def _collect_srcs(srcs):
    """Convert srcs to depset, handling both list and depset types."""
    if type(srcs) == type([]):
        return depset(srcs)
    return srcs

def _go_mod_aspect_impl(target, ctx):
    """Aspect to collect all transitive source files mapped to their importpaths."""
    local_mappings = []

    # Collect source files from this target and map them to its importpath.
    if GoInfo in target:
        go_info = target[GoInfo]
        importpath = getattr(go_info, "importpath", None)

        if importpath:
            # Collect .go source files
            if hasattr(go_info, "srcs"):
                srcs_depset = _collect_srcs(go_info.srcs)
                for f in srcs_depset.to_list():
                    local_mappings.append(struct(file = f, importpath = importpath))

            # Collect go:embed resource files if the Go toolchain exposes them.
            if hasattr(go_info, "embedsrcs"):
                for f in _collect_srcs(go_info.embedsrcs).to_list():
                    local_mappings.append(struct(file = f, importpath = importpath))

            # Collect any additional sources/data that are listed on the rule (e.g., .txt files).
            if hasattr(ctx.rule, "files"):
                if hasattr(ctx.rule.files, "srcs"):
                    srcs_files = _collect_srcs(ctx.rule.files.srcs)
                    for f in srcs_files.to_list():
                        local_mappings.append(struct(file = f, importpath = importpath))
                if hasattr(ctx.rule.files, "data"):
                    data_files = _collect_srcs(ctx.rule.files.data)
                    for f in data_files.to_list():
                        local_mappings.append(struct(file = f, importpath = importpath))

    # Collect transitive mappings from dependencies and embedded libraries using depsets.
    transitive_mappings_depsets = []
    for attr_name in ["deps", "embed"]:
        if hasattr(ctx.rule.attr, attr_name):
            for dep in getattr(ctx.rule.attr, attr_name):
                if hasattr(dep, "go_mod_mappings"):
                    # go_mod_mappings is a depset, collect it for transitive merging
                    transitive_mappings_depsets.append(dep.go_mod_mappings)

    # Create depset from local mappings and merge with transitive depsets
    local_mappings_depset = depset(local_mappings)
    if transitive_mappings_depsets:
        return struct(
            go_mod_mappings = depset(transitive = [local_mappings_depset] + transitive_mappings_depsets),
        )
    else:
        return struct(
            go_mod_mappings = local_mappings_depset,
        )

_go_mod_aspect = aspect(
    implementation = _go_mod_aspect_impl,
    attr_aspects = ["deps", "embed"],
)

def _go_mod_impl(ctx):
    """Implementation of the go_mod rule."""
    
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
    
    # Map files to their importpaths using mappings computed by the aspect.
    # Collect all mappings from deps using depsets to avoid compilation dependencies
    all_mappings_depsets = []
    workspace_files_depsets = []
    file_to_importpath = {}
    
    for dep in ctx.attr.deps:
        if hasattr(dep, "go_mod_mappings"):
            all_mappings_depsets.append(dep.go_mod_mappings)
    
    # Merge all mappings depsets and process them
    if all_mappings_depsets:
        merged_mappings = depset(transitive = all_mappings_depsets)
        for entry in merged_mappings.to_list():
            src_file = entry.file
            importpath = entry.importpath
            # Skip external repository files.
            owner = src_file.owner
            if owner and owner.workspace_name:
                continue
            if src_file.short_path.startswith("external/"):
                continue
            file_to_importpath[src_file] = importpath
        
        # Create depset of workspace files
        workspace_files_depsets = [depset(list(file_to_importpath.keys()))]
    
    # Add all source files to inputs using depset
    all_input_files = depset(input_files, transitive = workspace_files_depsets)
    
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
            "MODULE_PATH": ctx.attr.module_path,
        },
        mnemonic = "GoModDirectory",
    )
    
    return [
        DefaultInfo(
            files = depset([output_dir]),
        ),
    ]

go_mod = rule(
    implementation = _go_mod_impl,
    attrs = {
        "module_path": attr.string(
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
            default = "@bazel_go_mod//rules/go_mod:go_mod_script.sh",
            allow_single_file = True,
            doc = "The shell script to copy files",
        ),
    },
    doc = "Generates go.mod and go.sum files from Bazel Go dependencies. Depends transitively on all source files.",
)

