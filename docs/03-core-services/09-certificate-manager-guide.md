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

```mermaid
---
title: Certificate Manager Architecture
---
flowchart TB
    subgraph certmgr["phosphor-certificate-manager"]
        direction LR
        https["HTTPS Certs<br/>(/etc/ssl/certs/https/)"]
        ldapcert["LDAP Certs<br/>(/etc/ssl/certs/ldap/)"]
        authority["Authority Certs<br/>(Trusted CAs)"]
        csr["CSR Generation<br/>(Signing Req)"]
    end

    subgraph consumers["Certificate Consumers"]
        direction LR
        bmcweb["bmcweb<br/>(HTTPS server)"]
        ldapclient["LDAP Client<br/>(secure auth)"]
    end

    certmgr --> consumers
```

<details markdown="1">
<summary>ASCII-art version (for comparison)</summary>

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

</details>

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

## Deep Dive
{: .text-delta }

Advanced implementation details for certificate management developers.

### X.509 Certificate Chain Validation

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    Certificate Chain Validation Flow                       │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  INCOMING CERTIFICATE CHAIN                                                │
│  ──────────────────────────                                                │
│                                                                            │
│  ┌─────────────────────┐                                                   │
│  │   Leaf Certificate  │  Subject: CN=bmc.example.com                      │
│  │   (Server Cert)     │  Issuer: CN=Intermediate CA                       │
│  │                     │  Key Usage: Digital Signature, Key Encipherment   │
│  │                     │  Ext Key Usage: TLS Web Server Authentication     │
│  └──────────┬──────────┘                                                   │
│             │ Signed by                                                    │
│             v                                                              │
│  ┌─────────────────────┐                                                   │
│  │ Intermediate CA     │  Subject: CN=Intermediate CA                      │
│  │ Certificate         │  Issuer: CN=Root CA                               │
│  │                     │  Basic Constraints: CA:TRUE, pathLen:0            │
│  │                     │  Key Usage: Certificate Sign, CRL Sign            │
│  └──────────┬──────────┘                                                   │
│             │ Signed by                                                    │
│             v                                                              │
│  ┌─────────────────────┐                                                   │
│  │   Root CA           │  Subject: CN=Root CA (self-signed)                │
│  │   Certificate       │  Issuer: CN=Root CA                               │
│  │   (Trust Anchor)    │  Basic Constraints: CA:TRUE                       │
│  └─────────────────────┘                                                   │
│                                                                            │
│  VALIDATION STEPS (OpenSSL in phosphor-certificate-manager):               │
│  ──────────────────────────────────────────────────────────                │
│                                                                            │
│  1. PARSE CERTIFICATE CHAIN                                                │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │ PEM_read_bio_X509() for each certificate in chain               │    │
│     │ Build X509_STORE with trusted root CAs from /etc/ssl/certs/     │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│                                                                            │
│  2. VERIFY CERTIFICATE SIGNATURES                                          │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │ X509_verify(leaf_cert, intermediate_pubkey) == 1                │    │
│     │ X509_verify(intermediate_cert, root_pubkey) == 1                │    │
│     │ X509_verify(root_cert, root_pubkey) == 1 (self-signed)          │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│                                                                            │
│  3. CHECK VALIDITY PERIOD                                                  │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │ X509_cmp_current_time(X509_get_notBefore(cert)) <= 0            │    │
│     │ X509_cmp_current_time(X509_get_notAfter(cert)) >= 0             │    │
│     │                                                                 │    │
│     │ notBefore ──────────── NOW ──────────── notAfter                │    │
│     │     ✓                   │                   ✓                   │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│                                                                            │
│  4. VERIFY KEY USAGE & EXTENDED KEY USAGE                                  │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │ For HTTPS server certificate:                                   │    │
│     │   - digitalSignature bit must be set                            │    │
│     │   - keyEncipherment bit must be set (RSA) OR                    │    │
│     │   - keyAgreement bit must be set (ECDH)                         │    │
│     │   - extKeyUsage: id-kp-serverAuth (1.3.6.1.5.5.7.3.1)           │    │
│     │                                                                 │    │
│     │ For LDAP client certificate:                                    │    │
│     │   - extKeyUsage: id-kp-clientAuth (1.3.6.1.5.5.7.3.2)           │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│                                                                            │
│  5. BUILD TRUST CHAIN TO ROOT                                              │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │ X509_STORE_CTX_init(ctx, store, leaf_cert, intermediates)       │    │
│     │ X509_verify_cert(ctx)                                           │    │
│     │                                                                 │    │
│     │ Result: X509_V_OK (0) or error code                             │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Certificate Storage and File Format

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    Certificate Storage Architecture                        │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  /etc/ssl/                                                                 │
│  ├── certs/                                                                │
│  │   ├── https/                                                            │
│  │   │   ├── server.pem          ← HTTPS server cert + private key         │
│  │   │   └── authority/          ← Trusted CA certs for client auth        │
│  │   │       ├── ca1.pem                                                   │
│  │   │       └── ca2.pem                                                   │
│  │   └── ldap/                                                             │
│  │       └── client.pem          ← LDAP client certificate                 │
│  └── private/                                                              │
│      └── server.pem              ← Private key (mode 0600)                 │
│                                                                            │
│  COMBINED PEM FILE FORMAT (server.pem):                                    │
│  ─────────────────────────────────────                                     │
│                                                                            │
│  -----BEGIN PRIVATE KEY-----                                               │
│  MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC...                    │
│  ... (Base64 encoded private key) ...                                      │
│  -----END PRIVATE KEY-----                                                 │
│  -----BEGIN CERTIFICATE-----                                               │
│  MIIDXTCCAkWgAwIBAgIJAJC1HiIAZAiUMA0GCSqGSIb3Qq...                         │
│  ... (Base64 encoded server certificate) ...                               │
│  -----END CERTIFICATE-----                                                 │
│  -----BEGIN CERTIFICATE-----                                               │
│  MIIDrzCCApegAwIBAgIQCDvgVpBCRrGhdWrJWZHHSj...                             │
│  ... (Base64 encoded intermediate CA - optional) ...                       │
│  -----END CERTIFICATE-----                                                 │
│                                                                            │
│  D-BUS OBJECT STRUCTURE:                                                   │
│  ─────────────────────                                                     │
│                                                                            │
│  /xyz/openbmc_project/certs                                                │
│  ├── server                                                                │
│  │   └── https                                                             │
│  │       └── 1                   ← Certificate object                      │
│  │           ├── xyz.openbmc_project.Certs.Certificate                     │
│  │           │   ├── CertificateString (PEM)                               │
│  │           │   ├── Subject                                               │
│  │           │   ├── Issuer                                                │
│  │           │   ├── ValidNotBefore                                        │
│  │           │   └── ValidNotAfter                                         │
│  │           └── xyz.openbmc_project.Object.Delete                         │
│  └── authority                                                             │
│      └── truststore                                                        │
│          ├── 1                   ← CA certificate 1                        │
│          └── 2                   ← CA certificate 2                        │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### CSR Generation Process

