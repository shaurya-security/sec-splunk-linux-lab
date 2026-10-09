# Sigma authentication detections

These experimental rules cover the current lab telemetry:

- Linux event source: `linux_endpoint`, sourcetype `linux_secure`, from `/var/log/secure`.
- Windows event source: `windows_endpoint`, Security channel with XML rendering, including failed-logon Event ID `4625`.
- Linux and Windows Universal Forwarder inputs are defined in `terraform/lab/userdata/linux-endpoint.sh` and `terraform/lab/userdata/windows-endpoint.sh`.

## Rules

- `linux/linux_ssh_failed_auth.yml`: individual failed SSH authentication events.
- `windows/windows_failed_logon.yml`: individual Windows failed-logon events.
- `correlation/linux_ssh_brute_force.yml` and `correlation/windows_logon_brute_force.yml`: more than five failures in five minutes for the same source, host, and account.
- `correlation/linux_ssh_password_spray.yml` and `correlation/windows_password_spray.yml`: failures against more than ten distinct accounts in ten minutes from one source to one host.

Thresholds are starting values for this lab; tune them using observed event volume before enabling alerts.

## Splunk field and index mapping

Sigma logsource metadata identifies event semantics; it does not constrain Splunk searches to these indexes. Configure the Sigma-to-Splunk conversion/deployment to scope Linux rules to `index=linux_endpoint` and Windows rules to `index=windows_endpoint`.

Before deploying, inspect raw events and confirm or normalize these fields:

| Sigma field | Linux source | Windows Security source |
|---|---|---|
| `message` | Map to the raw event (`_raw`) or an extracted message field. | Not used by the Windows event rule. |
| `SourceIp` | Extract the remote address from the secure-log message. | Map from the event's `IpAddress` field. |
| `User` | Extract the account from the secure-log message. | Map from `TargetUserName` if using a shared normalized schema. |
| `ComputerName` | Map from the event host, expected to be `linux-endpoint-01`. | Map from the event host, expected to be `windows-endpoint-01`. |
| `EventID` | Not used by the Linux event rule. | Map to the actual extracted event ID field (often `EventCode` or `EventID`). |
| `TargetUserName`, `IpAddress` | Not used directly by the Linux event rule. | Confirm these are extracted from the XML-rendered Security event. |

The correlation rules require the group-by fields to be present on the matched events. In particular, Linux correlation will not work until source address and account extraction are confirmed. Sigma correlation support and field mapping vary by backend; convert and inspect the generated SPL before deployment.
For Windows, normalize placeholder source addresses such as `-` and loopback values to null and exclude them from source-based correlations; otherwise unrelated local failures can be grouped together.

## Validation and coverage limits

1. Confirm failed authentication events arrive in each index and that Windows audit policy emits Event ID `4625`.
2. Test the event-level rule against raw representative events, then test correlation with controlled events and check grouping, time windows, and thresholds.
3. Tune false positives and thresholds before creating alert actions.

The endpoint security groups intentionally have no inbound rules and Session Manager is the access path. These rules detect authentication failures that are logged; they do not imply that internet SSH or RDP attempts can reach the endpoints. Do not open public SSH/RDP for testing. Use controlled local or synthetic events instead.
