$ErrorActionPreference = "Stop"

$Port = 8797
$Root = Join-Path $PSScriptRoot "build\web"

if (-not (Test-Path (Join-Path $Root "index.html"))) {
    Write-Host "ERROR: build\web\index.html not found." -ForegroundColor Red
    exit 1
}

$mime = @{
    ".html" = "text/html; charset=utf-8"
    ".js" = "application/javascript; charset=utf-8"
    ".css" = "text/css; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".wasm" = "application/wasm"
    ".png" = "image/png"
    ".jpg" = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif" = "image/gif"
    ".svg" = "image/svg+xml"
    ".ico" = "image/x-icon"
    ".woff" = "font/woff"
    ".woff2" = "font/woff2"
    ".ttf" = "font/ttf"
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()

Write-Host "NineSoft local UI preview is running:" -ForegroundColor Green
Write-Host "http://127.0.0.1:$Port"
Write-Host "Press Ctrl+C to stop."

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 8192, $true)
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) {
                $client.Close()
                continue
            }

            while ($true) {
                $line = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($line)) { break }
            }

            $parts = $requestLine.Split(" ")
            $method = $parts[0]
            $rawPath = if ($parts.Length -gt 1) { $parts[1] } else { "/" }

            if ($method -ne "GET" -and $method -ne "HEAD") {
                $payload = [System.Text.Encoding]::UTF8.GetBytes("Method Not Allowed")
                $crlf = [Environment]::NewLine
                $header = "HTTP/1.1 405 Method Not Allowed${crlf}Content-Type: text/plain; charset=utf-8${crlf}Content-Length: $($payload.Length)${crlf}Connection: close${crlf}${crlf}"
                $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
                $stream.Write($headerBytes, 0, $headerBytes.Length)
                if ($method -ne "HEAD") { $stream.Write($payload, 0, $payload.Length) }
                continue
            }

            $pathOnly = $rawPath.Split("?")[0]
            $decoded = [System.Uri]::UnescapeDataString($pathOnly)
            if ($decoded -eq "/") { $decoded = "/index.html" }

            $relative = $decoded.TrimStart("/").Replace("/", [System.IO.Path]::DirectorySeparatorChar)
            $candidate = [System.IO.Path]::GetFullPath((Join-Path $Root $relative))
            $rootFull = [System.IO.Path]::GetFullPath($Root)

            if (-not $candidate.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                $candidate = Join-Path $Root "index.html"
            }

            if (-not (Test-Path $candidate -PathType Leaf)) {
                $candidate = Join-Path $Root "index.html"
            }

            $bytes = [System.IO.File]::ReadAllBytes($candidate)
            $ext = [System.IO.Path]::GetExtension($candidate).ToLowerInvariant()
            $contentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
            $crlf = [Environment]::NewLine
            $header = "HTTP/1.1 200 OK${crlf}Content-Type: $contentType${crlf}Content-Length: $($bytes.Length)${crlf}Cache-Control: no-cache${crlf}Connection: close${crlf}${crlf}"
            $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            if ($method -ne "HEAD") {
                $stream.Write($bytes, 0, $bytes.Length)
            }
        }
        catch {
            Write-Host "Request error: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
        finally {
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}