package app

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestRestaurantDeletionPreservesHistoryAndClosesEveryEntryPoint(t *testing.T) {
	f := newFixture(t)
	f.app.Config.MockPayments = true
	owner := f.user("owner@example.com", "USER")
	f.user("admin@example.com", "ADMIN")
	admin, user := f.login("admin@example.com"), f.login("owner@example.com")
	venue := f.venue(owner, "Venue to remove")
	other := f.venue(owner, "Venue to keep")
	order, token := f.order(venue, "12.34")
	table := f.scalar(`SELECT id::text FROM restaurant_tables WHERE qr_token=$1`, token)
	payment, freedom, iiko := NewID(), NewID(), NewID()
	f.sql(`INSERT INTO payments(id,order_id,restaurant_id,amount,status,provider,paid_at) VALUES($1,$2,$3,12.34,'PAID','FREEDOM_PAY',now())`, payment, order, venue)
	f.sql(`INSERT INTO freedom_pay_applications(id,restaurant_id) VALUES($1,$2)`, freedom, venue)
	f.sql(`INSERT INTO iiko_applications(id,restaurant_id) VALUES($1,$2)`, iiko, venue)
	path := "/admin/restaurants/" + venue + "/delete"
	before := csrfState(f)
	for _, method := range []string{"GET", "HEAD"} {
		f.request(admin, method, path+"?confirm=yes", nil, 200)
	}
	f.request(user, "GET", path, nil, 403)
	f.request(user, "POST", path, url.Values{"confirm": {"yes"}}, 403)
	f.request(f.client(), "POST", path, url.Values{"confirm": {"yes"}}, 303)
	f.request(admin, "POST", path, url.Values{}, 422)
	f.request(admin, "POST", path+"?confirm=yes", url.Values{}, 422)
	if csrfState(f) != before {
		t.Fatal("preview, missing confirmation or forbidden deletion changed data")
	}
	_, response := f.request(admin, "POST", path, url.Values{"confirm": {"yes"}}, 303)
	if response.Header.Get("Location") != "/restaurants?deleted=1" {
		t.Fatal("deletion did not return to the restaurant list")
	}
	if f.scalar(`SELECT count(*)::text FROM restaurant_orders WHERE id=$1`, order) != "1" || f.scalar(`SELECT amount::text||':'||status FROM payments WHERE id=$1`, payment) != "12.34:PAID" || f.scalar(`SELECT count(*)::text FROM order_items WHERE order_id=$1`, order) != "1" {
		t.Fatal("deletion lost order or payment history")
	}
	for _, list := range []string{"/admin", "/dashboard", "/restaurants", "/admin/freedom-pay/applications", "/admin/iiko/applications"} {
		body, _ := f.request(admin, "GET", list, nil, 200)
		if strings.Contains(body, "Venue to remove") {
			t.Fatalf("deleted venue still appears at %s", list)
		}
	}
	f.request(user, "GET", "/restaurants/"+other, nil, 200)
	f.request(user, "GET", "/account", nil, 200)
	var p Page
	r, _ := http.NewRequest("GET", "/admin", nil)
	r = r.WithContext(context.WithValue(r.Context(), userKey, &User{ID: owner, Role: "ADMIN"}))
	if err := f.app.loadMetrics(r, &p); err != nil || p.Metrics.Venues != 1 || p.Metrics.Tables != 0 || p.Metrics.PaidCount != 0 || p.Metrics.Revenue != "0" {
		t.Fatalf("deleted venue contributes to metrics: %+v, %v", p.Metrics, err)
	}
	for _, url := range []string{
		"/restaurants/" + venue, "/restaurants/" + venue + "/tables", "/restaurants/" + venue + "/tables/" + table + "/qr.png",
		"/restaurants/" + venue + "/orders", "/restaurants/" + venue + "/payments", "/restaurants/" + venue + "/payments/freedom-pay", "/restaurants/" + venue + "/integrations/iiko",
		"/r/venue-" + venue + "/q/" + token, "/api/v1/orders/current?restaurantId=" + venue + "&tableNumber=5",
		"/admin/freedom-pay/applications/" + freedom, "/admin/iiko/applications/" + iiko,
		"/payments/" + payment + "/mock", "/payments/" + payment + "/success", path,
	} {
		f.request(admin, "GET", url, nil, 404)
	}
	f.request(admin, "POST", "/payments/create", url.Values{"order_id": {order}}, 404)
	f.request(admin, "POST", "/payments/"+payment+"/mock/success", url.Values{}, 404)
	f.request(admin, "POST", "/admin/iiko/applications/"+iiko+"/approve", url.Values{}, 404)
	f.request(admin, "POST", path, url.Values{"confirm": {"yes"}}, 404)
	if f.scalar(`SELECT count(*)::text FROM audit_events WHERE action='restaurant.delete' AND entity_id=$1`, venue) != "1" {
		t.Fatal("deletion must have one audit event")
	}
}

