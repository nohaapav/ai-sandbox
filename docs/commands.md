# Useful commands

Run these from the `ai-sandbox` repository root.

Start the container:

```bash
docker compose up -d
```

Stop the container:

```bash
docker compose stop
```

Restart the container:

```bash
docker compose restart agent
```

Enter the container:

```bash
docker compose exec agent bash
```

Recreate the container:

```bash
docker compose up -d --force-recreate
```

Rebuild the image:

```bash
docker compose up -d --build
```

View container logs:

```bash
docker compose logs -f agent
```

Inspect the resolved Compose configuration:

```bash
docker compose config
```
