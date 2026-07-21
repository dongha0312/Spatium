FROM eclipse-temurin:17-jdk-noble AS build

WORKDIR /workspace

COPY gradlew .
COPY gradle gradle
COPY settings.gradle build.gradle ./

RUN chmod +x gradlew
RUN ./gradlew dependencies --no-daemon

COPY src src

RUN ./gradlew clean bootJar --no-daemon \
    && JAR_FILE="$(find build/libs -maxdepth 1 -type f -name '*.jar' ! -name '*-plain.jar' -print -quit)" \
    && test -n "$JAR_FILE" \
    && cp "$JAR_FILE" /workspace/app.jar


FROM eclipse-temurin:17-jre-noble

WORKDIR /app

RUN groupadd --system spring \
    && useradd --system --gid spring --home-dir /app --shell /usr/sbin/nologin spring \
    && mkdir -p /app/data \
    && chown -R spring:spring /app

COPY --from=build --chown=spring:spring /workspace/app.jar /app/app.jar

USER spring

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
