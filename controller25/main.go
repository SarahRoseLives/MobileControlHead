package main

import (
    "encoding/json"
    "io"
    "log"
    "net/http"
    "os"
    "os/exec"
    "os/signal"
    "path/filepath"
    "strconv"
    "strings"
    "sync"
    "syscall"
    "time"

    "controller25/audio"
    "controller25/config"
    "controller25/health"
    "controller25/log"
    "controller25/mdns"
    "controller25/talkgroup"
)

type Op25State struct {
    cmdObj     *exec.Cmd
    stdoutPipe io.ReadCloser
    stderrPipe io.ReadCloser
    running    bool
    flags      []string
    mu         sync.Mutex
}

var op25 Op25State
var tgParser *talkgroup.Parser

// killExistingOP25Processes finds and kills any running rx.py processes
func killExistingOP25Processes() {
    log.Println("Checking for existing OP25 processes...")
    
    // Use pgrep to find processes matching rx.py
    cmd := exec.Command("pgrep", "-f", "rx.py")
    output, err := cmd.Output()
    if err != nil {
        // Exit code 1 means no processes found, which is fine
        if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
            log.Println("No existing OP25 processes found")
            return
        }
        log.Printf("Warning: Failed to check for existing OP25 processes: %v", err)
        return
    }
    
    // Parse PIDs from output
    pids := strings.Split(strings.TrimSpace(string(output)), "\n")
    if len(pids) == 0 || (len(pids) == 1 && pids[0] == "") {
        log.Println("No existing OP25 processes found")
        return
    }
    
    log.Printf("Found %d existing OP25 process(es), cleaning up...", len(pids))
    
    for _, pidStr := range pids {
        pidStr = strings.TrimSpace(pidStr)
        if pidStr == "" {
            continue
        }
        
        pid, err := strconv.Atoi(pidStr)
        if err != nil {
            log.Printf("Warning: Invalid PID '%s': %v", pidStr, err)
            continue
        }
        
        // Kill the process
        process, err := os.FindProcess(pid)
        if err != nil {
            log.Printf("Warning: Failed to find process %d: %v", pid, err)
            continue
        }
        
        err = process.Signal(syscall.SIGTERM)
        if err != nil {
            log.Printf("Warning: Failed to kill process %d: %v", pid, err)
            // Try SIGKILL as fallback
            _ = process.Signal(syscall.SIGKILL)
        } else {
            log.Printf("Killed existing OP25 process (PID %d)", pid)
        }
    }
    
    // Give processes time to shut down
    time.Sleep(1 * time.Second)
    log.Println("OP25 process cleanup complete")
}

// API request/response types
type Op25StartRequest struct {
    Flags []string `json:"flags"`
}
type Op25StartResponse struct {
    Started bool   `json:"started"`
    Error   string `json:"error,omitempty"`
}
type Op25StatusResponse struct {
    Running bool     `json:"running"`
    Flags   []string `json:"flags"`
}

// Trunk API types
type TrunkReadResponse struct {
    SysName        string `json:"sysname"`
    ControlChannel string `json:"control_channel"`
    Error          string `json:"error,omitempty"`
}
type TrunkWriteRequest struct {
    SysName        string `json:"sysname"`
    ControlChannel string `json:"control_channel"`
}
type TrunkWriteResponse struct {
    Success bool   `json:"success"`
    Error   string `json:"error,omitempty"`
}

// OP25 Config API types
type Op25ConfigResponse struct {
    SdrDevice  string `json:"sdr_device"`
    SampleRate string `json:"sample_rate"`
    LnaGain    string `json:"lna_gain"`
    TrunkFile  string `json:"trunk_file"`
    Error      string `json:"error,omitempty"`
}
type Op25ConfigRequest struct {
    SdrDevice  string `json:"sdr_device"`
    SampleRate string `json:"sample_rate"`
    LnaGain    string `json:"lna_gain"`
    TrunkFile  string `json:"trunk_file"`
}

func stopOp25(audioBroadcaster **audio.Broadcaster, logBroadcaster **logstream.Broadcaster) {
    if op25.cmdObj != nil && op25.cmdObj.Process != nil {
        log.Println("Terminating OP25 process...")
        syscall.Kill(-op25.cmdObj.Process.Pid, syscall.SIGKILL)
        op25.cmdObj.Wait()
        log.Println("OP25 process terminated")
    }
    op25.running = false
    op25.flags = nil
    op25.cmdObj = nil
    op25.stdoutPipe = nil
    op25.stderrPipe = nil
    if *audioBroadcaster != nil {
        (*audioBroadcaster).Shutdown()
        *audioBroadcaster = nil
    }
    if *logBroadcaster != nil {
        *logBroadcaster = nil
    }
}

