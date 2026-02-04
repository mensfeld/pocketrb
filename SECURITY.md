# Security Policy

## Supported Versions

Currently supported versions with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: **maciej@mensfeld.pl**

Include as much information as possible:

- Type of vulnerability
- Full paths of source file(s) related to the vulnerability
- Location of affected source code (tag/branch/commit/direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if available)
- Impact of the issue, including how an attacker might exploit it

You should receive a response within 48 hours. If for some reason you do not, please follow up via email to ensure we received your original message.

## Security Considerations

### API Keys and Secrets

- Never commit API keys or secrets to the repository
- Use environment variables for sensitive configuration
- The `.gitignore` file excludes `.env` and `.env.local` files
- Review code for accidentally committed secrets before submitting PRs

### Command Execution

- The `exec` tool allows shell command execution - use with caution
- In multi-user environments, consider restricting tool access
- Use the `allowed_users` option for Telegram/WhatsApp channels

### File Access

- The agent has file system access within the configured workspace
- Use `--workspace` to restrict access to specific directories
- Be cautious when running as root or with elevated privileges

### Third-Party Services

- Web search requires Brave API key - keep it secure
- LLM provider API keys should be protected
- OAuth tokens should be handled securely

## Best Practices

1. **Limit workspace access**: Use `--workspace` to restrict file access
2. **User allowlists**: Use `--allowed-users` for messaging channels
3. **Secure API keys**: Use environment variables, never hardcode
4. **Review commands**: Monitor what commands the agent executes
5. **Keep updated**: Regularly update to the latest version for security patches
