FROM eclipse-temurin:21-jdk-jammy

WORKDIR /app

COPY . .

RUN sed -i 's/\r$//' mvnw

RUN chmod +x mvnw

RUN ./mvnw --version

RUN ./mvnw clean package -DskipTests

EXPOSE 8080

ENTRYPOINT ["sh","-c","java -jar target/*.jar"]