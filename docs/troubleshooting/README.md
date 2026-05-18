# Troubleshooting

The maintained troubleshooting guide is [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md).

Quick checks:

```bash
scripts/health_check.sh
curl -sS http://localhost:8080/api/system/health | python3 -m json.tool
curl -sS http://localhost:8091/health | python3 -m json.tool
docker compose -f infra/docker-compose.yml ps
```

