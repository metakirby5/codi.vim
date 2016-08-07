function! codi#interpret(...)
  let interpreter = a:0 == 1 ? a:1 : &ft
endfunction
