package web

import "embed"

//go:embed templates/*.html static/* documents/*.pdf
var Files embed.FS
