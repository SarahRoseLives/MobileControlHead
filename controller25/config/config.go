package config

import (
    "gopkg.in/ini.v1"
    "io"
    "log"
    "net"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "syscall"
    "fmt"
)

type Config struct {
    Op25RxPath string
    SdrDevice  string
    SampleRate string
    LnaGain    string
    TrunkFile  string
}

func MustLoadConfig(filename string) *Config {
    cfg, err := ini.Load(filename)
    if err != nil {
        log.Fatalf("Failed to load config: %v", err)
    }
    op25rxpath := cfg.Section("").Key("op25rxpath").String()
    if op25rxpath == "" {
        log.Fatalf("op25rxpath not found in config file")
    }
    
    // Load OP25 section with defaults
    op25Section := cfg.Section("op25")
    sdrDevice := op25Section.Key("sdr_device").MustString("rtl")
    sampleRate := op25Section.Key("sample_rate").MustString("1400000")
    lnaGain := op25Section.Key("lna_gain").MustString("47")
    trunkFile := op25Section.Key("trunk_file").MustString("trunk.tsv")
    
    return &Config{
        Op25RxPath: op25rxpath,
        SdrDevice:  sdrDevice,
        SampleRate: sampleRate,
        LnaGain:    lnaGain,
        TrunkFile:  trunkFile,
    }
}

func MustChdir(path string) {
    if err := os.Chdir(path); err != nil {
        log.Fatalf("Failed to change working directory: %v", err)
    }
}

// SaveConfig writes the configuration back to the INI file
func SaveConfig(filename string, cfg *Config) error {
    iniFile, err := ini.Load(filename)
    if err != nil {
        return fmt.Errorf("failed to load config file: %v", err)
    }
    
    // Update OP25 section
    op25Section, err := iniFile.GetSection("op25")
    if err != nil {
        op25Section, err = iniFile.NewSection("op25")
        if err != nil {
            return fmt.Errorf("failed to create op25 section: %v", err)
        }
    }
    
    op25Section.Key("sdr_device").SetValue(cfg.SdrDevice)
    op25Section.Key("sample_rate").SetValue(cfg.SampleRate)
    op25Section.Key("lna_gain").SetValue(cfg.LnaGain)
    op25Section.Key("trunk_file").SetValue(cfg.TrunkFile)
    
    return iniFile.SaveTo(filename)
}

// BuildOP25Flags constructs the OP25 command flags from the config
// Always includes audio streaming flags to preserve functionality
func BuildOP25Flags(cfg *Config) []string {
    // Build device arg - for rtl_tcp, append server IP
    deviceArg := cfg.SdrDevice
    if cfg.SdrDevice == "rtl_tcp" {
        serverIP := GetServerIP()
        deviceArg = fmt.Sprintf("rtl_tcp=%s:1234", serverIP)
    }
    
    flags := []string{
        "--args", fmt.Sprintf("'%s'", deviceArg),
        "-N", fmt.Sprintf("LNA:%s", cfg.LnaGain),
        "-S", cfg.SampleRate,
        "-T", cfg.TrunkFile,
        // Critical flags for audio streaming and functionality - DO NOT REMOVE
        "-X",
        "-x", "9.0",
        "-V",
        "-v", "9",
        "-l", "http:0.0.0.0:8080",
        "-w",
        "-W", "127.0.0.1",
    }
    return flags
}

// GetServerIP returns the primary non-loopback IPv4 address of the server
// This is the same IP that mDNS advertises and that the Flutter app connects to
func GetServerIP() string {
    ifaces, err := net.Interfaces()
    if err != nil {
        log.Printf("Error getting network interfaces: %v", err)
        return "127.0.0.1"
    }

    // Prioritize non-loopback, non-virtual interfaces
    for _, iface := range ifaces {
        // Skip loopback, down interfaces, and virtual interfaces
        if iface.Flags&net.FlagLoopback != 0 || iface.Flags&net.FlagUp == 0 {
            continue
        }
        // Skip virtual interfaces (vmnet, docker, etc.)
        ifaceName := strings.ToLower(iface.Name)
        if strings.Contains(ifaceName, "vmnet") || 
           strings.Contains(ifaceName, "docker") || 
           strings.Contains(ifaceName, "vbox") {
            continue
        }

        addrs, err := iface.Addrs()
        if err != nil {
            continue
        }

        for _, addr := range addrs {
            ipNet, ok := addr.(*net.IPNet)
            if !ok {
                continue
            }
            // Return first IPv4 address found on valid interface
            if ipNet.IP.To4() != nil {
                log.Printf("Using server IP %s for rtl_tcp", ipNet.IP.String())
                return ipNet.IP.String()
            }
        }
    }

    log.Printf("Could not determine server IP, using localhost")
    return "127.0.0.1"
}

// Deprecated: do not use for startup! Only here for legacy usage, returns 4 values now.
func StartOp25ProcessUDP() (*exec.Cmd, io.ReadCloser, io.ReadCloser, error) {
    op25_args := []string{
        "--args", "'rtl'",
        "-N", "LNA:47",
        "-S", "1400000",
        "-T", "trunk.tsv",
        "-X",
        "-x", "9.0",
        "-V",
        "-v", "9",
        "-l", "http:0.0.0.0:8080",
        "-w",
        "-W", "127.0.0.1",
    }
    return StartOp25ProcessUDPWithFlags(op25_args)
}

// Use this for all OP25 process starts; returns 4 values (cmd, stdout, stderr, error)
func StartOp25ProcessUDPWithFlags(flags []string) (*exec.Cmd, io.ReadCloser, io.ReadCloser, error) {
    var op25Cmd *exec.Cmd

    var full_command []string
    if filepath.Ext("rx.py") == ".py" {
        full_command = append([]string{"-n", "-15", "python3", "rx.py"}, flags...)
    } else {
        full_command = append([]string{"-n", "-15", "./rx.py"}, flags...)
    }

    op25Cmd = exec.Command("nice", full_command...)
    op25Cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

    stdout, err := op25Cmd.StdoutPipe()
    if err != nil {
        return nil, nil, nil, fmt.Errorf("failed to get OP25 stdout pipe: %v", err)
    }
    stderr, err := op25Cmd.StderrPipe()
    if err != nil {
        return nil, nil, nil, fmt.Errorf("failed to get OP25 stderr pipe: %v", err)
    }

    log.Printf("Starting OP25 with command: %s %v", op25Cmd.Path, op25Cmd.Args)
    if err := op25Cmd.Start(); err != nil {
        return nil, nil, nil, fmt.Errorf("failed to start op25: %v", err)
    }
    log.Printf("OP25 process started with PID: %d", op25Cmd.Process.Pid)
    return op25Cmd, stdout, stderr, nil
}