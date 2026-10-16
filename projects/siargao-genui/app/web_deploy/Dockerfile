# Serves the Flutter web build (app/build/web) on Cloud Run.
# Build the web app first with the deployed AGENT_URL and MCP_URL baked in.
# deploy.sh copies build/web into ./site before uploading.
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY site /usr/share/nginx/html
EXPOSE 8080
