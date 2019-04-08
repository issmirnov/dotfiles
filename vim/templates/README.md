# Vim Templates

Per https://shapeshed.com/vim-templates/, it's possible to create template files
and have them autopopulate a new buffer.

Simply linking this folder to `~/.vim/templates` and adding this snippet below
is enough to activate this functionality.

```
if has("autocmd")
  augroup templates
    autocmd BufNewFile *.sh 0r ~/.vim/templates/skeleton.sh
    autocmd BufNewFile *.zsh 0r ~/.vim/templates/skeleton.zsh
  augroup END
endif
```
