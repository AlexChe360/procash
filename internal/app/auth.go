package app

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
)

func CheckPassword(hash, password string) bool {
	if len(password) > 72 {
		return false
	}
	hash = strings.TrimPrefix(hash, "{bcrypt}")
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}
func PasswordHash(password string) (string, error) {
	b, e := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(b), e
}
func (a *App) login(w http.ResponseWriter, r *http.Request) {
	p := Page{Title: "Вход в кабинет"}
	if r.Method == "GET" {
		if u := CurrentUser(r); u != nil {
			a.redirect(w, r, "/dashboard")
			return
		}
		a.render(w, r, "login.html", p, 200)
		return
	}
	email := strings.ToLower(form(r, "email"))
	p.Values = map[string]string{"email": email}
	limit, err := a.limited(r, "login-ip:"+clientIP(r), 25, 15*time.Minute)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	keyed, e := a.limited(r, "login:"+email+":"+clientIP(r), 5, 15*time.Minute)
	if e != nil {
		a.fail(w, r, e)
		return
	}
	if limit || keyed {
		p.Error = "Слишком много попыток. Повторите через 15 минут."
		a.render(w, r, "login.html", p, 429)
		return
	}
	var u User
	var hash string
	var enabled, expired bool
	err = a.DB.QueryRow(r.Context(), `SELECT id,email,name,phone,role,must_change_password,password_hash,enabled,COALESCE(temporary_password_expires_at<=now(),false) FROM users WHERE lower(email)=$1`, email).Scan(&u.ID, &u.Email, &u.Name, &u.Phone, &u.Role, &u.MustChange, &hash, &enabled, &expired)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		a.fail(w, r, err)
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		hash = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy"
	}
	ok := CheckPassword(hash, r.FormValue("password"))
	if !ok || u.ID == "" || !enabled || expired {
		p.Error = "Неверный email или пароль. Если срок временного пароля истёк, обратитесь в ProCash."
		a.render(w, r, "login.html", p, 422)
		return
	}
	token := RandomToken()
	_, err = a.DB.Exec(r.Context(), `INSERT INTO sessions(token_hash,user_id,expires_at) VALUES($1,$2,now()+interval '12 hours')`, hashToken(token), u.ID)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.cookie(w, "session", token, 43200)
	if u.MustChange {
		a.redirect(w, r, "/account/password")
	} else if u.Admin() {
		a.redirect(w, r, "/admin")
	} else {
		a.redirect(w, r, "/dashboard")
	}
}
func (a *App) logout(w http.ResponseWriter, r *http.Request) {
	if c, e := r.Cookie(a.cookieName("session")); e == nil {
		if _, err := a.DB.Exec(r.Context(), `DELETE FROM sessions WHERE token_hash=$1`, hashToken(c.Value)); err != nil {
			a.fail(w, r, err)
			return
		}
	}
	a.cookie(w, "session", "", -1)
	a.cookie(w, "csrf", "", -1)
	a.redirect(w, r, "/login")
}
func (a *App) profile(w http.ResponseWriter, r *http.Request) {
	u := CurrentUser(r)
	p := Page{Title: "Мои данные", Active: "account", Values: map[string]string{"name": u.Name, "email": u.Email, "phone": u.Phone}}
	if r.URL.Query().Get("saved") == "1" {
		p.Message = "Данные сохранены."
	}
	if r.Method == "GET" {
		a.render(w, r, "profile.html", p, 200)
		return
	}
	p.Values = formValues(r, "name", "email", "phone")
	p.Values["email"] = strings.ToLower(p.Values["email"])
	if !fieldsValid(p.Values, map[string]int{"name": 255, "email": 255}) || !validEmail(p.Values["email"]) || len(p.Values["phone"]) > 30 {
		p.Error = "Укажите имя, корректный email и телефон до 30 символов."
		a.render(w, r, "profile.html", p, 422)
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var hash, currentEmail string
	err = tx.QueryRow(r.Context(), `SELECT password_hash,email FROM users WHERE id=$1 FOR UPDATE`, u.ID).Scan(&hash, &currentEmail)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	changed := !strings.EqualFold(currentEmail, p.Values["email"])
	if changed && !CheckPassword(hash, r.FormValue("current_password")) {
		p.Error = "Для изменения email укажите текущий пароль."
		a.render(w, r, "profile.html", p, 422)
		return
	}
	var exists bool
	err = tx.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM users WHERE lower(email)=$1 AND id<>$2)`, p.Values["email"], u.ID).Scan(&exists)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if exists {
		p.Error = "Этот email уже используется."
		a.render(w, r, "profile.html", p, 422)
		return
	}
	_, err = tx.Exec(r.Context(), `UPDATE users SET name=$1,email=$2,phone=$3,updated_at=now() WHERE id=$4`, p.Values["name"], p.Values["email"], p.Values["phone"], u.ID)
	if err == nil && changed {
		_, err = tx.Exec(r.Context(), `DELETE FROM sessions WHERE user_id=$1`, u.ID)
	}
	if err == nil {
		err = audit(r.Context(), tx, u.ID, "profile.updated", u.ID)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if changed {
		a.cookie(w, "session", "", -1)
		a.redirect(w, r, "/login?changed=1")
	} else {
		a.redirect(w, r, "/account?saved=1")
	}
}
func (a *App) password(w http.ResponseWriter, r *http.Request) {
	u := CurrentUser(r)
	p := Page{Title: "Изменить пароль", Active: "account"}
	if r.Method == "GET" {
		a.render(w, r, "password.html", p, 200)
		return
	}
	limited, err := a.limited(r, "password:"+u.ID, 5, 15*time.Minute)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if limited {
		p.Error = "Слишком много попыток. Повторите через 15 минут."
		a.render(w, r, "password.html", p, 429)
		return
	}
	next := r.FormValue("password")
	if len(next) < 12 || len(next) > 72 || next != r.FormValue("password_confirmation") || next == r.FormValue("current_password") {
		p.Error = "Новый пароль должен отличаться от текущего, содержать от 12 до 72 байт и совпадать с подтверждением."
		a.render(w, r, "password.html", p, 422)
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var hash string
	err = tx.QueryRow(r.Context(), `SELECT password_hash FROM users WHERE id=$1 FOR UPDATE`, u.ID).Scan(&hash)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if !CheckPassword(hash, r.FormValue("current_password")) {
		p.Error = "Текущий пароль указан неправильно."
		a.render(w, r, "password.html", p, 422)
		return
	}
	hash, err = PasswordHash(next)
	if err == nil {
		_, err = tx.Exec(r.Context(), `UPDATE users SET password_hash=$1,must_change_password=false,temporary_password_expires_at=NULL,updated_at=now() WHERE id=$2`, hash, u.ID)
	}
	if err == nil {
		_, err = tx.Exec(r.Context(), `DELETE FROM sessions WHERE user_id=$1`, u.ID)
	}
	token := RandomToken()
	if err == nil {
		_, err = tx.Exec(r.Context(), `INSERT INTO sessions(token_hash,user_id,expires_at) VALUES($1,$2,now()+interval '12 hours')`, hashToken(token), u.ID)
	}
	if err == nil {
		err = audit(r.Context(), tx, u.ID, "password.changed", u.ID)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.cookie(w, "session", token, 43200)
	if u.Admin() {
		a.redirect(w, r, "/admin?password=changed")
	} else {
		a.redirect(w, r, "/dashboard?password=changed")
	}
}
