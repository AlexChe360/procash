package app

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5"
)

func (a *App) deleteRestaurant(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !ValidID(id) {
		a.notFound(w, r)
		return
	}
	var q rowQuerier = a.DB
	var tx pgx.Tx
	var err error
	query := `SELECT id,name FROM restaurants WHERE id=$1 AND deleted_at IS NULL`
	if r.Method == http.MethodPost {
		tx, err = a.DB.Begin(r.Context())
		if err != nil {
			a.fail(w, r, err)
			return
		}
		defer tx.Rollback(r.Context())
		q = tx
		query += ` FOR UPDATE`
	}
	v := &Restaurant{}
	err = q.QueryRow(r.Context(), query, id).Scan(&v.ID, &v.Name)
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	p := Page{Title: "Удалить заведение", Active: "restaurants", Restaurant: v}
	if r.Method != http.MethodPost {
		a.render(w, r, "deletion.html", p, 200)
		return
	}
	if form(r, "confirm") != "yes" {
		p.Error = "Подтвердите удаление заведения."
		a.render(w, r, "deletion.html", p, 422)
		return
	}
	_, err = tx.Exec(r.Context(), `UPDATE restaurants SET deleted_at=now(),active=false,updated_at=now() WHERE id=$1`, id)
	if err == nil {
		_, err = tx.Exec(r.Context(), `UPDATE restaurant_tables SET active=false,updated_at=now() WHERE restaurant_id=$1`, id)
	}
	if err == nil {
		err = audit(r.Context(), tx, CurrentUser(r).ID, "restaurant.delete", id)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.redirect(w, r, "/restaurants?deleted=1")
}

func (a *App) deleteUser(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("user")
	if !ValidID(id) {
		a.notFound(w, r)
		return
	}
	var q rowQuerier = a.DB
	var tx pgx.Tx
	var err error
	query := `SELECT u.email,u.name,u.role,(SELECT count(*) FROM restaurants WHERE owner_id=u.id AND deleted_at IS NULL) FROM users u WHERE u.id=$1 AND u.deleted_at IS NULL`
	if r.Method == http.MethodPost {
		tx, err = a.DB.Begin(r.Context())
		if err != nil {
			a.fail(w, r, err)
			return
		}
		defer tx.Rollback(r.Context())
		q = tx
		query += ` FOR UPDATE OF u`
	}
	var email, name, role string
	var venues int
	err = q.QueryRow(r.Context(), query, id).Scan(&email, &name, &role, &venues)
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if role == "ADMIN" || id == CurrentUser(r).ID {
		http.Error(w, "Удаление администратора через панель запрещено.", 403)
		return
	}
	p := Page{Title: "Удалить пользователя", Active: "users", Values: map[string]string{"user": id, "name": name, "email": email, "restaurant_count": strconv.Itoa(venues)}}
	if r.Method != http.MethodPost {
		a.render(w, r, "deletion.html", p, 200)
		return
	}
	if form(r, "confirm") != "yes" {
		p.Error = "Подтвердите удаление пользователя и его заведений."
		a.render(w, r, "deletion.html", p, 422)
		return
	}
	// Release the email for a fresh application without reconnecting it to old
	// sessions, venues or credentials. Foreign keys still preserve transaction history.
	tombstone := "deleted-" + id + "-" + RandomToken()[:12] + "@users.invalid"
	_, err = tx.Exec(r.Context(), `UPDATE users SET deleted_at=now(),enabled=false,email=$1,name='Удалённый пользователь',phone='',password_hash='',must_change_password=false,temporary_password_expires_at=NULL,updated_at=now() WHERE id=$2`, tombstone, id)
	if err == nil {
		_, err = tx.Exec(r.Context(), `DELETE FROM sessions WHERE user_id=$1`, id)
	}
	if err == nil {
		_, err = tx.Exec(r.Context(), `UPDATE restaurants SET deleted_at=now(),active=false,updated_at=now() WHERE owner_id=$1 AND deleted_at IS NULL`, id)
	}
	if err == nil {
		_, err = tx.Exec(r.Context(), `UPDATE restaurant_tables SET active=false,updated_at=now() WHERE restaurant_id IN (SELECT id FROM restaurants WHERE owner_id=$1)`, id)
	}
	if err == nil {
		_, err = tx.Exec(r.Context(), `UPDATE mail_outbox SET status='CANCELLED',payload=NULL,lease_until=NULL,last_error='' WHERE lower(recipient)=lower($1) AND subject IN ('Новый доступ к кабинету ProCash','Доступ к кабинету ProCash','Обновление заявки ProCash') AND status IN ('PENDING','SENDING','FAILED')`, email)
	}
	if err == nil {
		err = audit(r.Context(), tx, CurrentUser(r).ID, "user.delete", id)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.redirect(w, r, "/admin/users?deleted=1")
}
