package app

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
)

type Field struct {
	Name, Label, Type, Pattern, Value string
	Max                               int
	Required                          bool
}
type Integration struct {
	ID, Kind, RestaurantID, RestaurantName, OwnerEmail, Status, Step, ReviewComment, Reference, MerchantID string
	Values                                                                                                 map[string]string
	Editable, Complete                                                                                     bool
}
type rowQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

var freedomSteps = []string{"company", "director", "address", "bank", "restaurant", "review"}

func f(name, label, kind string, max int) Field {
	return Field{Name: name, Label: label, Type: kind, Max: max, Required: true}
}
func freedomFields(step string) []Field {
	switch step {
	case "company":
		return []Field{f("organization_type", "Форма организации (ИП / ТОО)", "text", 50), f("company_name", "Наименование компании", "text", 255), {Name: "bin", Label: "БИН / ИИН", Type: "text", Pattern: "[0-9]{12}", Max: 12, Required: true}}
	case "director":
		return []Field{f("director_name", "ФИО руководителя", "text", 255), f("director_iin", "ИИН руководителя", "text", 12), f("director_phone", "Телефон руководителя", "tel", 30), f("director_email", "Email руководителя", "email", 255)}
	case "address":
		return []Field{f("legal_address", "Юридический адрес", "text", 500), f("city", "Город", "text", 100), f("postal_code", "Почтовый индекс", "text", 6)}
	case "bank":
		return []Field{f("iban", "IBAN (KZ…)", "text", 20), f("bank_name", "Название банка", "text", 255), f("bank_bic", "БИК", "text", 11)}
	case "restaurant":
		return []Field{f("website_url", "Сайт ресторана", "url", 500), f("business_category", "Категория бизнеса", "text", 150), f("business_description", "Описание деятельности", "textarea", 1500), f("average_check", "Средний чек, ₸", "text", 20), f("expected_monthly_turnover", "Ожидаемый месячный оборот, ₸", "text", 20)}
	}
	return nil
}
func allFreedomFields() []Field {
	var out []Field
	for _, step := range freedomSteps {
		out = append(out, freedomFields(step)...)
	}
	return out
}

var iikoFields = []Field{f("contact_name", "Контактное лицо", "text", 255), f("contact_email", "Контактный email", "email", 255), f("contact_phone", "Контактный телефон", "tel", 30), f("address", "Адрес заведения", "text", 500), f("pos_type", "Версия подключения: iikoCloud / iikoServer / не знаю", "text", 100), {Name: "software_version", Label: "Версия iiko (если известна)", Type: "text", Max: 100}, {Name: "server_url", Label: "Адрес iikoServer (если известен)", Type: "url", Max: 500}, {Name: "comment", Label: "Комментарий и удобное время для связи", Type: "textarea", Max: 3000}}

