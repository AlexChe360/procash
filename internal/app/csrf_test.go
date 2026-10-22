package app

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestHEADCannotChangeProfileWithoutCSRF(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	c := f.login("owner@example.com")
	name := f.scalar(`SELECT name FROM users WHERE id=$1`, owner)
	query := url.Values{"name": {"FORGED"}, "email": {"owner@example.com"}, "phone": {"+77011234567"}}
	r, _ := http.NewRequest(http.MethodHead, f.server.URL+"/account?"+query.Encode(), nil)
	r.Header.Set("Origin", "https://evil.example")
	response, err := c.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if f.scalar(`SELECT name FROM users WHERE id=$1`, owner) != name {
		t.Fatal("HEAD changed the profile without a CSRF token")
	}
	if response.StatusCode != http.StatusOK {
		t.Fatalf("HEAD should be read-only: got %d", response.StatusCode)
	}
}

func csrfState(f *fixture) string {
	f.t.Helper()
	var tables []string
	for _, table := range []string{"users", "restaurants", "restaurant_tables", "restaurant_orders", "order_items", "payments", "freedom_pay_applications", "iiko_applications", "connection_requests", "mail_outbox", "audit_events", "sessions", "rate_limits"} {
		order := "id"
		if table == "sessions" {
			order = "token_hash"
		} else if table == "rate_limits" {
			order = "key"
		}
		tables = append(tables, fmt.Sprintf("'%s',(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY %s),'[]'::jsonb) FROM %s t)", table, order, table))
	}
	return f.scalar("SELECT md5(jsonb_build_object(" + strings.Join(tables, ",") + ")::text)")
}

func TestGETAndHEADNeverChangeApplicationState(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	c := f.login("owner@example.com")
	venue := f.venue(owner, "Original")
	paths := []string{"/connect", "/login", "/account", "/account/password", "/restaurants/" + venue, "/restaurants/" + venue + "/tables", "/restaurants/" + venue + "/integrations/iiko"}
	for _, step := range []string{"company", "director", "address", "bank", "restaurant", "review"} {
		paths = append(paths, "/restaurants/"+venue+"/payments/freedom-pay/"+step)
	}
	query := url.Values{"name": {"FORGED"}, "email": {"owner@example.com"}, "password": {"fixture-password"}, "current_password": {"fixture-password"}, "password_confirmation": {"fixture-password"}, "contact_name": {"FORGED"}, "restaurant_name": {"FORGED"}, "city": {"Алматы"}, "phone": {"+77011234567"}, "consent": {"yes"}, "company_name": {"FORGED"}, "organization_type": {"ТОО"}, "bin": {"123456789012"}, "contact_email": {"owner@example.com"}, "contact_phone": {"+77011234567"}, "address": {"Алматы"}, "pos_type": {"iikoCloud"}}
	before := csrfState(f)
	for _, method := range []string{http.MethodGet, http.MethodHead} {
		for _, path := range paths {
			for _, client := range []*http.Client{c, f.client()} {
				r, _ := http.NewRequest(method, f.server.URL+path+"?"+query.Encode(), nil)
				r.Header.Set("Origin", "https://evil.example")
				response, err := client.Do(r)
				if err != nil {
					t.Fatal(err)
				}
				response.Body.Close()
				if csrfState(f) != before {
					t.Fatalf("%s %s changed data, sessions, mail or rate limits", method, path)
				}
			}
		}
	}
}

func csrfCookies(f *fixture, client *http.Client) (session, token string) {
	u, _ := url.Parse(f.server.URL)
	for _, cookie := range client.Jar.Cookies(u) {
		if cookie.Name == f.app.cookieName("session") {
			session = cookie.Value
		} else if cookie.Name == f.app.cookieName("csrf") {
			token = cookie.Value
		}
	}
	return
}

