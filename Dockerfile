FROM opensuse:latest

# copy the app
ADD app/bin/server /app/server

ENTRYPOINT /app/server
EXPOSE 8000
