# Contributing

Thanks for deciding to contribute to codi.vim!

## Submitting an issue

Please follow the issue template.

## Adding new language support

It's helpful to use `g:codi#raw` and `g:codi#log` to get an idea of what the
output looks like. Once you know how to implement the interpreter
configuration, please add it to `s:codi_default_interpreters` in
`autoload/codi/codi.vim`. Finally, please add relevant documentation to the
following places:

- `README.md`, line 16 and 57
- `doc/codi.txt`, line 327

## Adding a new feature

Follow existing conventions (e.g. style and configuration access patterns) and
add relevant documentation in `doc/codi.txt`.