func TestEveryPOSTActionRejectsCSRFAttacksWithoutSideEffects(t *testing.T) {
	f := newFixture(t)
	f.app.Config.MockPayments = true
	owner := f.user("owner@example.com", "USER")
	f.user("admin@example.com", "ADMIN")
	admin := f.login("admin@example.com")
	session, csrf := csrfCookies(f, admin)
	_, foreignToken := csrfCookies(f, f.login("owner@example.com"))
	guest := f.client()
	f.request(guest, "GET", "/connect", nil, 200)
	_, anonymousToken := csrfCookies(f, guest)
	venue := f.venue(owner, "Original")
	order, _ := f.order(venue, "12.34")
	request, freedom, iiko, mail, payment := NewID(), NewID(), NewID(), NewID(), NewID()
	f.sql(`INSERT INTO connection_requests(id,contact_name,email,phone,restaurant_name,city) VALUES($1,'Owner','new@example.com','+77011234567','Original','Алматы')`, request)
	f.sql(`INSERT INTO freedom_pay_applications(id,restaurant_id) VALUES($1,$2)`, freedom, venue)
	f.sql(`INSERT INTO iiko_applications(id,restaurant_id) VALUES($1,$2)`, iiko, venue)
	f.sql(`INSERT INTO mail_outbox(id,recipient,subject,status) VALUES($1,'owner@example.com','Original','FAILED')`, mail)
	f.sql(`INSERT INTO payments(id,order_id,restaurant_id,amount,status,provider) VALUES($1,$2,$3,12.34,'PENDING','FREEDOM_PAY')`, payment, order, venue)
	paths := []string{"/login", "/connect", "/register", "/logout", "/account", "/account/password", "/restaurants/" + venue, "/restaurants/" + venue + "/tables", "/restaurants/" + venue + "/payments/freedom-pay/submit", "/restaurants/" + venue + "/integrations/iiko", "/restaurants/" + venue + "/integrations/iiko/submit", "/admin/mail/" + mail + "/retry", "/payments/create", "/payments/" + payment + "/mock/success", "/payments/" + payment + "/mock/fail"}
	for _, step := range []string{"company", "director", "address", "bank", "restaurant", "review"} {
		paths = append(paths, "/restaurants/"+venue+"/payments/freedom-pay/"+step)
	}
	for _, action := range []string{"approve", "review", "reject"} {
		paths = append(paths, "/admin/requests/"+request+"/"+action)
	}
	for _, action := range []string{"reset", "enable", "disable"} {
		paths = append(paths, "/admin/users/"+owner+"/"+action)
	}
	for _, action := range []string{"send", "approve", "changes", "reject"} {
		paths = append(paths, "/admin/freedom-pay/applications/"+freedom+"/"+action, "/admin/iiko/applications/"+iiko+"/"+action)
	}
	// A new POST route must be represented in the rejection matrix.
	source, err := parser.ParseFile(token.NewFileSet(), "server.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	ast.Inspect(source, func(node ast.Node) bool {
		call, ok := node.(*ast.CallExpr)
		if !ok || len(call.Args) == 0 {
			return true
		}
		literal, ok := call.Args[0].(*ast.BasicLit)
		if !ok || literal.Kind != token.STRING {
			return true
		}
		pattern, _ := strconv.Unquote(literal.Value)
		if !strings.HasPrefix(pattern, "POST ") {
			return true
		}
		matcher := regexp.MustCompile("^" + regexp.MustCompile(`\{[^}]+\}`).ReplaceAllString(strings.TrimPrefix(pattern, "POST "), `[^/]+`) + "$")
		for _, path := range paths {
			if matcher.MatchString(path) {
				return true
			}
		}
		t.Errorf("POST route missing from CSRF matrix: %s", pattern)
		return true
	})
	tests := []string{"missing", "invalid", "missing-cookie", "forged-cookie", "foreign-session", "anonymous-token", "query-only", "duplicate-field", "duplicate-header", "header-body-mismatch", "duplicate-csrf-cookie", "duplicate-session-cookie", "foreign-origin", "null-origin", "origin-path", "duplicate-origin", "empty-origin", "foreign-referer", "duplicate-referer", "cross-site", "same-site", "duplicate-fetch-site", "forwarded-origin", "plain-text", "json", "method-override", "hx-request"}
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	before := csrfState(f)
	for _, path := range paths {
		for _, attack := range tests {
			values := url.Values{"_csrf": {csrf}, "name": {"FORGED"}, "email": {"admin@example.com"}, "password": {"forged-new-password"}, "current_password": {"fixture-password"}, "password_confirmation": {"forged-new-password"}, "order_id": {order}, "table_number": {"999"}, "review_comment": {"FORGED"}, "partner_reference": {"FORGED"}, "merchant_id": {"FORGED"}}
			cookie := csrf
			headers := http.Header{"Content-Type": {"application/x-www-form-urlencoded"}}
			suffix := ""
			switch attack {
			case "missing":
				values.Del("_csrf")
			case "invalid":
				values.Set("_csrf", "invalid")
			case "missing-cookie":
				cookie = ""
			case "forged-cookie":
				cookie = strings.Repeat("a", 43) + "." + strings.Repeat("0", 64)
				values.Set("_csrf", cookie)
			case "foreign-session":
				cookie = foreignToken
				values.Set("_csrf", cookie)
			case "anonymous-token":
				cookie = anonymousToken
				values.Set("_csrf", cookie)
			case "query-only":
				values.Del("_csrf")
				suffix = "?_csrf=" + url.QueryEscape(csrf)
			case "duplicate-field":
				values.Add("_csrf", "invalid")
			case "duplicate-header":
				headers["X-Csrf-Token"] = []string{csrf, "invalid"}
			case "header-body-mismatch":
				headers.Set("X-CSRF-Token", csrf)
				values.Set("_csrf", "invalid")
			case "foreign-origin":
				headers.Set("Origin", "https://evil.example")
			case "null-origin":
				headers.Set("Origin", "null")
			case "origin-path":
				headers.Set("Origin", f.server.URL+"/path")
			case "duplicate-origin":
				headers["Origin"] = []string{f.server.URL, "https://evil.example"}
			case "empty-origin":
				headers["Origin"] = []string{""}
			case "foreign-referer":
				headers.Set("Referer", "https://evil.example/form")
			case "duplicate-referer":
				headers["Referer"] = []string{f.server.URL + "/account", "https://evil.example/form"}
			case "cross-site":
				headers.Set("Sec-Fetch-Site", "cross-site")
			case "same-site":
				headers.Set("Sec-Fetch-Site", "same-site")
			case "duplicate-fetch-site":
				headers["Sec-Fetch-Site"] = []string{"same-origin", "cross-site"}
			case "forwarded-origin":
				headers.Set("Origin", "https://evil.example")
				headers.Set("X-Forwarded-Host", "evil.example")
				headers.Set("Forwarded", "host=evil.example;proto=https")
			case "plain-text":
				headers.Set("Content-Type", "text/plain")
			case "json":
				headers.Set("Content-Type", "application/json")
			case "method-override":
				values.Del("_csrf")
				values.Set("_method", "HEAD")
				headers.Set("X-HTTP-Method-Override", "HEAD")
			case "hx-request":
				values.Del("_csrf")
				headers.Set("HX-Request", "true")
				headers.Set("X-Requested-With", "XMLHttpRequest")
			}
			r, _ := http.NewRequest("POST", f.server.URL+path+suffix, strings.NewReader(values.Encode()))
			r.Header = headers
			r.AddCookie(&http.Cookie{Name: f.app.cookieName("session"), Value: session})
			if cookie != "" {
				r.AddCookie(&http.Cookie{Name: f.app.cookieName("csrf"), Value: cookie})
			}
			if attack == "duplicate-csrf-cookie" {
				r.AddCookie(&http.Cookie{Name: f.app.cookieName("csrf"), Value: csrf})
			}
			if attack == "duplicate-session-cookie" {
				r.AddCookie(&http.Cookie{Name: f.app.cookieName("session"), Value: session})
			}
			response, err := client.Do(r)
			if err != nil {
				t.Fatal(err)
			}
			response.Body.Close()
			if response.StatusCode != http.StatusForbidden || len(response.Cookies()) != 0 || response.Header.Get("X-ProCash-Error") != "csrf" {
				t.Fatalf("%s %s: got %d, cookies=%d", attack, path, response.StatusCode, len(response.Cookies()))
			}
			if csrfState(f) != before {
				t.Fatalf("%s %s changed application state", attack, path)
			}
		}
	}
	t.Logf("Rejected %d attack variants across %d POST actions (%d requests), preserving all application state", len(tests), len(paths), len(tests)*len(paths))
}

