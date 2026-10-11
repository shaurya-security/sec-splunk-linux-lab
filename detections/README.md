# Detections (SPL)

Two scheduled Splunk alerts, written directly in SPL. No Sigma layer.

| Saved search | SPL | Fires when (5-minute window, runs every minute) |
|---|---|---|
| Linux SSH Brute Force | `spl/linux_ssh_brute_force.spl` | more than 5 failed `sshd` auth records from one `addr` against one `host` |
| Windows Failed Logon Brute Force | `spl/windows_failed_logon_brute_force.spl` | more than 5 Event ID 4625 from one `src_ip` (`IpAddress`; `-` and loopback ignored) against one `host` |

`deployment.yml` holds schedule, window, severity and alert settings. Email is disabled until SMTP and a
real recipient are verified; `alert.track=1` keeps triggered-alert history as the active notification path.

## Data sources and add-ons

- Linux: `index IN (linux_endpoint, linux_audit)`, `sourcetype=linux_audit`; needs `Splunk_TA_nix`.
- Windows: `index=windows_endpoint source="XmlWinEventLog:Security"` (XML-rendered); needs `Splunk_TA_windows`.
- Fields used: Linux `type exe res acct addr host`; Windows `EventCode TargetUserName IpAddress host`.

## Deploy

```bash
python3 tools/deploy_searches.py                  # dry run
tools/release.sh <bucket> <splunk-instance-id> <password-ssm-param>           # create disabled, via SSM
tools/release.sh <bucket> <splunk-instance-id> <password-ssm-param> --apply   # (add --enable after review)
```

The client calls Splunk on 127.0.0.1:8089 from the Splunk host; port 8089 stays closed. Note `release.sh`
passes `--apply`/`--enable` straight through; without `--apply` it is a dry run on the host.

## Verify fields after deployment

Each counted field should be close to `events`; `0` means the add-on is missing.

```spl
index=windows_endpoint source="XmlWinEventLog:Security" EventCode=4625
| stats count AS events count(TargetUserName) AS TargetUserName count(IpAddress) AS IpAddress BY host
```

```spl
(index=linux_endpoint OR index=linux_audit) sourcetype=linux_audit (type=USER_AUTH OR type=USER_LOGIN)
| stats count AS events count(acct) AS acct count(addr) AS addr count(exe) AS exe count(res) AS res BY index host
```

If `EventCode` is empty, check `Splunk_TA_windows` with
`$SPLUNK_HOME/bin/splunk btool props list XmlWinEventLog --debug`. If auditd fields are empty, fall back to
`rex field=_raw "acct=\"(?<acct>[^\"]*)\""` and `rex field=_raw "addr=(?<addr>\S+)"` while fixing extraction.

## Limits

Thresholds are lab starting values. Overlapping windows can re-alert every minute; add throttling if noisy.
Endpoints have no inbound SSH/RDP: test with synthetic or local events, never by opening public access.
