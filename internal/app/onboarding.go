package app

import (
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type ConnectionRequest struct {
	ID, ContactName, Email, Phone, RestaurantName, City, POS, Comment, Status, ReviewComment, UserID, RestaurantID string
	CreatedAt                                                                                                      time.Time
}

const requestColumns = `id,contact_name,email,phone,restaurant_name,city,pos_system,comment,status,review_comment,COALESCE(user_id::text,''),COALESCE(restaurant_id::text,''),created_at`

func scanRequest(row pgx.Row) (v ConnectionRequest, err error) {
	err = row.Scan(&v.ID, &v.ContactName, &v.Email, &v.Phone, &v.RestaurantName, &v.City, &v.POS, &v.Comment, &v.Status, &v.ReviewComment, &v.UserID, &v.RestaurantID, &v.CreatedAt)
	return
}
func (a *App) connect(w http.ResponseWriter, r *http.Request) {
	p := Page{Title: "Подключить ресторан"}
	if r.Method == "GET" {
		if r.URL.Query().Get("sent") == "1" {
			p.Message = "Заявка принята. Команда ProCash свяжется с вами и после проверки предоставит доступ к кабинету."
		}
		if u := CurrentUser(r); u != nil {
			p.Values = map[string]string{"contact_name": u.Name, "email": u.Email, "phone": u.Phone}
		}
		a.render(w, r, "connect.html", p, 200)
		return
	}
	p.Values = formValues(r, "contact_name", "email", "phone", "restaurant_name", "city", "pos_system", "comment")
	p.Values["email"] = strings.ToLower(p.Values["email"])
	limit, err := a.limited(r, "connect:"+clientIP(r), 5, time.Hour)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if limit {
		p.Error = "Слишком много заявок. Попробуйте через час."
		a.render(w, r, "connect.html", p, 429)
		return
	}
	if form(r, "website") != "" {
		a.redirect(w, r, "/connect?sent=1")
		return
	}
	if !fieldsValid(p.Values, map[string]int{"contact_name": 255, "email": 255, "phone": 30, "restaurant_name": 150, "city": 100}) || !validEmail(p.Values["email"]) || len(p.Values["phone"]) < 10 || len(p.Values["pos_system"]) > 100 || len(p.Values["comment"]) > 3000 || r.FormValue("consent") != "yes" {
		p.Error = "Заполните контактные данные и название заведения, укажите корректный email и подтвердите согласие."
		a.render(w, r, "connect.html", p, 422)
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	id := NewID()
	_, err = tx.Exec(r.Context(), `INSERT INTO connection_requests(id,contact_name,email,phone,restaurant_name,city,pos_system,comment) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, id, p.Values["contact_name"], p.Values["email"], p.Values["phone"], p.Values["restaurant_name"], p.Values["city"], p.Values["pos_system"], p.Values["comment"])
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		a.redirect(w, r, "/connect?sent=1")
		return
	}
	body := fmt.Sprintf("Новая заявка на подключение ProCash\n\nЗаведение: %s\nГород: %s\nКонтакт: %s\nEmail: %s\nТелефон: %s\nPOS: %s\nКомментарий: %s\n\nОткрыть заявку: %s/admin/requests/%s", p.Values["restaurant_name"], p.Values["city"], p.Values["contact_name"], p.Values["email"], p.Values["phone"], p.Values["pos_system"], p.Values["comment"], a.Config.BaseURL, id)
	if err == nil {
		err = a.queueMail(r.Context(), tx, a.Config.NotifyEmail, "Новая заявка на подключение ProCash", body)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.redirect(w, r, "/connect?sent=1")
}
func (a *App) requests(w http.ResponseWriter, r *http.Request) {
	p := Page{Title: "Заявки на подключение", Active: "requests"}
	status := r.URL.Query().Get("status")
	if !contains([]string{"", "NEW", "IN_REVIEW", "APPROVED", "REJECTED"}, status) {
		status = ""
	}
	p.Values = map[string]string{"status": status}
	rows, err := a.DB.Query(r.Context(), `SELECT `+requestColumns+` FROM connection_requests WHERE ($1='' OR status=$1) ORDER BY created_at DESC LIMIT 200`, status)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		v, e := scanRequest(rows)
		if e != nil {
			a.fail(w, r, e)
			return
		}
		p.Requests = append(p.Requests, v)
	}
	if rows.Err() != nil {
		a.fail(w, r, rows.Err())
		return
	}
	a.render(w, r, "requests.html", p, 200)
}
func (a *App) request(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("request")
	if !ValidID(id) {
		a.notFound(w, r)
		return
	}
	v, err := scanRequest(a.DB.QueryRow(r.Context(), `SELECT `+requestColumns+` FROM connection_requests WHERE id=$1`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.render(w, r, "request.html", Page{Title: v.RestaurantName, Active: "requests", Request: &v}, 200)
}
func (a *App) reviewRequest(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("request")
	action := r.PathValue("action")
	if !ValidID(id) || !contains([]string{"approve", "review", "reject"}, action) {
		a.notFound(w, r)
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	v, err := scanRequest(tx.QueryRow(r.Context(), `SELECT `+requestColumns+` FROM connection_requests WHERE id=$1 FOR UPDATE`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	p := Page{Title: v.RestaurantName, Active: "requests", Request: &v, LoginURL: a.Config.BaseURL + "/login"}
	if v.Status == "APPROVED" || v.Status == "REJECTED" {
		p.Error = "Заявка уже обработана."
		a.render(w, r, "request.html", p, 409)
		return
	}
	comment := form(r, "review_comment")
	if len(comment) > 3000 || (action == "reject" && comment == "") {
		p.Error = "Укажите причину отказа (до 3000 символов)."
		a.render(w, r, "request.html", p, 422)
		return
	}
	if action == "approve" {
		// Serialize grants to the same email, including concurrent requests for different venues.
		if _, err = tx.Exec(r.Context(), `SELECT pg_advisory_xact_lock(hashtext($1))`, v.Email); err != nil {
			a.fail(w, r, err)
			return
		}
		var role string
		var enabled bool
		err = tx.QueryRow(r.Context(), `SELECT id,role,enabled FROM users WHERE lower(email)=lower($1) FOR UPDATE`, v.Email).Scan(&v.UserID, &role, &enabled)
		if errors.Is(err, pgx.ErrNoRows) {
			v.UserID = NewID()
			p.TemporaryPassword = RandomToken()[:24]
			var hash string
			hash, err = PasswordHash(p.TemporaryPassword)
			if err == nil {
				_, err = tx.Exec(r.Context(), `INSERT INTO users(id,email,name,phone,password_hash,role,enabled,must_change_password,temporary_password_expires_at,created_at,updated_at) VALUES($1,$2,$3,$4,$5,'USER',true,true,now()+interval '7 days',now(),now())`, v.UserID, v.Email, v.ContactName, v.Phone, hash)
			}
		} else if err == nil && (role == "ADMIN" || !enabled) {
			p.Error = "Нельзя выдать доступ через заявку для администратора или отключённого аккаунта."
			a.render(w, r, "request.html", p, 409)
			return
		}
		if err != nil {
			a.fail(w, r, err)
			return
		}
		v.RestaurantID = NewID()
		slug := "restaurant-" + strings.ReplaceAll(v.RestaurantID, "-", "")[:12]
		_, err = tx.Exec(r.Context(), `INSERT INTO restaurants(id,owner_id,name,slug,phone,city,status,active,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,'DRAFT',false,now(),now())`, v.RestaurantID, v.UserID, v.RestaurantName, slug, v.Phone, v.City)
		invitation := fmt.Sprintf("Здравствуйте, %s!\n\nДля заведения «%s» открыт кабинет ProCash.\nСсылка для входа: %s/login\nEmail: %s\n", v.ContactName, v.RestaurantName, a.Config.BaseURL, v.Email)
		if p.TemporaryPassword != "" {
			invitation += "Временный пароль: " + p.TemporaryPassword + "\nОн действует 7 дней. При первом входе обязательно установите собственный пароль.\n"
		} else {
			invitation += "Войдите с существующим паролем. Он не изменился.\n"
		}
		if err == nil {
			err = a.queueMail(r.Context(), tx, v.Email, "Доступ к кабинету ProCash", invitation)
		}
		v.Status = "APPROVED"
	} else if action == "review" {
		v.Status = "IN_REVIEW"
	} else {
		v.Status = "REJECTED"
	}
	if err == nil {
		_, err = tx.Exec(r.Context(), `UPDATE connection_requests SET status=$1,review_comment=$2,user_id=$3,restaurant_id=$4,reviewed_by=$5,updated_at=now() WHERE id=$6`, v.Status, comment, nullableID(v.UserID), nullableID(v.RestaurantID), CurrentUser(r).ID, id)
	}
	if err == nil {
		err = audit(r.Context(), tx, CurrentUser(r).ID, "connection."+action, id)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	p.Request = &v
	p.Message = "Заявка обновлена."
	if action == "approve" {
		p.Message = "Кабинет и заведение созданы. Письмо с доступом добавлено в очередь отправки."
	}
	a.render(w, r, "request.html", p, 200)
}
func contains(values []string, s string) bool {
	for _, v := range values {
		if v == s {
			return true
		}
	}
	return false
}
func nullableID(id string) any {
	if id == "" {
		return nil
	}
	return id
}