func TestCSRFOriginNormalizationAndCookieFlags(t *testing.T) {
	a, err := New(nil, Config{BaseURL: "https://procash.kz", Key: []byte(strings.Repeat("k", 32))})
	if err != nil {
		t.Fatal(err)
	}
	session := RandomToken()
	nonce := RandomToken()
	csrf := nonce + "." + a.csrfSignatureForSession(session, nonce)
	tests := []struct {
		name    string
		headers http.Header
		valid   bool
	}{
		{"origin", http.Header{"Origin": {"https://procash.kz"}}, true},
		{"default-port", http.Header{"Origin": {"https://PROCASH.kz:443"}}, true},
		{"legacy", http.Header{}, true},
		{"same-origin-fetch", http.Header{"Sec-Fetch-Site": {"same-origin"}}, true},
		{"referer", http.Header{"Referer": {"https://procash.kz/account?saved=1"}}, true},
		{"subdomain", http.Header{"Origin": {"https://evil.procash.kz"}}, false},
		{"suffix", http.Header{"Origin": {"https://procash.kz.evil.example"}}, false},
		{"userinfo", http.Header{"Origin": {"https://evil@procash.kz"}}, false},
		{"scheme", http.Header{"Origin": {"http://procash.kz"}}, false},
		{"port", http.Header{"Origin": {"https://procash.kz:8443"}}, false},
		{"fragment", http.Header{"Origin": {"https://procash.kz#"}}, false},
		{"query", http.Header{"Origin": {"https://procash.kz?"}}, false},
	}
	for _, test := range tests {
		r := httptest.NewRequest("POST", "/logout", strings.NewReader(url.Values{"_csrf": {csrf}}.Encode()))
		r.Header = test.headers.Clone()
		r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		r.AddCookie(&http.Cookie{Name: a.cookieName("session"), Value: session})
		r.AddCookie(&http.Cookie{Name: a.cookieName("csrf"), Value: csrf})
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		if a.validateCSRF(r) != test.valid {
			t.Errorf("origin case %s: incorrect validation", test.name)
		}
	}
	w := httptest.NewRecorder()
	a.setSession(w, session, 43200)
	for _, cookie := range w.Result().Cookies() {
		if !strings.HasPrefix(cookie.Name, "__Host-") || !cookie.Secure || !cookie.HttpOnly || cookie.SameSite != http.SameSiteLaxMode || cookie.Path != "/" || cookie.Domain != "" {
			t.Fatal("production cookie attributes weakened")
		}
	}
}

