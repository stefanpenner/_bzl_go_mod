package go_modlang

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/bazelbuild/bazel-gazelle/rule"
)

func TestParseModulePath(t *testing.T) {
	t.Run("parses module directive", func(t *testing.T) {
		dir := t.TempDir()
		path := filepath.Join(dir, "go.mod")

		const contents = `
module example.com/demo

go 1.25
`
		if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
			t.Fatalf("WriteFile: %v", err)
		}

		got, err := parseModulePath(path)
		if err != nil {
			t.Fatalf("parseModulePath returned error: %v", err)
		}
		if got != "example.com/demo" {
			t.Fatalf("parseModulePath = %q, want %q", got, "example.com/demo")
		}
	})
}

func TestCollectGoLibraries(t *testing.T) {
	f := rule.EmptyFile("BUILD.bazel", "")
	r1 := rule.NewRule("go_library", "lib1")
	r2 := rule.NewRule("go_binary", "bin")
	r3 := rule.NewRule("go_library", "lib2")

	f.Rules = append(f.Rules, r1, r2, r3)

	got := collectGoLibraries(f)
	want := []string{":lib1", ":lib2"}

	if len(got) != len(want) {
		t.Fatalf("collectGoLibraries len = %d, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("collectGoLibraries[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}