```
┌────────────────────────────────────────────────────────────────────────────┐
│                   Certificate Signing Request (CSR) Flow                   │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  REDFISH CSR REQUEST                                                       │
│  ───────────────────                                                       │
│  POST /redfish/v1/CertificateService/Actions/                              │
│       CertificateService.GenerateCSR                                       │
│  {                                                                         │
│      "CommonName": "bmc.example.com",                                      │
│      "Organization": "ACME Corp",                                          │
│      "OrganizationalUnit": "IT",                                           │
│      "City": "San Francisco",                                              │
│      "State": "CA",                                                        │
│      "Country": "US",                                                      │
│      "AlternativeNames": ["bmc", "192.168.1.100"],                         │
│      "KeyPairAlgorithm": "EC",                                             │
│      "KeyCurveId": "secp384r1"                                             │
│  }                                                                         │
│                                                                            │
│  CSR GENERATION STEPS:                                                     │
│  ────────────────────                                                      │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  1. Generate Key Pair                                               │   │
│  │     ────────────────────                                            │   │
│  │     // For EC key (recommended)                                     │   │
│  │     EVP_PKEY* pkey = EVP_EC_gen("secp384r1");                       │   │
│  │                                                                     │   │
│  │     // For RSA key                                                  │   │
│  │     EVP_PKEY* pkey = EVP_RSA_gen(2048);                             │   │
│  └────────────────────────────────────────────────────────────────────-┘   │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  2. Create CSR Structure                                            │   │
│  │     ─────────────────────                                           │   │
│  │     X509_REQ* req = X509_REQ_new();                                 │   │
│  │     X509_REQ_set_pubkey(req, pkey);                                 │   │
│  │     X509_REQ_set_version(req, 0);  // Version 1                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  3. Set Subject Distinguished Name                                  │   │
│  │     ────────────────────────────                                    │   │
│  │     X509_NAME* name = X509_REQ_get_subject_name(req);               │   │
│  │     X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,            │   │
│  │                                "bmc.example.com", -1, -1, 0);       │   │
│  │     X509_NAME_add_entry_by_txt(name, "O", MBSTRING_ASC,             │   │
│  │                                "ACME Corp", -1, -1, 0);             │   │
│  │     // ... additional fields                                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  4. Add Subject Alternative Names (SAN) Extension                   │   │
│  │     ──────────────────────────────────────────                      │   │
│  │     STACK_OF(X509_EXTENSION)* exts = sk_X509_EXTENSION_new_null();  │   │
│  │     X509_EXTENSION* san_ext = X509V3_EXT_conf_nid(                  │   │
│  │         NULL, NULL, NID_subject_alt_name,                           │   │
│  │         "DNS:bmc,DNS:bmc.example.com,IP:192.168.1.100");            │   │
│  │     sk_X509_EXTENSION_push(exts, san_ext);                          │   │
│  │     X509_REQ_add_extensions(req, exts);                             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  5. Sign CSR with Private Key                                       │   │
│  │     ──────────────────────────                                      │   │
│  │     X509_REQ_sign(req, pkey, EVP_sha384());                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  6. Output PEM-encoded CSR                                          │   │
│  │     ─────────────────────                                           │   │
│  │     -----BEGIN CERTIFICATE REQUEST-----                             │   │
│  │     MIICpDCCAYwCAQAwXzELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNB...         │   │
│  │     ... (Base64 encoded CSR) ...                                    │   │
│  │     -----END CERTIFICATE REQUEST-----                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  7. Store private key in /etc/ssl/private/ (mode 0600)                     │
│  8. Return CSR to administrator for CA signing                             │
│  9. After signing, install certificate via Replace action                  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Service Restart Integration

```
┌────────────────────────────────────────────────────────────────────────────┐
│              Certificate Installation Service Integration                  │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  Certificate Installed                                                     │
│         │                                                                  │
│         v                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  phosphor-certificate-manager                                       │   │
│  │                                                                     │   │
│  │  1. Write certificate to filesystem                                 │   │
│  │     install(cert_pem, "/etc/ssl/certs/https/server.pem")            │   │
│  │                                                                     │   │
│  │  2. Set proper permissions                                          │   │
│  │     chmod 0644 server.pem (cert)                                    │   │
│  │     chmod 0600 private key                                          │   │
│  │                                                                     │   │
│  │  3. Notify dependent services via D-Bus                             │   │
│  │     Certificate.Install signal                                      │   │
│  └────────────────────────────────────────────────────────────────────-┘   │
│         │                                                                  │
│         v                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Service Restart Mechanism                                          │   │
│  │                                                                     │   │
│  │  Option 1: systemd unit dependency (phosphor-certificate-manager)   │   │
│  │    [Unit]                                                           │   │
│  │    PropagatesReloadTo=bmcweb.service                                │   │
│  │                                                                     │   │
│  │  Option 2: Direct service restart                                   │   │
│  │    sd_bus_call_method(                                              │   │
│  │        bus, "org.freedesktop.systemd1",                             │   │
│  │        "/org/freedesktop/systemd1",                                 │   │
│  │        "org.freedesktop.systemd1.Manager",                          │   │
│  │        "RestartUnit", "bmcweb.service", "replace"                   │   │
│  │    );                                                               │   │
│  │                                                                     │   │
│  │  Option 3: Service watches certificate file                         │   │
│  │    inotify_add_watch(fd, "/etc/ssl/certs/https/", IN_MODIFY)        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│         │                                                                  │
│         v                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  bmcweb SSL Context Reload                                          │   │
│  │                                                                     │   │
│  │  SSL_CTX_use_certificate_chain_file(ctx, "/etc/ssl/.../server.pem") │   │
│  │  SSL_CTX_use_PrivateKey_file(ctx, "/etc/ssl/.../server.pem")        │   │
│  │                                                                     │   │
│  │  New connections use new certificate                                │   │
│  │  Existing connections continue with old cert until closed           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Source Code Reference

Key implementation files in [phosphor-certificate-manager](https://github.com/openbmc/phosphor-certificate-manager):

| File | Description |
|------|-------------|
| `certificate.cpp` | Certificate class with X.509 parsing and validation |
| `certs_manager.cpp` | Main certificate manager handling install/replace/delete |
| `csr.cpp` | CSR generation using OpenSSL |
| `argument.cpp` | CLI argument parsing for certificate types |
| `watch.cpp` | Filesystem watcher for certificate changes |

---

## References

- [phosphor-certificate-manager](https://github.com/openbmc/phosphor-certificate-manager)
- [Redfish CertificateService](https://redfish.dmtf.org/schemas/CertificateService.v1_0_3.json)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