func TestCSRFSupportsMultipartAndHeaderOnlyAndRotatesOnAuthentication(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	c := f.client()
	f.request(c, "GET", "/login", nil, 200)
	_, anonymous := csrfCookies(f, c)
	f.request(c, "POST", "/login", url.Values{"email": {"owner@example.com"}, "password": {"fixture-password"}}, 303)
	session, csrf := csrfCookies(f, c)
	if csrf == anonymous || !f.app.validCSRF(requestWithSession(f.app, session), csrf) {
		t.Fatal("login must rotate and bind CSRF")
	}
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	for key, value := range map[string]string{"_csrf": csrf, "name": "Multipart name", "email": "owner@example.com"} {
		if err := writer.WriteField(key, value); err != nil {
			t.Fatal(err)
		}
	}
	writer.Close()
	r, _ := http.NewRequest("POST", f.server.URL+"/account", &body)
	r.Header.Set("Content-Type", writer.FormDataContentType())
	response, err := c.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 303 || f.scalar(`SELECT name FROM users WHERE id=$1`, owner) != "Multipart name" {
		t.Fatal("legitimate multipart form failed")
	}
	f.request(c, "POST", "/account/password", url.Values{"current_password": {"fixture-password"}, "password": {"new-secure-password"}, "password_confirmation": {"new-secure-password"}}, 303)
	newSession, newCSRF := csrfCookies(f, c)
	if newSession == session || newCSRF == csrf || f.app.validCSRF(requestWithSession(f.app, newSession), csrf) {
		t.Fatal("password change did not rotate session-bound CSRF")
	}
	r, _ = http.NewRequest("POST", f.server.URL+"/logout", nil)
	r.Header.Set("X-CSRF-Token", newCSRF)
	response, err = c.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	logoutSession, logoutCSRF := csrfCookies(f, c)
	if response.StatusCode != 303 || logoutCSRF != "" || logoutSession != "" {
		t.Fatal("header-only logout must clear session and CSRF cookies")
	}
	f.request(c, "GET", "/login", nil, 200)
	_, logoutCSRF = csrfCookies(f, c)
	if logoutCSRF == newCSRF || !f.app.validCSRF(requestWithSession(f.app, ""), logoutCSRF) {
		t.Fatal("new login form must use fresh anonymous CSRF")
	}
}

func requestWithSession(a *App, session string) *http.Request {
	r := httptest.NewRequest("POST", "/", nil)
	if session != "" {
		r.AddCookie(&http.Cookie{Name: a.cookieName("session"), Value: session})
	}
	return r
}

