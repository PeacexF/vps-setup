### This package of Scripts is used for configuring postfix and dovecot

### Recomended to set up ufw and basic hardening before running these

**Structure (unfinished)**:
``` text
bundle/
├── install.sh
├── config.env
├── lib/
│   ├── common.sh
│   ├── validation.sh
│   ├── backup.sh
│   ├── logging.sh
│   └── service.sh
│
├── modules/
│   ├── 00-preflight.sh
│   ├── 01-packages.sh
│   ├── 02-hostname.sh
│   ├── 03-tls.sh
│   ├── 04-postfix-base.sh
│   ├── 05-postfix-submission.sh
│   ├── 06-dovecot-base.sh
│   ├── 07-maildir.sh
│   ├── 08-auth.sh
│   ├── 09-security.sh
│   ├── 10-systemd.sh
│   ├── 11-healthcheck.sh
│   └── 12-summary.sh
│
├── templates/
│   ├── postfix/
│   ├── dovecot/
│   └── systemd/
│
├── state/
│   ├── installed_modules/
│   └── backups/
│
├── logs/
│   └── setup.log
│
└── rollback/
    ├── rollback-postfix.sh
    └── rollback-dovecot.sh
```