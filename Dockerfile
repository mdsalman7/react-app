# Stage 1: Build
FROM node:14 AS build

# Set the working directory
WORKDIR /usr/src/app

# Copy package files and install dependencies
COPY package*.json ./
RUN npm install

# Copy the rest of the application source code
COPY . .

# Build the application (if applicable, e.g., for frontend builds)
RUN npm run build  # Uncomment this if your app requires a build step

# Stage 2: Runtime
FROM node:14-slim AS runtime

# Set the working directory
WORKDIR /usr/src/app

# Copy only the required files from the build stage
COPY --from=build /usr/src/app .

# Expose the application's port
EXPOSE 3000

# Define the default command
CMD ["node", "index.js"]


