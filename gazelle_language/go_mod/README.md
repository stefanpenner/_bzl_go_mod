# go_mod bzl rule with corresponding gazelle language rule

Ensure gazelle manages `go_mod` rules, via

```sh
bazel run gazelle
```

which uses a custom gazelle language extension:
```
"@bazel_go_mod//gazelle_language/go_mod:go_mod",
```

via:

```starlark
gazelle_binary(
    name = "gazelle_with_go_mod",
    languages = [
        "@gazelle//language/go",
        "@gazelle//language/proto",
        "@bazel_go_mod//gazelle_language/go_mod:go_mod",
    ],
    visibility = ["//visibility:public"],
)
```

Then any directory with a go.mod file, will get a :go_mod_dir target

```sh
bazel build //rules/go_mod/testdata:go_mod_dir
```
Which produces:

```sh
tree  bazel-bin/rules/go_mod/testdata/go_mod_dir
bazel-bin/rules/go_mod/testdata/go_mod_dir
└── rules
    └── go_mod
        └── testdata
            ├── go.mod
            ├── go.sum
            ├── cmd
            │   └── app
            │       └── main.go
            ├── embedfs
            │   ├── data.txt
            │   └── embedfs.go
            ├── models
            │   └── user.go
            └── utils
                └── utils.go
```