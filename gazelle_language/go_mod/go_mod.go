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
	go_library_targets_by_go_mod_dir map[string][]string
}

// NewLanguage is the constructor that Gazelle looks for when loading this extension.
func NewLanguage() language.Language {
	return &goModLanguage{
		// Track go_library targets per go.mod dir, since aggregation happens at the go_mod, not package, level.
		// This is more complicated than pkg_tar and protos gazelle language extension, so we need to do more book keeping
		go_library_targets_by_go_mod_dir: make(map[string][]string),
	}
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

func (*goModLanguage) Configure(config *config.Config, rel string, file *rule.File) {

}

func (l *goModLanguage) GenerateRules(args language.GenerateArgs) language.GenerateResult {
	fmt.Printf("\n\nGenerateRules dir: %s, rel: %s\n", args.Dir, args.Rel)
	res := language.GenerateResult{}

	repoRoot := args.Config.RepoRoot

	// let's check if we are in a go_mod directory
	isGoModDir := slices.Contains(args.RegularFiles, "go.mod")

	fmt.Printf("- isGoModDir: %t\n", isGoModDir)
	fmt.Printf("- repoRoot: %s\n", repoRoot)
	fmt.Printf("- args.Dir: %s\n", args.Dir)

	var goModDir string
	var err error
	if isGoModDir {
		goModDir = args.Dir
	} else {
		// if we aren't in a go_mod directory, we need to find the closest go.mod file between the current directory and the repo root
		goModDir, err = findGoModDirBetween(args.Dir, repoRoot)
		fmt.Printf("- findGoModDirBetween: %s and %s == %s\n", args.Dir, repoRoot, goModDir)

		if err != nil {
			fmt.Printf("Error finding go.mod between %s and %s: %v\n", args.Dir, repoRoot, err)
			return res
		}

		if goModDir == "" {
			fmt.Printf("No go.mod found between %s and %s\n", args.Dir, repoRoot)
			return res
		}
	}

	// always populate library collecting for the go_mod directory
	go_library_targets := collectGoLibraries(args.File, args.OtherGen, args.Rel)

	// insert the go_libraries into the appropriate go_mod directory slot
	if l.go_library_targets_by_go_mod_dir[goModDir] == nil {
		l.go_library_targets_by_go_mod_dir[goModDir] = make([]string, 0)
	}

	l.go_library_targets_by_go_mod_dir[goModDir] = append(l.go_library_targets_by_go_mod_dir[goModDir], go_library_targets...)

	fmt.Printf("- go_library_targets_by_go_mod_dir: key: %s targets: %v\n", goModDir, l.go_library_targets_by_go_mod_dir[goModDir])
	// if we aren't in a go_mod directory, we don't need to generate a go_mod rule, so we exit early
	if !isGoModDir {
		fmt.Printf("- not in a go_mod directory, so we exit early\n")
		return res
	}
	fmt.Printf("- we are in a go_mod directory, so we continue\n")

	modulePath, err := parseModulePath(filepath.Join(args.Dir, "go.mod"))
	if err != nil {
		return res
	}

	fmt.Printf(" - generating go_mod rule for: %s\n", goModDir)
	// Delete any existing go_mod rules first
	for _, existingRule := range args.File.Rules {
		if existingRule.Kind() == "go_mod" {
			existingRule.Delete()
		}
	}

	// Always create a new rule
	r := rule.NewRule("go_mod", "go_mod_dir")
	// always create a new rule, just preserve the tags and visibility from the existing rule
	r.SetAttr("module_path", modulePath)
	r.SetAttr("go_mod", ":go.mod")
	if slices.Contains(args.RegularFiles, "go.sum") {
		r.SetAttr("go_sum", ":go.sum")
	}
	r.SetAttr("deps", l.go_library_targets_by_go_mod_dir[goModDir])

	res.Gen = append(res.Gen, r)
	res.Imports = make([]interface{}, len(res.Gen))
	fmt.Printf(" - added rule to res.Gen, total rules: %d\n", len(res.Gen))
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

// findGoModBetween finds the go.mod file between currentDir and repoRoot.
// It walks up from currentDir towards repoRoot and returns the first go.mod found.
// Returns an error if currentDir is not equal to or a descendant of repoRoot.
func findGoModDirBetween(currentDir, repoRoot string) (string, error) {
	// Normalize paths to handle symlinks and relative paths
	currentDirAbs, err := filepath.Abs(currentDir)
	if err != nil {
		return "", fmt.Errorf("failed to resolve currentDir: %w", err)
	}
	repoRootAbs, err := filepath.Abs(repoRoot)
	if err != nil {
		return "", fmt.Errorf("failed to resolve repoRoot: %w", err)
	}

	// Check if currentDir is equal to or a descendant of repoRoot
	rel, err := filepath.Rel(repoRootAbs, currentDirAbs)
	if err != nil {
		return "", fmt.Errorf("currentDir %q is not relative to repoRoot %q: %w", currentDirAbs, repoRootAbs, err)
	}

	// If rel starts with "..", currentDir is not a descendant of repoRoot
	if strings.HasPrefix(rel, "..") {
		return "", fmt.Errorf("currentDir %q is not equal to or a descendant of repoRoot %q", currentDirAbs, repoRootAbs)
	}

	// Walk up from currentDir towards repoRoot looking for go.mod
	dir := currentDirAbs
	for {
		goModPath := filepath.Join(dir, "go.mod")
		if fileExists(goModPath) {
			return filepath.Dir(goModPath), nil
		}

		// Stop if we've reached repoRoot
		if dir == repoRootAbs {
			break
		}

		// Move up one directory
		parent := filepath.Dir(dir)
		if parent == dir {
			// Reached filesystem root without finding go.mod
			break
		}
		dir = parent
	}

	return "", fmt.Errorf("go.mod not found between %q and %q", currentDirAbs, repoRootAbs)
}
