# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YATT::Lite is a template engine for Perl that emphasizes static error checking and designer-friendly syntax. It detects errors like misspellings and undefined variables at compile time rather than runtime, making it safer for web development.

## Key Commands

### Building
```bash
perl Build.PL
./Build
```

### Testing
```bash
# Run all tests
./t/runtests.zsh

# Run tests with coverage
./t/runtests.zsh -C

# Run tests in taint mode
./t/runtests.zsh -T

# Run specific test
prove -bv t/lite.t

# Run sample app tests
cd samples/basic/1 && prove -I../../../lib t/*.t
```

### Linting and Checking
```bash
# Lint YATT templates
scripts/yatt lint html/*.yatt

# Lint Perl modules
scripts/yatt lintpm lib/

# Check template rendering
scripts/yatt render html/index.yatt
```

## Architecture Overview

### Core Components

1. **YATT::Lite** - Main template engine that compiles `.yatt` files into Perl code
2. **YATT::Lite::WebMVC0::SiteApp** - PSGI application framework for serving YATT templates
3. **YATT::Lite::LRXML** - Parser for the YATT template syntax
4. **YATT::Lite::VFS** - Virtual File System managing template sets

### Template Processing Flow

1. **Parse Phase**: LRXML parser converts YATT syntax to AST
2. **Compile Phase**: CGen (Code Generator) converts AST to Perl code
3. **Runtime Phase**: Generated Perl code executes with automatic output escaping

### Key Design Patterns

- **Factory Pattern**: YATT::Lite::Factory manages template compilation and caching
- **Connection Pattern**: Each HTTP request gets a Connection object managing state
- **VFS Pattern**: Templates organized in virtual file systems, not individual files

### Important Conventions

- Files starting with dot (e.g., `.htyattconfig.xhf`) are configuration files
- `.yatt` files are public templates
- `.ytmpl` files are private/library templates
- `.ydo` files handle form actions
- XHF format used for configuration and testing

### Error Handling

The framework emphasizes compile-time error detection. When developing:
- Template errors appear with precise line numbers
- Use `yatt lint` to check templates before runtime
- Error templates can be customized via `error.ytmpl`

## Development Notes

### Adding New Features

- Template widgets go in `.yatt` or `.ytmpl` files
- Backend logic goes in SiteApp subclasses or Entity modules
- Use `<!yatt:args>` for declaring widget parameters with types

### Testing Approach

- Unit tests use standard Perl testing (Test::More)
- Template tests use XHF format (eXtended Header Format)
- PSGI app tests use Plack::Test
- Coverage reports generated with Devel::Cover

### Language Server

For IDE integration, use:
```bash
scripts/yatt-langserver.pl
```

This provides real-time error checking and completion support.