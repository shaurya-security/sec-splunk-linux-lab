# Sigma authentication detections

These experimental rules cover the lab's configured telemetry:

- Linux endpoint: `index=linux_endpoint`, sourcetype `linux_audit`, from `/var/log/audit/audit.log`.
- Splunk host: the same auditd log path is collected locally into `index=linux_audit`, sourcetype `linux_audit`.
- Windows endpoint: `index=windows_endpoint`, Security channel with XML rendering (`renderXml = true`), which Splunk labels `sourcetype=XmlWinEventLog`, `source=XmlWinEventLog:Security`.
- Universal Forwarder inputs are defined in `terraform/lab/userdata/linux-endpoint.sh` and `terraform/lab/userdata/windows-endpoint.sh`; the receiving Splunk host and its add-ons are configured in `terraform/lab/userdata/splunk-install.sh`.

## Splunk add-ons

Field extraction happens at search time on the Splunk host, so the add-ons are installed there only. The Universal Forwarders need none. `splunk-install.sh` extracts every `.tgz`/`.spl` found under `apps/` in the userdata bucket and reports each expected add-on as `OK` or `WARNING` in `/var/log/splunk-install.log`.

| Add-on | Directory | Splunkbase | Provides |
|---|---|---|---|
| Splunk Add-on for Microsoft Windows | `Splunk_TA_windows` | 742 | `XmlWinEventLog` field extractions (`EventCode`, `TargetUserName`, `IpAddress`, `LogonType`, ...) |
| Splunk Add-on for Unix and Linux | `Splunk_TA_nix` | 833 | `linux_audit` sourcetype handling (Splunk-supported; documented CIM Authentication/Change mapping) |

Download the package versions that Splunkbase lists as compatible with Splunk Enterprise 10.4 and upload them under `apps/`; the file name does not matter:

```bash
aws s3 cp ./<windows-addon>.tgz s3://shaurya-terraform-userdata-2026/apps/
aws s3 cp ./<unix-linux-addon>.tgz s3://shaurya-terraform-userdata-2026/apps/
```

The archived community "Linux Auditd" add-on (Splunkbase 4232) is not used: it lists support only up to Splunk 9.4.

## Rules

File names follow `<logsource>_<description>.yml`; correlation rules add a `corr_` prefix.

| File | Rule | Level |
|---|---|---|
| `linux/lnx_auditd_ssh_failed_auth.yml` | Failed `sshd` `USER_AUTH` / `USER_LOGIN` auditd records | low |
| `windows/win_security_failed_logon.yml` | Individual failed logons, Event ID `4625` | low |
| `correlation/corr_lnx_auditd_ssh_brute_force.yml` | More than 5 SSH failures in 5 minutes for one account, source, and host | medium |
| `correlation/corr_win_security_brute_force.yml` | More than 5 failed logons in 5 minutes for one account, source, and host | medium |
| `correlation/corr_lnx_auditd_ssh_password_spray.yml` | More than 10 distinct accounts in 10 minutes from one source to one host | high |
| `correlation/corr_win_security_password_spray.yml` | More than 10 distinct accounts in 10 minutes from one source to one host | high |

Thresholds are starting values for this lab; tune them using observed event volume before enabling alerts.

## Conventions

- Metadata order and style follow the Sigma specification and SigmaHQ conventions: 4-space indentation, descriptions starting with "Detects", ISO `date`/`modified`, `experimental` status for new rules.
- ATT&CK mappings are tags only (tactic in the hyphenated form, e.g. `attack.credential-access`), not reference links. Event rules carry the parent technique `attack.t1110`; correlation rules carry the specific sub-technique: `attack.t1110.001` for brute force and `attack.t1110.003` for password spray.
- Rules use each log source's native field names, so they stay portable to other backends. Splunk-specific scoping and renaming lives in one place, `pipelines/lab_splunk.yml`.
- `Computer` is the one logical field shared by both operating systems. Auditd records carry no host key, so the pipeline maps `Computer` to the Splunk `host` field for Linux and Windows.

## Splunk field and index mapping

The pipeline scopes rules by logsource and renames fields:

