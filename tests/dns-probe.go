package main

import (
	"fmt"
	"net"
	"os"
	"strings"
	"time"
)

func main() {
	for _, domain := range []string{"googleads.g.doubleclick.net", "adx.roiplusad.com", "csj-sp.csjdeveloper.com", "example.com"} {
		query := []byte{0x58, 0x47, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0}
		for _, label := range strings.Split(domain, ".") {
			query = append(query, byte(len(label)))
			query = append(query, label...)
		}
		query = append(query, 0, 0, 1, 0, 1)
		connection, err := net.DialTimeout("udp", "10.231.0.1:53", 5*time.Second)
		if err != nil {
			panic(err)
		}
		connection.SetDeadline(time.Now().Add(10 * time.Second))
		connection.Write(query)
		response := make([]byte, 4096)
		length, err := connection.Read(response)
		connection.Close()
		if err != nil {
			panic(err)
		}
		if length < 12 {
			panic("short DNS response")
		}
		code := response[3] & 15
		fmt.Printf("%s: RCODE=%d, bytes=%d\n", domain, code, length)
		if domain != "example.com" && code != 3 {
			os.Exit(1)
		}
		if domain == "example.com" && code != 0 {
			os.Exit(2)
		}
	}
}
