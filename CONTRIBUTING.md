# Contributing to Pocketrb

Thank you for your interest in contributing to Pocketrb! This document provides guidelines and instructions for contributing.

## Code of Conduct

This project adheres to a code of conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to maciej@mensfeld.pl.

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce** the issue
- **Expected behavior** vs actual behavior
- **Environment details** (Ruby version, OS, gem version)
- **Code samples** or error messages if applicable

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, include:

- **Clear title and description** of the enhancement
- **Use case** explaining why this would be useful
- **Possible implementation** if you have ideas

### Pull Requests

1. **Fork the repository** and create your branch from `master`
2. **Make your changes** following the style guidelines below
3. **Add tests** for new functionality
4. **Update documentation** (README, CHANGELOG, comments)
5. **Ensure tests pass** with `bundle exec rspec`
6. **Ensure code quality** with `bundle exec rubocop`
7. **Submit a pull request**

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/pocketrb.git
cd pocketrb

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linters
bundle exec rubocop
bundle exec yard-lint lib/**/*.rb
```

## Style Guidelines

### Ruby Style

- Follow the existing code style
- Run `bundle exec rubocop` before committing
- Keep methods focused and concise
- Add comments for complex logic

### Git Commit Messages

- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move cursor to..." not "Moves cursor to...")
- Keep first line under 50 characters
- Reference issues and PRs when applicable
- Follow [Conventional Commits](https://www.conventionalcommits.org/) format:
  - `feat:` for new features
  - `fix:` for bug fixes
  - `docs:` for documentation changes
  - `refactor:` for code refactoring
  - `test:` for test additions/changes
  - `chore:` for maintenance tasks

### Documentation

- Update README.md for user-facing changes
- Update CHANGELOG.md following [Keep a Changelog](https://keepachangelog.com/)
- Add YARD documentation for public APIs
- Include examples for new features

## Testing

- Write tests for all new functionality
- Maintain or improve test coverage
- Tests should be independent and repeatable
- Use descriptive test names

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/unit/tools/read_file_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec
```

## CI Pipeline

All pull requests must pass:
- **RSpec tests** (full test suite)
- **Rubocop** (style checks)
- **YARD-lint** (documentation checks)
- **Lostconf** (config hygiene)

## Release Process

Releases are handled by maintainers:

1. Update version in `lib/pocketrb/version.rb`
2. Update `CHANGELOG.md` with release date
3. Commit changes: `git commit -m "chore: release v0.x.0"`
4. Create tag: `git tag v0.x.0`
5. Push: `git push && git push --tags`
6. GitHub Actions will automatically publish to RubyGems

## Questions?

Feel free to open an issue for questions or reach out to maciej@mensfeld.pl.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
