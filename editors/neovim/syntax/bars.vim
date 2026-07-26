" Bars syntax highlighting for Vim/Neovim
if exists("b:current_syntax")
  finish
endif

syntax match barsComment /;;.*$/
syntax region barsString start=/"/ skip=/\\./ end=/"/
syntax match barsNumber /-\?\d\+/
syntax keyword barsBoolean true false nil
syntax match barsKeywordLit /:[A-Za-z0-9_\-+*/!?]\+/
syntax keyword barsKeyword defn defmacro def let if do loop recur fn match when unless cond require extern defstruct deftype load

highlight default link barsComment Comment
highlight default link barsString String
highlight default link barsNumber Number
highlight default link barsBoolean Boolean
highlight default link barsKeywordLit Constant
highlight default link barsKeyword Keyword

let b:current_syntax = "bars"
