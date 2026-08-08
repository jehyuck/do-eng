# Exp168 diagnostic-only runtime image.
# Keep the production Dockerfile unchanged; this file exists only to make the
# fresh-binary provenance check reproducible after the deprecated openjdk:11
# image stopped resolving from Docker Hub.
FROM eclipse-temurin:11.0.31_11-jre

# Build context must be backend/doEngGameFlux so this path resolves to the
# fresh JAR produced by the Exp168 recovery build.
ARG JAR_FILE_PATH=build/libs/doEngGameFlux-0.0.1-SNAPSHOT.jar

COPY ${JAR_FILE_PATH} /app.jar

ENTRYPOINT java -jar /app.jar --server.port=8000
