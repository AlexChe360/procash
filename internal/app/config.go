package app

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"net"
	"net/mail"
	"net/url"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	Addr, Env, BaseURL, DatabaseURL, NotifyEmail                       string
	Key                                                                []byte
	SMTPHost, SMTPPort, SMTPUser, SMTPPassword, SMTPFrom, SMTPSecurity string
	MockPayments, MockOrders                                           bool
}

func Env(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}
	return fallback
}

func LoadConfig() (Config, error) {
	_ = godotenv.Load()
	c := Config{Addr: Env("HTTP_ADDR", ":8080"), Env: Env("APP_ENV", "local"), BaseURL: strings.TrimRight(Env("APP_URL", "http://localhost:8080"), "/"), NotifyEmail: Env("NOTIFY_EMAIL", "info@procash.kz"),
		SMTPHost: Env("SMTP_HOST", Env("MAIL_HOST", "")), SMTPPort: Env("SMTP_PORT", Env("MAIL_PORT", "587")), SMTPUser: Env("SMTP_USERNAME", Env("MAIL_USERNAME", "")), SMTPPassword: Env("SMTP_PASSWORD", Env("MAIL_PASSWORD", "")), SMTPFrom: Env("SMTP_FROM", Env("MAIL_FROM_ADDRESS", "info@procash.kz")), SMTPSecurity: Env("SMTP_SECURITY", "starttls"),
		MockPayments: Env("PROCASH_MOCK_PAYMENTS", "false") == "true", MockOrders: Env("PROCASH_MOCK_ORDERS", "false") == "true"}
	if c.SMTPPort == "465" && os.Getenv("SMTP_SECURITY") == "" {
		c.SMTPSecurity = "tls"
	}
	u, err := url.Parse(c.BaseURL)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil || u.Path != "" || u.RawQuery != "" || u.Fragment != "" {
		return c, errors.New("APP_URL must be a valid origin without path")
	}
	if c.Env == "production" && u.Scheme != "https" {
		return c, errors.New("production APP_URL must use HTTPS")
	}
	for _, email := range []string{c.NotifyEmail, c.SMTPFrom} {
		address, e := mail.ParseAddress(email)
		if e != nil || address.Address != email {
			return c, errors.New("invalid notification or sender address")
		}
	}
	if c.SMTPPort != "" {
		n, e := strconv.Atoi(c.SMTPPort)
		if e != nil || n < 1 || n > 65535 {
			return c, errors.New("invalid SMTP_PORT")
		}
	}
	if c.SMTPSecurity != "starttls" && c.SMTPSecurity != "tls" && !(c.SMTPSecurity == "none" && c.Env != "production") {
		return c, errors.New("SMTP_SECURITY must be starttls or tls")
	}
	c.DatabaseURL = Env("DATABASE_URL", "")
	if c.DatabaseURL == "" {
		d := url.URL{Scheme: "postgres", Host: net.JoinHostPort(Env("DB_HOST", "127.0.0.1"), Env("DB_PORT", "5432")), Path: "/" + Env("DB_DATABASE", Env("POSTGRES_DB", "procash")), User: url.UserPassword(Env("DB_USERNAME", Env("POSTGRES_USER", "procash_user")), Env("DB_PASSWORD", Env("POSTGRES_PASSWORD", "")))}
		q := d.Query()
		q.Set("sslmode", Env("DB_SSLMODE", "disable"))
		d.RawQuery = q.Encode()
		c.DatabaseURL = d.String()
	}
	c.Key, err = ParseKey(os.Getenv("APP_KEY"))
	return c, err
}

func ParseKey(value string) ([]byte, error) {
	key := []byte(value)
	var err error
	if strings.HasPrefix(value, "base64:") {
		key, err = base64.StdEncoding.DecodeString(strings.TrimPrefix(value, "base64:"))
	}
	if err != nil || len(key) != 32 {
		return nil, errors.New("APP_KEY must contain a persistent 32-byte key; run procash keygen")
	}
	return key, nil
}

func RandomToken() string {
	value := make([]byte, 32)
	if _, err := rand.Read(value); err != nil {
		panic(err)
	}
	return base64.RawURLEncoding.EncodeToString(value)
}
func NewID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	b[6] = (b[6] & 15) | 64
	b[8] = (b[8] & 63) | 128
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[:4], b[4:6], b[6:8], b[8:10], b[10:])
}
