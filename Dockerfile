# syntax=docker/dockerfile:1

FROM eclipse-temurin:21-jdk-jammy AS builder

WORKDIR /app

COPY gradlew .
COPY gradle gradle
COPY build.gradle.kts .
COPY settings.gradle.kts .

RUN chmod +x gradlew

# Прогреваем Gradle и сохраняем cache между Docker build
RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew dependencies --no-daemon || true

COPY src src

RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew bootJar --no-daemon


FROM eclipse-temurin:21-jre-jammy

WORKDIR /app

RUN groupadd --system procash \
    && useradd --system \
       --gid procash \
       --home-dir /app \
       --shell /usr/sbin/nologin \
       procash

COPY --from=builder \
    --chown=procash:procash \
    /app/build/libs/procash-0.0.1-SNAPSHOT.jar \
    /app/app.jar

USER procash

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]