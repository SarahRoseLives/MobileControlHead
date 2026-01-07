package mdns

import (
	"log"
	"net"
	"time"

	"github.com/grandcat/zeroconf"
)

func StartmDNSService(shutdown chan struct{}) {
	instanceName := "OP25MCH" // Fixed instance name
	serviceType := "_op25mch._tcp"
	domain := "local."
	port := 9000

	// Get all network interfaces
	ifaces, err := net.Interfaces()
	if err != nil {
		log.Printf("Error getting network interfaces: %v", err)
	}

	// Log all available interfaces
	log.Printf("Available network interfaces:")
	for _, iface := range ifaces {
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		log.Printf("- %s (HW: %s, Flags: %v)", iface.Name, iface.HardwareAddr, iface.Flags)
		for _, addr := range addrs {
			log.Printf("  %s", addr.String())
		}
	}

	// Register service on ALL interfaces (pass nil to zeroconf.Register)
	server, err := zeroconf.Register(
		instanceName,
		serviceType,
		domain,
		port,
		[]string{"txtv=0", "version=1.0"},
		nil, // Passing nil means all available interfaces
	)
	if err != nil {
		log.Fatalf("Failed to start mDNS service: %v", err)
	}

	log.Printf("mDNS service registered as %s.%s%s:%d on all interfaces", instanceName, serviceType, domain, port)

	// Periodically log advertising status
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				log.Printf("mDNS service actively advertising on all interfaces")
			case <-shutdown:
				return
			}
		}
	}()

	<-shutdown
	log.Println("Shutting down mDNS service...")
	server.Shutdown()
	log.Println("mDNS service shut down.")
}