func TestUnsafeMethodsAndQueryOnlyDataCannotBypassCSRF(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	c := f.login("owner@example.com")
	_, csrf := csrfCookies(f, c)
	before := csrfState(f)
	for _, method := range []string{"PUT", "PATCH", "DELETE"} {
		r, _ := http.NewRequest(method, f.server.URL+"/account", strings.NewReader("name=FORGED"))
		r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		response, err := c.Do(r)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if response.StatusCode != 403 || csrfState(f) != before {
			t.Fatalf("unsafe method %s bypassed CSRF", method)
		}
	}
	query := url.Values{"name": {"FORGED"}, "email": {"owner@example.com"}}
	f.request(c, "POST", "/account?"+query.Encode(), nil, 422)
	if f.scalar(`SELECT name FROM users WHERE id=$1`, owner) == "FORGED" {
		t.Fatal("mutation read data from URL parameters")
	}
	// Invalid multipart bodies must fail before any action executes.
	r, _ := http.NewRequest("POST", f.server.URL+"/account", strings.NewReader(strings.Repeat("x", 70000)))
	r.Header.Set("Content-Type", "multipart/form-data; boundary=fixture")
	r.Header.Set("X-CSRF-Token", csrf)
	response, err := c.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 400 || csrfState(f) != before {
		t.Fatal("malformed oversized form changed state")
	}
}

func TestBrowserCSRFWithProductionCookiesAndSiblingOrigins(t *testing.T) {
	f := newFixture(t)
	f.app.Config.MockPayments = true
	owner := f.user("owner@example.test", "USER")
	f.user("admin@example.test", "ADMIN")
	attacker := f.user("attacker@example.test", "USER")
	f.sql(`UPDATE users SET name='Original' WHERE id=$1`, owner)
	venue := f.venue(owner, "Original")
	order, _ := f.order(venue, "12.34")
	payment, request := NewID(), NewID()
	f.sql(`INSERT INTO payments(id,order_id,restaurant_id,amount,status,provider) VALUES($1,$2,$3,12.34,'PENDING','FREEDOM_PAY')`, payment, order, venue)
	f.sql(`INSERT INTO connection_requests(id,contact_name,email,phone,restaurant_name,city) VALUES($1,'Owner','new@example.test','+77011234567','Original','Алматы')`, request)
	type observation struct {
		Method  string `json:"method"`
		Path    string `json:"path"`
		Origin  string `json:"origin"`
		Site    string `json:"site"`
		Session bool   `json:"session"`
	}
	var observed []observation
	var observedMu sync.Mutex
	handler := f.app.Handler()
	victim := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Out-of-band observations prove the headers/cookies received by the
		// server even when the browser correctly exposes an opaque response.
		if r.URL.Path == "/__csrf-observations" {
			observedMu.Lock()
			defer observedMu.Unlock()
			JSON(w, observed)
			return
		}
		_, cookieErr := r.Cookie(f.app.cookieName("session"))
		observedMu.Lock()
		observed = append(observed, observation{r.Method, r.URL.RequestURI(), r.Header.Get("Origin"), r.Header.Get("Sec-Fetch-Site"), cookieErr == nil})
		observedMu.Unlock()
		handler.ServeHTTP(w, r)
	}))
	t.Cleanup(victim.Close)
	u, _ := url.Parse(victim.URL)
	f.app.Config.BaseURL = "https://app.procash.test:" + u.Port()
	evil := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, "<!doctype html><title>Untrusted origin fixture</title><body>Untrusted origin</body>")
	}))
	t.Cleanup(evil.Close)
	evilURL, _ := url.Parse(evil.URL)
	input := map[string]string{"base": f.app.Config.BaseURL, "observer": victim.URL, "sibling": "https://evil.procash.test:" + evilURL.Port(), "external": "https://attacker.other.test:" + evilURL.Port(), "payment": payment, "order": order, "request": request, "owner": owner}
	raw, _ := json.Marshal(input)
	script, _ := filepath.Abs("../../tests/csrf_browser.cjs")
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, "node", script)
	command.Stdin = bytes.NewReader(raw)
	command.Env = os.Environ()
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("browser CSRF checks failed: %v\n%s", err, output)
	}
	t.Log(string(output))
	if f.scalar(`SELECT name||':'||enabled::text FROM users WHERE id=$1`, owner) != "Legitimate:true" || f.scalar(`SELECT count(*)::text FROM sessions WHERE user_id=$1`, attacker) != "0" || f.scalar(`SELECT status FROM payments WHERE id=$1`, payment) != "PENDING" || f.scalar(`SELECT status FROM connection_requests WHERE id=$1`, request) != "NEW" || f.scalar(`SELECT count(*)::text FROM mail_outbox`) != "0" {
		t.Fatal("forged browser requests changed account, session, payment, request or mail state")
	}
}
