# Use the official .NET SDK image as the build image
# Verify the SDK and runtime versions match the ones in global.json
FROM mcr.microsoft.com/dotnet/sdk:9.0.300-bookworm-slim AS build
WORKDIR /src

COPY . .

# Publish the application
FROM build AS publish
RUN pwsh "eng/scripts/Build-Module.ps1" -OutputPath /app/publish -OperatingSystem Linux -Architecture x64

# Build the runtime image
FROM mcr.microsoft.com/dotnet/aspnet:9.0.5-bookworm-slim AS runtime
WORKDIR /app

# Install Azure CLI and required dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    apt-transport-https \
    lsb-release \
    gnupg \
    libx11-6 \
    && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && rm -rf /var/lib/apt/lists/*

# Install Microsoft Graph CLI
RUN curl -L https://github.com/microsoftgraph/msgraph-cli/releases/download/v1.9.0/msgraph-cli-linux-x64-1.9.0.tar.gz -o /tmp/mgc.tar.gz \
    && tar -xzf /tmp/mgc.tar.gz -C /tmp \
    && mv /tmp/mgc /usr/local/bin/mgc \
    && rm /tmp/mgc.tar.gz

# Create a non-root user
RUN useradd -m appuser
USER appuser

# Copy the published application
COPY --from=publish "/app/publish/linux-x64/dist" .

# Ensure the app user owns the files
USER root
RUN chown -R appuser:appuser /app
USER appuser

CMD ["./azmcp", "server", "start", "--transport", "sse"]
