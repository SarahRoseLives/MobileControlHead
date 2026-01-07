package radioreference

import (
	"bytes"
	"encoding/base64"
	"encoding/csv"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const (
	soapEndpoint = "http://api.radioreference.com/soap2/"
	appKey       = "Mjg4MDExNjM=" // Base64 encoded app key
)

type Client struct {
	username string
	password string
	appKey   string
}

// Response structures
type SOAPEnvelope struct {
	XMLName xml.Name `xml:"Envelope"`
	Body    SOAPBody `xml:"Body"`
}

type SOAPBody struct {
	XMLName             xml.Name                 `xml:"Body"`
	GetTrsSitesResponse *GetTrsSitesResponse     `xml:"getTrsSitesResponse,omitempty"`
	GetTrsTalkgroupsResponse *GetTrsTalkgroupsResponse `xml:"getTrsTalkgroupsResponse,omitempty"`
}

type GetTrsSitesResponse struct {
	XMLName xml.Name `xml:"getTrsSitesResponse"`
	Return  struct {
		Items []Site `xml:"item"`
	} `xml:"return"`
}

type Site struct {
	SiteID    int       `xml:"siteId"`
	SiteDescr string    `xml:"siteDescr"`
	Lat       string    `xml:"lat"`
	Lon       string    `xml:"lon"`
	NAC       string    `xml:"nac"`
	SiteFreqs SiteFreqs `xml:"siteFreqs"`
}

type SiteFreqs struct {
	Items []Frequency `xml:"item"`
}

type Frequency struct {
	Freq string `xml:"freq"`
	Use  string `xml:"use"`
}

type GetTrsTalkgroupsResponse struct {
	XMLName xml.Name `xml:"getTrsTalkgroupsResponse"`
	Return  struct {
		Items []Talkgroup `xml:"item"`
	} `xml:"return"`
}

type Talkgroup struct {
	TgDec   string `xml:"tgDec"`
	TgAlpha string `xml:"tgAlpha"`
	Enc     string `xml:"enc"`
}

func NewClient(username, password string) *Client {
	decodedKey, _ := base64.StdEncoding.DecodeString(appKey)
	return &Client{
		username: username,
		password: password,
		appKey:   string(decodedKey),
	}
}

func (c *Client) buildSOAPRequest(method string, params string) string {
	authInfo := fmt.Sprintf(`
		<authInfo>
			<appKey>%s</appKey>
			<username>%s</username>
			<password>%s</password>
			<version>latest</version>
			<style>rpc</style>
		</authInfo>`, c.appKey, c.username, c.password)

	return fmt.Sprintf(`<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
               xmlns:xsd="http://www.w3.org/2001/XMLSchema" 
               xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <%s xmlns="http://api.radioreference.com/soap2/">
      %s
      %s
    </%s>
  </soap:Body>
</soap:Envelope>`, method, params, authInfo, method)
}

func (c *Client) soapRequest(method string, params string) ([]byte, error) {
	envelope := c.buildSOAPRequest(method, params)
	
	req, err := http.NewRequest("POST", soapEndpoint, bytes.NewBufferString(envelope))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "text/xml; charset=utf-8")
	req.Header.Set("SOAPAction", fmt.Sprintf("http://api.radioreference.com/soap2/%s", method))

	log.Printf("RadioReference: Calling %s", method)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("SOAP request failed with status %d: %s", resp.StatusCode, string(body))
	}

	return body, nil
}

func (c *Client) GetTrsSites(systemID int) ([]Site, error) {
	params := fmt.Sprintf("<sid>%d</sid>", systemID)
	
	respBody, err := c.soapRequest("getTrsSites", params)
	if err != nil {
		return nil, err
	}

	var envelope SOAPEnvelope
	if err := xml.Unmarshal(respBody, &envelope); err != nil {
		return nil, fmt.Errorf("failed to parse SOAP envelope: %w", err)
	}

	if envelope.Body.GetTrsSitesResponse == nil {
		return nil, fmt.Errorf("no getTrsSitesResponse in SOAP body")
	}

	sites := envelope.Body.GetTrsSitesResponse.Return.Items
	log.Printf("RadioReference: Found %d sites for system %d", len(sites), systemID)
	return sites, nil
}

func (c *Client) GetTrsTalkgroups(systemID int) ([]Talkgroup, error) {
	params := fmt.Sprintf("<sid>%d</sid><start>0</start><limit>0</limit><filter>0</filter>", systemID)
	
	respBody, err := c.soapRequest("getTrsTalkgroups", params)
	if err != nil {
		return nil, err
	}

	var envelope SOAPEnvelope
	if err := xml.Unmarshal(respBody, &envelope); err != nil {
		return nil, fmt.Errorf("failed to parse SOAP envelope: %w", err)
	}

	if envelope.Body.GetTrsTalkgroupsResponse == nil {
		return nil, fmt.Errorf("no getTrsTalkgroupsResponse in SOAP body")
	}

	// Filter unencrypted only
	var unencrypted []Talkgroup
	for _, tg := range envelope.Body.GetTrsTalkgroupsResponse.Return.Items {
		if tg.Enc == "0" {
			unencrypted = append(unencrypted, tg)
		}
	}

	log.Printf("RadioReference: Found %d unencrypted talkgroups for system %d", len(unencrypted), systemID)
	return unencrypted, nil
}

