package config

import (
    "bufio"
    "fmt"
    "os"
    "strings"
    "sync"
)

const TrunkFileName = "trunk.tsv"

// TrunkSystem represents a row in trunk.tsv.
type TrunkSystem struct {
    SysName           string
    ControlChannel    string
}

// Lock for concurrent trunk.tsv access
var trunkLock sync.Mutex

// ReadTrunkSystem reads the first non-header entry from trunk.tsv.
// Returns nil if no entry is found.
func ReadTrunkSystem(filename string) (*TrunkSystem, error) {
    trunkLock.Lock()
    defer trunkLock.Unlock()

    f, err := os.Open(filename)
    if err != nil {
        return nil, err
    }
    defer f.Close()

    scanner := bufio.NewScanner(f)
    // Read header
    if !scanner.Scan() {
        return nil, fmt.Errorf("trunk file empty")
    }
    // Read first data row
    for scanner.Scan() {
        line := scanner.Text()
        cols := splitTSV(line)
        if len(cols) < 2 {
            continue
        }
        sys := TrunkSystem{
            SysName:        strings.Trim(cols[0], `"`),
            ControlChannel: strings.Trim(cols[1], `"`),
        }
        return &sys, nil
    }
    return nil, fmt.Errorf("no system found")
}

// WriteTrunkSystem replaces the first non-header row in trunk.tsv (creates file if needed).
func WriteTrunkSystem(filename string, sys *TrunkSystem) error {
    trunkLock.Lock()
    defer trunkLock.Unlock()

    lines := []string{}
    foundHeader := false
    header := `"Sysname"	"Control Channel List"	"Offset"	"NAC"	"Modulation"	"TGID Tags File"	"Whitelist"	"Blacklist"	"Center Frequency"`

    // Read all lines if file exists
    if f, err := os.Open(filename); err == nil {
        scanner := bufio.NewScanner(f)
        for scanner.Scan() {
            lines = append(lines, scanner.Text())
        }
        f.Close()
    }

    if len(lines) == 0 || !strings.Contains(lines[0], "Sysname") {
        // No header: insert
        lines = append([]string{header}, lines...)
        foundHeader = true
    } else {
        foundHeader = true
    }

    newRow := fmt.Sprintf(`"%s"	"%s"	"0"	"0"	"cqpsk"	""	""	""	""`, sys.SysName, sys.ControlChannel)

    if foundHeader && len(lines) > 1 {
        // Replace first data row
        lines[1] = newRow
    } else if foundHeader && len(lines) == 1 {
        // Only header, append row
        lines = append(lines, newRow)
    } else if !foundHeader {
        // Should never happen
        lines = []string{header, newRow}
    }

    // Write back
    return os.WriteFile(filename, []byte(strings.Join(lines, "\n")+"\n"), 0644)
}

// Helper: split a TSV row, trimming extra whitespace
func splitTSV(line string) []string {
    fields := strings.Split(line, "\t")
    for i, f := range fields {
        fields[i] = strings.TrimSpace(f)
    }
    return fields
}