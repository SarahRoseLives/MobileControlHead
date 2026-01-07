package talkgroup

import (
	"regexp"
	"strconv"
	"sync"
	"time"
)

type TalkgroupInfo struct {
	Tgid         int       `json:"tgid"`
	Srcid        int       `json:"srcid"`
	Frequency    string    `json:"frequency"`
	LastUpdate   time.Time `json:"last_update"`
	Active       bool      `json:"active"`
}

func (t *TalkgroupInfo) GetTgid() int {
	return t.Tgid
}

func (t *TalkgroupInfo) GetSrcid() int {
	return t.Srcid
}

type Parser struct {
	mu              sync.RWMutex
	activeTalkgroup *TalkgroupInfo
	controlChannel  string
	
	// Regex patterns
	tgidRegex   *regexp.Regexp
	srcRegex    *regexp.Regexp
	freqRegex   *regexp.Regexp
	ccRegex     *regexp.Regexp
}

func NewParser() *Parser {
	return &Parser{
		tgidRegex: regexp.MustCompile(`tgid[=:]?\s*(\d+)`),
		srcRegex:  regexp.MustCompile(`(?:src|source|srcaddr)[=:]?\s*(\d+)`),
		freqRegex: regexp.MustCompile(`freq[=:]?\s*([\d.]+)`),
		ccRegex:   regexp.MustCompile(`(?i)(?:control|tracking).*?([\d.]+)\s*(?:MHz|Hz)?`),
	}
}

// ParseLine processes a log line and extracts talkgroup information
func (p *Parser) ParseLine(line string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	
	// Extract talkgroup ID
	if match := p.tgidRegex.FindStringSubmatch(line); match != nil {
		tgid, _ := strconv.Atoi(match[1])
		
		// Extract source ID (optional)
		srcid := 0
		if srcMatch := p.srcRegex.FindStringSubmatch(line); srcMatch != nil {
			srcid, _ = strconv.Atoi(srcMatch[1])
		}
		
		// Extract frequency (optional)
		freq := ""
		if freqMatch := p.freqRegex.FindStringSubmatch(line); freqMatch != nil {
			freq = freqMatch[1]
		}
		
		// Update or create active talkgroup
		if p.activeTalkgroup == nil || p.activeTalkgroup.Tgid != tgid || (srcid > 0 && p.activeTalkgroup.Srcid != srcid) {
			p.activeTalkgroup = &TalkgroupInfo{
				Tgid:       tgid,
				Srcid:      srcid,
				Frequency:  freq,
				LastUpdate: time.Now(),
				Active:     true,
			}
		} else {
			// Update existing
			if srcid > 0 {
				p.activeTalkgroup.Srcid = srcid
			}
			if freq != "" {
				p.activeTalkgroup.Frequency = freq
			}
			p.activeTalkgroup.LastUpdate = time.Now()
		}
	}
	
	// Extract control channel
	if match := p.ccRegex.FindStringSubmatch(line); match != nil {
		p.controlChannel = match[1]
	}
}

// GetActiveTalkgroup returns the current active talkgroup, or nil if none/expired
func (p *Parser) GetActiveTalkgroup() interface{
	GetTgid() int
	GetSrcid() int
} {
	p.mu.RLock()
	defer p.mu.RUnlock()
	
	if p.activeTalkgroup == nil {
		return nil
	}
	
	// Check if talkgroup has expired (5 seconds of inactivity)
	if time.Since(p.activeTalkgroup.LastUpdate) > 5*time.Second {
		return nil
	}
	
	// Return the active talkgroup
	return p.activeTalkgroup
}

// GetActiveTalkgroupData returns full talkgroup data for API responses
func (p *Parser) GetActiveTalkgroupData() *TalkgroupInfo {
	p.mu.RLock()
	defer p.mu.RUnlock()
	
	if p.activeTalkgroup == nil {
		return nil
	}
	
	// Check if talkgroup has expired (5 seconds of inactivity)
	if time.Since(p.activeTalkgroup.LastUpdate) > 5*time.Second {
		return nil
	}
	
	// Return a copy
	tg := *p.activeTalkgroup
	return &tg
}

// GetControlChannel returns the current control channel frequency
func (p *Parser) GetControlChannel() string {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return p.controlChannel
}

// ClearExpired marks talkgroups as inactive if they've expired
func (p *Parser) ClearExpired() {
	p.mu.Lock()
	defer p.mu.Unlock()
	
	if p.activeTalkgroup != nil && time.Since(p.activeTalkgroup.LastUpdate) > 5*time.Second {
		p.activeTalkgroup = nil
	}
}
