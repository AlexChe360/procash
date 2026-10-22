package app

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/skip2/go-qrcode"
)

type Restaurant struct {
	ID, OwnerID, Name, Slug, Description, Phone, City, Status, FreedomStatus, IikoStatus string
	Active                                                                               bool
	Tables, Orders, PaidCount                                                            int
	Revenue                                                                              string
}
type Metrics struct {
	Venues, Active, Tables, Orders, PaidCount, NewRequests, Users, PendingMail int
	Revenue                                                                    string
}

const restaurantColumns = `r.id,r.owner_id,r.name,r.slug,COALESCE(r.description,''),COALESCE(r.phone,''),COALESCE(r.city,''),r.status,r.active,COALESCE((SELECT status FROM freedom_pay_applications f WHERE f.restaurant_id=r.id),'DRAFT'),COALESCE((SELECT status FROM iiko_applications i WHERE i.restaurant_id=r.id),'DRAFT'),(SELECT count(*) FROM restaurant_tables t WHERE t.restaurant_id=r.id)`

func scanRestaurant(row pgx.Row) (v Restaurant, err error) {
	err = row.Scan(&v.ID, &v.OwnerID, &v.Name, &v.Slug, &v.Description, &v.Phone, &v.City, &v.Status, &v.Active, &v.FreedomStatus, &v.IikoStatus, &v.Tables)
	return
}
func (a *App) ownedRestaurant(w http.ResponseWriter, r *http.Request) *Restaurant {
	id := r.PathValue("id")
	if !ValidID(id) {
		a.notFound(w, r)
		return nil
	}
	u := CurrentUser(r)
	v, err := scanRestaurant(a.DB.QueryRow(r.Context(), `SELECT `+restaurantColumns+` FROM restaurants r WHERE r.id=$1 AND ($2::boolean OR r.owner_id=$3)`, id, u.Admin(), u.ID))
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return nil
	}
	if err != nil {
		a.fail(w, r, err)
		return nil
	}
	return &v
}
func (a *App) loadMetrics(r *http.Request, p *Page) error {
	p.Days = 30
	if n, err := strconv.Atoi(r.URL.Query().Get("days")); err == nil && contains([]string{"7", "30", "90"}, strconv.Itoa(n)) {
		p.Days = n
	}
	u := CurrentUser(r)
	today := time.Now().In(almaty)
	start := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, almaty).AddDate(0, 0, -p.Days+1)
	err := a.DB.QueryRow(r.Context(), `WITH owned AS (SELECT id,active FROM restaurants WHERE ($1::boolean OR owner_id=$2)) SELECT (SELECT count(*) FROM owned),(SELECT count(*) FROM owned WHERE active),(SELECT count(*) FROM restaurant_tables WHERE restaurant_id IN (SELECT id FROM owned)),(SELECT count(*) FROM restaurant_orders WHERE restaurant_id IN (SELECT id FROM owned) AND opened_at>=$3 AND opened_at<=now()),(SELECT count(*) FROM payments WHERE restaurant_id IN (SELECT id FROM owned) AND status='PAID' AND paid_at>=$3 AND paid_at<=now()),COALESCE((SELECT sum(amount)::text FROM payments WHERE restaurant_id IN (SELECT id FROM owned) AND status='PAID' AND paid_at>=$3 AND paid_at<=now()),'0')`, u.Admin(), u.ID, start).Scan(&p.Metrics.Venues, &p.Metrics.Active, &p.Metrics.Tables, &p.Metrics.Orders, &p.Metrics.PaidCount, &p.Metrics.Revenue)
	if err != nil {
		return err
	}
	rows, err := a.DB.Query(r.Context(), `SELECT `+restaurantColumns+`,(SELECT count(*) FROM restaurant_orders o WHERE o.restaurant_id=r.id AND opened_at>=$3 AND opened_at<=now()),(SELECT count(*) FROM payments p WHERE p.restaurant_id=r.id AND p.status='PAID' AND p.paid_at>=$3 AND paid_at<=now()),COALESCE((SELECT sum(amount)::text FROM payments p WHERE p.restaurant_id=r.id AND p.status='PAID' AND p.paid_at>=$3 AND paid_at<=now()),'0') FROM restaurants r WHERE ($1::boolean OR r.owner_id=$2) ORDER BY r.created_at DESC LIMIT 200`, u.Admin(), u.ID, start)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var v Restaurant
		err = rows.Scan(&v.ID, &v.OwnerID, &v.Name, &v.Slug, &v.Description, &v.Phone, &v.City, &v.Status, &v.Active, &v.FreedomStatus, &v.IikoStatus, &v.Tables, &v.Orders, &v.PaidCount, &v.Revenue)
		if err != nil {
			return err
		}
		p.Restaurants = append(p.Restaurants, v)
	}
	return rows.Err()
}
func (a *App) dashboard(w http.ResponseWriter, r *http.Request) {
	p := Page{Title: "Обзор заведений", Active: "dashboard"}
	if err := a.loadMetrics(r, &p); err != nil {
		a.fail(w, r, err)
		return
	}
	a.render(w, r, "dashboard.html", p, 200)
}
func (a *App) adminDashboard(w http.ResponseWriter, r *http.Request) {
	p := Page{Title: "Панель ProCash", Active: "dashboard"}
	if err := a.loadMetrics(r, &p); err != nil {
		a.fail(w, r, err)
		return
	}
	err := a.DB.QueryRow(r.Context(), `SELECT (SELECT count(*) FROM connection_requests WHERE status IN ('NEW','IN_REVIEW')),(SELECT count(*) FROM users WHERE role='USER'),(SELECT count(*) FROM mail_outbox WHERE status<>'SENT')`).Scan(&p.Metrics.NewRequests, &p.Metrics.Users, &p.Metrics.PendingMail)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.render(w, r, "dashboard.html", p, 200)
}
func (a *App) restaurants(w http.ResponseWriter, r *http.Request) {
	p := Page{Title: "Заведения", Active: "restaurants"}
	if err := a.loadMetrics(r, &p); err != nil {
		a.fail(w, r, err)
		return
	}
	a.render(w, r, "restaurants.html", p, 200)
}
func (a *App) restaurant(w http.ResponseWriter, r *http.Request) {
	v := a.ownedRestaurant(w, r)
	if v == nil {
		return
	}
	p := Page{Title: v.Name, Active: "restaurants", Restaurant: v, Values: map[string]string{"name": v.Name, "description": v.Description, "phone": v.Phone, "city": v.City}}
	if r.Method == "POST" {
		p.Values = formValues(r, "name", "description", "phone", "city")
		if !fieldsValid(p.Values, map[string]int{"name": 150}) || len(p.Values["description"]) > 1000 || len(p.Values["phone"]) > 30 || len(p.Values["city"]) > 100 {
			p.Error = "Проверьте название, город и контактные данные."
			a.render(w, r, "restaurant.html", p, 422)
			return
		}
		_, err := a.DB.Exec(r.Context(), `UPDATE restaurants SET name=$1,description=$2,phone=$3,city=$4,updated_at=now() WHERE id=$5`, p.Values["name"], p.Values["description"], p.Values["phone"], p.Values["city"], v.ID)
		if err != nil {
			a.fail(w, r, err)
			return
		}
		a.redirect(w, r, "/restaurants/"+v.ID+"?saved=1")
		return
	}
	if r.URL.Query().Get("saved") == "1" {
		p.Message = "Данные заведения сохранены."
	}
	a.render(w, r, "restaurant.html", p, 200)
}