func validFields(values map[string]string, fields []Field) string {
	for _, field := range fields {
		v := values[field.Name]
		if (field.Required && v == "") || len([]rune(v)) > field.Max {
			return "Проверьте поле «" + field.Label + "»."
		}
		if v == "" {
			continue
		}
		if field.Type == "email" && !validEmail(v) {
			return "Укажите корректный email."
		}
		if field.Type == "url" {
			u, err := url.Parse(v)
			if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
				return "Укажите полный адрес сайта с https:// или http://."
			}
		}
		pattern := ""
		switch field.Name {
		case "bin", "director_iin":
			pattern = `^[0-9]{12}$`
		case "postal_code":
			pattern = `^[0-9]{6}$`
		case "iban":
			pattern = `^KZ[0-9]{2}[A-Z0-9]{16}$`
		case "bank_bic":
			pattern = `^[A-Z0-9]{8,11}$`
		case "director_phone", "contact_phone":
			pattern = `^\+?[0-9 ()-]{10,25}$`
		case "average_check", "expected_monthly_turnover":
			pattern = `^[0-9]{1,17}(\.[0-9]{1,2})?$`
			n, ok := new(big.Rat).SetString(v)
			if !ok || n.Cmp(big.NewRat(1, 1)) < 0 {
				return "Суммы должны быть не меньше 1 ₸."
			}
		case "business_description":
			if len([]rune(v)) < 20 {
				return "Добавьте описание деятельности (не менее 20 символов)."
			}
		}
		if pattern != "" && !regexp.MustCompile(pattern).MatchString(v) {
			return "Проверьте формат поля «" + field.Label + "»."
		}
	}
	return ""
}
func readFields(r *http.Request, fields []Field) map[string]string {
	m := map[string]string{}
	for _, f := range fields {
		m[f.Name] = form(r, f.Name)
	}
	return m
}
func decodeValues(data []byte) map[string]string {
	var raw map[string]any
	dec := json.NewDecoder(strings.NewReader(string(data)))
	dec.UseNumber()
	_ = dec.Decode(&raw)
	values := map[string]string{}
	for k, v := range raw {
		if v != nil {
			values[k] = fmt.Sprint(v)
		}
	}
	return values
}
func loadFreedom(ctx context.Context, q rowQuerier, id string) (Integration, error) {
	var v Integration
	var data []byte
	err := q.QueryRow(ctx, `SELECT f.id,f.restaurant_id,f.status,lower(f.current_step),COALESCE(f.review_comment,''),COALESCE(f.partner_application_id,''),COALESCE(f.merchant_id,''),to_jsonb(f),r.name,u.email FROM freedom_pay_applications f JOIN restaurants r ON r.id=f.restaurant_id JOIN users u ON u.id=r.owner_id WHERE f.restaurant_id=$1`, id).Scan(&v.ID, &v.RestaurantID, &v.Status, &v.Step, &v.ReviewComment, &v.Reference, &v.MerchantID, &data, &v.RestaurantName, &v.OwnerEmail)
	v.Kind = "freedom-pay"
	v.Values = decodeValues(data)
	v.Editable = contains([]string{"DRAFT", "NEEDS_CHANGES"}, v.Status)
	v.Complete = validFields(v.Values, allFreedomFields()) == ""
	return v, err
}
func lockRestaurant(ctx context.Context, tx pgx.Tx, id string) error {
	var actual string
	return tx.QueryRow(ctx, `SELECT id FROM restaurants WHERE id=$1 FOR UPDATE`, id).Scan(&actual)
}
func (a *App) freedom(w http.ResponseWriter, r *http.Request) {
	v := a.ownedRestaurant(w, r)
	if v == nil {
		return
	}
	step := r.PathValue("step")
	if step == "" {
		step = "company"
	}
	if !contains(freedomSteps, step) {
		a.notFound(w, r)
		return
	}
	application, err := loadFreedom(r.Context(), a.DB, v.ID)
	if errors.Is(err, pgx.ErrNoRows) {
		application = Integration{RestaurantID: v.ID, Kind: "freedom-pay", Status: "DRAFT", Values: map[string]string{}, Editable: true}
	} else if err != nil {
		a.fail(w, r, err)
		return
	}
	p := Page{Title: "Подключение Freedom Pay", Active: "restaurants", Restaurant: v, Application: &application, Fields: freedomFields(step), Values: application.Values}
	p.Application.Step = step
	if step == "review" {
		p.Fields = allFreedomFields()
	}
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		a.render(w, r, "freedom.html", p, 200)
		return
	}
	if step == "review" {
		http.Error(w, "Метод недоступен", 405)
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	if err = lockRestaurant(r.Context(), tx, v.ID); err != nil {
		a.fail(w, r, err)
		return
	}
	if _, err = tx.Exec(r.Context(), `INSERT INTO freedom_pay_applications(id,restaurant_id,status,current_step,created_at,updated_at) VALUES($1,$2,'DRAFT','COMPANY',now(),now()) ON CONFLICT(restaurant_id) DO NOTHING`, NewID(), v.ID); err != nil {
		a.fail(w, r, err)
		return
	}
	locked, err := loadFreedom(r.Context(), tx, v.ID)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if !locked.Editable {
		p.Error = "Заявка уже отправлена. Изменения недоступны."
		a.render(w, r, "freedom.html", p, 409)
		return
	}
	p.Values = readFields(r, p.Fields)
	if p.Error = validFields(p.Values, p.Fields); p.Error != "" {
		a.render(w, r, "freedom.html", p, 422)
		return
	}
	sets := []string{"updated_at=now()"}
	args := []any{}
	for _, field := range p.Fields {
		args = append(args, p.Values[field.Name])
		sets = append(sets, field.Name+"=$"+strconv.Itoa(len(args)))
	}
	args = append(args, strings.ToUpper(step))
	sets = append(sets, "current_step=$"+strconv.Itoa(len(args)))
	args = append(args, v.ID)
	_, err = tx.Exec(r.Context(), `UPDATE freedom_pay_applications SET `+strings.Join(sets, ",")+` WHERE restaurant_id=$`+strconv.Itoa(len(args)), args...)
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	next := "review"
	for i, s := range freedomSteps {
		if s == step && i+1 < len(freedomSteps) {
			next = freedomSteps[i+1]
		}
	}
	a.redirect(w, r, "/restaurants/"+v.ID+"/payments/freedom-pay/"+next)
}
func (a *App) freedomSubmit(w http.ResponseWriter, r *http.Request) {
	v := a.ownedRestaurant(w, r)
	if v == nil {
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	if err = lockRestaurant(r.Context(), tx, v.ID); err != nil {
		a.fail(w, r, err)
		return
	}
	app, err := loadFreedom(r.Context(), tx, v.ID)
	if errors.Is(err, pgx.ErrNoRows) {
		app = Integration{RestaurantID: v.ID, Kind: "freedom-pay", Status: "DRAFT", Values: map[string]string{}, Editable: true}
	} else if err != nil {
		a.fail(w, r, err)
		return
	}
	app.Step = "review"
	p := Page{Title: "Подключение Freedom Pay", Active: "restaurants", Restaurant: v, Application: &app, Values: app.Values, Fields: allFreedomFields()}
	if !app.Editable || !app.Complete {
		p.Error = "Заполните все шаги. Отправка доступна для черновика или заявки на исправление."
		a.render(w, r, "freedom.html", p, 422)
		return
	}
	_, err = tx.Exec(r.Context(), `UPDATE freedom_pay_applications SET status='READY_FOR_REVIEW',current_step='REVIEW',review_comment=NULL,updated_at=now() WHERE id=$1`, app.ID)
	if err == nil {
		err = a.queueMail(r.Context(), tx, a.Config.NotifyEmail, "Заявка на подключение Freedom Pay", fmt.Sprintf("Заведение: %s\nПроверить заявку: %s/admin/freedom-pay/applications/%s", v.Name, a.Config.BaseURL, app.ID))
	}
	if err == nil {
		err = audit(r.Context(), tx, CurrentUser(r).ID, "freedom.submitted", app.ID)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.redirect(w, r, "/restaurants/"+v.ID+"/payments/freedom-pay/review")
}
func loadIiko(ctx context.Context, q rowQuerier, id string) (Integration, error) {
	var v Integration
	var data []byte
	err := q.QueryRow(ctx, `SELECT i.id,i.restaurant_id,i.status,i.data,i.review_comment,i.partner_reference,r.name,u.email FROM iiko_applications i JOIN restaurants r ON r.id=i.restaurant_id JOIN users u ON u.id=r.owner_id WHERE i.restaurant_id=$1`, id).Scan(&v.ID, &v.RestaurantID, &v.Status, &data, &v.ReviewComment, &v.Reference, &v.RestaurantName, &v.OwnerEmail)
	v.Kind = "iiko"
	v.Values = decodeValues(data)
	v.Editable = contains([]string{"DRAFT", "NEEDS_CHANGES"}, v.Status)
	v.Complete = validFields(v.Values, iikoFields) == ""
	return v, err
}
func (a *App) iiko(w http.ResponseWriter, r *http.Request) {
	v := a.ownedRestaurant(w, r)
	if v == nil {
		return
	}
	app, err := loadIiko(r.Context(), a.DB, v.ID)
	if errors.Is(err, pgx.ErrNoRows) {
		app = Integration{RestaurantID: v.ID, Kind: "iiko", Status: "DRAFT", Values: map[string]string{}, Editable: true}
	} else if err != nil {
		a.fail(w, r, err)
		return
	}
	p := Page{Title: "Подключение iiko", Active: "restaurants", Restaurant: v, Application: &app, Fields: iikoFields, Values: app.Values}
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		a.render(w, r, "iiko.html", p, 200)
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	if err = lockRestaurant(r.Context(), tx, v.ID); err != nil {
		a.fail(w, r, err)
		return
	}
	if _, err = tx.Exec(r.Context(), `INSERT INTO iiko_applications(id,restaurant_id) VALUES($1,$2) ON CONFLICT(restaurant_id) DO NOTHING`, NewID(), v.ID); err != nil {
		a.fail(w, r, err)
		return
	}
	locked, err := loadIiko(r.Context(), tx, v.ID)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	if !locked.Editable {
		p.Error = "Заявка уже в работе, изменения недоступны."
		a.render(w, r, "iiko.html", p, 409)
		return
	}
	p.Values = readFields(r, iikoFields)
	if p.Error = validFields(p.Values, iikoFields); p.Error != "" {
		a.render(w, r, "iiko.html", p, 422)
		return
	}
	data, _ := json.Marshal(p.Values)
	_, err = tx.Exec(r.Context(), `UPDATE iiko_applications SET data=$1,updated_at=now() WHERE id=$2`, data, locked.ID)
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.redirect(w, r, "/restaurants/"+v.ID+"/integrations/iiko?saved=1")
}
func (a *App) iikoSubmit(w http.ResponseWriter, r *http.Request) {
	v := a.ownedRestaurant(w, r)
	if v == nil {
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	if err = lockRestaurant(r.Context(), tx, v.ID); err != nil {
		a.fail(w, r, err)
		return
	}
	app, err := loadIiko(r.Context(), tx, v.ID)
	if errors.Is(err, pgx.ErrNoRows) {
		app = Integration{RestaurantID: v.ID, Kind: "iiko", Status: "DRAFT", Values: map[string]string{}, Editable: true}
	} else if err != nil {
		a.fail(w, r, err)
		return
	}
	if !app.Editable || !app.Complete {
		a.render(w, r, "iiko.html", Page{Title: "Подключение iiko", Restaurant: v, Application: &app, Fields: iikoFields, Values: app.Values, Error: "Заполните и сохраните анкету перед отправкой."}, 422)
		return
	}
	_, err = tx.Exec(r.Context(), `UPDATE iiko_applications SET status='READY_FOR_REVIEW',review_comment='',updated_at=now() WHERE id=$1`, app.ID)
	if err == nil {
		err = a.queueMail(r.Context(), tx, a.Config.NotifyEmail, "Заявка на подключение iiko", fmt.Sprintf("Заведение: %s\nПроверить заявку: %s/admin/iiko/applications/%s", v.Name, a.Config.BaseURL, app.ID))
	}
	if err == nil {
		err = audit(r.Context(), tx, CurrentUser(r).ID, "iiko.submitted", app.ID)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.redirect(w, r, "/restaurants/"+v.ID+"/integrations/iiko")
}
func (a *App) adminIntegrations(w http.ResponseWriter, r *http.Request) {
	kind := "freedom-pay"
	table := "freedom_pay_applications"
	title := "Заявки Freedom Pay"
	if strings.Contains(r.URL.Path, "/iiko/") {
		kind = "iiko"
		table = "iiko_applications"
		title = "Заявки iiko"
	}
	p := Page{Title: title, Active: kind}
	rows, err := a.DB.Query(r.Context(), `SELECT i.id,i.restaurant_id,r.name,u.email,i.status FROM `+table+` i JOIN restaurants r ON r.id=i.restaurant_id JOIN users u ON u.id=r.owner_id ORDER BY i.updated_at DESC LIMIT 200`)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		v := Integration{Kind: kind}
		if err = rows.Scan(&v.ID, &v.RestaurantID, &v.RestaurantName, &v.OwnerEmail, &v.Status); err != nil {
			a.fail(w, r, err)
			return
		}
		p.Applications = append(p.Applications, v)
	}
	if rows.Err() != nil {
		a.fail(w, r, rows.Err())
		return
	}
	a.render(w, r, "applications.html", p, 200)
}
func (a *App) findIntegration(w http.ResponseWriter, r *http.Request, kind string) *Integration {
	id := r.PathValue("application")
	if !ValidID(id) {
		a.notFound(w, r)
		return nil
	}
	table := "freedom_pay_applications"
	if kind == "iiko" {
		table = "iiko_applications"
	}
	var restaurant string
	err := a.DB.QueryRow(r.Context(), `SELECT restaurant_id FROM `+table+` WHERE id=$1`, id).Scan(&restaurant)
	if errors.Is(err, pgx.ErrNoRows) {
		a.notFound(w, r)
		return nil
	}
	if err != nil {
		a.fail(w, r, err)
		return nil
	}
	var v Integration
	if kind == "iiko" {
		v, err = loadIiko(r.Context(), a.DB, restaurant)
	} else {
		v, err = loadFreedom(r.Context(), a.DB, restaurant)
	}
	if err != nil {
		a.fail(w, r, err)
		return nil
	}
	return &v
}
func (a *App) adminFreedom(w http.ResponseWriter, r *http.Request) {
	if v := a.findIntegration(w, r, "freedom-pay"); v != nil {
		a.render(w, r, "application.html", Page{Title: "Заявка Freedom Pay", Active: v.Kind, Application: v, Fields: allFreedomFields(), Values: v.Values}, 200)
	}
}
func (a *App) adminIiko(w http.ResponseWriter, r *http.Request) {
	if v := a.findIntegration(w, r, "iiko"); v != nil {
		a.render(w, r, "application.html", Page{Title: "Заявка iiko", Active: v.Kind, Application: v, Fields: iikoFields, Values: v.Values}, 200)
	}
}
func (a *App) reviewFreedom(w http.ResponseWriter, r *http.Request) {
	a.reviewIntegration(w, r, "freedom-pay")
}
func (a *App) reviewIiko(w http.ResponseWriter, r *http.Request) { a.reviewIntegration(w, r, "iiko") }
func (a *App) reviewIntegration(w http.ResponseWriter, r *http.Request, kind string) {
	v := a.findIntegration(w, r, kind)
	if v == nil {
		return
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	if err = lockRestaurant(r.Context(), tx, v.RestaurantID); err != nil {
		a.fail(w, r, err)
		return
	}
	if kind == "iiko" {
		*v, err = loadIiko(r.Context(), tx, v.RestaurantID)
	} else {
		*v, err = loadFreedom(r.Context(), tx, v.RestaurantID)
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	action := r.PathValue("action")
	comment := form(r, "review_comment")
	reference := form(r, "partner_reference")
	merchant := form(r, "merchant_id")
	next := ""
	problem := "Действие недоступно в текущем статусе."
	inProgress := v.Status == "UNDER_FREEDOM_REVIEW" || v.Status == "SUBMITTED_TO_FREEDOM" || v.Status == "IN_PROGRESS"
	switch action {
	case "send":
		if v.Status == "READY_FOR_REVIEW" && v.Complete {
			if kind == "iiko" {
				next = "IN_PROGRESS"
			} else if reference != "" {
				next = "UNDER_FREEDOM_REVIEW"
			} else {
				problem = "Укажите реальный номер заявки у Freedom Pay после её отправки партнёру."
			}
		}
	case "approve":
		if inProgress {
			if kind == "iiko" {
				next = "APPROVED"
			} else if merchant != "" {
				next = "APPROVED"
			} else {
				problem = "Укажите merchant ID, полученный от Freedom Pay."
			}
		}
	case "changes", "reject":
		if (v.Status == "READY_FOR_REVIEW" || inProgress) && comment != "" {
			next = "NEEDS_CHANGES"
			if action == "reject" {
				next = "REJECTED"
			}
		} else {
			problem = "Укажите комментарий к решению."
		}
	}
	p := Page{Title: "Проверка заявки", Active: kind, Application: v, Fields: iikoFields, Values: v.Values}
	if kind != "iiko" {
		p.Fields = allFreedomFields()
	}
	if next == "" || len(comment) > 3000 || len(reference) > 255 || len(merchant) > 255 {
		p.Error = problem
		a.render(w, r, "application.html", p, 422)
		return
	}
	if kind == "iiko" {
		_, err = tx.Exec(r.Context(), `UPDATE iiko_applications SET status=$1,review_comment=$2,partner_reference=CASE WHEN $3='' THEN partner_reference ELSE $3 END,updated_at=now() WHERE id=$4`, next, comment, reference, v.ID)
	} else {
		_, err = tx.Exec(r.Context(), `UPDATE freedom_pay_applications SET status=$1,review_comment=$2,partner_application_id=CASE WHEN $3='' THEN partner_application_id ELSE $3 END,merchant_id=CASE WHEN $4='' THEN merchant_id ELSE $4 END,updated_at=now() WHERE id=$5`, next, comment, reference, merchant, v.ID)
	}
	if err == nil && next == "APPROVED" && kind == "freedom-pay" {
		_, err = tx.Exec(r.Context(), `UPDATE restaurants SET active=true,status='ACTIVE',updated_at=now() WHERE id=$1`, v.RestaurantID)
	}
	if err == nil {
		err = a.queueMail(r.Context(), tx, v.OwnerEmail, "Обновление заявки ProCash", fmt.Sprintf("Заведение: %s\nПодключение: %s\nСтатус: %s\nКомментарий: %s\n\nКабинет: %s/restaurants/%s", v.RestaurantName, kind, StatusLabel(next), comment, a.Config.BaseURL, v.RestaurantID))
	}
	if err == nil {
		err = audit(r.Context(), tx, CurrentUser(r).ID, kind+"."+action, v.ID)
	}
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.redirect(w, r, "/admin/"+kind+"/applications/"+v.ID)
}
