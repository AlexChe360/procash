package app

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"mime"
	"mime/quotedprintable"
	"net"
	"net/http"
	"net/smtp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

type Message struct{ ID, To, Subject, Body string }
type Mailer interface {
	Send(context.Context, Message) error
}
type SMTPMailer struct{ Config Config }

func (m SMTPMailer) Send(ctx context.Context, msg Message) error {
	c := m.Config
	if c.SMTPHost == "" {
		return errors.New("SMTP is not configured")
	}
	address := net.JoinHostPort(c.SMTPHost, c.SMTPPort)
	dialer := net.Dialer{Timeout: 10 * time.Second}
	var conn net.Conn
	var err error
	tlsConfig := &tls.Config{ServerName: c.SMTPHost, MinVersion: tls.VersionTLS12}
	if c.SMTPSecurity == "tls" {
		conn, err = (&tls.Dialer{NetDialer: &dialer, Config: tlsConfig}).DialContext(ctx, "tcp", address)
	} else {
		conn, err = dialer.DialContext(ctx, "tcp", address)
	}
	if err != nil {
		return err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(25 * time.Second))
	client, err := smtp.NewClient(conn, c.SMTPHost)
	if err != nil {
		return err
	}
	defer client.Close()
	if c.SMTPSecurity == "starttls" {
		if ok, _ := client.Extension("STARTTLS"); !ok {
			return errors.New("SMTP server does not offer STARTTLS")
		}
		if err = client.StartTLS(tlsConfig); err != nil {
			return err
		}
	}
	if c.SMTPUser != "" {
		if err = client.Auth(smtp.PlainAuth("", c.SMTPUser, c.SMTPPassword, c.SMTPHost)); err != nil {
			return err
		}
	}
	if err = client.Mail(c.SMTPFrom); err != nil {
		return err
	}
	if err = client.Rcpt(msg.To); err != nil {
		return err
	}
	writer, err := client.Data()
	if err != nil {
		return err
	}
	domain := strings.SplitN(c.SMTPFrom, "@", 2)[1]
	headers := fmt.Sprintf("From: ProCash <%s>\r\nTo: %s\r\nSubject: %s\r\nDate: %s\r\nMessage-ID: <%s@%s>\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n", c.SMTPFrom, msg.To, mime.BEncoding.Encode("UTF-8", strings.NewReplacer("\r", " ", "\n", " ").Replace(msg.Subject)), time.Now().Format(time.RFC1123Z), msg.ID, domain)
	if _, err = io.WriteString(writer, headers); err != nil {
		return err
	}
	encoder := quotedprintable.NewWriter(writer)
	if _, err = io.WriteString(encoder, msg.Body); err != nil {
		return err
	}
	if err = encoder.Close(); err != nil {
		return err
	}
	if err = writer.Close(); err != nil {
		return err
	}
	return client.Quit()
}
func (a *App) encrypt(body string) ([]byte, error) {
	block, err := aes.NewCipher(a.Config.Key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return nil, err
	}
	return gcm.Seal(nonce, nonce, []byte(body), []byte("procash-mail-v1")), nil
}
func (a *App) decrypt(payload []byte) (string, error) {
	block, err := aes.NewCipher(a.Config.Key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	if len(payload) < gcm.NonceSize() {
		return "", errors.New("invalid encrypted payload")
	}
	plain, err := gcm.Open(nil, payload[:gcm.NonceSize()], payload[gcm.NonceSize():], []byte("procash-mail-v1"))
	return string(plain), err
}
func (a *App) queueMail(ctx context.Context, tx pgx.Tx, to, subject, body string) error {
	if !validEmail(to) {
		return errors.New("invalid recipient")
	}
	encrypted, err := a.encrypt(body)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO mail_outbox(id,recipient,subject,payload) VALUES($1,$2,$3,$4)`, NewID(), to, subject, encrypted)
	return err
}
func (a *App) DeliverOne(ctx context.Context) (bool, error) {
	if a.Config.SMTPHost == "" {
		return false, nil
	}
	tx, err := a.DB.Begin(ctx)
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx)
	var msg Message
	var payload []byte
	var attempts int
	err = tx.QueryRow(ctx, `SELECT id,recipient,subject,payload,attempts FROM mail_outbox WHERE (status='PENDING' AND next_attempt_at<=now()) OR (status='SENDING' AND lease_until<now()) ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED`).Scan(&msg.ID, &msg.To, &msg.Subject, &payload, &attempts)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if _, err = tx.Exec(ctx, `UPDATE mail_outbox SET status='SENDING',lease_until=now()+interval '2 minutes',attempts=attempts+1 WHERE id=$1`, msg.ID); err != nil {
		return false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return false, err
	}
	msg.Body, err = a.decrypt(payload)
	if err == nil {
		err = a.Mailer.Send(ctx, msg)
	}
	if err == nil {
		_, err = a.DB.Exec(ctx, `UPDATE mail_outbox SET status='SENT',sent_at=now(),payload=NULL,last_error='',lease_until=NULL WHERE id=$1`, msg.ID)
		return true, err
	}
	a.logger.Warn("mail delivery failed", "message_id", msg.ID, "error", err)
	status := "PENDING"
	if attempts >= 23 {
		status = "FAILED"
	}
	delay := time.Minute * time.Duration(1<<min(attempts, 6))
	_, saveErr := a.DB.Exec(ctx, `UPDATE mail_outbox SET status=$1,lease_until=NULL,next_attempt_at=now()+$2::interval,last_error='Не удалось отправить письмо. Проверьте SMTP и повторите отправку.' WHERE id=$3`, status, fmt.Sprintf("%d seconds", int(delay.Seconds())), msg.ID)
	return true, saveErr
}
func (a *App) RunWorker(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	cleanup := time.NewTicker(time.Hour)
	defer cleanup.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			for i := 0; i < 20; i++ {
				ok, err := a.DeliverOne(ctx)
				if err != nil {
					a.logger.Error("mail worker", "error", err)
					break
				}
				if !ok {
					break
				}
			}
		case <-cleanup.C:
			_, err := a.DB.Exec(ctx, `DELETE FROM sessions WHERE expires_at<now(); DELETE FROM rate_limits WHERE window_start<now()-interval '2 days'`)
			if err != nil {
				a.logger.Error("cleanup", "error", err)
			}
		}
	}
}

type MailRow struct {
	ID, Recipient, Subject, Status, Error string
	Attempts                              int
	CreatedAt                             time.Time
}

func (a *App) mailQueue(w http.ResponseWriter, r *http.Request) {
	p := Page{Title: "Очередь писем", Active: "mail"}
	rows, err := a.DB.Query(r.Context(), `SELECT id,recipient,subject,status,last_error,attempts,created_at FROM mail_outbox ORDER BY created_at DESC LIMIT 200`)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		var v MailRow
		if err = rows.Scan(&v.ID, &v.Recipient, &v.Subject, &v.Status, &v.Error, &v.Attempts, &v.CreatedAt); err != nil {
			a.fail(w, r, err)
			return
		}
		p.Emails = append(p.Emails, v)
	}
	if rows.Err() != nil {
		a.fail(w, r, rows.Err())
		return
	}
	a.render(w, r, "mail.html", p, 200)
}
func (a *App) retryMail(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("mail")
	if !ValidID(id) {
		a.notFound(w, r)
		return
	}
	_, err := a.DB.Exec(r.Context(), `UPDATE mail_outbox SET status='PENDING',next_attempt_at=now(),attempts=0 WHERE id=$1 AND status IN ('FAILED','PENDING') AND payload IS NOT NULL`, id)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	a.redirect(w, r, "/admin/mail")
}
func Keygen() string {
	b := make([]byte, 32)
	if _, e := rand.Read(b); e != nil {
		panic(e)
	}
	return "base64:" + base64.StdEncoding.EncodeToString(b)
}
