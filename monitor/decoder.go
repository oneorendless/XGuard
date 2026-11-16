package main

import (
	"encoding/binary"
	"net"
	"strings"
	"time"
)

type event struct {
	Time        int64  `json:"time"`
	Domain      string `json:"domain"`
	Source      string `json:"source"`
	Destination string `json:"destination"`
	RuleBlocked bool   `json:"rule_blocked"`
}
type segment struct {
	next uint32
	data []byte
	seen time.Time
}
type decoder struct{ streams map[string]*segment }

func validName(s string) bool {
	if len(s) < 3 || len(s) > 253 || !strings.Contains(s, ".") {
		return false
	}
	for _, label := range strings.Split(s, ".") {
		if len(label) == 0 || len(label) > 63 {
			return false
		}
		for _, c := range label {
			if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '_') {
				return false
			}
		}
	}
	return true
}
func dnsName(b []byte, pos int) (string, bool) {
	labels := []string{}
	total := 0
	for hops := 0; hops < 32; hops++ {
		if pos >= len(b) {
			return "", false
		}
		n := int(b[pos])
		pos++
		if n == 0 {
			s := strings.ToLower(strings.Join(labels, "."))
			return s, validName(s)
		}
		if n&192 == 192 {
			if pos >= len(b) {
				return "", false
			}
			pos = ((n & 63) << 8) | int(b[pos])
			continue
		}
		if n > 63 || pos+n > len(b) {
			return "", false
		}
		total += n + 1
		if total > 254 {
			return "", false
		}
		labels = append(labels, string(b[pos:pos+n]))
		pos += n
	}
	return "", false
}
func dnsQuestion(b []byte) (string, bool) {
	if len(b) < 17 || b[2]&128 != 0 || binary.BigEndian.Uint16(b[4:6]) == 0 {
		return "", false
	}
	return dnsName(b, 12)
}
func tlsName(b []byte) (string, bool) {
	// Reconstruct handshake bytes across TLS records before parsing ClientHello.
	h := []byte{}
	for len(b) >= 5 {
		if b[0] != 22 || b[1] != 3 {
			break
		}
		n := int(binary.BigEndian.Uint16(b[3:5]))
		if n > 32768 || len(b) < n+5 {
			break
		}
		h = append(h, b[5:n+5]...)
		b = b[n+5:]
	}
	if len(h) < 42 || h[0] != 1 {
		return "", false
	}
	n := int(h[1])<<16 | int(h[2])<<8 | int(h[3])
	if len(h) < n+4 {
		return "", false
	}
	h = h[4 : 4+n]
	p := 34
	if p >= len(h) {
		return "", false
	}
	p += 1 + int(h[p])
	if p+2 > len(h) {
		return "", false
	}
	p += 2 + int(binary.BigEndian.Uint16(h[p:p+2]))
	if p >= len(h) {
		return "", false
	}
	p += 1 + int(h[p])
	if p+2 > len(h) {
		return "", false
	}
	end := p + 2 + int(binary.BigEndian.Uint16(h[p:p+2]))
	p += 2
	if end > len(h) {
		return "", false
	}
	for p+4 <= end {
		typ := binary.BigEndian.Uint16(h[p : p+2])
		size := int(binary.BigEndian.Uint16(h[p+2 : p+4]))
		p += 4
		if p+size > end {
			return "", false
		}
		if typ == 0 && size >= 5 {
			x := h[p : p+size]
			l := int(binary.BigEndian.Uint16(x[:2]))
			if l+2 > len(x) {
				return "", false
			}
			for q := 2; q+3 <= 2+l; {
				kind := x[q]
				ln := int(binary.BigEndian.Uint16(x[q+1 : q+3]))
				q += 3
				if q+ln > 2+l {
					return "", false
				}
				if kind == 0 {
					s := strings.ToLower(string(x[q : q+ln]))
					return s, validName(s)
				}
				q += ln
			}
		}
		p += size
	}
	return "", false
}
func (d *decoder) packet(b []byte) (event, bool) {
	if len(b) < 20 {
		return event{}, false
	}
	proto := byte(0)
	var src, dst string
	switch b[0] >> 4 {
	case 4:
		hl := int(b[0]&15) * 4
		n := int(binary.BigEndian.Uint16(b[2:4]))
		if hl < 20 || len(b) < hl || n < hl || n > len(b) || binary.BigEndian.Uint16(b[6:8])&0x3fff != 0 {
			return event{}, false
		}
		src = net.IP(b[12:16]).String()
		dst = net.IP(b[16:20]).String()
		proto = b[9]
		b = b[hl:n]
	case 6:
		if len(b) < 40 {
			return event{}, false
		}
		n := 40 + int(binary.BigEndian.Uint16(b[4:6]))
		if n > len(b) {
			return event{}, false
		}
		src = net.IP(b[8:24]).String()
		dst = net.IP(b[24:40]).String()
		proto = b[6]
		b = b[40:n]
		for count := 0; count < 6 && (proto == 0 || proto == 43 || proto == 60); count++ {
			if len(b) < 8 {
				return event{}, false
			}
			size := (int(b[1]) + 1) * 8
			if size > len(b) {
				return event{}, false
			}
			proto, b = b[0], b[size:]
		}
	default:
		return event{}, false
	}
	if len(b) < 8 {
		return event{}, false
	}
	sp := binary.BigEndian.Uint16(b[:2])
	dp := binary.BigEndian.Uint16(b[2:4])
	name := ""
	ok := false
	source := "dns"
	if proto == 17 && dp == 53 {
		size := int(binary.BigEndian.Uint16(b[4:6]))
		if size < 8 || size > len(b) {
			return event{}, false
		}
		name, ok = dnsQuestion(b[8:size])
	} else if proto == 6 && (dp == 53 || dp == 443) {
		if len(b) < 20 {
			return event{}, false
		}
		hl := int(b[12]>>4) * 4
		if hl < 20 || hl > len(b) {
			return event{}, false
		}
		payload := b[hl:]
		if len(payload) == 0 {
			return event{}, false
		}
		key := src + ":" + stringPort(sp) + ">" + dst + ":" + stringPort(dp)
		seq := binary.BigEndian.Uint32(b[4:8])
		if d.streams == nil {
			d.streams = map[string]*segment{}
		}
		s := d.streams[key]
		if s == nil {
			if dp == 443 && payload[0] != 22 {
				return event{}, false
			}
			if len(d.streams) >= 256 {
				for k, v := range d.streams {
					if time.Since(v.seen) > 5*time.Second {
						delete(d.streams, k)
					}
				}
				if len(d.streams) >= 256 {
					return event{}, false
				}
			}
			s = &segment{next: seq}
			d.streams[key] = s
		}
		if seq != s.next {
			return event{}, false
		}
		if len(s.data)+len(payload) > 32768 {
			delete(d.streams, key)
			return event{}, false
		}
		s.data = append(s.data, payload...)
		s.next += uint32(len(payload))
		s.seen = time.Now()
		if dp == 443 {
			source = "tls"
			name, ok = tlsName(s.data)
		} else if len(s.data) >= 2 {
			size := int(binary.BigEndian.Uint16(s.data[:2]))
			if size+2 <= len(s.data) {
				name, ok = dnsQuestion(s.data[2 : 2+size])
			}
		}
		if ok {
			delete(d.streams, key)
		}
	}
	return event{Time: time.Now().Unix(), Domain: name, Source: source, Destination: dst}, ok
}
func stringPort(n uint16) string { return string([]byte{byte(n >> 8), byte(n)}) }
