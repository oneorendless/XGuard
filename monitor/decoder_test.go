package main

import (
	"crypto/tls"
	"encoding/binary"
	"math/rand"
	"net"
	"testing"
	"time"
)

func dnsFixture() []byte {
	b := make([]byte, 12)
	b[2] = 1
	b[5] = 1
	b = append(b, 3, 'a', 'd', 's', 7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0, 0, 1, 0, 1)
	return b
}
func ipFixture(p []byte, proto byte, port uint16, seq uint32, v6 bool) []byte {
	size := 8
	if proto == 6 {
		size = 20
	}
	b := make([]byte, size)
	binary.BigEndian.PutUint16(b[:2], 45000)
	binary.BigEndian.PutUint16(b[2:4], port)
	if proto == 6 {
		b[12] = 0x50
		binary.BigEndian.PutUint32(b[4:8], seq)
	} else {
		binary.BigEndian.PutUint16(b[4:6], uint16(size+len(p)))
	}
	b = append(b, p...)
	if v6 {
		h := make([]byte, 40)
		h[0] = 0x60
		h[6] = proto
		binary.BigEndian.PutUint16(h[4:6], uint16(len(b)))
		h[23] = 1
		h[39] = 2
		return append(h, b...)
	}
	h := make([]byte, 20)
	h[0] = 0x45
	h[9] = proto
	binary.BigEndian.PutUint16(h[2:4], uint16(20+len(b)))
	copy(h[12:16], []byte{10, 0, 0, 1})
	copy(h[16:20], []byte{1, 1, 1, 1})
	return append(h, b...)
}
func TestDNSAcrossIPVersions(t *testing.T) {
	for _, v6 := range []bool{false, true} {
		d := decoder{}
		e, ok := d.packet(ipFixture(dnsFixture(), 17, 53, 0, v6))
		if !ok || e.Domain != "ads.example.com" || e.Source != "dns" {
			t.Fatalf("DNS not decoded: %+v %v", e, ok)
		}
	}
	b := dnsFixture()
	b[2] |= 128
	if _, ok := dnsQuestion(b); ok {
		t.Fatal("response reported as new outgoing query")
	}
	b = append(make([]byte, 12), 0xc0, 12, 0, 1, 0, 1)
	b[5] = 1
	if _, ok := dnsQuestion(b); ok {
		t.Fatal("compression loop accepted")
	}
}
func TestRealTLSClientHelloAndTCPSegmentation(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	client.SetDeadline(time.Now().Add(time.Second))
	server.SetDeadline(time.Now().Add(time.Second))
	go func() {
		conn := tls.Client(client, &tls.Config{ServerName: "www.example.org", MinVersion: tls.VersionTLS12})
		conn.Handshake()
		conn.Close()
	}()
	b := make([]byte, 32768)
	n, err := server.Read(b)
	if err != nil {
		t.Fatal(err)
	}
	b = b[:n]
	if name, ok := tlsName(b); !ok || name != "www.example.org" {
		t.Fatalf("ClientHello: %s %v", name, ok)
	}
	d := decoder{}
	half := len(b) / 2
	if _, ok := d.packet(ipFixture(b[:half], 6, 443, 100, false)); ok {
		t.Fatal("incomplete hello accepted")
	}
	if _, ok := d.packet(ipFixture(b[:half], 6, 443, 100, false)); ok {
		t.Fatal("retransmission accepted")
	}
	e, ok := d.packet(ipFixture(b[half:], 6, 443, 100+uint32(half), false))
	if !ok || e.Domain != "www.example.org" {
		t.Fatalf("split hello: %+v %v", e, ok)
	}
}
func TestMalformedTrafficDoesNotPanic(t *testing.T) {
	r := rand.New(rand.NewSource(83))
	d := decoder{}
	for n := 0; n < 7000; n++ {
		b := make([]byte, r.Intn(2000))
		r.Read(b)
		d.packet(b)
		dnsQuestion(b)
		tlsName(b)
	}
}
