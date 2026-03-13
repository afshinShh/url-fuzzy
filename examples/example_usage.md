# URL Fuzzy - Example Usage

Copy-paste commands to get started with URL Fuzzy.

## Prerequisites

From the project root:

```bash
chmod +x url-fuzzy.sh
```

## 1. Single URL with Character Replacements

Replace `%0D` and `%0A` with `%20` and `%00`:

```bash
./url-fuzzy.sh \
    -u "https://example.com/api?q=test%0D%0Apayload" \
    -c "%0D %0A" \
    -r "%20 %00"
```

## 2. Batch Mode with File

Create `my_urls.txt` with one URL per line, then:

```bash
./url-fuzzy.sh \
    -f my_urls.txt \
    -c "%0D %0A %09" \
    -r "%20 %00 %FF" \
    -o results.txt
```

## 3. Multiple URLs and Output File

```bash
./url-fuzzy.sh \
    -u "https://target1.com/redirect?url=%0D%0A" \
    -u "https://target2.com/redirect?url=%0D%0A" \
    -c "%0D %0A" \
    -r "%20 %00" \
    -t 15 \
    -o results.txt -v
```

## 4. Interactive Mode

Run without URLs or character sets to be prompted:

```bash
./url-fuzzy.sh --interactive
```

Or simply:

```bash
./url-fuzzy.sh
```

You will be asked for:
- URLs (one per line, empty line to finish)
- Characters to find (e.g., `%0D %0A %09`)
- Replacement characters (e.g., `%20 %00 %FF`)

## 5. Gopher/Redis-Style Payloads

For gopher protocol URLs (e.g., SSRF to Redis):

```bash
./url-fuzzy.sh \
    -u "gopher://127.0.0.1:6379/_YOUR_PAYLOAD_HERE" \
    -c "%0D %0A %09" \
    -r "%20 %00 %FF" \
    -t 5
```

## Common Hex Encodings

| Char | Hex     | Description        |
|------|---------|--------------------|
| CR   | `%0D`   | Carriage return    |
| LF   | `%0A`   | Line feed          |
| Tab  | `%09`   | Horizontal tab     |
| Space| `%20`   | Space              |
| NUL  | `%00`   | Null byte          |
| FF   | `%FF`   | Form feed / 0xFF   |
