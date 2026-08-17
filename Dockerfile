FROM eclipse-temurin:21-jre
WORKDIR /app
COPY server/build/libs/server-all.jar app.jar
ENV TECHNEXUS_CACHE_DIR=/tmp/ktorCache
ENTRYPOINT ["java","-XX:MaxRAMPercentage=75","-XX:+UseSerialGC","-jar","/app/app.jar"]