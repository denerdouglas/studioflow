FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN mkdir -p /out && dart compile exe bin/server.dart -o /out/studioflow-api

FROM debian:bookworm-slim
RUN useradd --create-home --uid 10001 studioflow
WORKDIR /app
COPY --from=build /out/studioflow-api /usr/local/bin/studioflow-api
RUN mkdir -p /app/storage && chown -R studioflow:studioflow /app
USER studioflow
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/studioflow-api"]
