# codi.vim

The interactive scratchpad for hackers.

![Codi Demo](https://ptpb.pw/TsaW.gif)

_Using Codi as a Python scratchpad through the
[shell wrapper](#shell-wrapper)_

Codi is an interactive scratchpad for hackers, with a similar interface to
[Numi](https://numi.io). It opens a pane synchronized to your main buffer
which displays the results of evaluating each line *as you type* (if Vim has
`+job` and `+channel`, asynchronously). It's extensible to nearly any
language that provides a REPL (interactive interpreter)!

Languages with built-in support:
Python, JavaScript, Haskell, Ruby, OCaml, R

[Pull requests](https://github.com/metakirby5/codi.vim/pulls)
for new language support welcome!

*Note:* without async support, evaluation will trigger on cursor hold rather
than text change.

For more information, check out the [documentation](doc/codi.txt).
Watch a [screencast](https://ptpb.pw/t/~codi)!

## Installation

Use your favorite package manager
([vim-plug](https://github.com/junegunn/vim-plug),
[Vundle](https://github.com/VundleVim/Vundle.vim),
[pathogen.vim](https://github.com/tpope/vim-pathogen)),
or add this directory to your Vim runtime path.

For example, if you're using vim-plug, add the following line to `~/.vimrc`:

```
Plug 'metakirby5/codi.vim'
```

### Dependencies

- OS X or Linux (Windows support coming
  [soon](https://github.com/metakirby5/codi.vim/issues/14)!)
- Vim 7.4 (with `+job` and `+channel` for asynchronous evaluation)
- `uname`
- `script` (BSD or Linux, manpage should say at least 2013)

Each interpreter also depends on its REPL. These are loaded on-demand. For
example, if you only want to use the Python Codi interpreter, you will not
need `ghci`.

Default interpreter dependencies:

  - Python:     `python`
  - JavaScript: `node`
  - Haskell:    `ghci` (be really careful with lazy evaluation!)
  - Ruby:       `irb`
  - OCaml:      `ocaml`
  - R:          `R`

## Usage

- `Codi [filetype]` activates Codi for the current buffer, using the provided
  filetype or the buffer's filetype.
- `Codi!` deactivates Codi for the current buffer.
- `Codi!! [filetype]` toggles Codi for the current buffer.

### Shell wrapper

A nice way to use Codi is through a shell wrapper that you can stick in your
`~/.bashrc`:

```sh
# Codi
# Usage: codi [filetype] [filename]
codi() {
  vim "$2" -c \
    "let g:startify_disable_at_vimenter = 1 |\
    set bt=nofile ls=0 noru nonu nornu |\
    hi ColorColumn ctermbg=NONE |\
    hi VertSplit ctermbg=NONE |\
    hi NonText ctermfg=0 |\
    Codi ${1:-python}"
}
```

### Options

- `g:codi#interpreters` is a list of user-defined interpreters.
  See the [documentation](doc/codi.txt) for more information.
- `g:codi#aliases` is a list of user-defined interpreter filetype aliases.
  See the [documentation](doc/codi.txt) for more information.

The below options can also be set on a per-interpreter basis via
`g:codi#interpreters`:

- `g:codi#autocmd` determines what autocommands trigger updates.
  See the [documentation](doc/codi.txt) for more information.
- `g:codi#width` is the width of the Codi split.
- `g:codi#rightsplit` is whether or not Codi spawns on the right side.
- `g:codi#rightalign` is whether or not to right-align the Codi buffer.
- `g:codi#autoclose` is whether or not to close Codi when the associated
  buffer is closed.
- `g:codi#raw` is whether or not to display interpreter results without
  alignment formatting (useful for debugging).
- `g:codi#sync` is whether or not to force synchronous execution. No reason to
  touch this unless you want to compare async to sync.

### Autocommands

- `CodiEnterPre`, `CodiEnterPost`: When a Codi pane enters.
- `CodiUpdatePre`, `CodiUpdatePost`: When a Codi pane updates.
- `CodiLeavePre`, `CodiLeavePost`: When a Codi pane leaves.

## FAQ

- _Why doesn't X work in Codi, when it works in a normal source file?_
  - Codi is not meant to be a replacement for actually running your program;
    it supports nothing more than what the underlying REPL supports. This is
    why Haskell language pragmas don't work and OCaml statements must end with
    `;;`.

## Thanks to

- [@DanielFGray](https://github.com/DanielFGray) and
  [@purag](https://github.com/purag) for testing, feedback, and suggestions
- [@Joaquin-V](https://github.com/Joaquin-V) for helping me discover critical
  bugs with vanilla settings
- Everyone who has reported an issue or sent in a pull request :)
