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

### YATT Syntax Overview

YATT uses LRXML (Loose but Recursive XML) syntax. The namespace prefix (commonly `yatt:`) is configurable and multiple namespaces can be defined. All widgets (both user-defined and built-in) use the same syntax:

1. **Widget invocation**: `<yatt:widgetname/>` or `<yatt:widgetname>...</yatt:widgetname>`
   - Examples: `<yatt:foo/>`, `<yatt:if var="x">...</yatt:if>`, `<yatt:my var="x" value="1"/>`
   - No syntax distinction between user-defined and built-in widgets

2. **Attribute elements**: `<:yatt:argname>...</:yatt:argname>` 
   - For passing complex arguments containing tags

3. **Entity references**: `&yatt:varname;` or `&yatt:entity();`
   - Variable interpolation and function calls

4. **Declarations**: `<!yatt:widget name args...>`, `<!yatt:args vars...>`
   - Widget definitions and argument declarations

5. **Comments**: `<!--#yatt ... -->`
   - Ignored by parser

6. **Processing instructions**: `<?yatt ... ?>`, `<?perl ... ?>`
   - Direct target language embedding

### Macro System

YATT implements a Lisp-like macro system for both widgets and entities:

#### Widget Macros
Widgets like `<yatt:if>`, `<yatt:foreach>`, etc.:
- Methods in `YATT::Lite::CGen::Perl` with names starting with `macro_*`
- Examples: `macro_if`, `macro_foreach`, `macro_my`, etc.

#### Entity Macros
Entity functions like `&yatt:if(cond,then,else);`:
- Methods in `YATT::Lite::CGen::Perl` with names starting with `entmacro_*`
- Examples: `entmacro_if`, `entmacro_unless`, etc.
- Evaluated at code generation time

Both can be extended by inheriting `YATT::Lite::CGen::Perl`.

To get the complete list of available macros:
```perl
my ($tmpl, $core) = $self->find_template($fileName);
my $cgen = $core->build_cgen_of('perl');
# For widget macros: methods starting with 'macro_'
# For entity macros: methods starting with 'entmacro_'
```

### Entity Functions

Two types of entity functions exist:

1. **Entity Macros** - Compile-time macros (`entmacro_*` methods)
2. **Regular Entities** - Runtime functions (`entity_*` methods)
   - Defined with `<!yatt:entity name ...>` in templates
   - Generated as `entity_name` methods in compiled classes
   - Inherited through class hierarchy
   
To list all available entities, recursively check methods starting with `entity_*` in the generated class and its parents (see `cmd_list_entities` in Inspector.pm).

### Entity Resolution Order

Entity Path Expressions like `&yatt:foo;` or `&yatt:foo();` are resolved in the following priority order:

1. **Entity macro (entmacro)** - If `entmacro_foo` exists, it's used with highest priority
2. **Variable reference** - If variable `foo` exists, its value is referenced (`&yatt:foo();` invokes code-type variables)
3. **Entity function** - Calls `entity_foo` method

This means macros have the highest priority, followed by variables, and finally entity functions.

### Namespace Configuration

YATT namespaces are configurable and multiple namespaces can be defined:

- Default namespace is often `yatt`, but this is configurable per application
- Multiple namespaces can be active simultaneously
- To get current namespace configuration in Inspector:
  ```perl
  my @namespace = YATT::Lite::Util::lexpand($self->{_SITE}->cget('namespace'))
  ```
- This affects all syntax elements: `<ns:widget>`, `&ns:entity;`, `<!ns:declaration>`, etc.

### Widget Search Order

YATT searches for widgets in the following order:
1. **Macros (built-in widgets)** - `if`, `foreach`, `my`, etc. implemented as `macro_*` methods in `YATT::Lite::CGen::Perl`
2. **Same file** - widgets defined in the current template file
3. **Same directory** - widgets in other files in the same directory
4. **Other template directories** - configured template directories

The search is performed at **compile time** and results in a compilation error if not found.

Key implementation details:
- `from_element` in CGen/Perl.pm implements the search priority (macro first, then regular widgets)
- `lookup_widget` in CGen.pm searches both with and without namespace
- `find_part_from` in VFS.pm implements the actual search logic for user-defined widgets
- Widget paths can use `:` separator for subdirectories (e.g., `foo:bar` for `foo/bar.yatt`)
- The same search order applies to entity functions

### Widget Path Resolution

Widget names can be paths using `:` as separator (e.g., `<yatt:foo:bar/>`). 

#### File vs Directory Priority
When both `foo.yatt` file and `foo/` directory exist:
1. **File widget takes precedence**: `foo.yatt` containing `<!yatt:widget bar>` is checked first
2. **Directory fallback**: `foo/bar.yatt` with default widget (`<!yatt:args>`) is checked second

