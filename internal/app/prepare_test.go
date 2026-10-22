package app

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/joho/godotenv"
)

func TestPrepareEnvPreservesSecretsAndDoesNotExecuteShell(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".env")
	original := "# Server settings\nPOSTGRES_PASSWORD='fixture-password'\nCUSTOM='$(touch must-not-execute)'\nAPP_KEY=\n"
	if err := os.WriteFile(path, []byte(original), 0600); err != nil {
		t.Fatal(err)
	}
	settings := `{"SMTP_HOST":"smtp.example.com","SMTP_PASSWORD":"a$b'c\"d","SMTP_FROM":"info@procash.kz"}`
	if err := PrepareEnv(path, "", strings.NewReader(settings)); err != nil {
		t.Fatal(err)
	}
	values, err := godotenv.Read(path)
	if err != nil {
		t.Fatal(err)
	}
	if values["SMTP_PASSWORD"] != "a$b'c\"d" || values["CUSTOM"] != "$(touch must-not-execute)" {
		t.Fatal("settings escaped incorrectly")
	}
	if _, err = ParseKey(values["APP_KEY"]); err != nil {
		t.Fatal(err)
	}
	first, _ := os.ReadFile(path)
	if err = PrepareEnv(path, "", strings.NewReader(settings)); err != nil {
		t.Fatal(err)
	}
	second, _ := os.ReadFile(path)
	if string(first) != string(second) {
		t.Fatal("persistent settings changed on repeat")
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0600 {
		t.Fatal("incorrect settings permissions")
	}
}
func TestPrepareEnvRejectsInvalidExistingKey(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".env")
	original := "POSTGRES_PASSWORD=fixture\nAPP_KEY=invalid\n"
	os.WriteFile(path, []byte(original), 0600)
	if err := PrepareEnv(path, "", nil); err == nil {
		t.Fatal("invalid key accepted")
	}
	after, _ := os.ReadFile(path)
	if string(after) != original {
		t.Fatal("invalid key overwritten")
	}
}

func TestInitEnvPreservesLocalKeyWithoutRequiringSMTPOrServerPassword(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".env")
	if err := os.WriteFile(path, []byte("APP_KEY=\nDB_PASSWORD=\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := InitEnv(path); err != nil {
		t.Fatal(err)
	}
	first, _ := os.ReadFile(path)
	if err := InitEnv(path); err != nil {
		t.Fatal(err)
	}
	second, _ := os.ReadFile(path)
	if string(first) != string(second) {
		t.Fatal("local key changed on repeat")
	}
}
func TestPrepareEnvRejectsDuplicatePersistentKeys(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".env")
	key := Keygen()
	os.WriteFile(path, []byte("POSTGRES_PASSWORD=fixture\nAPP_KEY="+key+"\nAPP_KEY="+key+"\n"), 0600)
	if err := PrepareEnv(path, "", nil); err == nil {
		t.Fatal("duplicate keys accepted")
	}
}
