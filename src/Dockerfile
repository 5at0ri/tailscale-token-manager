FROM alpine:latest

RUN apk add --no-cache curl jq bash python3

COPY token-refresh.sh /usr/local/bin/token-refresh.sh
COPY start.sh /usr/local/bin/start.sh
COPY proxy.py /usr/local/bin/proxy.py
RUN chmod +x /usr/local/bin/token-refresh.sh /usr/local/bin/start.sh

# Create directory for tokens
RUN mkdir -p /tokens

WORKDIR /tokens

EXPOSE 1180

CMD ["/usr/local/bin/start.sh"]