type Table struct {
	ID, RestaurantID, Number, Name, Token, URL string
	Active                                     bool
}

func scanTable(row pgx.Row) (t Table, err error) {
	err = row.Scan(&t.ID, &t.RestaurantID, &t.Number, &t.Name, &t.Token, &t.Active)
	return
}

const tableColumns = `id,restaurant_id,table_number,COALESCE(display_name,''),qr_token,active`

func (a *App) tables(w http.ResponseWriter, r *http.Request) {
	v := a.ownedRestaurant(w, r)
	if v == nil {
		return
	}
	p := Page{Title: "Столы и QR-коды", Active: "restaurants", Restaurant: v}
	if r.Method == "POST" {
		number := form(r, "table_number")
		name := form(r, "display_name")
		if number == "" || len(number) > 50 || len(name) > 150 {
			p.Error = "Укажите номер стола (до 50 символов) и название (до 150 символов)."
		} else {
			_, err := a.DB.Exec(r.Context(), `INSERT INTO restaurant_tables(id,restaurant_id,table_number,display_name,qr_token,active,created_at,updated_at) VALUES($1,$2,$3,$4,$5,true,now(),now())`, NewID(), v.ID, number, name, NewID())
			var pgErr *pgconn.PgError
			if errors.As(err, &pgErr) && pgErr.Code == "23505" {
				p.Error = "Стол с этим номером уже существует."
			} else if err != nil {
				a.fail(w, r, err)
				return
			} else {
				a.redirect(w, r, "/restaurants/"+v.ID+"/tables")
				return
			}
		}
	}
	rows, err := a.DB.Query(r.Context(), `SELECT `+tableColumns+` FROM restaurant_tables WHERE restaurant_id=$1 ORDER BY table_number LIMIT 500`, v.ID)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		t, err := scanTable(rows)
		if err != nil {
			a.fail(w, r, err)
			return
		}
		p.Tables = append(p.Tables, t)
	}
	if rows.Err() != nil {
		a.fail(w, r, rows.Err())
		return
	}
	code := 200
	if p.Error != "" {
		code = 422
	}
	a.render(w, r, "tables.html", p, code)
}
func (a *App) ownedTable(w http.ResponseWriter, r *http.Request, v *Restaurant) *Table {
	id := r.PathValue("table")
	if !ValidID(id) {
		a.notFound(w, r)
		return nil
	}
	t, err := scanTable(a.DB.QueryRow(r.Context(), `SELECT `+tableColumns+` FROM restaurant_tables WHERE id=$1 AND restaurant_id=$2`, id, v.ID))
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return nil
	}
	if err != nil {
		a.fail(w, r, err)
		return nil
	}
	t.URL = a.Config.BaseURL + "/r/" + v.Slug + "/q/" + t.Token
	return &t
}
func (a *App) table(w http.ResponseWriter, r *http.Request) {
	v := a.ownedRestaurant(w, r)
	if v == nil {
		return
	}
	t := a.ownedTable(w, r, v)
	if t == nil {
		return
	}
	a.render(w, r, "table.html", Page{Title: "Стол " + t.Number, Active: "restaurants", Restaurant: v, Table: t}, 200)
}
func (a *App) qr(w http.ResponseWriter, r *http.Request) {
	v := a.ownedRestaurant(w, r)
	if v == nil {
		return
	}
	t := a.ownedTable(w, r, v)
	if t == nil {
		return
	}
	size := 640
	if raw := r.URL.Query().Get("size"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 200 || n > 2000 {
			http.Error(w, "Размер QR-кода должен быть от 200 до 2000", 400)
			return
		}
		size = n
	}
	png, err := qrcode.Encode(t.URL, qrcode.Medium, size)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	w.Header().Set("Content-Type", "image/png")
	w.Header().Set("Content-Disposition", `attachment; filename="procash-table-`+t.ID+`.png"`)
	w.Write(png)
}

