package audio

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
)

type HLSBroadcaster struct {
	mu           sync.RWMutex
	segments     [][]byte          // Audio segments
	segmentIndex int               // Current segment being written
	maxSegments  int               // Max segments to keep (e.g., 5)
	segmentDuration time.Duration  // Duration per segment (e.g., 2 seconds)
	sampleRate   int
	channels     int
	buffer       *bytes.Buffer     // Current segment buffer
	tgGetter     TalkgroupGetter
}

func NewHLSBroadcaster(sampleRate, channels int) *HLSBroadcaster {
	return &HLSBroadcaster{
		segments:        make([][]byte, 0),
		maxSegments:     10, // Keep last 10 segments (20 seconds)
		segmentDuration: 2 * time.Second,
		sampleRate:      sampleRate,
		channels:        channels,
		buffer:          &bytes.Buffer{},
	}
}

func (h *HLSBroadcaster) SetTalkgroupGetter(tg TalkgroupGetter) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.tgGetter = tg
}

// AddAudioData adds PCM audio data and creates segments
func (h *HLSBroadcaster) AddAudioData(data []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()

	// Add data to current buffer
	h.buffer.Write(data)

	// Calculate bytes needed for segment duration
	// PCM S16_LE: 2 bytes per sample * sampleRate * channels * duration
	bytesPerSegment := 2 * h.sampleRate * h.channels * int(h.segmentDuration.Seconds())

	// If buffer has enough data, create a segment
	if h.buffer.Len() >= bytesPerSegment {
		segmentData := h.buffer.Next(bytesPerSegment)
		
		// Create WAV segment with header
		wavData := h.makeWAVSegment(segmentData)
		
		h.segments = append(h.segments, wavData)
		
		// Keep only max segments
		if len(h.segments) > h.maxSegments {
			h.segments = h.segments[1:]
		} else {
			h.segmentIndex++
		}
	}
}

func (h *HLSBroadcaster) makeWAVSegment(pcmData []byte) []byte {
	buf := &bytes.Buffer{}
	
	// WAV header
	dataSize := len(pcmData)
	buf.WriteString("RIFF")
	binary.Write(buf, binary.LittleEndian, uint32(36+dataSize))
	buf.WriteString("WAVE")
	
	// fmt chunk
	buf.WriteString("fmt ")
	binary.Write(buf, binary.LittleEndian, uint32(16))        // chunk size
	binary.Write(buf, binary.LittleEndian, uint16(1))         // PCM
	binary.Write(buf, binary.LittleEndian, uint16(h.channels))
	binary.Write(buf, binary.LittleEndian, uint32(h.sampleRate))
	binary.Write(buf, binary.LittleEndian, uint32(h.sampleRate*h.channels*2)) // byte rate
	binary.Write(buf, binary.LittleEndian, uint16(h.channels*2))              // block align
	binary.Write(buf, binary.LittleEndian, uint16(16))                        // bits per sample
	
	// data chunk
	buf.WriteString("data")
	binary.Write(buf, binary.LittleEndian, uint32(dataSize))
	buf.Write(pcmData)
	
	return buf.Bytes()
}

// ServePlaylist serves the HLS playlist (.m3u8)
func (h *HLSBroadcaster) ServePlaylist(w http.ResponseWriter, r *http.Request) {
	h.mu.RLock()
	numSegments := len(h.segments)
	startIndex := h.segmentIndex - numSegments
	if startIndex < 0 {
		startIndex = 0
	}
	h.mu.RUnlock()

	w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
	w.Header().Set("Cache-Control", "no-cache")
	
	// Write HLS playlist
	fmt.Fprintf(w, "#EXTM3U\n")
	fmt.Fprintf(w, "#EXT-X-VERSION:3\n")
	fmt.Fprintf(w, "#EXT-X-TARGETDURATION:%d\n", int(h.segmentDuration.Seconds())+1)
	fmt.Fprintf(w, "#EXT-X-MEDIA-SEQUENCE:%d\n", startIndex)
	
	for i := 0; i < numSegments; i++ {
		fmt.Fprintf(w, "#EXTINF:%.1f,\n", h.segmentDuration.Seconds())
		fmt.Fprintf(w, "/audio/segment%d.wav\n", startIndex+i)
	}
}

// ServeSegment serves an audio segment
func (h *HLSBroadcaster) ServeSegment(w http.ResponseWriter, r *http.Request) {
	var segmentNum int
	fmt.Sscanf(r.URL.Path, "/audio/segment%d.wav", &segmentNum)
	
	h.mu.RLock()
	startIndex := h.segmentIndex - len(h.segments)
	if startIndex < 0 {
		startIndex = 0
	}
	
	segmentOffset := segmentNum - startIndex
	if segmentOffset < 0 || segmentOffset >= len(h.segments) {
		h.mu.RUnlock()
		http.Error(w, "Segment not found", http.StatusNotFound)
		return
	}
	
	segmentData := h.segments[segmentOffset]
	h.mu.RUnlock()
	
	w.Header().Set("Content-Type", "audio/wav")
	w.Header().Set("Content-Length", fmt.Sprintf("%d", len(segmentData)))
	w.Header().Set("Cache-Control", "no-cache")
	
	// Add talkgroup metadata
	h.mu.RLock()
	if h.tgGetter != nil {
		if tg := h.tgGetter.GetActiveTalkgroup(); tg != nil {
			w.Header().Set("X-Talkgroup-ID", fmt.Sprintf("%d", tg.GetTgid()))
			w.Header().Set("X-Source-ID", fmt.Sprintf("%d", tg.GetSrcid()))
		}
	}
	h.mu.RUnlock()
	
	w.Write(segmentData)
	log.Printf("Served HLS segment %d (%d bytes)", segmentNum, len(segmentData))
}
