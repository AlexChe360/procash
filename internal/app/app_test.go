package app

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"os"
	"regexp"
	"strings"
	"sync"
	"testing"

	"github.com/AlexChe360/procash/internal/db"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

type fakeMailer struct {
	mu       sync.Mutex
	Messages []Message
	Fail     bool
}

func (m *fakeMailer) Send(_ context.Context, v Message) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Fail {
		return errors.New("SMTP unavailable")
	}
	m.Messages = append(m.Messages, v)
	return nil
}

type fixture struct {
	t      *testing.T
	app    *App
	pool   *pgxpool.Pool
	server *httptest.Server
	mail   *fakeMailer
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is required for PostgreSQL integration tests")
	}
	parsed, err := url.Parse(dsn)
	if err != nil || !strings.Contains(parsed.Path, "test") {
		t.Fatal("integration tests require a dedicated database with 'test' in its name")
	}
	ctx := context.Background()
	admin, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	schema := "test_" + strings.ReplaceAll(NewID(), "-", "")
	quoted := pgx.Identifier{schema}.Sanitize()
	if _, err = admin.Exec(ctx, "CREATE SCHEMA "+quoted); err != nil {
		t.Fatal(err)
	}
	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	config.ConnConfig.RuntimeParams["search_path"] = schema
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		pool.Close()
		_, e := admin.Exec(ctx, "DROP SCHEMA "+quoted+" CASCADE")
		if e != nil {
			t.Error(e)
		}
		admin.Close()
	})
	if err = db.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	app, err := New(pool, Config{Env: "testing", Key: []byte(strings.Repeat("k", 32)), NotifyEmail: "info@procash.kz", SMTPHost: "smtp.fixture", SMTPPort: "587", SMTPFrom: "info@procash.kz", SMTPSecurity: "starttls"})
	if err != nil {
		t.Fatal(err)
	}
	mailer := &fakeMailer{}
	app.Mailer = mailer
	server := httptest.NewServer(app.Handler())
	app.Config.BaseURL = server.URL
	t.Cleanup(server.Close)
	return &fixture{t, app, pool, server, mailer}
}
func (f *fixture) client() *http.Client {
	jar, _ := cookiejar.New(nil)
	return &http.Client{Jar: jar, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
}
func (f *fixture) request(c *http.Client, method, path string, values url.Values, expected int) (string, *http.Response) {
	f.t.Helper()
	if values == nil {
		values = url.Values{}
	}
	if method == "POST" && values.Get("_csrf") == "" {
		u, _ := url.Parse(f.server.URL)
		var token string
		for _, cookie := range c.Jar.Cookies(u) {
			if cookie.Name == "procash_csrf" {
				token = cookie.Value
			}
		}
		if token == "" {
			f.request(c, "GET", "/connect", nil, 200)
			for _, cookie := range c.Jar.Cookies(u) {
				if cookie.Name == "procash_csrf" {
					token = cookie.Value
				}
			}
		}
		values.Set("_csrf", token)
	}
	request, err := http.NewRequest(method, f.server.URL+path, strings.NewReader(values.Encode()))
	if err != nil {
		f.t.Fatal(err)
	}
	if method == "POST" {
		request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	response, err := c.Do(request)
	if err != nil {
		f.t.Fatal(err)
	}
	defer response.Body.Close()
	raw, err := io.ReadAll(response.Body)
	if err != nil {
		f.t.Fatal(err)
	}
	if response.StatusCode != expected {
		f.t.Fatalf("%s %s: got %d, want %d: %s", method, path, response.StatusCode, expected, string(raw))
	}
	return string(raw), response
}
func (f *fixture) sql(query string, args ...any) {
	f.t.Helper()
	if _, err := f.pool.Exec(context.Background(), query, args...); err != nil {
		f.t.Fatal(err)
	}
}
func (f *fixture) scalar(query string, args ...any) string {
	f.t.Helper()
	var s string
	if err := f.pool.QueryRow(context.Background(), query, args...).Scan(&s); err != nil {
		f.t.Fatal(err)
	}
	return s
}
func (f *fixture) user(email, role string) string {
	id := NewID()
	hash, _ := bcrypt.GenerateFromPassword([]byte("fixture-password"), bcrypt.MinCost)
	f.sql(`INSERT INTO users(id,email,password_hash,name,role,enabled,created_at,updated_at) VALUES($1,$2,$3,'Тестовый владелец',$4,true,now(),now())`, id, email, string(hash), role)
	return id
}
func (f *fixture) login(email string) *http.Client {
	c := f.client()
	_, response := f.request(c, "POST", "/login", url.Values{"email": {email}, "password": {"fixture-password"}}, 303)
	if response.Header.Get("Location") == "/account/password" {
		f.t.Fatal("unexpected forced password change")
	}
	return c
}
func (f *fixture) venue(owner, name string) string {
	id := NewID()
	f.sql(`INSERT INTO restaurants(id,owner_id,name,slug,city,status,active,created_at,updated_at) VALUES($1,$2,$3,$4,'Алматы','DRAFT',false,now(),now())`, id, owner, name, "venue-"+id)
	return id
}
func (f *fixture) submitRequest(c *http.Client, email, name string) string {
	f.request(c, "POST", "/connect", url.Values{"contact_name": {"Иван"}, "email": {email}, "phone": {"+77011234567"}, "restaurant_name": {name}, "city": {"Алматы"}, "pos_system": {"iiko"}, "comment": {"Тестовая заявка"}, "consent": {"yes"}, "role": {"ADMIN"}}, 303)
	return f.scalar(`SELECT id::text FROM connection_requests WHERE email=$1`, email)
}

func TestPublicApplicationDoesNotCreateAnAccount(t *testing.T) {
	f := newFixture(t)
	c := f.client()
	body, _ := f.request(c, "GET", "/", nil, 200)
	if !strings.Contains(body, `href="/connect"`) || strings.Contains(body, `href="/register"`) {
		t.Fatal("home CTA must lead to application")
	}
	f.request(c, "GET", "/register", nil, 303)
	f.request(c, "POST", "/register", url.Values{"email": {"self@example.com"}, "password": {"fixture-password"}}, 410)
	id := f.submitRequest(c, "owner@example.com", "Кофейня")
	if f.scalar(`SELECT count(*)::text FROM users`) != "0" {
		t.Fatal("application created a user")
	}
	if f.scalar(`SELECT status FROM connection_requests WHERE id=$1`, id) != "NEW" {
		t.Fatal("wrong initial state")
	}
	f.submitRequest(c, "owner@example.com", "Кофейня")
	if f.scalar(`SELECT count(*)::text FROM mail_outbox`) != "1" {
		t.Fatal("duplicate notification")
	}
	ok, err := f.app.DeliverOne(context.Background())
	if !ok || err != nil {
		t.Fatal(err)
	}
	if len(f.mail.Messages) != 1 || f.mail.Messages[0].To != "info@procash.kz" || !strings.Contains(f.mail.Messages[0].Body, "/admin/requests/"+id) {
		t.Fatal("incorrect admin notification")
	}
}

func TestAdminGrantFirstLoginAndPasswordRotation(t *testing.T) {
	f := newFixture(t)
	f.user("admin@example.com", "ADMIN")
	admin := f.login("admin@example.com")
	id := f.submitRequest(f.client(), "new@example.com", "Новое заведение")
	body, _ := f.request(admin, "POST", "/admin/requests/"+id+"/approve", nil, 200)
	match := regexp.MustCompile(`id="temporary-password">([^<]+)<`).FindStringSubmatch(body)
	if len(match) != 2 {
		t.Fatal("one-time temporary password missing")
	}
	temporary := match[1]
	ownerID := f.scalar(`SELECT id::text FROM users WHERE email='new@example.com'`)
	if f.scalar(`SELECT role||':'||must_change_password::text FROM users WHERE id=$1`, ownerID) != "USER:true" {
		t.Fatal("access must require password change")
	}
	detail, _ := f.request(admin, "GET", "/admin/requests/"+id, nil, 200)
	if strings.Contains(detail, temporary) {
		t.Fatal("password exposed after one-time response")
	}
	f.request(admin, "POST", "/admin/requests/"+id+"/approve", nil, 409)
	if f.scalar(`SELECT count(*)::text FROM restaurants`) != "1" {
		t.Fatal("duplicate grant")
	}
	owner := f.client()
	_, response := f.request(owner, "POST", "/login", url.Values{"email": {"new@example.com"}, "password": {temporary}}, 303)
	if response.Header.Get("Location") != "/account/password" {
		t.Fatal("first login must require password change")
	}
	_, response = f.request(owner, "GET", "/dashboard", nil, 303)
	if response.Header.Get("Location") != "/account/password" {
		t.Fatal("mandatory password change bypassed")
	}
	f.request(owner, "POST", "/account/password", url.Values{"current_password": {temporary}, "password": {"new-secure-password"}, "password_confirmation": {"new-secure-password"}}, 303)
	f.request(owner, "GET", "/dashboard", nil, 200)
	f.request(f.client(), "POST", "/login", url.Values{"email": {"new@example.com"}, "password": {temporary}}, 422)
	for i := 0; i < 2; i++ {
		if _, err := f.app.DeliverOne(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	if len(f.mail.Messages) != 2 || !strings.Contains(f.mail.Messages[1].Body, temporary) || f.mail.Messages[1].To != "new@example.com" {
		t.Fatal("invitation not delivered to owner")
	}
	if f.scalar(`SELECT count(*)::text FROM mail_outbox WHERE payload IS NOT NULL`) != "0" {
		t.Fatal("delivered secrets retained")
	}
}
func TestExistingAccountPasswordIsPreservedOnGrant(t *testing.T) {
	f := newFixture(t)
	owner := f.user("existing@example.com", "USER")
	hash := f.scalar(`SELECT password_hash FROM users WHERE id=$1`, owner)
	f.user("admin@example.com", "ADMIN")
	id := f.submitRequest(f.client(), "existing@example.com", "Ещё одно заведение")
	body, _ := f.request(f.login("admin@example.com"), "POST", "/admin/requests/"+id+"/approve", nil, 200)
	if strings.Contains(body, `id="temporary-password"`) || f.scalar(`SELECT password_hash FROM users WHERE id=$1`, owner) != hash {
		t.Fatal("existing password was replaced")
	}
	if f.scalar(`SELECT count(*)::text FROM users`) != "2" {
		t.Fatal("duplicate user")
	}
	detail, _ := f.request(f.login("admin@example.com"), "GET", "/admin/requests/"+id, nil, 200)
	if !strings.Contains(detail, `action="/admin/users/`+owner+`/reset"`) {
		t.Fatal("approved request must offer issuing access when the recipient has no known password")
	}
	for i := 0; i < 2; i++ {
		if _, err := f.app.DeliverOne(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	invitation := f.mail.Messages[1]
	if invitation.To != "existing@example.com" || !strings.Contains(invitation.Body, "Если доступ ещё не выдавался или пароль неизвестен") || strings.Contains(invitation.Body, "Войдите с существующим паролем. Он не изменился.") {
		t.Fatal("invitation must explain how to obtain access without assuming a known password")
	}
}

func TestGrantCanExplicitlyIssuePasswordForExistingRecord(t *testing.T) {
	f := newFixture(t)
	owner := f.user("existing@example.com", "USER")
	f.venue(owner, "Прежнее заведение")
	oldSession := f.login("existing@example.com")
	f.user("admin@example.com", "ADMIN")
	admin := f.login("admin@example.com")
	id := f.submitRequest(f.client(), "existing@example.com", "Новое заведение")
	body, _ := f.request(admin, "GET", "/admin/requests/"+id, nil, 200)
	if !strings.Contains(body, `name="issue_temporary_password"`) {
		t.Fatal("administrator must be able to explicitly choose a new password")
	}
	body, _ = f.request(admin, "POST", "/admin/requests/"+id+"/approve", url.Values{"issue_temporary_password": {"yes"}}, 200)
	match := regexp.MustCompile(`id="temporary-password">([^<]+)<`).FindStringSubmatch(body)
	if len(match) != 2 {
		t.Fatal("existing record did not receive temporary access")
	}
	temporary := match[1]
	hash := f.scalar(`SELECT password_hash FROM users WHERE id=$1`, owner)
	if !CheckPassword(hash, temporary) || CheckPassword(hash, "fixture-password") {
		t.Fatal("new credential was not applied")
	}
	if f.scalar(`SELECT count(*)::text FROM users`) != "2" || f.scalar(`SELECT count(*)::text FROM restaurants WHERE owner_id=$1`, owner) != "2" {
		t.Fatal("grant must reuse the user and preserve existing venues")
	}
	f.request(oldSession, "GET", "/dashboard", nil, 303)
	_, response := f.request(f.client(), "POST", "/login", url.Values{"email": {"existing@example.com"}, "password": {temporary}}, 303)
	if response.Header.Get("Location") != "/account/password" {
		t.Fatal("issued access must require a new personal password")
	}
	f.request(admin, "POST", "/admin/requests/"+id+"/approve", url.Values{"issue_temporary_password": {"yes"}}, 409)
	if f.scalar(`SELECT password_hash FROM users WHERE id=$1`, owner) != hash || f.scalar(`SELECT count(*)::text FROM mail_outbox`) != "2" {
		t.Fatal("repeated approval changed credentials or sent another invitation")
	}
	for i := 0; i < 2; i++ {
		if _, err := f.app.DeliverOne(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	if f.mail.Messages[1].To != "existing@example.com" || !strings.Contains(f.mail.Messages[1].Body, "Временный пароль: "+temporary) {
		t.Fatal("invitation must contain the usable new password")
	}
}

func TestRequestCannotResetAdministratorOrDisabledUser(t *testing.T) {
	for _, target := range []string{"ADMIN", "disabled"} {
		t.Run(target, func(t *testing.T) {
			f := newFixture(t)
			role := "USER"
			if target == "ADMIN" {
				role = "ADMIN"
			}
			owner := f.user("existing@example.com", role)
			if target == "disabled" {
				f.sql(`UPDATE users SET enabled=false WHERE id=$1`, owner)
			}
			hash := f.scalar(`SELECT password_hash FROM users WHERE id=$1`, owner)
			f.user("admin@example.com", "ADMIN")
			id := f.submitRequest(f.client(), "existing@example.com", "Новое заведение")
			f.request(f.login("admin@example.com"), "POST", "/admin/requests/"+id+"/approve", url.Values{"issue_temporary_password": {"yes"}}, 409)
			if f.scalar(`SELECT password_hash FROM users WHERE id=$1`, owner) != hash || f.scalar(`SELECT count(*)::text FROM restaurants`) != "0" || f.scalar(`SELECT count(*)::text FROM mail_outbox`) != "1" {
				t.Fatal("disallowed grant changed the account or created access")
			}
		})
	}
}
func TestLegacyBcryptAndExpiredOrDisabledAccess(t *testing.T) {
	f := newFixture(t)
	id := f.user("legacy@example.com", "USER")
	hash := f.scalar(`SELECT password_hash FROM users WHERE id=$1`, id)
	f.sql(`UPDATE users SET password_hash=$1 WHERE id=$2`, "{bcrypt}"+strings.Replace(hash, "$2a$", "$2y$", 1), id)
	c := f.login("LEGACY@example.com")
	f.request(c, "GET", "/dashboard", nil, 200)
	f.sql(`UPDATE users SET enabled=false WHERE id=$1`, id)
	f.request(c, "GET", "/dashboard", nil, 303)
	f.request(f.client(), "POST", "/login", url.Values{"email": {"legacy@example.com"}, "password": {"fixture-password"}}, 422)
	f.sql(`UPDATE users SET enabled=true,must_change_password=true,temporary_password_expires_at=now()-interval '1 minute' WHERE id=$1`, id)
	f.request(f.client(), "POST", "/login", url.Values{"email": {"legacy@example.com"}, "password": {"fixture-password"}}, 422)
}
func TestOwnershipAndAdminAuthorization(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	other := f.user("other@example.com", "USER")
	own := f.venue(owner, "Своё")
	alien := f.venue(other, "Чужое")
	c := f.login("owner@example.com")
	f.request(c, "GET", "/restaurants/"+own, nil, 200)
	for _, path := range []string{"/restaurants/" + alien, "/restaurants/" + alien + "/tables", "/restaurants/" + alien + "/orders", "/restaurants/" + alien + "/payments/freedom-pay", "/restaurants/" + alien + "/integrations/iiko"} {
		f.request(c, "GET", path, nil, 404)
	}
	f.request(c, "POST", "/restaurants/"+alien, url.Values{"name": {"Угнанное"}}, 404)
	f.request(c, "GET", "/admin", nil, 403)
	f.request(c, "GET", "/admin/users", nil, 403)
	f.request(f.client(), "GET", "/admin/requests", nil, 303)
}
func TestCSRFOriginAndRateLimits(t *testing.T) {
	f := newFixture(t)
	c := f.client()
	request, _ := http.NewRequest("POST", f.server.URL+"/connect", strings.NewReader("email=x@example.com"))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := c.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 403 {
		t.Fatal("missing CSRF accepted")
	}
	f.request(c, "GET", "/connect", nil, 200)
	u, _ := url.Parse(f.server.URL)
	var token string
	for _, cookie := range c.Jar.Cookies(u) {
		if cookie.Name == "procash_csrf" {
			token = cookie.Value
		}
	}
	request, _ = http.NewRequest("POST", f.server.URL+"/connect", strings.NewReader(url.Values{"_csrf": {token}}.Encode()))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.Header.Set("Origin", "https://evil.example")
	response, err = c.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 403 {
		t.Fatal("cross-origin POST accepted")
	}
	for i := 0; i < 5; i++ {
		f.request(c, "POST", "/login", url.Values{"email": {"absent@example.com"}, "password": {"wrong"}}, 422)
	}
	f.request(c, "POST", "/login", url.Values{"email": {"absent@example.com"}, "password": {"wrong"}}, 429)
}
func TestProfileChangesNeedPasswordAndNeverGrantAdmin(t *testing.T) {
	f := newFixture(t)
	id := f.user("owner@example.com", "USER")
	c := f.login("owner@example.com")
	f.request(c, "POST", "/account", url.Values{"name": {"Новое имя"}, "email": {"changed@example.com"}, "phone": {"+77011234567"}}, 422)
	f.request(c, "POST", "/account", url.Values{"name": {"Новое имя"}, "email": {"CHANGED@example.com"}, "phone": {"+77011234567"}, "current_password": {"fixture-password"}, "role": {"ADMIN"}}, 303)
	if f.scalar(`SELECT email||':'||role FROM users WHERE id=$1`, id) != "changed@example.com:USER" {
		t.Fatal("incorrect profile update")
	}
	f.request(c, "GET", "/dashboard", nil, 303)
	f.login("changed@example.com")
}
func TestPasswordChangeRevokesOtherSessions(t *testing.T) {
	f := newFixture(t)
	f.user("owner@example.com", "USER")
	first := f.login("owner@example.com")
	second := f.login("owner@example.com")
	f.request(first, "POST", "/account/password", url.Values{"current_password": {"fixture-password"}, "password": {"another-secure-password"}, "password_confirmation": {"another-secure-password"}}, 303)
	f.request(first, "GET", "/dashboard", nil, 200)
	f.request(second, "GET", "/dashboard", nil, 303)
}
func TestFreedomPayWorkflowAndReview(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	venue := f.venue(owner, "Кофейня")
	f.user("admin@example.com", "ADMIN")
	c := f.login("owner@example.com")
	base := "/restaurants/" + venue + "/payments/freedom-pay"
	f.request(c, "GET", base, nil, 200)
	f.request(c, "POST", base+"/submit", nil, 422)
	data := map[string]url.Values{"company": {"organization_type": {"ТОО"}, "company_name": {"Кофейня ТОО"}, "bin": {"123456789012"}}, "director": {"director_name": {"Иван Иванов"}, "director_iin": {"123456789012"}, "director_phone": {"+77011234567"}, "director_email": {"director@example.com"}}, "address": {"legal_address": {"ул. Абая, 1"}, "city": {"Алматы"}, "postal_code": {"050000"}}, "bank": {"iban": {"KZ86" + strings.Repeat("1", 16)}, "bank_name": {"Банк"}, "bank_bic": {"ABCDEFGH"}}, "restaurant": {"website_url": {"https://example.com"}, "business_category": {"Кофейня"}, "business_description": {"Кофейня и ресторан в центре города Алматы"}, "average_check": {"2500.50"}, "expected_monthly_turnover": {"1000000"}}}
	for _, step := range freedomSteps[:5] {
		f.request(c, "POST", base+"/"+step, data[step], 303)
	}
	body, _ := f.request(c, "GET", base+"/review", nil, 200)
	if !strings.Contains(body, "Кофейня ТОО") {
		t.Fatal("review does not show saved application")
	}
	f.request(c, "POST", base+"/submit", nil, 303)
	f.request(c, "POST", base+"/company", data["company"], 409)
	id := f.scalar(`SELECT id::text FROM freedom_pay_applications WHERE restaurant_id=$1`, venue)
	admin := f.login("admin@example.com")
	path := "/admin/freedom-pay/applications/" + id
	f.request(admin, "POST", path+"/send", nil, 422)
	f.request(admin, "POST", path+"/send", url.Values{"partner_reference": {"FP-fixture"}}, 303)
	f.request(admin, "POST", path+"/changes", url.Values{"review_comment": {"Уточните адрес"}}, 303)
	f.request(c, "POST", base+"/address", data["address"], 303)
	f.request(c, "POST", base+"/submit", nil, 303)
	f.request(admin, "POST", path+"/send", url.Values{"partner_reference": {"FP-fixture"}}, 303)
	f.request(admin, "POST", path+"/approve", nil, 422)
	f.request(admin, "POST", path+"/approve", url.Values{"merchant_id": {"merchant-fixture"}}, 303)
	if f.scalar(`SELECT status FROM freedom_pay_applications WHERE id=$1`, id) != "APPROVED" || f.scalar(`SELECT active::text FROM restaurants WHERE id=$1`, venue) != "true" {
		t.Fatal("approval did not activate venue")
	}
}
func TestIikoWorkflowAndDuplicateSubmission(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	venue := f.venue(owner, "iiko Кафе")
	f.user("admin@example.com", "ADMIN")
	c := f.login("owner@example.com")
	path := "/restaurants/" + venue + "/integrations/iiko"
	f.request(c, "GET", path, nil, 200)
	f.request(c, "POST", path+"/submit", nil, 422)
	values := url.Values{"contact_name": {"Иван"}, "contact_email": {"owner@example.com"}, "contact_phone": {"+77011234567"}, "address": {"Алматы, Абая 1"}, "pos_type": {"iikoCloud"}, "software_version": {"9"}, "comment": {"Настроить после обеда"}}
	f.request(c, "POST", path, values, 303)
	f.request(c, "POST", path+"/submit", nil, 303)
	f.request(c, "POST", path+"/submit", nil, 422)
	if f.scalar(`SELECT count(*)::text FROM mail_outbox`) != "1" {
		t.Fatal("duplicate iiko notification")
	}
	id := f.scalar(`SELECT id::text FROM iiko_applications WHERE restaurant_id=$1`, venue)
	admin := f.login("admin@example.com")
	f.request(admin, "GET", "/admin/iiko/applications/"+id, nil, 200)
	f.request(admin, "POST", "/admin/iiko/applications/"+id+"/send", nil, 303)
	f.request(admin, "POST", "/admin/iiko/applications/"+id+"/approve", nil, 303)
	f.request(c, "POST", path, values, 409)
	if f.scalar(`SELECT status FROM iiko_applications WHERE id=$1`, id) != "APPROVED" {
		t.Fatal("iiko review failed")
	}
}
func (f *fixture) order(venue, amount string) (string, string) {
	table := NewID()
	token := NewID()
	f.sql(`INSERT INTO restaurant_tables(id,restaurant_id,table_number,qr_token,active,created_at,updated_at) VALUES($1,$2,$3,$4,true,now(),now())`, table, venue, table[:8], token)
	id := NewID()
	f.sql(`INSERT INTO restaurant_orders(id,restaurant_id,restaurant_table_id,order_number,status,total_amount,opened_at,created_at,updated_at) VALUES($1,$2,$3,'1042','OPEN',$4,now(),now(),now())`, id, venue, table, amount)
	f.sql(`INSERT INTO order_items(id,order_id,name,quantity,unit_price,total_price,created_at) VALUES($1,$2,'Капучино',1,$3,$3,now())`, NewID(), id, amount)
	return id, token
}
func TestMetricsAreExactAndScoped(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	other := f.user("other@example.com", "USER")
	venue := f.venue(owner, "Своё заведение")
	alien := f.venue(other, "Чужое заведение")
	for _, amount := range []string{"10.25", "20.10"} {
		order, _ := f.order(venue, amount)
		f.sql(`INSERT INTO payments(id,order_id,restaurant_id,amount,status,provider,paid_at,created_at,updated_at) VALUES($1,$2,$3,$4,'PAID','FREEDOM_PAY',now(),now(),now())`, NewID(), order, venue, amount)
	}
	order, _ := f.order(alien, "999.99")
	f.sql(`INSERT INTO payments(id,order_id,restaurant_id,amount,status,provider,paid_at,created_at,updated_at) VALUES($1,$2,$3,999.99,'PAID','FREEDOM_PAY',now(),now(),now())`, NewID(), order, alien)
	c := f.login("owner@example.com")
	body, _ := f.request(c, "GET", "/dashboard?days=7", nil, 200)
	if !strings.Contains(body, "30,35 ₸") || strings.Contains(body, "Чужое заведение") || strings.Contains(body, "999,99") {
		t.Fatal("metrics leaked other owner or changed decimal amounts")
	}
	f.user("admin@example.com", "ADMIN")
	body, _ = f.request(f.login("admin@example.com"), "GET", "/admin", nil, 200)
	if !strings.Contains(body, "1030,34 ₸") || !strings.Contains(body, "Чужое заведение") {
		t.Fatal("admin metrics incorrect")
	}
}
func TestQRPublicBillAndIdempotentMockPayment(t *testing.T) {
	f := newFixture(t)
	f.app.Config.MockPayments = true
	owner := f.user("owner@example.com", "USER")
	venue := f.venue(owner, "Кофейня")
	order, token := f.order(venue, "2400.00")
	c := f.login("owner@example.com")
	table := f.scalar(`SELECT id::text FROM restaurant_tables WHERE qr_token=$1`, token)
	body, response := f.request(c, "GET", "/restaurants/"+venue+"/tables/"+table+"/qr.png", nil, 200)
	if response.Header.Get("Content-Type") != "image/png" || !strings.HasPrefix(body, "\x89PNG") {
		t.Fatal("not a real PNG")
	}
	f.request(c, "GET", "/restaurants/"+venue+"/tables/"+table+"/qr.png?size=99999", nil, 400)
	guest := f.client()
	body, _ = f.request(guest, "GET", "/r/venue-"+venue+"/q/"+token, nil, 200)
	if !strings.Contains(body, "Капучино") {
		t.Fatal("bill items missing")
	}
	_, response = f.request(guest, "POST", "/payments/create", url.Values{"order_id": {order}, "amount": {"0.01"}}, 303)
	payment := f.scalar(`SELECT id::text FROM payments WHERE order_id=$1`, order)
	f.request(guest, "POST", "/payments/create", url.Values{"order_id": {order}}, 303)
	f.request(guest, "POST", "/payments/"+payment+"/mock/success", nil, 303)
	f.request(guest, "POST", "/payments/"+payment+"/mock/success", nil, 303)
	if f.scalar(`SELECT amount::text||':'||status FROM payments WHERE id=$1`, payment) != "2400.00:PAID" {
		t.Fatal("server amount or idempotence failed")
	}
	f.request(guest, "GET", response.Header.Get("Location"), nil, 200)
	f.app.Config.MockPayments = false
	f.request(guest, "POST", "/payments/create", url.Values{"order_id": {order}}, 404)
}
func TestMailRetriesEncryptedPayloadAndConcurrentClaim(t *testing.T) {
	f := newFixture(t)
	f.submitRequest(f.client(), "owner@example.com", "Кофейня")
	var payload []byte
	if err := f.pool.QueryRow(context.Background(), `SELECT payload FROM mail_outbox`).Scan(&payload); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(payload), "owner@example.com") {
		t.Fatal("outbox stores plaintext")
	}
	f.mail.Fail = true
	if ok, err := f.app.DeliverOne(context.Background()); !ok || err != nil {
		t.Fatal(err)
	}
	if f.scalar(`SELECT status||':'||attempts::text FROM mail_outbox`) != "PENDING:1" {
		t.Fatal("failed SMTP was not scheduled for retry")
	}
	f.mail.Fail = false
	f.sql(`UPDATE mail_outbox SET next_attempt_at=now()`)
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := f.app.DeliverOne(context.Background()); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if len(f.mail.Messages) != 1 {
		t.Fatal("concurrent workers sent same message twice")
	}
}
func TestHTMXFragmentsEscapeInputAndUseRelativeActions(t *testing.T) {
	f := newFixture(t)
	c := f.client()
	f.request(c, "GET", "/login", nil, 200)
	request, _ := http.NewRequest("GET", f.server.URL+"/connect", nil)
	request.Header.Set("HX-Request", "true")
	response, err := c.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if strings.Contains(string(raw), "<!doctype") || !strings.Contains(string(raw), `action="/connect"`) {
		t.Fatal("fragment or relative HTTPS-safe action incorrect")
	}
	owner := f.user("owner@example.com", "USER")
	venue := f.venue(owner, `<script>alert("xss")</script>`)
	body, _ := f.request(f.login("owner@example.com"), "GET", "/restaurants/"+venue, nil, 200)
	if strings.Contains(body, `<script>alert("xss")`) {
		t.Fatal("stored XSS")
	}
}
func TestRepeatedMigrationPreservesRecords(t *testing.T) {
	f := newFixture(t)
	id := f.user("legacy@example.com", "ADMIN")
	venue := f.venue(id, "Существующее заведение")
	hash := f.scalar(`SELECT password_hash FROM users WHERE id=$1`, id)
	order, token := f.order(venue, "12.34")
	payment := NewID()
	application := NewID()
	f.sql(`INSERT INTO payments(id,order_id,restaurant_id,amount,status,provider,created_at,updated_at) VALUES($1,$2,$3,12.34,'PENDING','FREEDOM_PAY',now(),now())`, payment, order, venue)
	f.sql(`INSERT INTO freedom_pay_applications(id,restaurant_id,status,company_name) VALUES($1,$2,'UNDER_REVIEW','Legacy company')`, application, venue)
	f.sql(`DELETE FROM go_schema_migrations; ALTER TABLE users DROP COLUMN name, DROP COLUMN phone, DROP COLUMN must_change_password, DROP COLUMN temporary_password_expires_at`)
	if err := db.Migrate(context.Background(), f.pool); err != nil {
		t.Fatal(err)
	}
	if f.scalar(`SELECT password_hash FROM users WHERE id=$1`, id) != hash || f.scalar(`SELECT name FROM restaurants WHERE id=$1`, venue) != "Существующее заведение" {
		t.Fatal("migration altered existing data")
	}
	if f.scalar(`SELECT amount::text||':'||status FROM payments WHERE id=$1`, payment) != "12.34:PENDING" || f.scalar(`SELECT qr_token::text FROM restaurant_tables WHERE restaurant_id=$1`, venue) != token || f.scalar(`SELECT status FROM freedom_pay_applications WHERE id=$1`, application) != "UNDER_FREEDOM_REVIEW" {
		t.Fatal("legacy orders, QR tokens or applications changed during adoption")
	}
	if err := db.Migrate(context.Background(), f.pool); err != nil {
		t.Fatal(err)
	}
}
func TestAdminResetRevokesSessionsAndDoesNotExposePasswordAgain(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	adminID := f.user("admin@example.com", "ADMIN")
	c := f.login("owner@example.com")
	admin := f.login("admin@example.com")
	body, _ := f.request(admin, "POST", "/admin/users/"+owner+"/reset", nil, 200)
	match := regexp.MustCompile(`id="temporary-password">([^<]+)<`).FindStringSubmatch(body)
	if len(match) != 2 {
		t.Fatal("temporary credential not shown")
	}
	temporary := match[1]
	_, response := f.request(f.client(), "POST", "/login", url.Values{"email": {"owner@example.com"}, "password": {temporary}}, 303)
	if response.Header.Get("Location") != "/account/password" {
		t.Fatal("reset password must permit first login and require replacement")
	}
	if _, err := f.app.DeliverOne(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(f.mail.Messages) != 1 || f.mail.Messages[0].To != "owner@example.com" || !strings.Contains(f.mail.Messages[0].Body, "Временный пароль: "+temporary) {
		t.Fatal("password reset must send the usable temporary credential to the user")
	}
	f.request(c, "GET", "/dashboard", nil, 303)
	body, _ = f.request(admin, "GET", "/admin/users", nil, 200)
	if strings.Contains(body, `id="temporary-password"`) {
		t.Fatal("credential retained in users list")
	}
	f.request(admin, "POST", "/admin/users/"+adminID+"/disable", nil, 403)
}
func TestHealthChecksDatabase(t *testing.T) {
	f := newFixture(t)
	f.request(f.client(), "GET", "/favicon.ico", nil, 200)
	f.request(f.client(), "GET", "/robots.txt", nil, 200)
	body, _ := f.request(f.client(), "GET", "/actuator/health", nil, 200)
	var v map[string]string
	if json.Unmarshal([]byte(body), &v) != nil || v["status"] != "UP" {
		t.Fatal("invalid health response")
	}
}
func TestClientIPIgnoresUntrustedForwarding(t *testing.T) {
	r := httptest.NewRequest("POST", "http://example.com/login", nil)
	r.RemoteAddr = "203.0.113.5:3456"
	r.Header.Set("X-Forwarded-For", "198.51.100.1")
	if clientIP(r) != "203.0.113.5" {
		t.Fatal("untrusted IP header accepted")
	}
	r.RemoteAddr = "127.0.0.1:3456"
	r.Header.Set("X-Forwarded-For", "1.1.1.1, 198.51.100.2")
	if clientIP(r) != "198.51.100.2" {
		t.Fatal("wrong trusted proxy chain")
	}
}
func TestUUIDAndPasswordInputValidation(t *testing.T) {
	if !ValidID(NewID()) || ValidID("not-an-id") {
		t.Fatal("UUID validation")
	}
	hash, err := PasswordHash("correct-password")
	if err != nil || !CheckPassword(hash, "correct-password") || CheckPassword(hash, strings.Repeat("x", 73)) {
		t.Fatal("bcrypt validation")
	}
}

func TestOrderAPIPreservesContractAndOwnership(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	f.user("other@example.com", "USER")
	venue := f.venue(owner, "API Кафе")
	order, _ := f.order(venue, "3300.25")
	f.sql(`UPDATE restaurant_tables SET table_number='1' WHERE id=(SELECT restaurant_table_id FROM restaurant_orders WHERE id=$1)`, order)
	path := "/api/v1/orders/current?restaurantId=" + venue + "&tableNumber=1"
	f.request(f.client(), "GET", path, nil, 401)
	c := f.login("owner@example.com")
	body, _ := f.request(c, "GET", path, nil, 200)
	if !strings.Contains(body, `"totalAmount":3300.25`) {
		t.Fatal("API lost decimal amount")
	}
	f.request(f.login("other@example.com"), "GET", path, nil, 404)
	f.request(c, "GET", "/api/v1/orders/current", nil, 400)
	f.request(c, "GET", path+"x", nil, 400)
}
