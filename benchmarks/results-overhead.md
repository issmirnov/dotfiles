| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `cat /home/vania/.dotfiles/benchmarks/test-data/large-log.txt` | 1.5 ± 1.3 | 0.0 | 7.0 | 1.00 |
| `cat /home/vania/.dotfiles/benchmarks/test-data/large-log.txt \| /home/vania/.dotfiles/benchmarks/../bin/grcat /home/vania/.dotfiles/benchmarks/../grc/conf.log` | 75.5 ± 2.6 | 72.4 | 82.9 | 50.15 ± 43.19 |
