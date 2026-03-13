# URL Fuzzy

![Shell](https://img.shields.io/badge/Shell-Bash%204%2B-blue) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

General-purpose URL payload fuzzer for testing character-encoding variations. Generates permutations by replacing specified hex sequences (e.g., `%0D`, `%0A`) with alternatives across URLs, tests each variant via HTTP, and analyzes responses to detect unique handling patterns.

## Features

- **Permutation generation** – Cartesian product of find/replace character pairs across URLs
- **Multi-URL and file support** – Test single URLs, multiple URLs, or batch from a file
- **Response deduplication** – MD5 hashing to group identical responses
- **Anomaly detection** – Flags when different payloads produce different responses
- **Configurable timeout** – Adjust curl timeout per request
- **Output to file** – Save full results for later review
- **Interactive mode** – Prompt-driven input when flags are not provided

## Requirements

- Bash 4+ (for associative arrays)
- `curl`
- `md5sum` (Linux) or `md5` (macOS) for response hashing

## Installation

```bash
git clone https://github.com/yourusername/url-fuzzy.git
cd url-fuzzy
chmod +x url-fuzzy.sh
```

Optional: install to PATH for global access:

```bash
sudo install -m 755 url-fuzzy.sh /usr/local/bin/url-fuzzy
```

## Usage

```
Usage: ./url-fuzzy.sh [OPTIONS]

OPTIONS:
    -u, --url URL               Single URL to test (can be used multiple times)
    -f, --file FILE             File containing URLs (one per line)
    -c, --find CHARS            Hex characters to find (space-separated, e.g., "%0D %0A")
    -r, --replace CHARS         Replacement characters (space-separated, e.g., "%20 %00")
    -t, --timeout SECONDS       Curl timeout in seconds (default: 10)
    -o, --output FILE           Save results to file
    -v, --verbose               Enable verbose output
    -h, --help                  Show this help message
    --interactive               Interactive mode (prompted for inputs)
```

### Examples

**Single URL with character replacements:**

```bash
./url-fuzzy.sh -u "https://example.com/api?q=%0D%0A" -c "%0D %0A" -r "%20 %00"
```

**Multiple URLs with output file:**

```bash
./url-fuzzy.sh \
    -u "gopher://target1:6379/payload" \
    -u "gopher://target2:6379/payload" \
    -c "%0D %0A %09" \
    -r "%20 %00 %FF" \
    -o results.txt -v
```

**Batch mode from file:**

```bash
./url-fuzzy.sh -f urls.txt -c "%0D %0A" -r "%20 %00"
```

**Interactive mode:**

```bash
./url-fuzzy.sh --interactive
```

See [examples/example_usage.md](examples/example_usage.md) for more copy-paste commands.

## Use Cases

- **SSRF testing** – Fuzz URL parameters for encoding bypasses
- **Gopher protocol** – Redis, FastCGI, and other gopher-based payloads
- **HTTP parameter fuzzing** – Test how servers normalize or parse encoded characters
- **Encoding bypass research** – Any scenario where URL character encoding affects behavior

## Output

URL Fuzzy prints a summary of all payloads before testing and asks for confirmation. During execution it shows:

- Curl status per request (OK, TIMEOUT, CONN_FAILED, EMPTY_REPLY, etc.)
- Response body (truncated if long)
- Response analysis with status counts and unique response hashes
- Warnings when multiple different responses are detected, indicating potential different payload handling

## License

MIT License. See [LICENSE](LICENSE) for details.
