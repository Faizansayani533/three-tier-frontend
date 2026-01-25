# ---------- STAGE 1: Build React App ----------
FROM node:18-alpine AS build

WORKDIR /app

# Copy package files
COPY web-tier/package*.json ./

RUN npm install

# Copy rest of the frontend code
COPY web-tier/ .

# Build react app
RUN npm run build


# ---------- STAGE 2: Nginx Server ----------
FROM nginx:alpine

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy build files to nginx html folder
COPY --from=build /app/build /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
