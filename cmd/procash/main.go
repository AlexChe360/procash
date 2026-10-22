package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
	_ "time/tzdata"

	"github.com/AlexChe360/procash/internal/app"
	"github.com/AlexChe360/procash/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/term"
)

func main() {
	if err := run(); err != nil {
		slog.Error("procash stopped", "error", err)
		os.Exit(1)
	}
}
func run() error {
	command := "serve"
	if len(os.Args) > 1 {
		command = os.Args[1]
	}
	switch command {
	case "init-env":
		if len(os.Args) != 3 {
			return errors.New("usage: procash init-env /path/.env")
		}
		return app.InitEnv(os.Args[2])
	case "keygen":
		fmt.Println(app.Keygen())
		return nil
	case "prepare-env":
		if len(os.Args) < 3 {
			return errors.New("usage: procash prepare-env /path/.env [image]")
		}
		image := ""
		if len(os.Args) > 3 {
			image = os.Args[3]
		}
		if err := app.PrepareEnv(os.Args[2], image, os.Stdin); err != nil {
			return err
		}
		fmt.Println("Server configuration prepared; persistent APP_KEY preserved.")
		return nil
	case "healthcheck":
		client := http.Client{Timeout: 4 * time.Second}
		r, err := client.Get("http://127.0.0.1:8080/actuator/health")
		if err != nil {
			return errors.New("health request failed")
		}
		defer r.Body.Close()
		if r.StatusCode != 200 {
			return errors.New("database health check failed")
		}
		return nil
	case "serve", "migrate", "admin", "check-config":
	default:
		return errors.New("unknown command")
	}
	config, err := app.LoadConfig()
	if err != nil {
		return err
	}
	if command == "check-config" {
		if config.SMTPHost == "" {
			return errors.New("SMTP_HOST or MAIL_HOST is required to deliver application notifications")
		}
		fmt.Println("Production configuration checked; notification email is configured.")
		return nil
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	poolConfig, err := pgxpool.ParseConfig(config.DatabaseURL)
	if err != nil {
		return errors.New("invalid database connection configuration")
	}
	poolConfig.MaxConns = 10
	poolConfig.ConnConfig.ConnectTimeout = 5 * time.Second
	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err = pool.Ping(ctx); err != nil {
		return fmt.Errorf("database connection failed: %w", err)
	}
	if command == "migrate" {
		if err = db.Migrate(ctx, pool); err != nil {
			return err
		}
		fmt.Println("Database migrations applied; existing data preserved.")
		return nil
	}
	if command == "admin" {
		if len(os.Args) != 4 || os.Args[2] != "--email" {
			return errors.New("usage: procash admin --email address (password on stdin)")
		}
		fmt.Fprint(os.Stderr, "Admin password: ")
		var password string
		if term.IsTerminal(int(os.Stdin.Fd())) {
			raw, e := term.ReadPassword(int(os.Stdin.Fd()))
			if e != nil {
				return e
			}
			password = string(raw)
			fmt.Fprintln(os.Stderr)
		} else {
			password, err = bufio.NewReader(os.Stdin).ReadString('\n')
			if err != nil && password == "" {
				return err
			}
			password = strings.TrimRight(password, "\r\n")
		}
		if err = app.EnsureAdmin(ctx, pool, os.Args[3], password); err != nil {
			return err
		}
		fmt.Println("Administrator saved; previous sessions revoked.")
		return nil
	}
	serverApp, err := app.New(pool, config)
	if err != nil {
		return err
	}
	go serverApp.RunWorker(ctx)
	server := &http.Server{Addr: config.Addr, Handler: serverApp.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 32 * 1024}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
	}()
	slog.Info("ProCash started", "addr", config.Addr, "mail_configured", config.SMTPHost != "")
	if err = server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}
