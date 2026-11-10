# Benchmarks

`make bench N=2 RUNS=3` deletes and recreates VM N three times with `make reset`, times
each step and writes a report here: `<date>-reset.md`. The logins are kept, so a run
needs no input. Run it on your host and compare.

| Date | Host | Reset (median) | Report |
| --- | --- | ---: | --- |
| 2026-11-10 | MacBook Pro M1, 16 GB, macOS 27.0.1 | 69 s | [2026-11-10-reset.md](2026-11-10-reset.md) |

Most of a reset is the macOS boot (about 34 s). The other steps are scripts that talk to
the VM through the Tart guest agent.

## Other numbers from the same host

| What | Value |
| --- | --- |
| A browser task in a T3 thread (open 5 pages, write a table) | 3–4 minutes, with both VMs busy at the same time |
| Host RAM used by two running VMs (6 GB each) | 6.3 GB resident |