| Logsource | Added scope | Field renames |
|---|---|---|
| `product: windows`, `service: security` | `index=windows_endpoint source="XmlWinEventLog:Security"` | `EventID` -> `EventCode`, `Computer` -> `host` |
| `product: linux`, `service: auditd` | `index IN (linux_endpoint, linux_audit)`, `sourcetype=linux_audit` | `Computer` -> `host` |

Fields the rules read, and where each comes from:

| Sigma field | Linux auditd | Windows Security (XML) |
|---|---|---|
| `type`, `exe`, `res` | Raw auditd keys (`type=`, `exe=`, `res=`). `res` is matched with `startswith` because the extracted value can carry the closing quote of `msg='...'`. | Not used |
| `acct`, `addr` | Raw auditd keys: account name and remote address. | Not used |
| `EventID` | Not used | Extracted as `EventCode` by `Splunk_TA_windows` |
| `TargetUserName`, `IpAddress`, `LogonType` | Not used | `Data` elements of the Security event, extracted by `Splunk_TA_windows` |
| `Computer` | Mapped to `host` (expected `linux-endpoint-01`) | Mapped to `host` (expected `windows-endpoint-01`) |

## Convert to SPL

```bash
pip install sigma-cli pysigma-backend-splunk
sigma convert -t splunk -p detections/sigma/pipelines/lab_splunk.yml detections/sigma/
```

Use this pipeline on its own. The built-in `splunk_windows` pipeline scopes Windows rules to `source="WinEventLog:Security"` (classic format), which would not match the lab's XML-rendered events. Correlation support and the renaming of correlation `group-by` fields depend on the pySigma and backend versions: inspect the generated SPL and confirm each `stats ... by` clause uses `host`, `addr`, `acct`, `IpAddress`, or `TargetUserName` as intended before creating alerts. Run `sigma check detections/sigma/` for rule validation.

Normalize Windows placeholder source addresses such as `-` and loopback values to null and exclude them from source-based correlations.

## Verify fields after deployment

Run these in Search & Reporting once events have arrived. Each counted field should be close to `events`; a count of `0` means the add-on is missing or the extraction is not applied.

```spl
index=windows_endpoint source="XmlWinEventLog:Security" EventCode=4625
| stats count AS events count(TargetUserName) AS TargetUserName count(IpAddress) AS IpAddress count(LogonType) AS LogonType BY host
```

```spl
(index=linux_endpoint OR index=linux_audit) sourcetype=linux_audit (type=USER_AUTH OR type=USER_LOGIN)
| stats count AS events count(acct) AS acct count(addr) AS addr count(exe) AS exe count(res) AS res BY index host
```

```spl
(index=linux_endpoint OR index=linux_audit) sourcetype=linux_audit type=USER_AUTH
| stats count BY res
```

If `EventCode` is empty for Windows events, check `index=windows_endpoint | stats count BY sourcetype source` first: events labelled `XmlWinEventLog` need `Splunk_TA_windows`. On the Splunk host, `$SPLUNK_HOME/bin/splunk btool props list XmlWinEventLog --debug` should show lines from `etc/apps/Splunk_TA_windows/`.

If the auditd fields are empty, the raw events can still be searched while you adjust extraction, for example:

```spl
index=linux_endpoint sourcetype=linux_audit type=USER_AUTH res=failed*
| rex field=_raw "acct=\"(?<acct>[^\"]*)\""
| rex field=_raw "addr=(?<addr>\S+)"
| stats count BY acct addr host
```

## Validation and coverage limits

1. Confirm auditd events arrive in `linux_endpoint` and Windows audit policy emits Security Event ID `4625`.
2. Test each event-level rule against representative raw events, then test correlations with controlled events and check grouping, time windows, and thresholds.
3. Tune false positives and thresholds before creating alert actions.

The endpoint security groups intentionally have no inbound rules and Session Manager is the access path. These rules detect authentication failures that are logged; they do not imply that internet SSH or RDP attempts can reach the endpoints. Do not open public SSH/RDP for testing. Use controlled local or synthetic events instead.
