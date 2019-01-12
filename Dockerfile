FROM alpine:3.8 AS build

RUN apk add --no-cache \
            alpine-sdk \
            autoconf \
            bash \
            gnutls-dev \
            lua5.1-dev \
            flex \
            zlib-dev

WORKDIR /usr/src/wget-lua
COPY get-wget-lua.sh /usr/src/wget-lua/
RUN ./get-wget-lua.sh

FROM python:3-alpine

RUN apk add --no-cache git gnutls lua5.1 rsync zlib \
    && adduser -D -u 1000 grabber \
    && pip install --no-cache-dir seesaw

USER grabber
WORKDIR /home/grabber/

COPY --chown=1000 . /home/grabber/
COPY --chown=1000 --from=build /usr/src/wget-lua/wget-lua /home/grabber/

CMD ["run-pipeline3", "pipeline.py", "--concurrent", "6", "--disable-web-server", "mutantmonkey"]
