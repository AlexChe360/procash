package app

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

// PrepareEnv never evaluates shell expressions and writes updates atomically.
func PrepareEnv(path, image string, input io.Reader) error {
	contents, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	values, err := godotenv.Unmarshal(string(contents))
	if err != nil {
		return errors.New("invalid server .env")
	}
	if values["POSTGRES_PASSWORD"] == "" {
		return errors.New("set POSTGRES_PASSWORD securely in the server .env")
	}
	if len(regexp.MustCompile(`(?m)^[\t ]*(?:export[\t ]+)?APP_KEY[\t ]*=`).FindAll(contents, -1)) > 1 {
		return errors.New("duplicate APP_KEY declarations; no changes saved")
	}
	updates := map[string]string{}
	if values["APP_KEY"] == "" {
		updates["APP_KEY"] = Keygen()
	} else if _, err = ParseKey(values["APP_KEY"]); err != nil {
		return errors.New("existing APP_KEY is invalid; it has not been changed")
	}
	if image != "" {
		if !regexp.MustCompile(`^ghcr\.io/[a-z0-9._/-]+@sha256:[a-f0-9]{64}$`).MatchString(image) {
			return errors.New("expected an immutable GHCR image digest")
		}
		updates["PROCASH_IMAGE"] = image
	}
	if input != nil {
		raw, err := io.ReadAll(io.LimitReader(input, 65537))
		if err != nil {
			return err
		}
		if len(raw) > 65536 {
			return errors.New("settings payload is too large")
		}
		if strings.TrimSpace(string(raw)) != "" {
			var settings map[string]string
			if err = json.Unmarshal(raw, &settings); err != nil {
				return errors.New("invalid settings payload")
			}
			for key, value := range settings {
				if !contains([]string{"SMTP_HOST", "SMTP_PORT", "SMTP_USERNAME", "SMTP_PASSWORD", "SMTP_FROM", "SMTP_SECURITY", "NOTIFY_EMAIL"}, key) {
					return errors.New("unsupported settings field")
				}
				if value != "" {
					if strings.ContainsAny(value, "\r\n") {
						return errors.New("mail configuration must not contain newlines")
					}
					updates[key] = value
				}
			}
		}
	}
	return writeEnvironment(path, string(contents), updates)
}

func InitEnv(path string) error {
	contents, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	values, err := godotenv.Unmarshal(string(contents))
	if err != nil {
		return err
	}
	if values["APP_KEY"] != "" {
		_, err = ParseKey(values["APP_KEY"])
		return err
	}
	return writeEnvironment(path, string(contents), map[string]string{"APP_KEY": Keygen()})
}

func writeEnvironment(path, text string, updates map[string]string) error {
	for key, value := range updates {
		line, err := godotenv.Marshal(map[string]string{key: value})
		if key == "APP_KEY" || key == "PROCASH_IMAGE" {
			line = key + "=" + value
		}
		if err != nil {
			return err
		}
		pattern := regexp.MustCompile(`(?m)^[\t ]*(?:export[\t ]+)?` + regexp.QuoteMeta(key) + `[\t ]*=.*$`)
		matches := pattern.FindAllStringIndex(text, -1)
		if len(matches) > 1 {
			return fmt.Errorf("duplicate %s declarations; no changes saved", key)
		}
		if len(matches) == 1 {
			text = pattern.ReplaceAllStringFunc(text, func(string) string { return line })
		} else {
			text = strings.TrimRight(text, "\r\n") + "\n" + line + "\n"
		}
	}
	if len(updates) == 0 {
		return nil
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".procash-env-")
	if err != nil {
		return err
	}
	defer os.Remove(temporary.Name())
	if err = temporary.Chmod(0600); err == nil {
		_, err = io.WriteString(temporary, text)
	}
	if err == nil {
		err = temporary.Sync()
	}
	closeErr := temporary.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(temporary.Name(), path)
}
func EnsureAdmin(ctx context.Context, pool *pgxpool.Pool, email, password string) error {
	email = strings.ToLower(strings.TrimSpace(email))
	if !validEmail(email) {
		return errors.New("invalid admin email")
	}
	if len(password) < 12 || len(password) > 72 {
		return errors.New("password must contain 12 to 72 bytes")
	}
	hash, err := PasswordHash(password)
	if err != nil {
		return err
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, `INSERT INTO users(id,email,password_hash,name,role,enabled,must_change_password,temporary_password_expires_at,created_at,updated_at) VALUES($1,$2,$3,'Администратор','ADMIN',true,false,NULL,now(),now()) ON CONFLICT(lower(email)) DO UPDATE SET password_hash=EXCLUDED.password_hash,role='ADMIN',enabled=true,must_change_password=false,temporary_password_expires_at=NULL,updated_at=now()`, NewID(), email, hash)
	if err == nil {
		_, err = tx.Exec(ctx, `DELETE FROM sessions WHERE user_id=(SELECT id FROM users WHERE lower(email)=$1)`, email)
	}
	if err == nil {
		err = tx.Commit(ctx)
	}
	return err
}
