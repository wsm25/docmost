FROM alpine:3.22
RUN apk add --no-cache bash coreutils gzip openssl postgresql18-client rclone
WORKDIR /sync
COPY backup.sh /sync/backup.sh
RUN chmod +x /sync/backup.sh
RUN mkdir -p /root/.config/rclone
CMD ["/sync/backup.sh"]
