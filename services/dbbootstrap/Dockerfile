FROM postgres:16-alpine
COPY bootstrap.sql /bootstrap.sql
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bootstrap"]
