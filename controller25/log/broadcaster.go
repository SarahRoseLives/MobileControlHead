package logstream

import (
    "bufio"
    "fmt"
    "io"
    "log"
    "net/http"
    "sync"
    "time"
)

// LineParser interface for processing log lines
type LineParser interface {
    ParseLine(line string)
}

type Broadcaster struct {
    mu        sync.Mutex
    clients   map[chan string]struct{}
    stdout    io.Reader
    stderr    io.Reader
    history   []string
    maxLines  int
    startTime time.Time
    parser    LineParser
}

func NewBroadcaster(stdout, stderr io.Reader) *Broadcaster {
    lb := &Broadcaster{
        clients:   make(map[chan string]struct{}),
        stdout:    stdout,
        stderr:    stderr,
        history:   make([]string, 0),
        maxLines:  1000,
        startTime: time.Now(),
    }
    lb.broadcast(fmt.Sprintf("[system] OP25 process starting at %s", lb.startTime.Format(time.RFC3339)))
    return lb
}

// SetParser sets the line parser for processing log lines
func (b *Broadcaster) SetParser(parser LineParser) {
    b.mu.Lock()
    defer b.mu.Unlock()
    b.parser = parser
}

func (b *Broadcaster) Start() {
    b.broadcast("[system] Starting log broadcaster")
    b.broadcast("[system] Setting up stdout and stderr pipes")
    if b.stdout != nil {
        go b.readPipe(b.stdout, "[stdout]")
    } else {
        msg := "[system] Warning: nil stdout pipe, skipping stdout log streaming"
        log.Print(msg)
        b.broadcast(msg)
    }
    if b.stderr != nil {
        go b.readPipe(b.stderr, "[stderr]")
    } else {
        msg := "[system] Warning: nil stderr pipe, skipping stderr log streaming"
        log.Print(msg)
        b.broadcast(msg)
    }
}

func (b *Broadcaster) readPipe(pipe io.Reader, prefix string) {
    if pipe == nil {
        msg := fmt.Sprintf("[system] Error: readPipe called with nil pipe for %s", prefix)
        log.Print(msg)
        b.broadcast(msg)
        return
    }

    b.broadcast(fmt.Sprintf("[system] Starting to read from %s pipe", prefix))
    scanner := bufio.NewScanner(pipe)
    for scanner.Scan() {
        rawLine := scanner.Text()
        line := fmt.Sprintf("%s %s", prefix, rawLine)
        
        // Parse line if parser is set
        if b.parser != nil {
            b.parser.ParseLine(rawLine)
        }
        
        b.broadcast(line)
    }
    if err := scanner.Err(); err != nil {
        msg := fmt.Sprintf("[system] Error reading pipe %s: %v", prefix, err)
        log.Print(msg)
        b.broadcast(msg)
    }
    b.broadcast(fmt.Sprintf("[system] %s pipe closed", prefix))
}

func (b *Broadcaster) broadcast(line string) {
    log.Println(line)
    b.mu.Lock()
    defer b.mu.Unlock()
    b.history = append(b.history, line)
    if len(b.history) > b.maxLines {
        b.history = b.history[len(b.history)-b.maxLines:]
    }
    for ch := range b.clients {
        select {
        case ch <- line:
        default:
            delete(b.clients, ch)
            close(ch)
        }
    }
}

func (b *Broadcaster) ServeSSE(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "text/event-stream")
    w.Header().Set("Cache-Control", "no-cache")
    w.Header().Set("Connection", "keep-alive")
    w.Header().Set("Access-Control-Allow-Origin", "*")

    flusher, ok := w.(http.Flusher)
    if !ok {
        http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
        return
    }

    ch := make(chan string, 100)

    b.mu.Lock()
    for _, line := range b.history {
        fmt.Fprintf(w, "data: %s\n\n", line)
    }
    flusher.Flush()

    b.clients[ch] = struct{}{}
    b.mu.Unlock()

    defer func() {
        b.mu.Lock()
        delete(b.clients, ch)
        b.mu.Unlock()
        close(ch)
    }()

    notify := r.Context().Done()
    for {
        select {
        case line := <-ch:
            fmt.Fprintf(w, "data: %s\n\n", line)
            flusher.Flush()
        case <-notify:
            return
        }
    }
}