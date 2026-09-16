package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/rknightion/mq-exporter-dist/internal/dist"
	"os"
	"os/exec"
	"time"
)

func run() error {
	if len(os.Args) < 2 {
		return fmt.Errorf("commands: config, health, inspect, replace")
	}
	f := flag.NewFlagSet(os.Args[1], flag.ContinueOnError)
	switch os.Args[1] {
	case "smoke":
		binary := f.String("binary", "", "binary")
		config := f.String("config", "", "configuration file")
		if e := f.Parse(os.Args[2:]); e != nil {
			return e
		}
		if *binary == "" {
			return fmt.Errorf("binary required")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		args := []string{"--help"}
		if *config != "" {
			args = []string{"-f", *config}
		}
		command := exec.CommandContext(ctx, *binary, args...)
		command.Stdout = os.Stdout
		command.Stderr = os.Stderr
		return command.Run()
	case "metadata":
		if len(os.Args) != 5 {
			return fmt.Errorf("metadata file, version and platform required")
		}
		b, e := os.ReadFile(os.Args[2])
		if e != nil {
			return e
		}
		var m struct {
			Version  string `json:"distribution_version"`
			Platform string `json:"platform"`
		}
		if e = json.Unmarshal(b, &m); e != nil {
			return e
		}
		if m.Version != os.Args[3] || m.Platform != os.Args[4] {
			return fmt.Errorf("release metadata mismatch")
		}
		return nil
	case "same-identity":
		if len(os.Args) != 4 {
			return fmt.Errorf("expected and actual config required")
		}
		return dist.SameIdentity(os.Args[2], os.Args[3])
	case "config":
		c := dist.Config{}
		f.StringVar(&c.Exporter, "exporter", "prometheus", "prometheus or otel")
		f.StringVar(&c.Endpoint, "otlp-endpoint", "", "OTLP HTTPS URL or gRPC host:port")
		f.BoolVar(&c.Insecure, "otlp-insecure", false, "explicitly permit plaintext OTLP")
		f.StringVar(&c.QMgr, "qmgr", "", "queue manager")
		f.IntVar(&c.Port, "port", 9157, "port")
		f.StringVar(&c.Queues, "queues", "APP.*,!SYSTEM.*,!AMQ.*", "patterns")
		f.StringVar(&c.Channels, "channels", "*", "patterns")
		f.StringVar(&c.Mode, "mode", "bindings", "bindings or client")
		f.StringVar(&c.Channel, "channel", "", "channel")
		f.StringVar(&c.ConnName, "conn-name", "", "connection name")
		f.StringVar(&c.CCDT, "ccdt", "", "CCDT URL")
		f.StringVar(&c.User, "user", "", "MQ user")
		f.StringVar(&c.PasswordFile, "password-file", "", "password file")
		if e := f.Parse(os.Args[2:]); e != nil {
			return e
		}
		if f.NArg() != 0 {
			return fmt.Errorf("unexpected arguments")
		}
		b, e := dist.Render(c)
		if e != nil {
			return e
		}
		fmt.Println(string(b))
		return nil
	case "health":
		url := f.String("url", "http://127.0.0.1:9157/metrics", "endpoint")
		q := f.String("qmgr", "", "queue manager")
		if e := f.Parse(os.Args[2:]); e != nil {
			return e
		}
		r, e := dist.FetchHealth(*url, *q)
		if e != nil {
			return e
		}
		b, _ := json.Marshal(r)
		fmt.Println(string(b))
		if !r.Connected {
			return fmt.Errorf("MQ is not connected")
		}
		return nil
	case "inspect":
		p := f.String("platform", "linux", "platform")
		if e := f.Parse(os.Args[2:]); e != nil {
			return e
		}
		if f.NArg() != 1 {
			return fmt.Errorf("one binary required")
		}
		return dist.Inspect(f.Arg(0), *p)
	case "replace":
		if len(os.Args) != 4 {
			return fmt.Errorf("source and destination required")
		}
		b, e := dist.Replace(os.Args[2], os.Args[3])
		if b != "" {
			fmt.Println("Backup:", b)
		}
		return e
	default:
		return fmt.Errorf("unknown command")
	}
}
func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, "ERROR:", e)
		os.Exit(1)
	}
}
