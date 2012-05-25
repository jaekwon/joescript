{clazz, bisect:{bisect_right}} = require 'cardamom'
assert = require 'assert'

@inspect = (x) -> require('util').inspect x, false, 100

@CodeStream = CodeStream = clazz 'CodeStream', ->
  init: (@text) ->
    @pos = 0
    @numLines = 0
    # LAZY HACK
    @lineStarts = [0]
    @lineStarts.push(@pos) while @getUntil("\n").length > 0
    @lineStarts.pop() # last one is @ EOL.
    @pos = 0
    # END HACK

  line$: get: ->
    bisect_right(@lineStarts, @pos) - 1
  col$:  get: ->
    @pos - @lineStarts[@line]

  # Get until the string `end` is encountered.
  # Change @pos accordingly, including the `end`.
  getUntil: (end, ignoreEOF=yes) ->
    index = @text.indexOf end, @pos
    if index is -1
      if ignoreEOF
        index = @text.length
      else
        throw new EOFError
    else
      index += end.length
    return @text[@pos...(@pos=index)]

  peek: ({beforeChars, beforeLines, afterChars, afterLines}) ->
    if not beforeLines? and not beforeChars? then beforeChars = 0
    if not afterLines?  and not afterChars?  then afterChars  = 0
    assert.ok not (beforeChars is 0 and afterChars is 0), "You can't peek at nothing."

    if beforeLines?
      startLine = Math.max(0, @line-beforeLines)
      start = @lineStarts[startLine]
    else
      start = @pos - beforeChars
    if afterLines?
      endLine = Math.min(@lineStarts.length-1, @line+afterLines)
      if endLine < @lineStarts.length-1
        end = @lineStarts[endLine+1] - 1
      else
        end = @text.length
    else
      end = @pos + afterChars
    return @text[start...end]

  # Match a string or a regex
  # Regex returns null if match failed,
  # otherwise returns match[0] which may be ''
  match: ({regex, string}) ->
    if string?
      peek = @peek afterChars: string.length
      return null if peek isnt string
      @pos += string.length
      string
    else if regex?
      matched = @text[@pos...].match regex # TODO improve
      return null if matched is null
      @pos += matched[0].length
      matched[0]
