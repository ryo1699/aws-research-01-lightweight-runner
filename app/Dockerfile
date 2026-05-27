FROM alpine:3.20

WORKDIR /app
COPY build-info.sh /usr/local/bin/build-info

RUN chmod +x /usr/local/bin/build-info

CMD ["build-info"]
