#!/bin/bash
# Generate test data for benchmarking grc/grcat
set -e

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${BENCH_DIR}/test-data"

mkdir -p "${DATA_DIR}"

echo "Generating test data..."

# Generate a fake ls output
cat > "${DATA_DIR}/ls-output.txt" << 'EOF'
total 1024
drwxr-xr-x  5 user group  4096 Dec 13 10:30 .
drwxr-xr-x 20 user group  4096 Dec 12 15:20 ..
-rw-r--r--  1 user group   220 Dec 10 09:15 .bashrc
-rw-r--r--  1 user group  3526 Dec 10 09:15 .profile
drwxr-xr-x  2 user group  4096 Dec 13 10:30 Documents
drwxr-xr-x  3 user group  4096 Dec 13 08:45 Downloads
-rwxr-xr-x  1 user group  8192 Dec 12 16:22 script.sh
-rw-r--r--  1 user group 65536 Dec 11 14:30 data.json
lrwxrwxrwx  1 user group    15 Dec 10 10:05 link -> /usr/bin/bash
drwxr-xr-x  4 user group  4096 Dec 13 09:00 projects
-rw-------  1 user group  2048 Dec 13 11:15 secret.key
EOF

# Generate fake ping output
cat > "${DATA_DIR}/ping-output.txt" << 'EOF'
PING google.com (142.250.185.46) 56(84) bytes of data.
64 bytes from lax30s05-in-f14.1e100.net (142.250.185.46): icmp_seq=1 ttl=117 time=12.3 ms
64 bytes from lax30s05-in-f14.1e100.net (142.250.185.46): icmp_seq=2 ttl=117 time=11.8 ms
64 bytes from lax30s05-in-f14.1e100.net (142.250.185.46): icmp_seq=3 ttl=117 time=13.1 ms
64 bytes from lax30s05-in-f14.1e100.net (142.250.185.46): icmp_seq=4 ttl=117 time=12.0 ms
64 bytes from lax30s05-in-f14.1e100.net (142.250.185.46): icmp_seq=5 ttl=117 time=11.9 ms
Request timeout for icmp_seq 6
64 bytes from lax30s05-in-f14.1e100.net (142.250.185.46): icmp_seq=7 ttl=117 time=12.5 ms
64 bytes from lax30s05-in-f14.1e100.net (142.250.185.46): icmp_seq=8 ttl=117 time=11.7 ms

--- google.com ping statistics ---
8 packets transmitted, 7 received, 12.5% packet loss, time 7012ms
rtt min/avg/max/mdev = 11.723/12.185/13.089/0.451 ms
EOF

# Generate fake ps output
cat > "${DATA_DIR}/ps-output.txt" << 'EOF'
    PID TTY          TIME CMD
      1 ?        00:00:03 systemd
      2 ?        00:00:00 kthreadd
      3 ?        00:00:00 rcu_gp
      4 ?        00:00:00 rcu_par_gp
      5 ?        00:00:00 slub_flushwq
    547 ?        00:00:01 systemd-journal
    578 ?        00:00:00 systemd-udevd
    693 ?        00:00:00 cron
    694 ?        00:00:00 dbus-daemon
    712 ?        00:00:02 networkd-dispat
    713 ?        00:00:00 rsyslogd
    721 ?        00:00:01 systemd-logind
   1234 ?        00:00:05 docker
   2345 ?        00:01:23 python3
   3456 pts/0    00:00:00 bash
   4567 pts/0    00:00:00 vim
   5678 pts/0    00:00:00 ps
EOF

# Generate fake docker ps output
cat > "${DATA_DIR}/docker-ps-output.txt" << 'EOF'
CONTAINER ID   IMAGE          COMMAND                  CREATED        STATUS        PORTS                    NAMES
a1b2c3d4e5f6   nginx:latest   "/docker-entrypoint.…"   2 hours ago    Up 2 hours    0.0.0.0:80->80/tcp       web-server
b2c3d4e5f6a1   redis:alpine   "docker-entrypoint.s…"   3 hours ago    Up 3 hours    6379/tcp                 cache
c3d4e5f6a1b2   postgres:14    "docker-entrypoint.s…"   1 day ago      Up 1 day      0.0.0.0:5432->5432/tcp   database
d4e5f6a1b2c3   node:16        "docker-entrypoint.s…"   2 days ago     Up 2 days     3000/tcp                 api-server
EOF

# Generate fake diff output
cat > "${DATA_DIR}/diff-output.txt" << 'EOF'
--- file1.txt	2025-12-13 10:00:00.000000000 -0800
+++ file2.txt	2025-12-13 10:05:00.000000000 -0800
@@ -1,10 +1,12 @@
 This is a test file.
-This line will be removed.
+This line has been modified.
 This line stays the same.
 Another unchanged line.
-Delete this one too.
+This line is new.
 Keep this line.
+Add another new line here.
 Final line of the file.
+And one more addition.

 End of file.
+Extra line at the end.
EOF

# Generate a large log file for stress testing
echo "Generating large log file..."
for i in {1..1000}; do
    cat >> "${DATA_DIR}/large-log.txt" << EOF
2025-12-13 10:$(printf "%02d" $((i % 60))):$(printf "%02d" $((i % 60))) INFO Starting process $i
2025-12-13 10:$(printf "%02d" $((i % 60))):$(printf "%02d" $((i % 60))) DEBUG Connection established to 192.168.1.$((i % 255))
2025-12-13 10:$(printf "%02d" $((i % 60))):$(printf "%02d" $((i % 60))) WARNING Cache miss for key user_$i
2025-12-13 10:$(printf "%02d" $((i % 60))):$(printf "%02d" $((i % 60))) ERROR Failed to connect to database
2025-12-13 10:$(printf "%02d" $((i % 60))):$(printf "%02d" $((i % 60))) INFO Request completed in ${i}ms
EOF
done

echo "Test data generated in ${DATA_DIR}"
echo "Files created:"
ls -lh "${DATA_DIR}"
