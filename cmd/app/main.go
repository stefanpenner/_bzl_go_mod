package main

import (
	"fmt"

	"github.com/stefanpenner/bazel_go_mod/models"
	"github.com/stefanpenner/bazel_go_mod/utils"
)

func main() {
	fmt.Println(utils.Add(1, 2))
	fmt.Println(models.NewUser().ID)
}
