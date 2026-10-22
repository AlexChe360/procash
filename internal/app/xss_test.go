package app

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/AlexChe360/procash/web"
)

var xssPayloads = []string{
	`<script>globalThis.__xss=1</script>`,
	`<img src=x onerror="globalThis.__xss=1">`,
	`"><svg/onload=globalThis.__xss=1>`,
	`</textarea><img src=x onerror=globalThis.__xss=1>`,
	`</title><script>globalThis.__xss=1</script>`,
	`' autofocus onfocus='globalThis.__xss=1' x='`,
	`javascript:globalThis.__xss=1`,
	`&#x3c;img src=x onerror=globalThis.__xss=1&#x3e;`,
	`<math><mtext><table><mglyph><style><!--</style><img title="--><img src=x onerror=globalThis.__xss=1>">`,
	`"><div hx-get="/__xss/probe" hx-trigger="load" id="xss-probe"></div>`,
	`<form id="xss-probe"><input name="requestSubmit"><input name="action"></form>`,
	`<iframe srcdoc="<script>parent.__xss=1</script>"></iframe>`,
}

type browserXSSCase struct {
	Name string `json:"name"`
	HTML string `json:"html"`
}

func TestIntegrationURLsRejectExecutableSchemes(t *testing.T) {
	fields := []Field{{Name: "url", Type: "url", Max: 500, Required: true}}
	for _, value := range []string{"javascript:alert(1)", "JaVaScRiPt:alert(1)", "data:text/html,<script>alert(1)</script>", "vbscript:msgbox(1)", "file:///etc/passwd", "//example.com", "java\nscript:alert(1)", "&#106;avascript:alert(1)"} {
		if validFields(map[string]string{"url": value}, fields) == "" {
			t.Errorf("accepted executable or non-HTTP URL %q", value)
		}
	}
	for _, value := range []string{"https://example.com", "http://example.com/iiko?branch=1"} {
		if validFields(map[string]string{"url": value}, fields) != "" {
			t.Errorf("rejected ordinary URL %q", value)
		}
	}
}

// These documents are inspected without CSP as well: escaping must be sufficient
// on its own, rather than an injected element merely being blocked by policy.
func xssTemplateCases(t *testing.T, a *App) []browserXSSCase {
	t.Helper()
	entries, err := web.Files.ReadDir("templates")
	if err != nil {
		t.Fatal(err)
	}
	var cases []browserXSSCase
	for _, entry := range entries {
		name := entry.Name()
		if name == "layout.html" || name == "shared.html" || name == "home.html" {
			continue
		}
		for _, payload := range xssPayloads {
			id := NewID()
			values := map[string]string{}
			fields := append(allFreedomFields(), iikoFields...)
			for _, field := range fields {
				values[field.Name] = payload
			}
			for _, key := range []string{"name", "phone", "email", "description", "contact_name", "restaurant_name", "city", "pos_system", "comment"} {
				values[key] = payload
			}
			user := &User{ID: id, Role: "ADMIN", Name: payload, Email: payload, Phone: payload}
			restaurant := &Restaurant{ID: id, Name: payload, City: payload, Phone: payload, Description: payload, FreedomStatus: payload, IikoStatus: payload}
			application := &Integration{ID: id, RestaurantID: id, Kind: "freedom-pay", RestaurantName: payload, OwnerEmail: payload, ReviewComment: payload, Reference: payload, MerchantID: payload, Status: "READY_FOR_REVIEW", Step: "company", Values: values, Editable: true, Complete: true}
			p := Page{
				Title: payload, Error: payload, Message: payload, TemporaryPassword: payload, LoginURL: payload,
				Values: values, Fields: fields, Restaurant: restaurant, Restaurants: []Restaurant{*restaurant},
				Request:  &ConnectionRequest{ID: id, UserID: id, RestaurantID: id, ContactName: payload, Email: payload, Phone: payload, RestaurantName: payload, City: payload, POS: payload, Comment: payload, ReviewComment: payload, Status: "APPROVED"},
				Requests: []ConnectionRequest{{ID: id, ContactName: payload, Email: payload, Phone: payload, RestaurantName: payload, City: payload, Status: payload}},
				Users:    []UserRow{{User: *user, Enabled: true}}, Application: application, Applications: []Integration{*application},
				Table: &Table{ID: id, Number: payload, Name: payload, URL: payload}, Tables: []Table{{ID: id, Number: payload, Name: payload}},
				Orders:   []Order{{ID: id, Number: payload, Status: payload, Total: "12.34", Items: []OrderItem{{Name: payload, Quantity: "1", UnitPrice: "12.34", Total: "12.34"}}}},
				Payments: []Payment{{ID: id, Status: payload, Amount: "12.34"}}, Emails: []MailRow{{ID: id, Subject: payload, Recipient: payload, Error: payload, Status: "FAILED"}},
			}
			for _, fragment := range []bool{false, true} {
				r := httptest.NewRequest("GET", "/", nil).WithContext(context.WithValue(context.Background(), userKey, user))
				if fragment {
					r.Header.Set("HX-Request", "true")
				}
				w := httptest.NewRecorder()
				a.render(w, r, name, p, 200)
				if w.Code != 200 {
					t.Fatalf("render %s: %d %s", name, w.Code, w.Body.String())
				}
				cases = append(cases, browserXSSCase{Name: name, HTML: w.Body.String()})
			}
		}
	}
	return cases
}

