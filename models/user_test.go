package models

import (
	"testing"

	"github.com/google/uuid"
)

func TestNewUser(t *testing.T) {
	user := NewUser()
	if user.ID == uuid.Nil {
		t.Error("Expected non-nil UUID")
	}
}
