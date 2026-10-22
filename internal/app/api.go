package app

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5"
)

func (a *App) apiOrder(w http.ResponseWriter, r *http.Request) {
	restaurant := r.URL.Query().Get("restaurantId")
	if restaurant == "" {
		restaurant = r.URL.Query().Get("restaurant_id")
	}
	number := r.URL.Query().Get("tableNumber")
	if number == "" {
		number = r.URL.Query().Get("table_number")
	}
	problem := func(status int, code string) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		JSON(w, map[string]string{"code": code})
	}
	if restaurant == "" || number == "" {
		problem(400, "MISSING_PARAMETER")
		return
	}
	n, err := strconv.Atoi(number)
	if err != nil {
		problem(400, "INVALID_PARAMETER_TYPE")
		return
	}
	if n < 1 {
		problem(400, "VALIDATION_ERROR")
		return
	}
	if !ValidID(restaurant) {
		problem(404, "ORDER_NOT_FOUND")
		return
	}
	var o Order
	u := CurrentUser(r)
	err = a.DB.QueryRow(r.Context(), `SELECT o.id,o.order_number,o.status,o.total_amount::text,o.opened_at FROM restaurant_orders o JOIN restaurant_tables t ON t.id=o.restaurant_table_id JOIN restaurants r ON r.id=o.restaurant_id WHERE r.id=$1 AND ($2::boolean OR r.owner_id=$3) AND t.table_number=$4 AND t.active=true AND o.status='OPEN' ORDER BY o.opened_at DESC LIMIT 1`, restaurant, u.Admin(), u.ID, number).Scan(&o.ID, &o.Number, &o.Status, &o.Total, &o.OpenedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		problem(404, "ORDER_NOT_FOUND")
		return
	}
	if err != nil {
		a.fail(w, r, err)
		return
	}
	rows, err := a.DB.Query(r.Context(), `SELECT name,quantity::text,unit_price::text,total_price::text FROM order_items WHERE order_id=$1 ORDER BY created_at`, o.ID)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var v OrderItem
		if err = rows.Scan(&v.Name, &v.Quantity, &v.UnitPrice, &v.Total); err != nil {
			a.fail(w, r, err)
			return
		}
		items = append(items, map[string]any{"name": v.Name, "quantity": json.Number(v.Quantity), "unitPrice": json.Number(v.UnitPrice), "totalPrice": json.Number(v.Total)})
	}
	if rows.Err() != nil {
		a.fail(w, r, rows.Err())
		return
	}
	JSON(w, map[string]any{"id": o.ID, "restaurantId": restaurant, "tableNumber": n, "orderNumber": o.Number, "status": o.Status, "totalAmount": json.Number(o.Total), "items": items})
}
