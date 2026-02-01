---
layout: default
title: Certificate Manager Guide
parent: Core Services
nav_order: 9
difficulty: intermediate
prerequisites:
  - dbus-guide
  - redfish-guide
---

# Certificate Manager Guide
{: .no_toc }

Configure TLS/SSL certificates for secure BMC communication.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**phosphor-certificate-manager** manages X.509 certificates for HTTPS, LDAP, and other secure services on OpenBMC.

```
+-------------------------------------------------------------------+
|                Certificate Manager Architecture                   |
+-------------------------------------------------------------------+
|                                                                   |
|  +------------------------------------------------------------+   |
|  |             phosphor-certificate-manager                   |   |
|  |                                                            |   |
|  |   +------------------+  +------------------+               |   |
|  |   | HTTPS Certs      |  | LDAP Certs       |               |   |
|  |   | (/etc/ssl/certs/ |  | (/etc/ssl/certs/ |               |   |
|  |   |  https/)         |  |  ldap/)          |               |   |
|  |   +------------------+  +------------------+               |   |
|  |                                                            |   |
|  |   +------------------+  +------------------+               |   |
|  |   | Authority Certs  |  | CSR Generation   |               |   |
|  |   | (Trusted CAs)    |  | (Signing Req)    |               |   |
|  |   +------------------+  +------------------+               |   |
|  |                                                            |   |
|  +----------------------------+-------------------------------+   |
|                               |                                   |
|           +-------------------+-------------------+               |
|           |                                       |               |
|           v                                       v               |
|  +------------------+                   +------------------+      |
|  |     bmcweb       |                   |   LDAP Client    |      |
|  |  (HTTPS server)  |                   |  (secure auth)   |      |
|  +------------------+                   +------------------+      |
|                                                                   |
+-------------------------------------------------------------------+
```

---

## Setup & Configuration

### Build-Time Configuration

```bitbake
# Include certificate manager
IMAGE_INSTALL:append = " phosphor-certificate-manager"
```

### Certificate Locations

| Type | Path | Description |
|------|------|-------------|
| HTTPS Server | /etc/ssl/certs/https/server.pem | Web server certificate |
| HTTPS CA | /etc/ssl/certs/https/authority/ | Trusted CA certificates |
| LDAP Client | /etc/ssl/certs/ldap/ | LDAP client certificates |

---

## Managing Certificates

### View Current Certificate

```bash
# Via Redfish
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/CertificateService/CertificateLocations

# View certificate details
openssl x509 -in /etc/ssl/certs/https/server.pem -text -noout
```

### Generate Self-Signed Certificate

```bash
# Generate on BMC
openssl req -x509 -newkey rsa:2048 \
    -keyout /etc/ssl/private/server.pem \
    -out /etc/ssl/certs/https/server.pem \
    -days 365 -nodes \
    -subj "/CN=openbmc/O=MyOrg"

# Restart bmcweb
systemctl restart bmcweb
```

### Replace Certificate via Redfish

```bash
# Replace HTTPS certificate
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "CertificateType": "PEM",
        "CertificateString": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"
    }' \
    https://localhost/redfish/v1/Managers/bmc/NetworkProtocol/HTTPS/Certificates

# Generate CSR
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "CommonName": "bmc.example.com",
        "Organization": "MyOrg",
        "Country": "US"
    }' \
    https://localhost/redfish/v1/CertificateService/Actions/CertificateService.GenerateCSR
```

### Add CA Certificate

```bash
# Add trusted CA
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "CertificateType": "PEM",
        "CertificateString": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"
    }' \
    https://localhost/redfish/v1/Managers/bmc/Truststore/Certificates
```

---

## References

- [phosphor-certificate-manager](https://github.com/openbmc/phosphor-certificate-manager)
- [Redfish CertificateService](https://redfish.dmtf.org/schemas/CertificateService.v1_0_3.json)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
