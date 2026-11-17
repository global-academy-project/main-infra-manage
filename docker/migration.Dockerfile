FROM flyway/flyway:13.12-alpine

USER 65003:65003

COPY --chown=65003:65003 db/migration/ /flyway/sql/

CMD [ \
    "-url=jdbc:mysql://mysql-service:3306/agent_kb?allowPublicKeyRetrieval=true", \
    "-user=kb_owner", \
    "-validateMigrationNaming=true", \
    "migrate" \
]