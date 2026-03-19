FROM python:3.12-alpine

RUN apk add --no-cache \
    curl \
    bash \
    docker-cli \
    docker-cli-compose \
    && pip install --no-cache-dir poetry

WORKDIR /app/tools/pipeline_runner

COPY pyproject.toml poetry.lock* ./
RUN poetry config virtualenvs.create false \
    && poetry install --no-interaction --no-ansi --no-root

COPY . .
RUN poetry install --no-interaction --no-ansi

ENTRYPOINT ["poetry", "run", "pipeline"]
