# Troubleshooting

Check service logs first. Keep detailed output private; use synthetic names if
you report a problem publicly.

## The service retries without an HTTP listener

Prometheus exits `10` when its first MQ connection fails. It does not open the HTTP
listener first. The service retries after 15 seconds. Check the queue-manager
name, MQ installation, connection settings and the service account's MQ permissions.
For OTel, the equivalent first-connection failure normally exits `1`.

## HTTP works but metrics are missing

Run `mq-dist health` with the exact queue-manager name. Prometheus status `2`
means connected/running; `0` can follow the loss of an established connection.
HTTP 200 alone is not a health result. If the connection is healthy, check queue
patterns, exclusions and permissions, then compare observed queues with the
intended set. OTel delivery must be checked at its receiver, not with this helper.

## Windows reports a missing DLL

Check the installed MQ runtime and its prerequisites. MQ 9.3.0.27 client imports
include `VCRUNTIME140.dll` and `VCRUNTIME140_1.dll`. Install the appropriate
supported x64 Visual C++ runtime through your normal software-management process.
Do not copy DLLs from an unrelated workstation into the exporter directory.
Use the archive's `diagnose.ps1` to collect read-only platform details.

## curl or package tools load MQ libraries

MQ and system packages can provide libraries with the same name, including
`libcurl.so.4`. Loader-cache resolution can cause conflicts even when
`LD_LIBRARY_PATH` is unset. The installer gives system download utilities a
command-local `/usr/lib64:/lib64` path and gives the exporter its selected MQ path.
Do not export a system-only path globally, edit loader policy or remove MQ libraries.

## A file is readable in a shell but not by the service

Check the service account and service namespace. On Linux, `ProtectHome` hides
home directories from the service. Move the required file to a protected service
configuration location and update the path. On Windows, check the account's ACL
access and Log on as a service right. Do not solve access errors by running the
exporter as an administrator.

## A download or update fails

Keep HTTPS certificate verification enabled. Linux curl uses the normal proxy
variables and `CURL_CA_BUNDLE`; Windows uses its configured proxy and trust store.
For offline installation, transfer matching versioned assets and trusted checksums.

A checksum failure means installation must stop. Download the matching files
again through your approved channel. Do not edit the checksum to accept a file.
After an installation failure, inspect the reported error and `.bak-*` files.
Binary backup safety does not imply rollback of every configuration or service edit.
