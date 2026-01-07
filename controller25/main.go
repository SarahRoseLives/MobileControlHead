package main

import (
    "encoding/json"
    "fmt"
    "io"
    "log"
    "math"
    "mime/multipart"
    "net/http"
    "os"
    "os/exec"
    "os/signal"
    "path/filepath"
    "sort"
    "strconv"
    "strings"
    "sync"
    "syscall"
    "time"

    "controller25/audio"
    "controller25/config"
    "controller25/health"
    logstream "controller25/log"
    "controller25/mdns"
    "controller25/radioreference"
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

// RadioReference API types
type RadioReferenceCreateSystemRequest struct {
    Username string `json:"username"`
    Password string `json:"password"`
    SystemID int    `json:"system_id"`
}

type RadioReferenceCreateSystemResponse struct {
    Success      bool   `json:"success"`
    SystemID     int    `json:"system_id,omitempty"`
    SitesCount   int    `json:"sites_count,omitempty"`
    SystemFolder string `json:"system_folder,omitempty"`
    Error        string `json:"error,omitempty"`
}

type RadioReferenceListSitesRequest struct {
    SystemID int `json:"system_id"`
}

type RadioReferenceListSitesResponse struct {
    Success bool                  `json:"success"`
    Sites   []RadioReferenceSite  `json:"sites,omitempty"`
    Error   string                `json:"error,omitempty"`
}

type RadioReferenceSite struct {
    SiteID      int    `json:"site_id"`
    Description string `json:"description"`
    Latitude    string `json:"latitude"`
    Longitude   string `json:"longitude"`
    TrunkFile   string `json:"trunk_file"`
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
    
    // HLS endpoints
    http.HandleFunc("/audio.m3u8", func(w http.ResponseWriter, r *http.Request) {
        if audioBroadcaster == nil {
            http.Error(w, "Audio not broadcasting (OP25 not started)", http.StatusServiceUnavailable)
            return
        }
        audioBroadcaster.HLS.ServePlaylist(w, r)
    })
    http.HandleFunc("/audio/", func(w http.ResponseWriter, r *http.Request) {
        if audioBroadcaster == nil {
            http.Error(w, "Audio not broadcasting (OP25 not started)", http.StatusServiceUnavailable)
            return
        }
        audioBroadcaster.HLS.ServeSegment(w, r)
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
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
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
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
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
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
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
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
        op25.mu.Lock()
        defer op25.mu.Unlock()
        _ = json.NewEncoder(w).Encode(Op25StatusResponse{
            Running: op25.running,
            Flags:   op25.flags,
        })
    })

    // Trunk file read endpoint
    http.HandleFunc("/api/trunk/read", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
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
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
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

    // System file upload endpoint
    http.HandleFunc("/api/system/upload", func(w http.ResponseWriter, r *http.Request) {
        log.Printf("=== /api/system/upload called ===")
        log.Printf("Method: %s", r.Method)
        log.Printf("Remote Address: %s", r.RemoteAddr)
        log.Printf("Content-Type: %s", r.Header.Get("Content-Type"))
        
        // Set CORS headers
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        // Handle preflight request
        if r.Method == http.MethodOptions {
            log.Println("OPTIONS preflight request - returning 200")
            w.WriteHeader(http.StatusOK)
            return
        }
        
        if r.Method != http.MethodPost {
            log.Printf("Method not allowed: %s", r.Method)
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        
        log.Println("Parsing multipart form...")
        // Parse multipart form (max 10MB)
        err := r.ParseMultipartForm(10 << 20)
        if err != nil {
            log.Printf("Failed to parse multipart form: %v", err)
            http.Error(w, "Failed to parse form", http.StatusBadRequest)
            return
        }
        log.Println("Multipart form parsed successfully")
        
        // Get system_id and site_id from form
        systemID := r.FormValue("system_id")
        siteID := r.FormValue("site_id")
        
        log.Printf("Received form fields - system_id: %s, site_id: %s", systemID, siteID)
        
        if systemID == "" || siteID == "" {
            log.Println("ERROR: system_id or site_id is empty")
            http.Error(w, "system_id and site_id are required", http.StatusBadRequest)
            return
        }
        
        log.Printf("Creating system folder for system %s...", systemID)
        // Create systems folder structure
        systemFolder := filepath.Join(".", "systems", systemID)
        err = os.MkdirAll(systemFolder, 0755)
        if err != nil {
            log.Printf("ERROR: Failed to create system folder: %v", err)
            http.Error(w, "Failed to create system folder", http.StatusInternalServerError)
            return
        }
        log.Printf("System folder created: %s", systemFolder)
        
        log.Println("Getting trunk file from form...")
        // Get the trunk file
        trunkFile, trunkHeader, err := r.FormFile("trunk_file")
        if err != nil {
            log.Printf("ERROR: Failed to get trunk_file: %v", err)
            http.Error(w, "trunk_file is required", http.StatusBadRequest)
            return
        }
        defer trunkFile.Close()
        log.Printf("Trunk file received: %s", trunkHeader.Filename)
        
        log.Println("Getting optional talkgroup file...")
        // Get optional talkgroup file
        var tgFile multipart.File
        var tgHeader *multipart.FileHeader
        tgFile, tgHeader, _ = r.FormFile("talkgroup_file")
        if tgFile != nil {
            defer tgFile.Close()
            log.Printf("Talkgroup file received: %s", tgHeader.Filename)
        } else {
            log.Println("No talkgroup file provided")
        }
        
        log.Println("Saving trunk file...")
        // Save trunk file to systems folder
        trunkPath := filepath.Join(systemFolder, trunkHeader.Filename)
        trunkDest, err := os.Create(trunkPath)
        if err != nil {
            log.Printf("ERROR: Failed to create trunk file: %v", err)
            http.Error(w, "Failed to create trunk file", http.StatusInternalServerError)
            return
        }
        defer trunkDest.Close()
        
        _, err = io.Copy(trunkDest, trunkFile)
        if err != nil {
            log.Printf("ERROR: Failed to write trunk file: %v", err)
            http.Error(w, "Failed to write trunk file", http.StatusInternalServerError)
            return
        }
        log.Printf("Saved trunk file: %s", trunkPath)
        
        // Save talkgroup file if provided
        var tgPath string
        if tgFile != nil && tgHeader != nil {
            log.Println("Saving talkgroup file...")
            tgPath = filepath.Join(systemFolder, tgHeader.Filename)
            tgDest, err := os.Create(tgPath)
            if err != nil {
                log.Printf("ERROR: Failed to create talkgroup file: %v", err)
                http.Error(w, "Failed to create talkgroup file", http.StatusInternalServerError)
                return
            }
            defer tgDest.Close()
            
            _, err = io.Copy(tgDest, tgFile)
            if err != nil {
                log.Printf("ERROR: Failed to write talkgroup file: %v", err)
                http.Error(w, "Failed to write talkgroup file", http.StatusInternalServerError)
                return
            }
            log.Printf("Saved talkgroup file: %s", tgPath)
        }
        
        log.Println("Updating config.ini...")
        // Update config.ini to use this trunk file
        cfg.TrunkFile = filepath.Join("systems", systemID, trunkHeader.Filename)
        err = config.SaveConfig(configPath, cfg)
        if err != nil {
            log.Printf("Warning: Failed to update config.ini: %v", err)
        } else {
            log.Printf("Updated config.ini trunk_file to: %s", cfg.TrunkFile)
        }
        
        log.Println("Upload successful! Sending response...")
        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "success": true,
            "trunk_file": trunkPath,
            "talkgroup_file": tgPath,
            "system_folder": systemFolder,
        })
        log.Println("=== Upload complete ===")
    })

    // RadioReference - Create System endpoint
    http.HandleFunc("/api/radioreference/create-system", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
        if r.Method != http.MethodPost {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        
        var req RadioReferenceCreateSystemRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            _ = json.NewEncoder(w).Encode(RadioReferenceCreateSystemResponse{
                Success: false,
                Error:   "Invalid request body",
            })
            return
        }
        
        log.Printf("RadioReference: Creating system %d with username %s", req.SystemID, req.Username)
        
        // Create RadioReference client
        rrClient := radioreference.NewClient(req.Username, req.Password)
        
        // Create system files on server
        if err := rrClient.CreateSystemFiles(req.SystemID); err != nil {
            log.Printf("RadioReference: Failed to create system: %v", err)
            _ = json.NewEncoder(w).Encode(RadioReferenceCreateSystemResponse{
                Success: false,
                Error:   fmt.Sprintf("Failed to create system: %v", err),
            })
            return
        }
        
        // Get sites to return count
        sites, err := rrClient.GetTrsSites(req.SystemID)
        sitesCount := 0
        if err == nil {
            sitesCount = len(sites)
        }
        
        systemFolder := filepath.Join("systems", strconv.Itoa(req.SystemID))
        
        log.Printf("RadioReference: Successfully created system %d with %d sites", req.SystemID, sitesCount)
        
        _ = json.NewEncoder(w).Encode(RadioReferenceCreateSystemResponse{
            Success:      true,
            SystemID:     req.SystemID,
            SitesCount:   sitesCount,
            SystemFolder: systemFolder,
        })
    })

    // RadioReference - List Sites endpoint
    http.HandleFunc("/api/radioreference/list-sites", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
        if r.Method != http.MethodGet {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        
        systemIDStr := r.URL.Query().Get("system_id")
        if systemIDStr == "" {
            _ = json.NewEncoder(w).Encode(RadioReferenceListSitesResponse{
                Success: false,
                Error:   "system_id parameter is required",
            })
            return
        }
        
        systemID, err := strconv.Atoi(systemIDStr)
        if err != nil {
            _ = json.NewEncoder(w).Encode(RadioReferenceListSitesResponse{
                Success: false,
                Error:   "Invalid system_id",
            })
            return
        }
        
        // Check if system folder exists
        systemFolder := filepath.Join("systems", strconv.Itoa(systemID))
        if _, err := os.Stat(systemFolder); os.IsNotExist(err) {
            _ = json.NewEncoder(w).Encode(RadioReferenceListSitesResponse{
                Success: false,
                Error:   fmt.Sprintf("System %d not found. Please create it first.", systemID),
            })
            return
        }
        
        // Read site metadata JSON file
        metadataPath := filepath.Join(systemFolder, fmt.Sprintf("%d_sites.json", systemID))
        metadataBytes, err := os.ReadFile(metadataPath)
        if err != nil {
            _ = json.NewEncoder(w).Encode(RadioReferenceListSitesResponse{
                Success: false,
                Error:   "Failed to read site metadata",
            })
            return
        }
        
        type SiteMetadata struct {
            SiteID      int    `json:"site_id"`
            Description string `json:"description"`
            Latitude    string `json:"latitude"`
            Longitude   string `json:"longitude"`
        }
        
        var metadata []SiteMetadata
        if err := json.Unmarshal(metadataBytes, &metadata); err != nil {
            _ = json.NewEncoder(w).Encode(RadioReferenceListSitesResponse{
                Success: false,
                Error:   "Failed to parse site metadata",
            })
            return
        }
        
        // Get optional lat/lon for sorting
        latStr := r.URL.Query().Get("lat")
        lonStr := r.URL.Query().Get("lon")
        
        var sites []RadioReferenceSite
        for _, meta := range metadata {
            sites = append(sites, RadioReferenceSite{
                SiteID:      meta.SiteID,
                Description: meta.Description,
                Latitude:    meta.Latitude,
                Longitude:   meta.Longitude,
                TrunkFile:   filepath.Join("systems", strconv.Itoa(systemID), fmt.Sprintf("%d_%d_trunk.tsv", systemID, meta.SiteID)),
            })
        }
        
        // Sort by distance if lat/lon provided
        if latStr != "" && lonStr != "" {
            userLat, err1 := strconv.ParseFloat(latStr, 64)
            userLon, err2 := strconv.ParseFloat(lonStr, 64)
            
            if err1 == nil && err2 == nil {
                // Haversine distance calculation
                haversineDistance := func(lat1, lon1, lat2, lon2 float64) float64 {
                    const R = 6371.0 // Earth's radius in km
                    lat1Rad := lat1 * math.Pi / 180
                    lat2Rad := lat2 * math.Pi / 180
                    deltaLat := (lat2 - lat1) * math.Pi / 180
                    deltaLon := (lon2 - lon1) * math.Pi / 180
                    
                    a := math.Sin(deltaLat/2)*math.Sin(deltaLat/2) +
                        math.Cos(lat1Rad)*math.Cos(lat2Rad)*
                        math.Sin(deltaLon/2)*math.Sin(deltaLon/2)
                    c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
                    
                    return R * c
                }
                
                sort.Slice(sites, func(i, j int) bool {
                    iLat, _ := strconv.ParseFloat(sites[i].Latitude, 64)
                    iLon, _ := strconv.ParseFloat(sites[i].Longitude, 64)
                    jLat, _ := strconv.ParseFloat(sites[j].Latitude, 64)
                    jLon, _ := strconv.ParseFloat(sites[j].Longitude, 64)
                    
                    distI := haversineDistance(userLat, userLon, iLat, iLon)
                    distJ := haversineDistance(userLat, userLon, jLat, jLon)
                    
                    return distI < distJ
                })
                log.Printf("Sorted %d sites by distance from %.4f, %.4f", len(sites), userLat, userLon)
            }
        }
        
        _ = json.NewEncoder(w).Encode(RadioReferenceListSitesResponse{
            Success: true,
            Sites:   sites,
        })
    })

    // OP25 Config read endpoint
    http.HandleFunc("/api/op25/config", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
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
            
            // Update fields only if provided (non-empty)
            if req.SdrDevice != "" {
                // Validate SDR device only if provided
                validDevices := map[string]bool{"rtl": true, "rtl_tcp": true, "hackrf": true}
                if !validDevices[req.SdrDevice] {
                    _ = json.NewEncoder(w).Encode(Op25ConfigResponse{Error: "Invalid SDR device. Must be rtl, rtl_tcp, or hackrf"})
                    return
                }
                cfg.SdrDevice = req.SdrDevice
            }
            
            if req.SampleRate != "" {
                cfg.SampleRate = req.SampleRate
            }
            
            if req.LnaGain != "" {
                cfg.LnaGain = req.LnaGain
            }
            
            if req.TrunkFile != "" {
                cfg.TrunkFile = req.TrunkFile
            }
            
            // Save to file (use absolute path since we changed working directory)
            if err := config.SaveConfig(configPath, cfg); err != nil {
                _ = json.NewEncoder(w).Encode(Op25ConfigResponse{Error: err.Error()})
                return
            }
            
            log.Printf("OP25 config updated - Device: %s, Sample Rate: %s, LNA Gain: %s, Trunk File: %s", cfg.SdrDevice, cfg.SampleRate, cfg.LnaGain, cfg.TrunkFile)
            
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

    // List available systems endpoint
    http.HandleFunc("/api/systems/list", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
        if r.Method != http.MethodGet {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        
        type SystemInfo struct {
            SystemID string                   `json:"system_id"`
            Sites    []map[string]interface{} `json:"sites"`
        }
        
        systemsDir := "systems"
        entries, err := os.ReadDir(systemsDir)
        if err != nil {
            log.Printf("Error reading systems directory: %v", err)
            _ = json.NewEncoder(w).Encode(map[string]interface{}{
                "success": true,
                "systems": []SystemInfo{},
            })
            return
        }
        
        var systems []SystemInfo
        for _, entry := range entries {
            if !entry.IsDir() {
                continue
            }
            
            systemID := entry.Name()
            metadataPath := filepath.Join(systemsDir, systemID, systemID+"_sites.json")
            
            var sites []map[string]interface{}
            data, err := os.ReadFile(metadataPath)
            if err == nil {
                if err := json.Unmarshal(data, &sites); err != nil {
                    log.Printf("Error parsing metadata for system %s: %v", systemID, err)
                }
            }
            
            systems = append(systems, SystemInfo{
                SystemID: systemID,
                Sites:    sites,
            })
        }
        
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "success": true,
            "systems": systems,
        })
    })

    // Get talkgroups for current system endpoint
    http.HandleFunc("/api/talkgroups/list", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        
        if r.Method != http.MethodGet {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        
        type Talkgroup struct {
            ID   string `json:"id"`
            Name string `json:"name"`
        }
        
        // Get trunk file from config
        trunkFile := cfg.TrunkFile
        if trunkFile == "" {
            _ = json.NewEncoder(w).Encode(map[string]interface{}{
                "success":    false,
                "error":      "No system configured",
                "talkgroups": []Talkgroup{},
            })
            return
        }
        
        // Extract system ID from trunk file path (e.g., systems/6643/6643_12345_trunk.tsv)
        parts := strings.Split(trunkFile, "/")
        if len(parts) < 2 {
            _ = json.NewEncoder(w).Encode(map[string]interface{}{
                "success":    false,
                "error":      "Invalid trunk file path",
                "talkgroups": []Talkgroup{},
            })
            return
        }
        
        systemID := parts[1]
        talkgroupFile := filepath.Join("systems", systemID, systemID+"_talkgroups.tsv")
        
        // Read talkgroups file
        data, err := os.ReadFile(talkgroupFile)
        if err != nil {
            log.Printf("Error reading talkgroups file: %v", err)
            _ = json.NewEncoder(w).Encode(map[string]interface{}{
                "success":    false,
                "error":      fmt.Sprintf("Talkgroups file not found: %v", err),
                "talkgroups": []Talkgroup{},
            })
            return
        }
        
        // Parse TSV
        lines := strings.Split(string(data), "\n")
        var talkgroups []Talkgroup
        
        for _, line := range lines {
            line = strings.TrimSpace(line)
            if line == "" {
                continue
            }
            
            parts := strings.Split(line, "\t")
            if len(parts) >= 2 {
                talkgroups = append(talkgroups, Talkgroup{
                    ID:   strings.TrimSpace(parts[0]),
                    Name: strings.TrimSpace(parts[1]),
                })
            }
        }
        
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "success":    true,
            "system_id":  systemID,
            "talkgroups": talkgroups,
        })
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