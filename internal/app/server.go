package app

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"net/mail"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/AlexChe360/procash/web"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type User struct {
	ID, Email, Name, Phone, Role string
	MustChange                   bool
}

func (u *User) Admin() bool { return u != nil && u.Role == "ADMIN" }

type contextKey int

const userKey contextKey = 1

// Keep executable code in local static files. User data is escaped separately by
// html/template; CSP is an additional browser boundary, not an HTML sanitizer.
const contentSecurityPolicy = "default-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'self'; script-src 'self'; script-src-attr 'none'; style-src 'self' https://fonts.googleapis.com; style-src-attr 'none'; font-src 'self' https://fonts.gstatic.com; img-src 'self'; connect-src 'self'; frame-src 'none'"

type Page struct {
	Title, Active, CSRF, Error, Message, TemporaryPassword, LoginURL string
	User                                                             *User
	Content                                                          template.HTML
	Values                                                           map[string]string
	Fields                                                           []Field
	Restaurant                                                       *Restaurant
	Restaurants                                                      []Restaurant
	Requests                                                         []ConnectionRequest
	Request                                                          *ConnectionRequest
	Users                                                            []UserRow
	Applications                                                     []Integration
	Application                                                      *Integration
	Tables                                                           []Table
	Table                                                            *Table
	Orders                                                           []Order
	Payments                                                         []Payment
	Metrics                                                          Metrics
	Days                                                             int
	Emails                                                           []MailRow
	MailConfigured                                                   bool
}
type App struct {
	DB        *pgxpool.Pool
	Config    Config
	templates *template.Template
	Mailer    Mailer
	logger    *slog.Logger
}

func New(pool *pgxpool.Pool, c Config) (*App, error) {
	t, err := template.New("app").Funcs(template.FuncMap{"status": StatusLabel, "money": Money, "date": func(t time.Time) string { return t.In(almaty).Format("02.01.2006 15:04") }, "value": func(m map[string]string, k string) string { return m[k] }, "eqs": func(a, b string) bool { return a == b }}).ParseFS(web.Files, "templates/*.html")
	if err != nil {
		return nil, err
	}
	return &App{DB: pool, Config: c, templates: t, Mailer: SMTPMailer{Config: c}, logger: slog.Default()}, nil
}

var almaty = func() *time.Location {
	l, err := time.LoadLocation("Asia/Almaty")
	if err != nil {
		return time.FixedZone("Asia/Almaty", 5*3600)
	}
	return l
}()
var uuidPattern = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