func TestUserDeletionRevokesAccessAndAllowsFreshOnboarding(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	adminID := f.user("admin@example.com", "ADMIN")
	otherAdmin := f.user("other-admin@example.com", "ADMIN")
	otherOwner := f.user("unrelated@example.com", "USER")
	first := f.venue(owner, "First deleted venue")
	second := f.venue(owner, "Second deleted venue")
	kept := f.venue(otherOwner, "Unrelated venue")
	_, token := f.order(first, "12.34")
	user, admin := f.login("owner@example.com"), f.login("admin@example.com")
	f.login("owner@example.com")
	mail := NewID()
	payload, err := f.app.encrypt("Old temporary password")
	if err != nil {
		t.Fatal(err)
	}
	f.sql(`INSERT INTO mail_outbox(id,recipient,subject,payload) VALUES($1,'owner@example.com','Доступ к кабинету ProCash',$2)`, mail, payload)
	path := "/admin/users/" + owner + "/delete"
	before := csrfState(f)
	for _, method := range []string{"GET", "HEAD"} {
		f.request(admin, method, path+"?confirm=yes", nil, 200)
	}
	f.request(user, "GET", path, nil, 403)
	f.request(user, "POST", path, url.Values{"confirm": {"yes"}}, 403)
	for _, id := range []string{adminID, otherAdmin} {
		f.request(admin, "GET", "/admin/users/"+id+"/delete", nil, 403)
		f.request(admin, "POST", "/admin/users/"+id+"/delete", url.Values{"confirm": {"yes"}, "role": {"USER"}}, 403)
	}
	f.request(admin, "POST", path, url.Values{}, 422)
	f.request(admin, "POST", path+"?confirm=yes", url.Values{}, 422)
	if csrfState(f) != before {
		t.Fatal("unconfirmed or forbidden user deletion changed data")
	}
	f.request(admin, "POST", path, url.Values{"confirm": {"yes"}}, 303)
	if f.scalar(`SELECT count(*)::text FROM sessions WHERE user_id=$1`, owner) != "0" || f.scalar(`SELECT count(*)::text FROM restaurants WHERE owner_id=$1 AND deleted_at IS NULL`, owner) != "0" {
		t.Fatal("deleted user's sessions or venues remain active")
	}
	f.request(user, "GET", "/dashboard", nil, 303)
	f.request(f.client(), "POST", "/login", url.Values{"email": {"owner@example.com"}, "password": {"fixture-password"}}, 422)
	for _, action := range []string{"reset", "enable", "disable", "delete"} {
		f.request(admin, "POST", "/admin/users/"+owner+"/"+action, url.Values{"confirm": {"yes"}}, 404)
	}
	for _, venue := range []string{first, second} {
		f.request(admin, "GET", "/restaurants/"+venue, nil, 404)
	}
	f.request(f.client(), "GET", "/r/venue-"+first+"/q/"+token, nil, 404)
	f.request(admin, "GET", "/restaurants/"+kept, nil, 200)
	body, _ := f.request(admin, "GET", "/admin/users?deleted=1", nil, 200)
	if strings.Contains(body, "owner@example.com") || !strings.Contains(body, "unrelated@example.com") {
		t.Fatal("user list did not remove only the requested account")
	}
	f.request(admin, "POST", "/admin/mail/"+mail+"/retry", url.Values{}, 303)
	if f.scalar(`SELECT status||':'||(payload IS NULL)::text FROM mail_outbox WHERE id=$1`, mail) != "CANCELLED:true" {
		t.Fatal("deleted account's old credentials can still be sent")
	}
	request := f.submitRequest(f.client(), "owner@example.com", "New application")
	body, _ = f.request(admin, "POST", "/admin/requests/"+request+"/approve", url.Values{}, 200)
	newUser := f.scalar(`SELECT id::text FROM users WHERE email='owner@example.com'`)
	if newUser == owner || !strings.Contains(body, `id="temporary-password"`) || f.scalar(`SELECT count(*)::text FROM restaurants WHERE owner_id=$1 AND deleted_at IS NULL`, newUser) != "1" {
		t.Fatal("fresh onboarding reused the deleted account or failed to issue credentials")
	}
	if f.scalar(`SELECT count(*)::text FROM restaurants WHERE owner_id=$1 AND deleted_at IS NULL`, owner) != "0" || f.scalar(`SELECT count(*)::text FROM audit_events WHERE action='user.delete' AND entity_id=$1`, owner) != "1" {
		t.Fatal("onboarding restored old venues or lost the deletion audit")
	}
}

