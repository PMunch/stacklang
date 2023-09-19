"Starts an inline command" [ \len \inlinecmdstart \varpush \\] \noevaluntil [ mkcmd doccmd
"Ends an inline command" ] \inlinecmdstart \varpop \mkcmd ] mkcmd doccmd
"Empties the entire stack" clear 0 \\pop \until clear mkcmd doccmd
"Runs a command a given number of times" times 1 \- \swap \dup -2 \insert \cmdlbl \varpush \cmdlbl \varswp \call \cmdlbl \varswp \dup -1 \swap 0 \\pop \\goback \== \cmdlbl \varswp \cmdlbl \vardel times mkcmd doccmd
