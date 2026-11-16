//go:build linux || android

package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

type snapshot struct {
	Items    []event `json:"items"`
	Started  int64   `json:"started"`
	Updated  int64   `json:"updated"`
	Packets  uint64  `json:"packets"`
	Observed uint64  `json:"observed"`
}

func main() {
	out := flag.String("output", "/dev/xguard/activity.json", "Snapshot file")
	hosts := flag.String("hosts", "/data/adb/xguard/shield/hosts", "Effective hosts file")
	flag.Parse()
	os.Chmod(filepath.Dir(*out), 0700)
	// A passive AF_PACKET socket: it does not redirect DNS, bind resolver ports or change firewall rules.
	fd, err := syscall.Socket(syscall.AF_PACKET, syscall.SOCK_DGRAM, 0x0300)
	if err != nil {
		fmt.Fprintln(os.Stderr, "无法采集网络域名：", err)
		os.Exit(1)
	}
	defer syscall.Close(fd)
	syscall.SetsockoptTimeval(fd, syscall.SOL_SOCKET, syscall.SO_RCVTIMEO, &syscall.Timeval{Sec: 1})
	syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_RCVBUF, 262144)
	// Kernel BPF accepts IPv4/IPv6 TCP + UDP only. Deeper bounded parsing happens in userspace.
	filter := []syscall.SockFilter{{Code: 0x30, K: 0}, {Code: 0x54, K: 0xf0}, {Code: 0x15, Jt: 0, Jf: 4, K: 0x40}, {Code: 0x30, K: 9}, {Code: 0x15, Jt: 6, Jf: 0, K: 6}, {Code: 0x15, Jt: 5, Jf: 0, K: 17}, {Code: 0x06, K: 0}, {Code: 0x15, Jt: 0, Jf: 4, K: 0x60}, {Code: 0x30, K: 6}, {Code: 0x15, Jt: 1, Jf: 0, K: 6}, {Code: 0x15, Jt: 0, Jf: 1, K: 17}, {Code: 0x06, K: 65535}, {Code: 0x06, K: 0}}
	if err = syscall.AttachLsf(fd, filter); err != nil {
		fmt.Fprintln(os.Stderr, "BPF 过滤器不可用，使用有界解析：", err)
	}
	state := snapshot{Items: []event{}, Started: time.Now().Unix()}
	dec := decoder{}
	blocked := map[string]bool{}
	seen := map[string]int64{}
	var mod time.Time
	reload := func() {
		st, e := os.Stat(*hosts)
		if e != nil || st.ModTime() == mod {
			return
		}
		f, e := os.Open(*hosts)
		if e != nil {
			return
		}
		defer f.Close()
		next := map[string]bool{}
		scan := bufio.NewScanner(f)
		for scan.Scan() {
			parts := strings.Fields(scan.Text())
			if len(parts) > 1 && parts[0] == "0.0.0.0" {
				next[parts[1]] = true
			}
		}
		if scan.Err() == nil {
			blocked = next
			mod = st.ModTime()
		}
	}
	flush := func() {
		state.Updated = time.Now().Unix()
		for i := range state.Items {
			state.Items[i].RuleBlocked = blocked[state.Items[i].Domain]
		}
		data, e := json.Marshal(state)
		if e != nil {
			return
		}
		tmp := *out + ".tmp"
		if os.WriteFile(tmp, data, 0600) == nil {
			os.Rename(tmp, *out)
		}
	}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	reload()
	flush()
	last := time.Now()
	buffer := make([]byte, 65536)
	for {
		select {
		case <-stop:
			flush()
			return
		default:
		}
		n, _, e := syscall.Recvfrom(fd, buffer, 0)
		if e == nil {
			state.Packets++
			if item, ok := dec.packet(buffer[:n]); ok {
				key := item.Domain + "/" + item.Source
				if item.Time-seen[key] >= 2 {
					seen[key] = item.Time
					item.RuleBlocked = blocked[item.Domain]
					state.Items = append(state.Items, item)
					state.Observed++
					if len(state.Items) > 240 {
						state.Items = state.Items[len(state.Items)-240:]
					}
				}
			}
		} else if e != syscall.EAGAIN && e != syscall.EWOULDBLOCK && e != syscall.EINTR {
			fmt.Fprintln(os.Stderr, e)
			return
		}
		if time.Since(last) >= time.Second {
			if _, e := os.Stat(*out + ".clear"); e == nil {
				state.Items = []event{}
				state.Observed = 0
				seen = map[string]int64{}
				os.Remove(*out + ".clear")
			}
			reload()
			flush()
			last = time.Now()
			if len(seen) > 1024 {
				for k, v := range seen {
					if time.Now().Unix()-v > 30 {
						delete(seen, k)
					}
				}
			}
			if len(seen) > 2048 {
				seen = map[string]int64{}
			}
		}
	}
}