func ValidID(s string) bool { return uuidPattern.MatchString(s) }
func Money(s string) string {
	if s == "" {
		return "0 ₸"
	}
	return strings.ReplaceAll(s, ".", ",") + " ₸"
}
func StatusLabel(s string) string {
	labels := map[string]string{"NEW": "Новая", "IN_REVIEW": "На рассмотрении", "APPROVED": "Одобрена", "REJECTED": "Отклонена", "DRAFT": "Черновик", "READY_FOR_REVIEW": "На проверке ProCash", "NEEDS_CHANGES": "Нужны изменения", "UNDER_FREEDOM_REVIEW": "На рассмотрении Freedom Pay", "SUBMITTED_TO_FREEDOM": "Отправлена в Freedom Pay", "IN_PROGRESS": "В работе", "ACTIVE": "Активно", "OPEN": "Открыт", "PAID": "Оплачен", "PENDING": "Ожидает", "SENDING": "Отправляется", "SENT": "Доставлено SMTP-серверу", "FAILED": "Ошибка", "CREATED": "Создан"}
	if v, ok := labels[s]; ok {
		return v
	}
	return s
}
func CurrentUser(r *http.Request) *User { u, _ := r.Context().Value(userKey).(*User); return u }
func hashToken(s string) string         { v := sha256.Sum256([]byte(s)); return hex.EncodeToString(v[:]) }
func (a *App) cookieName(kind string) string {
	if strings.HasPrefix(a.Config.BaseURL, "https://") {
		return "__Host-procash_" + kind
	}
	return "procash_" + kind
}
func (a *App) cookie(w http.ResponseWriter, kind, value string, age int) {
	http.SetCookie(w, &http.Cookie{Name: a.cookieName(kind), Value: value, Path: "/", HttpOnly: true, Secure: strings.HasPrefix(a.Config.BaseURL, "https://"), SameSite: http.SameSiteLaxMode, MaxAge: age})
}
func (a *App) csrfSignature(token string) string {
	h := hmac.New(sha256.New, a.Config.Key)
	h.Write([]byte("csrf:" + token))
	return hex.EncodeToString(h.Sum(nil))
}
func (a *App) csrf(w http.ResponseWriter, r *http.Request) string {
	if c, err := r.Cookie(a.cookieName("csrf")); err == nil && a.validCSRF(c.Value) {
		return c.Value
	}
	token := RandomToken()
	token += "." + a.csrfSignature(token)
	a.cookie(w, "csrf", token, 43200)
	return token
}
func (a *App) validCSRF(token string) bool {
	parts := strings.Split(token, ".")
	return len(parts) == 2 && len(parts[0]) == 43 && hmac.Equal([]byte(parts[1]), []byte(a.csrfSignature(parts[0])))
}
func (a *App) validateCSRF(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin != "" {
		u, err := url.Parse(origin)
		base, _ := url.Parse(a.Config.BaseURL)
		if err != nil || !strings.EqualFold(u.Host, base.Host) || u.Scheme != base.Scheme {
			return false
		}
	}
	c, err := r.Cookie(a.cookieName("csrf"))
	if err != nil || !a.validCSRF(c.Value) {
		return false
	}
	token := r.Header.Get("X-CSRF-Token")
	if token == "" {
		token = r.FormValue("_csrf")
	}
	return subtle.ConstantTimeCompare([]byte(token), []byte(c.Value)) == 1
}
func (a *App) render(w http.ResponseWriter, r *http.Request, name string, p Page, status int) {
	p.User = CurrentUser(r)
	p.CSRF = a.csrf(w, r)
	p.MailConfigured = a.Config.SMTPHost != ""
	if p.Values == nil {
		p.Values = map[string]string{}
	}
	p.Fields = append([]Field(nil), p.Fields...)
	for i := range p.Fields {
		p.Fields[i].Value = p.Values[p.Fields[i].Name]
	}
	var content bytes.Buffer
	if err := a.templates.ExecuteTemplate(&content, name, p); err != nil {
		a.fail(w, r, err)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if r.Header.Get("HX-Request") == "true" && name != "home.html" {
		event, _ := json.Marshal(map[string]any{"pageChanged": map[string]string{"active": p.Active, "csrf": p.CSRF}})
		w.Header().Set("HX-Trigger-After-Swap", string(event))
		w.WriteHeader(status)
		fmt.Fprintf(w, "<title>%s — ProCash</title>", template.HTMLEscapeString(p.Title))
		w.Write(content.Bytes())
		return
	}
	if name == "home.html" {
		w.WriteHeader(status)
		w.Write(content.Bytes())
		return
	}
	p.Content = template.HTML(content.String()) // Compiled html/template output only; user strings were escaped above.
	var full bytes.Buffer
	if err := a.templates.ExecuteTemplate(&full, "layout.html", p); err != nil {
		a.fail(w, r, err)
		return
	}
	w.WriteHeader(status)
	w.Write(full.Bytes())
}
func (a *App) redirect(w http.ResponseWriter, r *http.Request, path string) {
	if r.Header.Get("HX-Request") == "true" {
		w.Header().Set("HX-Redirect", path)
		w.WriteHeader(http.StatusNoContent)
		return
	}
	http.Redirect(w, r, path, http.StatusSeeOther)
}
func (a *App) fail(w http.ResponseWriter, r *http.Request, err error) {
	a.logger.Error("request failed", "path", r.URL.Path, "error", err)
	http.Error(w, "Не удалось выполнить запрос. Попробуйте ещё раз.", 500)
}
func (a *App) notFound(w http.ResponseWriter, r *http.Request) { http.NotFound(w, r) }
func (a *App) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := CurrentUser(r)
		if u == nil {
			if strings.HasPrefix(r.URL.Path, "/api/") {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(401)
				JSON(w, map[string]string{"code": "UNAUTHORIZED"})
				return
			}
			a.redirect(w, r, "/login")
			return
		}
		if u.MustChange && r.URL.Path != "/account/password" && r.URL.Path != "/logout" {
			if strings.HasPrefix(r.URL.Path, "/api/") {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(403)
				JSON(w, map[string]string{"code": "PASSWORD_CHANGE_REQUIRED"})
				return
			}
			a.redirect(w, r, "/account/password")
			return
		}
		next(w, r)
	}
}
func (a *App) admin(next http.HandlerFunc) http.HandlerFunc {
	return a.auth(func(w http.ResponseWriter, r *http.Request) {
		if !CurrentUser(r).Admin() {
			http.Error(w, "Доступ запрещён", 403)
			return
		}
		next(w, r)
	})
}
func (a *App) Handler() http.Handler {
	mux := http.NewServeMux()
	assets, _ := fs.Sub(web.Files, "static")
	mux.Handle("GET /assets/", http.StripPrefix("/assets/", http.FileServerFS(assets)))
	mux.HandleFunc("GET /favicon.ico", func(w http.ResponseWriter, r *http.Request) {
		data, err := web.Files.ReadFile("static/favicon.ico")
		if err != nil {
			a.fail(w, r, err)
			return
		}
		w.Header().Set("Content-Type", "image/x-icon")
		w.Write(data)
	})
	mux.HandleFunc("GET /robots.txt", func(w http.ResponseWriter, r *http.Request) {
		data, err := web.Files.ReadFile("static/robots.txt")
		if err != nil {
			a.fail(w, r, err)
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write(data)
	})
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) { a.render(w, r, "home.html", Page{}, 200) })
	mux.HandleFunc("GET /api/v1/health", a.health)
	mux.HandleFunc("GET /actuator/health", a.health)
	mux.HandleFunc("GET /up", a.health)
	mux.HandleFunc("GET /login", a.login)
	mux.HandleFunc("POST /login", a.login)
	mux.HandleFunc("GET /connect", a.connect)
	mux.HandleFunc("POST /connect", a.connect)
	mux.HandleFunc("GET /register", func(w http.ResponseWriter, r *http.Request) { a.redirect(w, r, "/connect") })
	mux.HandleFunc("POST /register", func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "Самостоятельная регистрация отключена. Отправьте заявку на подключение.", 410)
	})
	mux.HandleFunc("POST /logout", a.auth(a.logout))
	mux.HandleFunc("GET /dashboard", a.auth(a.dashboard))
	mux.HandleFunc("GET /api/v1/orders/current", a.auth(a.apiOrder))
	mux.HandleFunc("GET /account", a.auth(a.profile))
	mux.HandleFunc("POST /account", a.auth(a.profile))
	mux.HandleFunc("GET /account/password", a.auth(a.password))
	mux.HandleFunc("POST /account/password", a.auth(a.password))
	mux.HandleFunc("GET /restaurants", a.auth(a.restaurants))
	mux.HandleFunc("GET /restaurants/new", a.auth(func(w http.ResponseWriter, r *http.Request) { a.redirect(w, r, "/connect") }))
	mux.HandleFunc("GET /restaurants/{id}", a.auth(a.restaurant))
	mux.HandleFunc("POST /restaurants/{id}", a.auth(a.restaurant))
	mux.HandleFunc("GET /restaurants/{id}/tables", a.auth(a.tables))
	mux.HandleFunc("POST /restaurants/{id}/tables", a.auth(a.tables))
	mux.HandleFunc("GET /restaurants/{id}/tables/new", a.auth(a.tables))
	mux.HandleFunc("GET /restaurants/{id}/tables/{table}", a.auth(a.table))
	mux.HandleFunc("GET /restaurants/{id}/tables/{table}/qr.png", a.auth(a.qr))
	mux.HandleFunc("GET /restaurants/{id}/orders", a.auth(a.orders))
	mux.HandleFunc("GET /restaurants/{id}/payments", a.auth(a.payments))
	mux.HandleFunc("GET /restaurants/{id}/payments/freedom-pay", a.auth(a.freedom))
	mux.HandleFunc("POST /restaurants/{id}/payments/freedom-pay/submit", a.auth(a.freedomSubmit))
	mux.HandleFunc("GET /restaurants/{id}/payments/freedom-pay/{step}", a.auth(a.freedom))
	mux.HandleFunc("POST /restaurants/{id}/payments/freedom-pay/{step}", a.auth(a.freedom))
	mux.HandleFunc("GET /restaurants/{id}/integrations/iiko", a.auth(a.iiko))
	mux.HandleFunc("POST /restaurants/{id}/integrations/iiko", a.auth(a.iiko))
	mux.HandleFunc("POST /restaurants/{id}/integrations/iiko/submit", a.auth(a.iikoSubmit))
	mux.HandleFunc("GET /admin", a.admin(a.adminDashboard))
	mux.HandleFunc("GET /admin/requests", a.admin(a.requests))
	mux.HandleFunc("GET /admin/requests/{request}", a.admin(a.request))
	mux.HandleFunc("POST /admin/requests/{request}/{action}", a.admin(a.reviewRequest))
	mux.HandleFunc("GET /admin/users", a.admin(a.users))
	mux.HandleFunc("POST /admin/users/{user}/{action}", a.admin(a.manageUser))
	mux.HandleFunc("GET /admin/freedom-pay/applications", a.admin(a.adminIntegrations))
	mux.HandleFunc("GET /admin/freedom-pay/applications/{application}", a.admin(a.adminFreedom))
	mux.HandleFunc("POST /admin/freedom-pay/applications/{application}/{action}", a.admin(a.reviewFreedom))
	mux.HandleFunc("GET /admin/iiko/applications", a.admin(a.adminIntegrations))
	mux.HandleFunc("GET /admin/iiko/applications/{application}", a.admin(a.adminIiko))
	mux.HandleFunc("POST /admin/iiko/applications/{application}/{action}", a.admin(a.reviewIiko))
	mux.HandleFunc("GET /admin/mail", a.admin(a.mailQueue))
	mux.HandleFunc("POST /admin/mail/{mail}/retry", a.admin(a.retryMail))
	mux.HandleFunc("GET /r/{slug}/q/{token}", a.publicTable)
	mux.HandleFunc("POST /payments/create", a.createPayment)
	mux.HandleFunc("GET /payments/{payment}/mock", a.mockPayment)
	mux.HandleFunc("POST /payments/{payment}/mock/{result}", a.completePayment)
	mux.HandleFunc("GET /payments/{payment}/success", a.paymentSuccess)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Security-Policy", contentSecurityPolicy)
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Cache-Control", "no-store")
		defer func() {
			if p := recover(); p != nil {
				a.logger.Error("request panic", "path", r.URL.Path, "error", fmt.Sprint(p))
				http.Error(w, "Ошибка сервера", 500)
			}
		}()
		r.Body = http.MaxBytesReader(w, r.Body, 64*1024)
		if r.Method == "POST" {
			if err := r.ParseForm(); err != nil {
				http.Error(w, "Некорректная форма", 400)
				return
			}
			if !a.validateCSRF(r) {
				http.Error(w, "Сессия формы истекла. Обновите страницу и попробуйте ещё раз.", 403)
				return
			}
		}
		if cookie, err := r.Cookie(a.cookieName("session")); err == nil && len(cookie.Value) == 43 {
			var u User
			err = a.DB.QueryRow(r.Context(), `SELECT u.id,u.email,u.name,u.phone,u.role,u.must_change_password FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=$1 AND s.expires_at>now() AND u.enabled=true AND (u.temporary_password_expires_at IS NULL OR u.temporary_password_expires_at>now())`, hashToken(cookie.Value)).Scan(&u.ID, &u.Email, &u.Name, &u.Phone, &u.Role, &u.MustChange)
			if err == nil {
				r = r.WithContext(context.WithValue(r.Context(), userKey, &u))
			} else if !errors.Is(err, pgx.ErrNoRows) {
				a.fail(w, r, err)
				return
			}
		}
		mux.ServeHTTP(w, r)
	})
}
func (a *App) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	w.Header().Set("Content-Type", "application/json")
	if err := a.DB.Ping(ctx); err != nil {
		w.WriteHeader(503)
		w.Write([]byte(`{"status":"DOWN"}`))
		return
	}
	w.Write([]byte(`{"status":"UP","service":"procash"}`))
}
func validEmail(s string) bool {
	m, e := mail.ParseAddress(s)
	return e == nil && m.Address == s && len(s) <= 255
}
func form(r *http.Request, key string) string { return strings.TrimSpace(r.FormValue(key)) }
func fieldsValid(values map[string]string, required map[string]int) bool {
	for k, max := range required {
		v := values[k]
		if v == "" || len([]rune(v)) > max {
			return false
		}
	}
	return true
}
func formValues(r *http.Request, keys ...string) map[string]string {
	m := map[string]string{}
	for _, k := range keys {
		m[k] = form(r, k)
	}
	return m
}
func (a *App) limited(r *http.Request, key string, max int, window time.Duration) (bool, error) {
	var attempts int
	err := a.DB.QueryRow(r.Context(), `INSERT INTO rate_limits(key,window_start,attempts) VALUES($1,now(),1) ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN rate_limits.window_start < now()-$2::interval THEN 1 ELSE rate_limits.attempts+1 END,window_start=CASE WHEN rate_limits.window_start < now()-$2::interval THEN now() ELSE rate_limits.window_start END RETURNING attempts`, hashToken(key), strconv.Itoa(int(window.Seconds()))+" seconds").Scan(&attempts)
	return attempts > max, err
}
func clientIP(r *http.Request) string {
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		ip = r.RemoteAddr
	}
	parsed := net.ParseIP(ip)
	if parsed != nil && (parsed.IsLoopback() || parsed.IsPrivate()) {
		parts := strings.Split(r.Header.Get("X-Forwarded-For"), ",")
		for i := len(parts) - 1; i >= 0; i-- {
			candidate := net.ParseIP(strings.TrimSpace(parts[i]))
			if candidate != nil && !candidate.IsLoopback() && !candidate.IsPrivate() {
				return candidate.String()
			}
		}
	}
	return ip
}
func audit(ctx context.Context, tx pgx.Tx, userID, action, entity string) error {
	_, err := tx.Exec(ctx, `INSERT INTO audit_events(actor_id,action,entity_id) VALUES($1,$2,$3)`, userID, action, entity)
	return err
}
func JSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}
