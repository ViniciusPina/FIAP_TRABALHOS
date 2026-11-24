// =============================================================================
// Kea D2 (DHCP-DDNS): recebe pedidos do kea-dhcp4 e atualiza o BIND.
// __TSIG_SECRET__ e substituido no start pelo segredo gerado no pki-init.
// =============================================================================
{
  "DhcpDdns": {
    "ip-address": "127.0.0.1",
    "port": 53001,
    "dns-server-timeout": 1000,

    "control-socket": {
      "socket-type": "unix",
      "socket-name": "/run/kea/kea-ddns-ctrl-socket"
    },

    "tsig-keys": [
      { "name": "ddns-key", "algorithm": "HMAC-SHA256", "secret": "__TSIG_SECRET__" }
    ],

    "forward-ddns": {
      "ddns-domains": [
        {
          "name": "vinheria.local.",
          "key-name": "ddns-key",
          "dns-servers": [ { "ip-address": "10.50.0.2", "port": 53 } ]
        }
      ]
    },

    "reverse-ddns": {
      "ddns-domains": [
        {
          "name": "0.50.10.in-addr.arpa.",
          "key-name": "ddns-key",
          "dns-servers": [ { "ip-address": "10.50.0.2", "port": 53 } ]
        }
      ]
    },

    "loggers": [
      {
        "name": "kea-dhcp-ddns",
        "output-options": [
          { "output": "stdout", "pattern": "%D{%Y-%m-%d %H:%M:%S.%q} %-5p [%c/%i] %m\n" }
        ],
        "severity": "INFO"
      }
    ]
  }
}