func TestDeletionRollsBackAllChangesOnFailure(t *testing.T) {
	for _, kind := range []string{"users", "restaurants"} {
		t.Run(kind, func(t *testing.T) {
			f := newFixture(t)
			owner := f.user("owner@example.com", "USER")
			f.user("admin@example.com", "ADMIN")
			venue := f.venue(owner, "Keep on failure")
			f.order(venue, "12.34")
			f.login("owner@example.com")
			admin := f.login("admin@example.com")
			f.sql(`ALTER TABLE audit_events ADD CONSTRAINT reject_deletion CHECK (action NOT IN ('user.delete','restaurant.delete'))`)
			before := csrfState(f)
			id := owner
			if kind == "restaurants" {
				id = venue
			}
			f.request(admin, "POST", "/admin/"+kind+"/"+id+"/delete", url.Values{"confirm": {"yes"}}, 500)
			if csrfState(f) != before {
				t.Fatal("failed deletion left partial changes")
			}
		})
	}
}

type blockedDeletionMailer struct{ started, release chan struct{} }

func (m blockedDeletionMailer) Send(ctx context.Context, _ Message) error {
	close(m.started)
	select {
	case <-m.release:
		return errors.New("fixture SMTP failure after deletion")
	case <-ctx.Done():
		return ctx.Err()
	}
}

func TestDeletedUserMailCannotReturnToTheQueue(t *testing.T) {
	f := newFixture(t)
	owner := f.user("owner@example.com", "USER")
	f.user("admin@example.com", "ADMIN")
	admin := f.login("admin@example.com")
	payload, err := f.app.encrypt("Old password")
	if err != nil {
		t.Fatal(err)
	}
	mail := NewID()
	f.sql(`INSERT INTO mail_outbox(id,recipient,subject,payload) VALUES($1,'owner@example.com','Доступ к кабинету ProCash',$2)`, mail, payload)
	m := blockedDeletionMailer{started: make(chan struct{}), release: make(chan struct{})}
	f.app.Mailer = m
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	done := make(chan error, 1)
	go func() { _, err := f.app.DeliverOne(ctx); done <- err }()
	select {
	case <-m.started:
	case <-ctx.Done():
		t.Fatal("worker did not claim the message")
	}
	f.request(admin, "POST", "/admin/users/"+owner+"/delete", url.Values{"confirm": {"yes"}}, 303)
	close(m.release)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if f.scalar(`SELECT status||':'||(payload IS NULL)::text FROM mail_outbox WHERE id=$1`, mail) != "CANCELLED:true" {
		t.Fatal("worker resurrected cancelled credentials after a failed send")
	}
}