func main() {
    log.Println("Starting controller25 server...")
    log.Println("Loading configuration...")

    // Store absolute path to config.ini before changing directories
    configPath, err := filepath.Abs("config.ini")
    if err != nil {
        log.Fatalf("Failed to get absolute path for config.ini: %v", err)
    }

    cfg := config.MustLoadConfig(configPath)
    log.Printf("Configuration loaded. OP25 path: %s", cfg.Op25RxPath)
    log.Printf("OP25 Config - Device: %s, Sample Rate: %s, LNA Gain: %s", cfg.SdrDevice, cfg.SampleRate, cfg.LnaGain)

    log.Println("Changing working directory...")
    config.MustChdir(cfg.Op25RxPath)
    log.Println("Working directory changed")

    // Clean up any existing OP25 processes to avoid port conflicts
    killExistingOP25Processes()

    // Do NOT auto-start OP25 on first run!
    // Instead, wait for API request to /api/op25/start

    // Create talkgroup parser
    tgParser = talkgroup.NewParser()
    
    // Start a ticker to clean up expired talkgroups
    go func() {
        ticker := time.NewTicker(2 * time.Second)
        defer ticker.Stop()
        for range ticker.C {
            tgParser.ClearExpired()
        }
    }()

    // Audio and log broadcasters are initialized when OP25 starts
    var (
        audioBroadcaster *audio.Broadcaster
        logBroadcaster   *logstream.Broadcaster
    )

    // Start mDNS Service
    mdnsShutdown := make(chan struct{})
    go mdns.StartmDNSService(mdnsShutdown)

    // Setup HTTP handlers
    http.HandleFunc("/audio.wav", func(w http.ResponseWriter, r *http.Request) {
        if audioBroadcaster == nil {
            http.Error(w, "Audio not broadcasting (OP25 not started)", http.StatusServiceUnavailable)
            return
        }
        audioBroadcaster.ServeWAV(w, r)
    })
    http.HandleFunc("/stream", func(w http.ResponseWriter, r *http.Request) {
        if logBroadcaster == nil {
            http.Error(w, "Logs not broadcasting (OP25 not started)", http.StatusServiceUnavailable)
            return
        }
        logBroadcaster.ServeSSE(w, r)
    })
    http.HandleFunc("/health", health.ServeHealth)
    
    // Talkgroup info endpoint
    http.HandleFunc("/api/talkgroup", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodGet {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        
        tg := tgParser.GetActiveTalkgroupData()
        cc := tgParser.GetControlChannel()
        
        response := map[string]interface{}{
            "talkgroup":       tg,
            "control_channel": cc,
        }
        
        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(response)
    })

    http.HandleFunc("/api/op25/start", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }

        op25.mu.Lock()
        defer op25.mu.Unlock()
        
        // Clean up any existing OP25 processes first
        killExistingOP25Processes()
        
        // If already running, shut down and restart
        if op25.running {
            stopOp25(&audioBroadcaster, &logBroadcaster)
            // Give time for UDP port to be fully released
            time.Sleep(500 * time.Millisecond)
        }

        // Build flags from config (includes audio streaming flags)
        flags := config.BuildOP25Flags(cfg)
        log.Printf("Starting OP25 with flags: %v", flags)
        
        // Start audio broadcaster BEFORE OP25 to ensure UDP listener is ready
        audioBroadcaster = audio.NewBroadcaster("127.0.0.1:23456")
        audioBroadcaster.SetTalkgroupGetter(tgParser)
        go audioBroadcaster.Start()
        
        // Give audio broadcaster time to bind to UDP port
        time.Sleep(100 * time.Millisecond)
        
        // Start OP25 with config-based flags
        op25Cmd, stdoutPipe, stderrPipe, err := config.StartOp25ProcessUDPWithFlags(flags)
        if err != nil {
            // Clean up audio broadcaster if OP25 fails to start
            audioBroadcaster.Shutdown()
            audioBroadcaster = nil
            resp := Op25StartResponse{Started: false, Error: err.Error()}
            _ = json.NewEncoder(w).Encode(resp)
            return
        }

        op25.cmdObj = op25Cmd
        op25.stdoutPipe = stdoutPipe
        op25.stderrPipe = stderrPipe
        op25.running = true
        op25.flags = flags

        // Start log broadcaster
        logBroadcaster = logstream.NewBroadcaster(stdoutPipe, stderrPipe)
        logBroadcaster.SetParser(tgParser)
        go logBroadcaster.Start()

        resp := Op25StartResponse{Started: true}
        _ = json.NewEncoder(w).Encode(resp)
    })

    http.HandleFunc("/api/op25/stop", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        op25.mu.Lock()
        defer op25.mu.Unlock()
        if !op25.running || op25.cmdObj == nil {
            w.WriteHeader(http.StatusConflict)
            _ = json.NewEncoder(w).Encode(Op25StartResponse{Started: false, Error: "OP25 not running"})
            return
        }
        stopOp25(&audioBroadcaster, &logBroadcaster)
        _ = json.NewEncoder(w).Encode(Op25StartResponse{Started: false})
    })

    http.HandleFunc("/api/op25/status", func(w http.ResponseWriter, r *http.Request) {
        op25.mu.Lock()
        defer op25.mu.Unlock()
        _ = json.NewEncoder(w).Encode(Op25StatusResponse{
            Running: op25.running,
            Flags:   op25.flags,
        })
    })

    // Trunk file read endpoint
    http.HandleFunc("/api/trunk/read", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodGet {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        sys, err := config.ReadTrunkSystem(config.TrunkFileName)
        if err != nil {
            _ = json.NewEncoder(w).Encode(TrunkReadResponse{Error: err.Error()})
            return
        }
        _ = json.NewEncoder(w).Encode(TrunkReadResponse{
            SysName:        sys.SysName,
            ControlChannel: sys.ControlChannel,
        })
    })

    // Trunk file write endpoint
    http.HandleFunc("/api/trunk/write", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        var req TrunkWriteRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            _ = json.NewEncoder(w).Encode(TrunkWriteResponse{Success: false, Error: "Invalid request body"})
            return
        }
        sys := &config.TrunkSystem{
            SysName:        req.SysName,
            ControlChannel: req.ControlChannel,
        }
        err := config.WriteTrunkSystem(config.TrunkFileName, sys)
        if err != nil {
            _ = json.NewEncoder(w).Encode(TrunkWriteResponse{Success: false, Error: err.Error()})
            return
        }
        _ = json.NewEncoder(w).Encode(TrunkWriteResponse{Success: true})
    })

    // OP25 Config read endpoint
    http.HandleFunc("/api/op25/config", func(w http.ResponseWriter, r *http.Request) {
        if r.Method == http.MethodGet {
            // Return current config
            _ = json.NewEncoder(w).Encode(Op25ConfigResponse{
                SdrDevice:  cfg.SdrDevice,
                SampleRate: cfg.SampleRate,
                LnaGain:    cfg.LnaGain,
                TrunkFile:  cfg.TrunkFile,
            })
        } else if r.Method == http.MethodPost {
            // Update config
            var req Op25ConfigRequest
            if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
                _ = json.NewEncoder(w).Encode(Op25ConfigResponse{Error: "Invalid request body"})
                return
            }
            
            // Validate SDR device
            validDevices := map[string]bool{"rtl": true, "rtl_tcp": true, "hackrf": true}
            if !validDevices[req.SdrDevice] {
                _ = json.NewEncoder(w).Encode(Op25ConfigResponse{Error: "Invalid SDR device. Must be rtl, rtl_tcp, or hackrf"})
                return
            }
            
            // Update config struct
            cfg.SdrDevice = req.SdrDevice
            cfg.SampleRate = req.SampleRate
            cfg.LnaGain = req.LnaGain
            cfg.TrunkFile = req.TrunkFile
            
            // Save to file (use absolute path since we changed working directory)
            if err := config.SaveConfig(configPath, cfg); err != nil {
                _ = json.NewEncoder(w).Encode(Op25ConfigResponse{Error: err.Error()})
                return
            }
            
            log.Printf("OP25 config updated - Device: %s, Sample Rate: %s, LNA Gain: %s", cfg.SdrDevice, cfg.SampleRate, cfg.LnaGain)
            
            _ = json.NewEncoder(w).Encode(Op25ConfigResponse{
                SdrDevice:  cfg.SdrDevice,
                SampleRate: cfg.SampleRate,
                LnaGain:    cfg.LnaGain,
                TrunkFile:  cfg.TrunkFile,
            })
        } else {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        }
    })

    // Channel for shutdown
    done := make(chan struct{})

    // Goroutine for graceful shutdown
    go func() {
        sigChan := make(chan os.Signal, 1)
        signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
        <-sigChan

        log.Println("Shutting down...")

        // Shutdown mDNS
        close(mdnsShutdown)

        // Shutdown audio broadcaster and OP25 process
        op25.mu.Lock()
        stopOp25(&audioBroadcaster, &logBroadcaster)
        op25.mu.Unlock()

        close(done)
    }()

    log.Println("Starting HTTP server on :9000")
    server := &http.Server{Addr: ":9000"}
    go func() {
        if err := server.ListenAndServe(); err != http.ErrServerClosed {
            log.Fatalf("HTTP server failed: %v", err)
        }
    }()

    <-done
    log.Println("Server shutdown complete")
}