func (c *Client) CreateSystemFiles(systemID int) error {
	log.Printf("RadioReference: Creating system files for system %d", systemID)

	// Create system folder
	systemFolder := filepath.Join(".", "systems", strconv.Itoa(systemID))
	if err := os.MkdirAll(systemFolder, 0755); err != nil {
		return fmt.Errorf("failed to create system folder: %w", err)
	}

	// Fetch sites
	sites, err := c.GetTrsSites(systemID)
	if err != nil {
		return fmt.Errorf("failed to fetch sites: %w", err)
	}

	if len(sites) == 0 {
		return fmt.Errorf("no sites found for system %d", systemID)
	}

	// Fetch talkgroups
	talkgroups, err := c.GetTrsTalkgroups(systemID)
	if err != nil {
		return fmt.Errorf("failed to fetch talkgroups: %w", err)
	}

	// Create site TSV files
	for _, site := range sites {
		if err := c.createSiteTSV(systemID, site, systemFolder); err != nil {
			log.Printf("Warning: Failed to create TSV for site %d: %v", site.SiteID, err)
		}
	}

	// Create talkgroups TSV file
	if len(talkgroups) > 0 {
		if err := c.createTalkgroupsTSV(systemID, talkgroups, systemFolder); err != nil {
			log.Printf("Warning: Failed to create talkgroups TSV: %v", err)
		}
	}

	// Save site metadata as JSON
	if err := c.saveSiteMetadata(systemID, sites, systemFolder); err != nil {
		log.Printf("Warning: Failed to save site metadata: %v", err)
	}

	log.Printf("RadioReference: Successfully created system files for system %d in %s", systemID, systemFolder)
	return nil
}

func (c *Client) createSiteTSV(systemID int, site Site, systemFolder string) error {
	filename := fmt.Sprintf("%d_%d_trunk.tsv", systemID, site.SiteID)
	filepath := filepath.Join(systemFolder, filename)

	// Extract and sort control channels
	var controlChannels []string
	primaryChannels := []string{}
	alternateChannels := []string{}

	for _, freq := range site.SiteFreqs.Items {
		if freq.Use != "" {
			if freq.Use == "a" {
				primaryChannels = append(primaryChannels, freq.Freq)
			} else {
				alternateChannels = append(alternateChannels, freq.Freq)
			}
		}
	}

	// Primary channels first, then alternates
	controlChannels = append(controlChannels, primaryChannels...)
	controlChannels = append(controlChannels, alternateChannels...)

	if len(controlChannels) == 0 {
		return fmt.Errorf("no control channels found for site %d", site.SiteID)
	}

	controlChannelList := strings.Join(controlChannels, ",")

	// Create TSV file
	file, err := os.Create(filepath)
	if err != nil {
		return fmt.Errorf("failed to create file: %w", err)
	}
	defer file.Close()

	writer := csv.NewWriter(file)
	writer.Comma = '\t'

	// Write header
	header := []string{
		"Sysname",
		"Control Channel List",
		"Offset",
		"NAC",
		"Modulation",
		"TGID Tags File",
		"Whitelist",
		"Blacklist",
		"Center Frequency",
	}
	if err := writer.Write(header); err != nil {
		return fmt.Errorf("failed to write header: %w", err)
	}

	// Write data row
	nac := site.NAC
	if nac == "" {
		nac = "0"
	} else {
		// Convert hex NAC to decimal if needed
		// NAC can come as "$34d", "0x34d", or just "34d"
		nacStr := strings.TrimPrefix(nac, "$")
		nacStr = strings.TrimPrefix(nacStr, "0x")
		nacStr = strings.TrimPrefix(nacStr, "0X")
		
		if nacInt, err := strconv.ParseInt(nacStr, 16, 64); err == nil {
			nac = strconv.FormatInt(nacInt, 10)
		} else {
			// If it's not hex, try decimal
			if _, err := strconv.Atoi(nac); err != nil {
				// If all else fails, use 0
				nac = "0"
			}
		}
	}

	row := []string{
		strconv.Itoa(systemID),
		controlChannelList,
		"0",
		nac,
		"cqpsk",
		fmt.Sprintf("systems/%d/%d_talkgroups.tsv", systemID, systemID),
		fmt.Sprintf("systems/%d/%d_whitelist.tsv", systemID, systemID),
		fmt.Sprintf("systems/%d/%d_blacklist.tsv", systemID, systemID),
		"",
	}
	if err := writer.Write(row); err != nil {
		return fmt.Errorf("failed to write data row: %w", err)
	}

	writer.Flush()
	if err := writer.Error(); err != nil {
		return fmt.Errorf("failed to flush writer: %w", err)
	}

	log.Printf("Created site TSV: %s with %d control channels", filepath, len(controlChannels))
	return nil
}

