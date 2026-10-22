package app

import (
	"errors"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5"
)

func (a *App) publicTable(w http.ResponseWriter, r *http.Request) {
	token := r.PathValue("token")
	if !ValidID(token) {
		a.notFound(w, r)
		return
	}
	var v Restaurant
	var t Table
	err := a.DB.QueryRow(r.Context(), `SELECT t.id,t.table_number,r.id,r.name,r.slug FROM restaurant_tables t JOIN restaurants r ON r.id=t.restaurant_id WHERE t.qr_token=$1 AND t.active=true AND lower(r.slug)=lower($2)`, token, r.PathValue("slug")).Scan(&t.ID, &t.Number, &v.ID, &v.Name, &v.Slug)
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	p := Page{Title: v.Name, Restaurant: &v, Table: &t}
	if r.URL.Query().Get("payment") == "failed" {
		p.Error = "Тестовый платёж не выполнен."
	}
	var o Order
	err = a.DB.QueryRow(r.Context(), `SELECT id,order_number,status,total_amount::text,opened_at FROM restaurant_orders WHERE restaurant_table_id=$1 AND status='OPEN' ORDER BY opened_at DESC LIMIT 1`, t.ID).Scan(&o.ID, &o.Number, &o.Status, &o.Total, &o.OpenedAt)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		a.fail(w, r, err)
		return
	}
	if err == nil {
		rows, e := a.DB.Query(r.Context(), `SELECT name,quantity::text,unit_price::text,total_price::text FROM order_items WHERE order_id=$1 ORDER BY created_at`, o.ID)
		if e != nil {
			a.fail(w, r, e)
			return
		}
		for rows.Next() {
			var item OrderItem
			if e = rows.Scan(&item.Name, &item.Quantity, &item.UnitPrice, &item.Total); e != nil {
				rows.Close()
				a.fail(w, r, e)
				return
			}
			o.Items = append(o.Items, item)
		}
		e = rows.Err()
		rows.Close()
		if e != nil {
			a.fail(w, r, e)
			return
		}
		p.Orders = []Order{o}
	}
	p.Values = map[string]string{"mock_payments": "false"}
	if a.Config.MockPayments {
		p.Values["mock_payments"] = "true"
	}
	a.render(w, r, "public.html", p, 200)
}
func (a *App) createPayment(w http.ResponseWriter, r *http.Request) {
	if !a.Config.MockPayments {
		a.notFound(w, r)
		return
	}
	id := form(r, "order_id")
	if !ValidID(id) {
		http.Error(w, "Некорректный заказ", 422)
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var state string
	var payable bool
	err = tx.QueryRow(r.Context(), `SELECT status,total_amount>0 FROM restaurant_orders WHERE id=$1 FOR UPDATE`, id).Scan(&state, &payable)
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if state != "OPEN" || !payable {
		http.Error(w, "Заказ недоступен для оплаты", 409)
		return
	}
	var payment string
	err = tx.QueryRow(r.Context(), `SELECT id FROM payments WHERE order_id=$1 AND status IN ('CREATED','PENDING') ORDER BY created_at DESC LIMIT 1`, id).Scan(&payment)
	if errors.Is(err, pgx.ErrNoRows) {
		payment = NewID()
		_, err = tx.Exec(r.Context(), `INSERT INTO payments(id,order_id,restaurant_id,amount,status,provider,created_at,updated_at) SELECT $1,id,restaurant_id,total_amount,'PENDING','FREEDOM_PAY',now(),now() FROM restaurant_orders WHERE id=$2`, payment, id)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.redirect(w, r, "/payments/"+payment+"/mock")
}
func (a *App) paymentRecord(w http.ResponseWriter, r *http.Request) *Payment {
	id := r.PathValue("payment")
	if !ValidID(id) {
		a.notFound(w, r)
		return nil
	}
	var p Payment
	err := a.DB.QueryRow(r.Context(), `SELECT id,order_id,status,amount::text,created_at FROM payments WHERE id=$1`, id).Scan(&p.ID, &p.OrderID, &p.Status, &p.Amount, &p.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return nil
	}
	if err != nil {
		a.fail(w, r, err)
		return nil
	}
	return &p
}
func (a *App) mockPayment(w http.ResponseWriter, r *http.Request) {
	if !a.Config.MockPayments {
		a.notFound(w, r)
		return
	}
	p := a.paymentRecord(w, r)
	if p == nil {
		return
	}
	a.render(w, r, "mock.html", Page{Title: "Тестовая оплата", Payments: []Payment{*p}}, 200)
}
func (a *App) completePayment(w http.ResponseWriter, r *http.Request) {
	if !a.Config.MockPayments {
		a.notFound(w, r)
		return
	}
	p := a.paymentRecord(w, r)
	if p == nil {
		return
	}
	result := r.PathValue("result")
	if result != "success" && result != "fail" {
		a.notFound(w, r)
		return
	}
	next := "FAILED"
	if result == "success" {
		next = "PAID"
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var orderStatus, paymentStatus string
	err = tx.QueryRow(r.Context(), `SELECT status FROM restaurant_orders WHERE id=$1 FOR UPDATE`, p.OrderID).Scan(&orderStatus)
	if err == nil {
		err = tx.QueryRow(r.Context(), `SELECT status FROM payments WHERE id=$1 FOR UPDATE`, p.ID).Scan(&paymentStatus)
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if paymentStatus != next {
		if !contains([]string{"PENDING", "CREATED"}, paymentStatus) || orderStatus != "OPEN" {
			http.Error(w, "Платёж уже обработан", 409)
			return
		}
		_, err = tx.Exec(r.Context(), `UPDATE payments SET status=$1::text,paid_at=CASE WHEN $1::text='PAID' THEN now() ELSE NULL END,updated_at=now() WHERE id=$2`, next, p.ID)
		if err == nil && next == "PAID" {
			_, err = tx.Exec(r.Context(), `UPDATE restaurant_orders SET status='PAID',updated_at=now() WHERE id=$1`, p.OrderID)
		}
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.redirect(w, r, "/payments/"+p.ID+"/success")
}
func (a *App) paymentSuccess(w http.ResponseWriter, r *http.Request) {
	p := a.paymentRecord(w, r)
	if p == nil {
		return
	}
	if p.Status != "PAID" {
		http.Error(w, "Платёж не подтверждён", 409)
		return
	}
	a.render(w, r, "payment-success.html", Page{Title: "Платёж подтверждён", Payments: []Payment{*p}, Values: map[string]string{"mock": strings.ToLower(strconvBool(a.Config.MockPayments))}}, 200)
}
func strconvBool(v bool) string {
	if v {
		return "true"
	}
	return "false"
}
