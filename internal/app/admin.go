package app

import (
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
)

type UserRow struct {
	User
	Enabled   bool
	CreatedAt time.Time
}

func (a *App) users(w http.ResponseWriter, r *http.Request) {
	p := Page{Title: "Пользователи", Active: "users"}
	if r.URL.Query().Get("deleted") == "1" {
		p.Message = "Пользователь и его заведения удалены. Доступ к кабинету закрыт."
	}
	rows, err := a.DB.Query(r.Context(), `SELECT id,email,name,phone,role,must_change_password,enabled,created_at FROM users WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT 200`)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		var v UserRow
		if err = rows.Scan(&v.ID, &v.Email, &v.Name, &v.Phone, &v.Role, &v.MustChange, &v.Enabled, &v.CreatedAt); err != nil {
			a.fail(w, r, err)
			return
		}
		p.Users = append(p.Users, v)
	}
	if rows.Err() != nil {
		a.fail(w, r, rows.Err())
		return
	}
	a.render(w, r, "users.html", p, 200)
}
func (a *App) manageUser(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("user")
	action := r.PathValue("action")
	if !ValidID(id) || !contains([]string{"reset", "disable", "enable"}, action) {
		a.notFound(w, r)
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var email, role string
	err = tx.QueryRow(r.Context(), `SELECT email,role FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE`, id).Scan(&email, &role)
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if role == "ADMIN" {
		http.Error(w, "Управление доступом администратора выполняется через серверную CLI-команду.", 403)
		return
	}
	p := Page{Title: "Доступ пользователя", Active: "users", LoginURL: a.Config.BaseURL + "/login", Values: map[string]string{"email": email}}
	if action == "reset" {
		p.TemporaryPassword = RandomToken()[:24]
		var hash string
		hash, err = PasswordHash(p.TemporaryPassword)
		if err == nil {
			_, err = tx.Exec(r.Context(), `UPDATE users SET password_hash=$1,must_change_password=true,temporary_password_expires_at=now()+interval '7 days',enabled=true,updated_at=now() WHERE id=$2`, hash, id)
		}
		if err == nil {
			err = a.queueMail(r.Context(), tx, email, "Новый доступ к кабинету ProCash", fmt.Sprintf("Ссылка: %s/login\nEmail: %s\nВременный пароль: %s\nПароль действует 7 дней. При первом входе установите собственный пароль.", a.Config.BaseURL, email, p.TemporaryPassword))
		}
	} else {
		_, err = tx.Exec(r.Context(), `UPDATE users SET enabled=$1,updated_at=now() WHERE id=$2`, action == "enable", id)
	}
	if err == nil {
		_, err = tx.Exec(r.Context(), `DELETE FROM sessions WHERE user_id=$1`, id)
	}
	if err == nil {
		err = audit(r.Context(), tx, CurrentUser(r).ID, "user."+action, id)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if action == "reset" {
		a.render(w, r, "credentials.html", p, 200)
	} else {
		a.redirect(w, r, "/admin/users")
	}
}