func TestSecurityHeadersCoverDocumentsFragmentsAssetsAndErrors(t *testing.T) {
	f := newFixture(t)
	for _, path := range []string{"/", "/connect", "/login", "/not-found", "/assets/app.js", "/actuator/health"} {
		for _, fragment := range []bool{false, true} {
			r, _ := http.NewRequest("GET", f.server.URL+path, nil)
			if fragment {
				r.Header.Set("HX-Request", "true")
			}
			response, err := f.client().Do(r)
			if err != nil {
				t.Fatal(err)
			}
			response.Body.Close()
			if response.Header.Get("Content-Security-Policy") != contentSecurityPolicy || response.Header.Get("X-Content-Type-Options") != "nosniff" {
				t.Fatalf("security headers missing on %s (fragment=%v)", path, fragment)
			}
		}
	}
	if strings.Contains(contentSecurityPolicy, "unsafe-") {
		t.Fatal("CSP must not permit inline scripts, handlers, eval or inline styles")
	}
}

func TestBrowserXSS(t *testing.T) {
	f := newFixture(t)
	f.app.Config.MockPayments = true
	const payload = `<img src=x onerror="globalThis.__xss=1">`
	owner := f.user("owner@example.test", "USER")
	f.user("admin@example.test", "ADMIN")
	f.sql(`UPDATE users SET name=$1 WHERE id=$2`, payload, owner)
	venue := f.venue(owner, payload)
	f.sql(`UPDATE restaurants SET description=$1,city=$1 WHERE id=$2`, payload, venue)
	order, token := f.order(venue, "12.34")
	table := f.scalar(`SELECT id::text FROM restaurant_tables WHERE qr_token=$1`, token)
	f.sql(`UPDATE restaurant_tables SET display_name=$1,table_number='5' WHERE id=$2`, payload, table)
	f.sql(`UPDATE restaurant_orders SET order_number=$1 WHERE id=$2`, payload, order)
	f.sql(`UPDATE order_items SET name=$1 WHERE order_id=$2`, payload, order)
	payment, freedom, iiko := NewID(), NewID(), NewID()
	f.sql(`INSERT INTO payments(id,order_id,restaurant_id,amount,status,provider) VALUES($1,$2,$3,12.34,'PENDING','FREEDOM_PAY')`, payment, order, venue)
	f.sql(`INSERT INTO freedom_pay_applications(id,restaurant_id,status,company_name,website_url,business_description,review_comment,partner_application_id,merchant_id) VALUES($1,$2,'NEEDS_CHANGES',$3::text,'javascript:globalThis.__xss=1',$3,$3,$3,$3)`, freedom, venue, payload)
	data, _ := json.Marshal(map[string]string{"contact_name": payload, "address": payload, "comment": `</textarea><svg/onload=globalThis.__xss=1>`, "server_url": "javascript:globalThis.__xss=1"})
	f.sql(`INSERT INTO iiko_applications(id,restaurant_id,status,data,review_comment,partner_reference) VALUES($1,$2,'NEEDS_CHANGES',$3,$4::text,$4)`, iiko, venue, data, payload)
	request := f.submitRequest(f.client(), "request@example.test", payload)
	f.sql(`UPDATE connection_requests SET contact_name=$1::text,city=$1,comment=$1,review_comment=$1 WHERE id=$2`, payload, request)
	f.sql(`INSERT INTO mail_outbox(id,recipient,subject,last_error,status) VALUES($1,'owner@example.test',$2::text,$2,'FAILED')`, NewID(), payload)
	input := map[string]any{
		"base": f.server.URL, "matrix": xssTemplateCases(t, f.app), "payload": payload,
		"venue": venue, "table": table, "publicURL": "/r/venue-" + venue + "/q/" + token,
		"payment": payment, "request": request, "freedom": freedom, "iiko": iiko,
	}
	raw, err := json.Marshal(input)
	if err != nil {
		t.Fatal(err)
	}
	script, err := filepath.Abs("../../tests/xss_browser.cjs")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	command := exec.CommandContext(ctx, "node", script)
	command.Stdin = bytes.NewReader(raw)
	command.Env = os.Environ()
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("browser XSS checks failed: %v\n%s", err, output)
	}
	t.Log(string(output))
}
