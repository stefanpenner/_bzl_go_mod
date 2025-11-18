package go_mod

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/language"
	"github.com/bazelbuild/bazel-gazelle/repo"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// goModLanguage implements Gazelle's language.Language interface and is responsible
// for generating a single go_mod rule for each Bazel package that contains a
// go.mod file. It only considers go_library targets, never go_binary.
type goModLanguage struct {
	go_library_targets []string
}

// NewLanguage is the constructor that Gazelle looks for when loading this extension.
func NewLanguage() language.Language {
	return &goModLanguage{}
}

func (*goModLanguage) Name() string {
	return "go_mod"
}

func (*goModLanguage) Kinds() map[string]rule.KindInfo {
	return map[string]rule.KindInfo{
		"go_mod": {
			NonEmptyAttrs: map[string]bool{
				"module_path": true,
				"go_mod":      true,
			},
			MergeableAttrs: map[string]bool{
				"deps": true,
			},
		},
	}
}

func (*goModLanguage) Loads() []rule.LoadInfo {
	return []rule.LoadInfo{
		{
			Name:    "//rules/go_mod:go_mod.bzl",
			Symbols: []string{"go_mod"},
		},
	}
}

func (*goModLanguage) Fix(*config.Config, *rule.File) {}

func (*goModLanguage) Configure(*config.Config, string, *rule.File) {}

func (l *goModLanguage) GenerateRules(args language.GenerateArgs) language.GenerateResult {
	fmt.Printf("GenerateRules %s, rel: %s\n", args.Dir, args.Rel)
	res := language.GenerateResult{}

	l.go_library_targets = append(l.go_library_targets, collectGoLibraries(args.File, args.OtherGen, args.Rel)...)

	if !slices.Contains(args.RegularFiles, "go.mod") {
		return res
	}
	// capture the existing visited go_libraries
	// and reset the list, as now we have what we need for the current go_mod rule
	go_library_targets := slices.Clone(l.go_library_targets)
	slices.Sort(go_library_targets)
	go_library_targets = slices.Compact(go_library_targets)

	// reset the list, as now we have what we need for the next go_mod rule
	l.go_library_targets = make([]string, 0)

	fmt.Printf("go_library_targets: %v dir: %s\n", go_library_targets, args.Dir)
	modulePath, err := parseModulePath(filepath.Join(args.Dir, "go.mod"))
	if err != nil {
		return res
	}

	var r *rule.Rule
	for _, existingRule := range args.File.Rules {
		if existingRule.Kind() == "go_mod" {
			existingRule.Delete()
			r = existingRule
			break
		}
	}

	if r == nil {
		r = rule.NewRule("go_mod", "go_mod_dir")
	}
	// always create a new rule, just preserve the tags and visibility from the existing rule
	r.SetAttr("module_path", modulePath)
	r.SetAttr("go_mod", ":go.mod")
	if slices.Contains(args.RegularFiles, "go.sum") {
		r.SetAttr("go_sum", ":go.sum")
	}
	r.SetAttr("deps", go_library_targets)

	res.Gen = append(res.Gen, r)
	res.Imports = make([]interface{}, len(res.Gen))
	return res
}

func (*goModLanguage) Imports(*config.Config, *rule.Rule, *rule.File) []resolve.ImportSpec {
	return nil
}

func (*goModLanguage) Embeds(r *rule.Rule, from label.Label) []label.Label {
	return nil
}

func (*goModLanguage) Resolve(*config.Config, *resolve.RuleIndex, *repo.RemoteCache, *rule.Rule, interface{}, label.Label) {
}

func (*goModLanguage) RegisterFlags(*flag.FlagSet, string, *config.Config) {}

func (*goModLanguage) CheckFlags(*flag.FlagSet, *config.Config) error {
	return nil
}

func (*goModLanguage) KnownDirectives() []string {
	return nil
}

// parseModulePath reads the given go.mod file and returns the module path from
// the first 'module' directive it finds.
func parseModulePath(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		// Check for module directive - must start with "module" followed by space or end of line
		if strings.HasPrefix(line, "module") {
			// Check if it's exactly "module" or "module " followed by content
			if len(line) == 6 || (len(line) > 6 && (line[6] == ' ' || line[6] == '\t')) {
				fields := strings.Fields(line)
				if len(fields) < 2 {
					return "", fmt.Errorf("invalid module directive in %s: missing module path", path)
				}
				// Handle quoted module paths. Go module paths can be quoted with double quotes.
				// Remove quotes only if they appear at the start and end of the field.
				mod := fields[1]
				if len(mod) >= 2 && mod[0] == '"' && mod[len(mod)-1] == '"' {
					mod = mod[1 : len(mod)-1]
				}
				if mod == "" {
					return "", fmt.Errorf("invalid module directive in %s: empty module path", path)
				}
				return mod, nil
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	return "", errors.New("no module directive found")
}

func collectGoLibraries(f *rule.File, otherGen []*rule.Rule, rel string) []string {
	var labels []string
	absRel := "//" + rel
	// Collect go_library rules from existing file
	if f != nil {
		for _, r := range f.Rules {
			if r.Kind() == "go_library" {
				// Use relative label format (":name") for same-package references.
				// This is the standard Bazel convention for targets in the same package.
				labels = append(labels, absRel+":"+r.Name())
			}
		}
	}

	// Collect go_library rules from OtherGen (rules generated by other languages)
	for _, r := range otherGen {
		if r.Kind() == "go_library" {
			// Use relative label format for same-package references
			labels = append(labels, absRel+":"+r.Name())
		}
	}

	return labels
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
