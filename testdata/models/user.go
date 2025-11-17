package models

import "github.com/google/uuid"

type User struct {
	ID uuid.UUID
}

func NewUser() *User {
	return &User{ID: uuid.New()}
}
