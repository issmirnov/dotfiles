| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `cat /home/vania/.dotfiles/benchmarks/test-data/ping-output.txt \| /home/vania/.dotfiles/benchmarks/../bin/grcat /home/vania/.dotfiles/benchmarks/../grc/conf.ping` | 21.8 ± 3.1 | 18.3 | 32.9 | 1.00 |
| `cat /home/vania/.dotfiles/benchmarks/test-data/ps-output.txt \| /home/vania/.dotfiles/benchmarks/../bin/grcat /home/vania/.dotfiles/benchmarks/../grc/conf.ps` | 22.6 ± 5.7 | 18.7 | 74.9 | 1.04 ± 0.30 |
| `cat /home/vania/.dotfiles/benchmarks/test-data/large-log.txt \| /home/vania/.dotfiles/benchmarks/../bin/grcat /home/vania/.dotfiles/benchmarks/../grc/conf.log` | 75.8 ± 2.5 | 72.4 | 83.6 | 3.48 ± 0.51 |