func (c *Client) createTalkgroupsTSV(systemID int, talkgroups []Talkgroup, systemFolder string) error {
	// Create talkgroups file
	tgFilename := fmt.Sprintf("%d_talkgroups.tsv", systemID)
	tgFilepath := filepath.Join(systemFolder, tgFilename)

	file, err := os.Create(tgFilepath)
	if err != nil {
		return fmt.Errorf("failed to create talkgroups file: %w", err)
	}
	defer file.Close()

	writer := csv.NewWriter(file)
	writer.Comma = '\t'

	for _, tg := range talkgroups {
		row := []string{tg.TgDec, tg.TgAlpha}
		if err := writer.Write(row); err != nil {
			return fmt.Errorf("failed to write talkgroup row: %w", err)
		}
	}

	writer.Flush()
	if err := writer.Error(); err != nil {
		return fmt.Errorf("failed to flush talkgroups writer: %w", err)
	}

	log.Printf("Created talkgroups TSV: %s with %d talkgroups", tgFilepath, len(talkgroups))

	// Create empty whitelist and blacklist files
	whitelistPath := filepath.Join(systemFolder, fmt.Sprintf("%d_whitelist.tsv", systemID))
	blacklistPath := filepath.Join(systemFolder, fmt.Sprintf("%d_blacklist.tsv", systemID))

	if err := os.WriteFile(whitelistPath, []byte(""), 0644); err != nil {
		return fmt.Errorf("failed to create whitelist: %w", err)
	}

	if err := os.WriteFile(blacklistPath, []byte(""), 0644); err != nil {
		return fmt.Errorf("failed to create blacklist: %w", err)
	}

	return nil
}

// GetSitesByDistance returns sites sorted by distance from given coordinates
func (c *Client) GetSitesByDistance(systemID int, lat, lon float64) ([]Site, error) {
	sites, err := c.GetTrsSites(systemID)
	if err != nil {
		return nil, err
	}

	// Calculate distances and sort
	type siteWithDistance struct {
		site     Site
		distance float64
	}

	sitesWithDist := make([]siteWithDistance, 0, len(sites))
	for _, site := range sites {
		siteLat, err1 := strconv.ParseFloat(site.Lat, 64)
		siteLon, err2 := strconv.ParseFloat(site.Lon, 64)
		
		if err1 == nil && err2 == nil {
			dist := haversineDistance(lat, lon, siteLat, siteLon)
			sitesWithDist = append(sitesWithDist, siteWithDistance{site: site, distance: dist})
		}
	}

	// Sort by distance
	sort.Slice(sitesWithDist, func(i, j int) bool {
		return sitesWithDist[i].distance < sitesWithDist[j].distance
	})

	// Extract sorted sites
	sortedSites := make([]Site, len(sitesWithDist))
	for i, sd := range sitesWithDist {
		sortedSites[i] = sd.site
	}

	return sortedSites, nil
}

// Haversine formula to calculate distance between two coordinates (in km)
func haversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371.0 // Earth's radius in km

	lat1Rad := lat1 * 3.14159265359 / 180
	lat2Rad := lat2 * 3.14159265359 / 180
	deltaLat := (lat2 - lat1) * 3.14159265359 / 180
	deltaLon := (lon2 - lon1) * 3.14159265359 / 180

	// Simplified haversine
	dLat := deltaLat / 2
	dLon := deltaLon / 2
	a := dLat*dLat + (lat1Rad * lat2Rad * dLon * dLon)
	c := 2 * a

	return R * c
}

func (c *Client) saveSiteMetadata(systemID int, sites []Site, systemFolder string) error {
	type SiteMetadata struct {
		SiteID      int    `json:"site_id"`
		Description string `json:"description"`
		Latitude    string `json:"latitude"`
		Longitude   string `json:"longitude"`
	}

	metadata := make([]SiteMetadata, len(sites))
	for i, site := range sites {
		metadata[i] = SiteMetadata{
			SiteID:      site.SiteID,
			Description: site.SiteDescr,
			Latitude:    site.Lat,
			Longitude:   site.Lon,
		}
	}

	jsonData, err := json.Marshal(metadata)
	if err != nil {
		return fmt.Errorf("failed to marshal metadata: %w", err)
	}

	metadataPath := filepath.Join(systemFolder, fmt.Sprintf("%d_sites.json", systemID))
	if err := os.WriteFile(metadataPath, jsonData, 0644); err != nil {
		return fmt.Errorf("failed to write metadata file: %w", err)
	}

	log.Printf("Saved site metadata to: %s", metadataPath)
	return nil
}
