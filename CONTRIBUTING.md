# Contributing

Thanks for deciding to contribute to codi.vim!

## Submitting an issue

Please include the following:

- OS
- Version of `script` (if you don't know, just paste the last line of the
  man page)
- Entire output of `vim --version`
- Log lines (see `:h g:codi#log`)
- Exact steps to reproduce the issue

## Adding new language support

It's helpful to use `g:codi#raw` and `g:codi#log` to get an idea of what the
output looks like. Once you know how to implement the interpreter
configuration, please add it to `s:codi_default_interpreters` in
`autoload/codi/codi.vim`. Finally, please add relevant documentation to the
following places:

- `README.md`, line 16 and 57
- `doc/codi.txt`, line 327

## Submitting a feature