#### Namespace Directory Priority
Widget lookup performs two searches:
1. **With namespace**: If `yatt/` directory exists, searches `yatt/foo/bar.yatt` or `yatt/foo.yatt` first
2. **Without namespace**: Falls back to `foo/bar.yatt` or `foo.yatt`

This allows organizing widgets under namespace directories (useful for organization/project names).

### Template Inheritance System

YATT implements OOP-style inheritance for template directories:

#### Default Inheritance
- `public/` automatically inherits from `ytmpl/`
- Any widget in `public/` can call widgets from `ytmpl/`

#### Directory-level Inheritance
- Set via `.htyattconfig.xhf` with `base:` element
- Can specify multiple parent directories (multiple inheritance)
- Examples:
  ```
  base: ../shared/templates
  ```
  or for multiple inheritance:
  ```
  base[
  - ../lib1
  - ../lib2
  ]
  ```

#### File-level Inheritance
- Declared with `<!yatt:base file="...">` or `<!yatt:base dir="...">`
- Overrides directory-level inheritance for that specific file

#### Implementation Details
- `lookup_base` in VFS.pm traverses the inheritance chain
- Search order when inheritance is involved:
  1. Current location (file/directory)
  2. Base directories/files in declaration order
  3. Recursive search through base's bases
- The entire widget search order (macros → same file → same dir → other dirs) applies at each inheritance level

### VFS and Template Organization

YATT uses a Virtual File System (VFS) that is directory-specific, not global:

- **Per-directory VFS**: Each directory has its own VFS instance managed by YATT
- **Core extends VFS**: `YATT::Lite::Core` inherits from `YATT::Lite::VFS`
- **Accessing VFS**: Use `find_template` method to get template and core:
  ```perl
  (my Template $tmpl, my $core) = $self->find_template($fileName);
  # $core is a YATT::Lite::Core instance (which IS-A VFS)  
  # $tmpl is the template object
  # Always use typed variable declarations for better static checking
  ```
- **Key methods**:
  - `find_template($fileName)`: Returns template and core for a file
  - `find_yatt_for_template($fileName)`: Gets YATT instance for a directory
  - `$core->find_part_from($tmpl, @path)`: Searches widgets following VFS rules

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

### Widget Argument Declaration Syntax

In YATT declarations, argument types are specified after `=`:

```html
<!yatt:args varname=type>
<!yatt:widget widgetname varname=type>
```

- **Type specification**: The type appears on the right side of `=`
- **Default type**: If type is omitted, it defaults to `text`
- **Required/Optional flags**: 
  - `!` suffix means required argument
  - `?` suffix means has default value (shows default when empty string or undef)
  
Examples:
```html
<!yatt:args title="text!" body=code>
<!yatt:widget mywidget a="text!" b=text c="text!">
```

### Testing Approach

- Unit tests use standard Perl testing (Test::More)
- Template tests use XHF format (eXtended Header Format)
- PSGI app tests use Plack::Test
- Coverage reports generated with Devel::Cover

### Testing Inspector.pm and CLI_JSON Modules

Inspector.pm inherits from `MOP4Import::Base::CLI_JSON`, making it a Modulino that can be executed directly from command line. This allows testing methods without writing Perl one-liners.

**Basic usage:**
```bash
./Lite/Inspector.pm [--constructor-args] subcommand [method args...]
```

**Constructor arguments:**
- Pass before the subcommand using `--name=value` format
- For HASH or ARRAY values, use JSON format

**Return values:**
- References (HASH/ARRAY): returned as JSONL (JSON Lines)
- Plain strings: returned as line-by-line plain text

**Example - Testing widget completion:**
```bash
# Good: Direct execution as Modulino
./Lite/Inspector.pm --dir=samples/basic/1 complete_widgets html/index.yatt yatt e

# Bad: Using perl -I with one-liner
perl -I./lib -MYATT::Lite::Inspector -E 'my $inspector = YATT::Lite::Inspector->new(dir => "samples/basic/1"); print $inspector->complete_widgets("html/index.yatt","yatt","e");'
```

**Development workflow for Inspector.pm changes:**
1. Edit the module (e.g., improve `complete_widgets` method)
2. Run static type checking: `perlminlint Lite/Inspector.pm`
3. Test as Modulino: `./Lite/Inspector.pm --dir=samples/basic/1 complete_widgets ...`
4. Add/update tests in `t/inspector.t`
5. Run tests: `prove -bv t/inspector.t`

This approach applies to any module inheriting from `MOP4Import::Base::CLI_JSON`.

### Static Analysis

Always run `perlminlint` after modifying Perl modules:
```bash
perlminlint Lite/Inspector.pm
```
This helps catch type errors and other issues at compile time.

### Language Server

For IDE integration, use:
```bash
scripts/yatt-langserver.pl
```

This provides real-time error checking and completion support.