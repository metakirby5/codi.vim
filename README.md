# codi.vim

The interactive scratchpad for hackers.

![Codi Screenshot](https://ptpb.pw/~codi-simple.png)

*Using Codi as a Python scratchpad through the
[shell wrapper](#shell-wrapper)*

Codi is an interactive scratchpad for hackers, with a similar interface to
Numi (https://numi.io). It opens a pane synchronized to your main buffer which
displays the results of evaluating each line *as you type* (asynchronously
for supported interpreters). It's extensible to nearly any language that
provides an interactive interpreter!

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

Vim should be compiled with `+job` for a smoother experience.

Command line utilities (BSD and Linux are both fine): `script`, `uname`.

Each interpreter also depends on its REPL:

  - Python:    `python`
  - Javscript: `node`
  - Haskell:   `ghci`
  - Ruby:      `irb`

## Usage

- `Codi [filetype]` activates Codi for the current buffer, using the provided
  filetype or the buffer's filetype.
- `Codi!` deactivates Codi for the current buffer.
- `Codi!! [filetype]` toggles Codi for the current buffer.

### Shell wrapper

A nice way to use Codi is through a shell wrapper that you can stick in your
~/.bashrc:

```sh
# Codi
# Usage: codi [filetype] [filename]
codi() {
  vim $2 -c \
    "let g:startify_disable_at_vimenter = 1 |\
    set laststatus=0 |\
    hi ColorColumn ctermbg=NONE |\
    hi VertSplit ctermbg=NONE |\
    hi NonText ctermfg=0 |\
    Codi ${1:-python}"
}
``````

### Options

- `g:codi#interpreters` is a list of user-defined interpreters.
  See the [documentation](doc/codi.txt) for more information.
- `g:codi#aliases` is a list of user-defined interpreter filetype aliases.
  See the [documentation](doc/codi.txt) for more information.
- `g:codi#width` is the width of the Codi split.
- `g:codi#rightsplit` is whether or not Codi spawns on the right side.
- `g:codi#rightalign` is whether or not to right-align the Codi buffer.
- `g:codi#autoclose` is whether or not to close Codi when the associated
  buffer is closed.
- `g:codi#raw` is whether or not to display interpreter results without
  alignment formatting (useful for debugging).

## Thanks to

- [@DanielFGray](https://github.com/DanielFGray) and
  [@purag](https://github.com/purag) for testing, feedback, and suggestions
