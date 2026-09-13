FROM couchdb:3.5

USER root

# The base image imports the CouchDB apt key with curl and then purges it, so a
# boot-time provisioning step has nothing to make HTTP calls with. jq parses the
# cluster membership responses.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl jq; \
    rm -rf /var/lib/apt/lists/*; \
    command -v curl; \
    command -v jq; \
    command -v setpriv

COPY entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 0755 /usr/local/bin/railway-entrypoint.sh; \
    bash -n /usr/local/bin/railway-entrypoint.sh

# The base ENTRYPOINT is `tini -- /docker-entrypoint.sh`. Replacing CMD rather than
# declaring an ENTRYPOINT keeps tini and the vendor entrypoint's chown, admin-ini
# and setpriv drop, which this wrapper re-enters on its final exec.
CMD ["/usr/local/bin/railway-entrypoint.sh"]
