package health

import (
    "net/http"
)

func ServeHealth(w http.ResponseWriter, r *http.Request) {
    w.Write([]byte("OK"))
}