type Order struct {
	ID, Number, Status, Total string
	OpenedAt                  time.Time
	Items                     []OrderItem
}
type OrderItem struct{ Name, Quantity, UnitPrice, Total string }
type Payment struct {
	ID, OrderID, Status, Amount string
	CreatedAt                   time.Time
}

func (a *App) orders(w http.ResponseWriter, r *http.Request) {
	v := a.ownedRestaurant(w, r)
	if v == nil {
		return
	}
	p := Page{Title: "Заказы", Active: "restaurants", Restaurant: v}
	rows, err := a.DB.Query(r.Context(), `SELECT id,order_number,status,total_amount::text,opened_at FROM restaurant_orders WHERE restaurant_id=$1 ORDER BY opened_at DESC LIMIT 200`, v.ID)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		var o Order
		if err = rows.Scan(&o.ID, &o.Number, &o.Status, &o.Total, &o.OpenedAt); err != nil {
			a.fail(w, r, err)
			return
		}
		p.Orders = append(p.Orders, o)
	}
	if rows.Err() != nil {
		a.fail(w, r, rows.Err())
		return
	}
	a.render(w, r, "orders.html", p, 200)
}
func (a *App) payments(w http.ResponseWriter, r *http.Request) {
	v := a.ownedRestaurant(w, r)
	if v == nil {
		return
	}
	p := Page{Title: "Платежи", Active: "restaurants", Restaurant: v}
	rows, err := a.DB.Query(r.Context(), `SELECT id,order_id,status,amount::text,created_at FROM payments WHERE restaurant_id=$1 ORDER BY created_at DESC LIMIT 200`, v.ID)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		var o Payment
		if err = rows.Scan(&o.ID, &o.OrderID, &o.Status, &o.Amount, &o.CreatedAt); err != nil {
			a.fail(w, r, err)
			return
		}
		p.Payments = append(p.Payments, o)
	}
	if rows.Err() != nil {
		a.fail(w, r, rows.Err())
		return
	}
	a.render(w, r, "payments.html", p, 200)
}
