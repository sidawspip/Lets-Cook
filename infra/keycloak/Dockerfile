FROM maven:3.9.11-eclipse-temurin-21 AS provider-builder
WORKDIR /provider
COPY providers/pom.xml ./pom.xml
COPY providers/src ./src
RUN mvn -q -DskipTests package

FROM quay.io/keycloak/keycloak:26.8.0
COPY --from=provider-builder /provider/target/lets-cook-x-email-mapper.jar /opt/keycloak/providers/lets-cook-x-email-mapper.jar
