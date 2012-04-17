###
JoeSon Parser
Jae Kwon 2012
###

_ = require 'underscore'
assert = require 'assert'
{inspect, CodeStream} = require './codestream'
{clazz} = require 'cardamom'
{red, blue, cyan, magenta, green, normal, black, white, yellow} = require './colors'

escape = (str) ->
  (''+str).replace(/\\/g, '\\\\').replace(/\r/g,'\\r').replace(/\n/g,'\\n').replace(/'/g, "\\'")
keystr = (key) -> "#{key.pos},#{key.name}"
debugLoopify = debugCache = no

# aka '$' in parse functions
@ParseContext = ParseContext = clazz 'ParseContext', ->

  init: ({@code, @grammar, @debug}={}) ->
    @debug ?= false
    @stack = []         # [ {name,pos,...}... ]
    @cache = {}         # { pos:{ "#{name}":{result,endPos}... } }
    @cacheStores = []   # [ {name,pos}... ]
    @recurse = {}       # { pos:{ "#{name}":{stage,base,endPos}... } }
    @storeCache = yes   # rule callbacks can override this
    @_ctr = 0

  # code.pos will be reverted if result is null
  try: (fn) ->
    pos = @code.pos
    result = fn(this)
    @code.pos = pos if result is null
    result

  log: (message, count=false) ->
    if @debug and not @skipLog
      if count
        console.log "#{++@_ctr}\t#{cyan Array(@stack.length-1).join '|'}#{message}"
      else
        console.log "#{@_ctr}\t#{cyan Array(@stack.length-1).join '|'}#{message}"

  cacheSet: (key, value) ->
    if not @cache[key.pos]?[key.name]?
      (@cache[key.pos]||={})[key.name] = value
      @cacheStores.push key
    else
      throw new Error "Cache store error @ $.cache[#{keystr key}]: existing entry"

  cacheMask: (pos, stopName) ->
    stash = []
    for i in [@cacheStores.length-1..0] by -1
      cacheKey = @cacheStores[i]
      continue if cacheKey.pos isnt pos
      cacheValue = @cache[cacheKey.pos][cacheKey.name]
      delete @cache[cacheKey.pos][cacheKey.name]
      stash.push {cacheKey, cacheValue}
      break if cacheKey.name is stopName
    stash

  # key: {name,pos}
  cacheDelete: (key) ->
    assert.ok @cache[key.pos]?[key.name]?, "Cannot delete missing cache item at key #{keystr key}"
    cacheStoresIdx = undefined
    for i in [@cacheStores.length-1..0] by -1
      cKey = @cacheStores[i]
      if cKey.pos is key.pos and cKey.name is key.name
        cacheStoresIdx = i
        break
    assert.ok cacheStoresIdx, "cacheStores[] is missing an entry for #{keystr key}"
    delete @cache[key.pos][key.name]
    @cacheStores.splice cacheStoresIdx, 1

# aka '$' in compile functions 
@CompileContext = CompileContext = clazz 'CompileContext', ->
  init: ({@grammar}={}) ->
    @vars = {}
  makeVar: (preferredName) ->
    idx = 0
    while @vars["#{preferredName}#{idx}"]?
      idx += 1
    @vars[_var = "#{preferredName}#{idx}"] = _var
    _var
  destroyVar: (_var) ->
    if not @vars[_var]?
      console.log @vars, _var
    assert.ok @vars[_var]?, "Unknown $.scope var #{_var}"
    delete @vars[_var]
  scope: (vars, fn) ->
    vars = vars.split(/, *| +/g) if (typeof vars) is 'string'
    vars = (@makeVar(v) for v in vars)
    fn.apply(this, vars)
    @destroyVar(v) for v in vars
    null

###
  In addition to the attributes defined by subclasses,
    the following attributes exist for all nodes.
  node.rule = The topmost node of a rule.
  node.rule = rule # sometimes true.
  node.name = name of the rule, if this is @rule.
###
@Node = Node = clazz 'Node', ->

  @optionKeys = ['skipLog', 'skipCache', 'cb']

  @$stack = (fn) -> ($) ->
    if this isnt @rule then return fn.call this, $
    stackItem = name:@name, pos:$.code.pos
    $.stack.push stackItem
    result = fn.call this, $
    popped = $.stack.pop()
    assert.ok stackItem is popped
    return result

  @$debug = (fn) -> ($) ->
    if not $.debug or $.skipLog or this isnt @rule then return fn.call this, $
    $.skipLog = yes if @skipLog
    bufferStr = escape $.code.peek chars:20
    bufferStr = if bufferStr.length < 20 then '['+bufferStr+']' else '['+bufferStr+'>'
    $.log "#{red @name}: #{blue this} #{black bufferStr}", true
    result = fn.call this, $
    $.log "^-- #{escape result} #{black typeof result}", true if result isnt null
    delete $.skipLog
    return result

  @$cache = (fn) -> ($) ->
    if this isnt @rule or @skipCache then return fn.call this, $
    key = name:@name, pos:$.code.pos
    if (cached=$.cache[key.pos]?[key.name])?
      $.log "[C] Cache hit @ $.cache[#{keystr key}]: #{escape cached.result}" if debugCache
      $.code.pos = cached.endPos
      return cached.result
    $.storeCache = yes
    result = fn.call this, $
    if $.storeCache
      if not $.cache[key.pos]?[key.name]?
        $.log "[C] Cache store @ $.cache[#{keystr key}]: #{escape result}" if debugCache
        $.cacheSet key, result:result, endPos:$.code.pos
      else
        throw new Error "Cache store error @ $.cache[#{keystr key}]: existing entry"
    else
      $.storeCache = yes
      $.log "[C] Cache store (#{keystr key}) skipped manually." if debugCache
    return result

  @$loopify = (fn) -> ($) ->
    if this isnt @rule then return fn.call this, $
    key = name:@name, pos:$.code.pos
    item = ($.recurse[key.pos]||={})[key.name] ||= stage:0

    switch item.stage
      when 0 # non-recursive (so far)
        item.stage = 1
        startPos = $.code.pos
        startCacheLength = $.cacheStores.length
        result = fn.call this, $
        #try
        switch item.stage
          when 1 # non-recursive (done)
            delete $.recurse[key.pos][key.name]
            return result
          when 2 # recursion detected
            if result is null
              $.log "[L] returning #{escape result} (no result)" if debugLoopify
              $.cacheDelete key
              delete $.recurse[key.pos][key.name]
              return result
            else
              $.log "[L] --- loop start --- (#{keystr key}) (initial result was #{escape result})" if debugLoopify
              item.stage = 3
              while result isnt null
                $.log "[L] --- loop iteration --- (#{keystr key})" if debugLoopify

                # Step 1: reset the cache state
                bestCacheStash = $.cacheMask startPos, @name
                # Step 2: set the cache to the last good result
                bestResult = item.base = result
                bestPos = item.endPos = $.code.pos
                $.cacheSet key, result:bestResult, endPos:bestPos
                # Step 3: reset the code state
                $.code.pos = startPos
                # Step 4: get the new result with above modifications
                result = fn.call this, $
                # Step 5: break when we found the best result
                $.log "[L] #{@name} break unless #{$.code.pos} > #{bestPos}" if debugLoopify
                break unless $.code.pos > bestPos

              # Tidy up state to best match
              # Step 1: reset the cache state again
              $.cacheMask startPos, @name
              # Step 2: revert to best cache stash
              while bestCacheStash.length > 0
                {cacheKey,cacheValue} = bestCacheStash.pop()
                $.cacheSet cacheKey, cacheValue if not (cacheKey.name is key.name and cacheKey.pos is key.pos)
              assert.ok $.cache[key.pos]?[key.name] is undefined, "Cache value for self should have been cleared"
              # Step 3: set best code pos
              $.code.pos = bestPos
              $.log "[L] --- loop done --- (final result: #{escape bestResult})" if debugLoopify
              # Step 4: return best result, which will get cached
              delete $.recurse[key.pos][key.name]
              return bestResult
          else
            throw new Error "Unexpected stage #{item.stage}"
        #finally
        #  delete $.recurse[key.pos][key.name]
      when 1,2 # recursion detected
        item.stage = 2
        $.log "[L] recursion detected! (#{keystr key})" if debugLoopify
        $.log "[L] returning null" if debugLoopify
        return null
      when 3 # loopified case
        throw new Error "This should not happen, cache should have hit (#{keystr key})"
        #$.log "[L] returning #{item.base} (base case)" if debugLoopify
        #$.code.pos = item.endPos
        #return item.base
      else
        throw new Error "Unexpected stage #{item.stage} (B)"

  @$ruleCallback = (fn) -> ($) ->
    result = fn.call this, $
    result = @cb.call $, result if result isnt null and @cb?
    return result

  # Sequence nodes handle labels for its items, but otherwise
  # labeled nodes get casted into an object like {"#{label}": result}.
  # Also, Existential nodes are special.
  @$applyLabel = (fn) -> ($) ->
    parent = @findParent (node) -> node not instanceof Existential
    if parent instanceof Sequence then return fn.call this, $
    result = fn.call this, $
    if result isnt null and @label? and @label not in ['@','&']
      result_ = {}
      result_[@label] = result
      result = result_
    return result

  @$wrap = (fn) ->
    @$stack @$debug @$cache @$loopify @$ruleCallback @$applyLabel fn

  capture: yes
  walk: ({pre, post}, parent=undefined) ->
    # pre, post: (parent, childNode) -> where childNode in parent.children.
    pre parent, @ if pre?
    if @children
      for child in @children
        if child not instanceof Node
          throw Error "Unexpected object encountered walking children: #{child}"
        child.walk {pre: pre, post:post}, @
    post parent, @ if post?
  prepare: -> # implement if needed
  toString: -> "[#{@constructor.name}]"
  include: (name, rule) ->
    @rules ||= {}
    assert.ok name?, "Rule needs a name: #{rule}"
    assert.ok rule instanceof Node, "Invalid rule with name #{name}"
    assert.ok not @rules[name]?, "Duplicate name #{name}"
    rule.name = name if not rule.name?
    @rules[name] = rule
    @children.push rule
  # NOT USED (YET?)
  deref: (name, excepts={}) ->
    return this if @name is name
    return @rules[name] if @rules?[name]?
    excepts[name] = yes
    for name, rule in @rules when not excepts[name]?
      derefed = rule.deref excepts
      return derefed if derefed?
    return @parent.deref name, excepts if @parent?
    return null
  # find a parent in the ancestry chain that satisfies condition
  findParent: (condition) ->
    parent = @parent
    loop
      return parent if condition parent
      parent = parent.parent

@Choice = Choice = clazz 'Choice', Node, ->

  init: (@choices) ->
    @children = @choices

  prepare: ->
    @capture = _.all @choices, (choice)->choice.capture

  parse$: @$wrap ($) ->
    for choice in @choices
      result = $.try choice.parse
      if result isnt null
        return result
    return null

  compile: ($, result) ->
    @Trail undefined, (o) =>
      o @Assign result, @Null
      for choice in @choices
        $.scope 'pos', (pos) =>
          o @Assign pos, @Code.pos
          o choice.compile $, result
          o @If @Operation(result, 'is', @Null),
              @Assign(@Code.pos, pos),
              @Statement 'break'

  toString: -> blue("(")+(@choices.join blue(' | '))+blue(")")

@Rank = Rank = clazz 'Rank', Choice, ->

  @fromLines = (name, lines) ->
    rank = Rank name
    for line, idx in lines
      if line instanceof OLine
        choice = line.toRule rank, index:rank.choices.length
        rank.addChoice choice
      else if line instanceof ILine
        for own name, rule of line.toRules()
          rank.include name, rule
      else if line instanceof Object and idx is lines.length-1
        assert.ok (_.intersection Node.optionKeys, _.keys(line)).length > 0,
          "Invalid options? #{inspect line}"
        _.extend rank, line
      else
        throw new Error "Unknown line type, expected 'o' or 'i' line, got '#{line}' (#{typeof line})"
    rank

  init: (@name, @choices=[], includes={}) ->
    @rules = {}
    @children = []
    for choice, i in @choices
      @addChoice choice
    for name, rule of includes
      @include name, rule

  addChoice: (rule) ->
    @include rule.name, rule
    @choices.push rule

  toString: -> blue("Rank(")+(@choices.map((c)->c.name).join blue(' | '))+blue(")")

@Sequence = Sequence = clazz 'Sequence', Node, ->
  init: (@sequence) ->
    @children = @sequence

  prepare: ->
    @labels = []
    @captures = []
    for child in @children
      if child instanceof Existential
        if child.label
          @labels.push child.label
        else
          _.extend @labels, child.labels
          @captures.push child.captures if child.capture
      else
        @labels.push child.label if child.label
        @captures.push child if child.capture
    @type =
      if @labels.length is 0
        if @captures.length > 1 then 'array' else 'single'
      else
        'object'

  parse$: @$wrap ($) ->
    switch @type
      when 'array'
        results = []
        for child in @sequence
          res = child.parse $
          return null if res is null
          results.push res if child.capture
        return results
      when 'single'
        result = undefined
        for child in @sequence
          res = child.parse $
          return null if res is null
          result = res if child.capture
        return result
      when 'object'
        results = {}
        for child in @sequence
          res = child.parse $
          return null if res is null
          if child.label is '&'
            results = _.extend res, results
          else if child.label is '@'
            _.extend results, res
          else if child.label?
            results[child.label] = res
        return results
      else
        throw new Error "Unexpected type #{@type}"
    throw new Error

  compile: ($, result) ->
    @Trail undefined, (o) =>
      o @Assign result, @Undefined
      switch @type
        when 'array'
          $.scope 'results res', (results, res) =>
            o @Assign results, @Arr()
            for child in @sequence
              o .compile $, res
              o @If @Operation(res, 'is', @Null),
                  @Statement 'break',
                  if child.capture
                    @Invocation(@Index(results,'push'), res)
            o @Assign result, results
        when 'single'
          $.scope 'res', (res) =>
            for child in @sequence
              o child.compile $, res
              o @If @Operation(res, 'is', @Null),
                  @Block (o) =>
                    o @Assign result, @Null
                    o @Statement 'break'
                  ,
                  if child.capture
                    o @Assign result, res
        when 'object'
          $.scope 'results res', (results, res) =>
            o @Assign results, @Obj(@Item(label,@Null) for label in @labels)
            for child in @sequence
              o child.compile $, res
              o @If @Operation(res, 'is', @Null),
                  @Statement 'break',
                  if child.label is '&'
                    @Assign results, @Invocation(@_.extend, res, results)
                  else if child.label is '@'
                    @Invocation @_.extend, results, res
                  else if child.label?
                    @Assign @Index(results,child.label), res
            o @Assign result, results

  toString: ->
    labeledStrs = for node in @sequence
      if node.label?
        "#{cyan node.label}#{blue ':'}#{node}"
      else
        ''+node
    blue("(")+(labeledStrs.join ' ')+blue(")")

@Lookahead = Lookahead = clazz 'Lookahead', Node, ->
  capture: no
  init: ({@chars, @words, @lines}) ->
  parse$: @$wrap ($) ->
    $.code.peek chars:@chars, words:@words, lines:@lines
  compile: ($, result)->
    @Invocation(@Code.peek, @Obj(@Item('chars',@chars),@Item('words':@words),@Item(lines:@lines)))
  toString: ->
    "<#{
      yellow @chars? and "chars:#{@chars}" or
             @words? and "words:#{@words}" or
             @lines? and "lines:#{@lines}"
    }>"

@Existential = Existential = clazz 'Existential', Node, ->
  init: (@it) ->
    @children = [@it]
  prepare: ->
    @labels = []
    @captures = []
    if @it.label?
      @labels.push @it.label
    else if @it instanceof Sequence or @it instanceof Existential
      _.extend @labels, @it.labels
      _.extend @captures, @it.captures
    else
      @captures.push this if @it.capture
    @label = '@' if not @label? and @labels.length > 0
    @capture = @captures.length > 0
  parse$: @$wrap ($) ->
    res = $.try @it.parse
    return res ? undefined
  compile: ($, result) ->
    @Block (o) => $.scope 'pos', (pos) =>
      o @Assign pos, @Code.pos
      o @it.compile $, result
      o @If @Operation(result, 'is', @Null),
          @Block (o) =>
            o @Assign(@Code.pos, pos),
            o @Assign(result, @Undefined)
  toString: -> ''+@it+blue("?")

@Pattern = Pattern = clazz 'Pattern', Node, ->
  init: ({@value, @join, @min, @max}) ->
    @children = if @join? then [@value, @join] else [@value]
    @capture = @value.capture
  parse$: @$wrap ($) ->
    matches = []
    result = $.try =>
      resV = @value.parse $
      if resV is null
        return null if @min? and @min > 0
        return []
      matches.push resV
      loop
        action = $.try =>
          if @join?
            resJ = @join.parse $
            # return null to revert pos
            return null if resJ is null
          resV = @value.parse $
          # return null to revert pos
          return null if resV is null
          matches.push resV
          return 'break' if @max? and matches.length >= @max
        break if action in ['break', null]
      return null if @min? and @min > matches.length
      return matches
    return result

  compile: ($, result) ->
    @Block (o) => $.scope 'matches pos resV', (matches, pos, resV) =>
      o @Assign matches, @Arr()
      o @Assign pos, @Code.pos
      o @Trail 'outer', (o) =>
        o @value.compile $, resV
        o @If @Operation(resV, 'is', @Null),
            @Block (o) =>
              if @min? and @min > 0
                o @Assign result, @Null
              else
                o @Assign result, @Arr()
              o @Statement 'break', 'outer'
        o @Invocation @Index(matches,'push'), resV
        o @Loop 'inner', (o) => $.scope 'pos resJ', (pos, resJ) =>
          o @Assign pos, @Code.pos
          if @join?
            o @join.compile $, resJ
            o @If @Operation(resJ, 'is', @Null),
                @Block (o) =>
                  o @Assign @Code.pos, pos
                  o @Statement 'break', 'inner'
          o @value.compile $, resV
          o @If @Operation(resV, 'is', @Null),
              @Block (o) =>
                o @Assign @Code.pos, pos
                o @Statement 'break', 'inner'
          o @Invocation @Index(matches,'push'), resV
          if @max?
            o @If @Operation(@Index(matches,'length'), '>=', @max),
                @Statement 'break', 'inner'
        if @min?
          o @If @Operation(@min, '>', @Index(matches,'length')),
              @Block (o) =>
                o @Assign result, @Null
                o @Assign @Code.pos, pos
                o @Statement 'break', 'outer'
      o @Assign result, matches
  toString: ->
    "#{@value}#{cyan "*"}#{@join||''}#{cyan if @min? or @max? then "{#{@min||''},#{@max||''}}" else ''}"

@Not = Not = clazz 'Not', Node, ->
  capture: no
  init: (@it) ->
    @children = [@it]
  parse$: @$wrap ($) ->
    pos = $.code.pos
    res = @it.parse $
    $.code.pos = pos
    if res isnt null
      return null
    else
      return undefined
  compile: ($, result) ->
    @Block (o) => $.scope 'pos res', (pos, res) =>
      o @Assign pos, @Code.pos
      o @it.compile $, res
      o @Assign @Code.pos, pos
      o @If @Operation(res,'isnt',@Null),
          @Assign result, @Null
          @Assign result, @Undefined
  toString: -> "#{yellow '!'}#{@it}"

@Ref = Ref = clazz 'Ref', Node, ->
  # note: @ref because @name is reserved.
  init: (@ref) ->
    @capture = no if @ref[0] is '_'
  parse$: @$wrap ($) ->
    node = $.grammar.rules[@ref]
    throw Error "Unknown reference #{@ref}" if not node?
    return node.parse $
  compile: ($, result) ->
    node = $.grammar.rules[@ref]
    throw Error "Unknown reference #{@ref}" if not node?
    @Assign result, @Invocation @Index($.Grammar,@ref)
  toString: -> red(@ref)

@Str = Str = clazz 'Str', Node, ->
  capture: no
  init: (@str) ->
  parse$: @$wrap ($) -> $.code.match string:@str
  compile: ($, result) -> @Invocation @Code.match, @Obj(@Item('string',@str))
  toString: -> green("'#{escape @str}'")

@Regex = Regex = clazz 'Regex', Node, ->
  init: (@reStr) ->
    if typeof @reStr isnt 'string'
      throw Error "Regex node expected a string but got: #{@reStr}"
    @re = RegExp '^'+@reStr
  parse$: @$wrap ($) -> $.code.match regex:@re
  compile: ($, result) -> @Invocation @Code.match, @Obj(@Item('regex',@re))
  toString: -> magenta(''+@re)

# Main external access.
# I dunno if Grammar should be a Node or not. It
# might come in handy when embedding grammars
# in some glue language.
@Grammar = Grammar = clazz 'Grammar', Node, ->

  # Temporary convenience function for loading a Joescript file with
  # a single GRAMMAR = ... definition, for parser generation.
  # A proper joescript environment should give access of
  # block ASTs to the runtime, thereby making this compilation step
  # unnecessary.
  @fromFile = (filename) ->
    js = require('./joescript_grammar')
    chars = require('fs').readFileSync filename, 'utf8'
    try
      fileAST = js.GRAMMAR.parse chars
    catch error
      console.log "Joeson couldn't parse #{filename}. Parse log..."
      js.GRAMMAR.parse chars, debug:yes
      throw error
    jsNodes = js.NODES
    assert.ok fileAST instanceof js.NODES.Block

    # Find GRAMMAR = ...
    grammarAssign = _.find fileAST.lines, (line) ->
      line instanceof js.NODES.Assign and
        ''+line.target is 'GRAMMAR' and
        line.type is '='
    grammarAST = grammarAssign.value

    # Compile an AST node
    # Func Nodes (->) become Arrays
    #  (unless it's a non-first parameter to an Invocation, a callback function)
    # Str, Obj, Arr, and Invocations become interpreted directly
    compileAST = (node) ->
      switch node.constructor
        when js.NODES.Func
          assert.ok node.params is undefined, "Rank function should accept no parameters"
          assert.ok node.type is '->', "Rank function should be ->, not #{node.type}"
          return node.block.lines.map( (item)->compileAST item ).filter (x)->x?
        when js.NODES.Word
          # words *should* be function references. Pass the AST on.
          return node
        when js.NODES.Invocation
          func = MACROS[''+node.func]
          assert.ok func?, "Function #{node.func.name} not in MACROS"
          params = node.params.map (p) ->
            # Func nodes that are direct invocation parameters do not
            # get interpreted, they are callback functions
            # & joeson rules need them as ASTs for parser generation.
            if p instanceof js.NODES.Func then p else compileAST p
          return func.apply null, params
        when js.NODES.Str
          assert.ok _.all node.parts, (part) -> typeof part is 'string'
          return node.parts.join ''
        when js.NODES.Arr
          return node.items.map (item) -> compileAST item
        when js.NODES.Obj
          obj = {}
          for item in node.items
            if ''+item.key in ['cb'] # pass the AST thru.
              obj[compileAST item.key] = item.value
            else
              obj[compileAST item.key] = compileAST item.value
          return obj
        when js.NODES.Heredoc
          return null
        else
          throw new Error "Unexpected node type #{node.constructor.name}"

    return Grammar compileAST grammarAST

  init: (rank) ->
    rank = rank(MACROS) if typeof rank is 'function'
    @rank = Rank.fromLines "__grammar__", rank if rank instanceof Array
    @rules = {}

    # Initial setup
    @rank.walk
      pre: (parent, node) =>
        if node.parent? and node isnt node.rule
          throw Error 'Grammar tree should be a DAG, nodes should not be referenced more than once.'
        # set node.parent, the immediate parent node
        node.parent = parent
        # set node.rule, the root node for this rule
        if not node.inlineLabel?
          node.rule ||= parent?.rule
        else
          # inline rules are special
          node.rule = node
          parent.rule.include node.inlineLabel, node
      post: (parent, node) =>
        # dereference all rules
        if node.rules?
          assert.equal (inter = _.intersection _.keys(@rules), _.keys(node.rules)).length, 0, "Duplicate key(s): #{inter.join ','}"
          _.extend @rules, node.rules
        # call prepare on all nodes
        node.prepare()

  parse$: (code, {debug,returnContext}={}) ->
    debug ?= no
    returnContext ?= no
    code = CodeStream code if code not instanceof CodeStream
    $ = ParseContext code:code, grammar:this, debug:debug
    $.result = @rank.parse $
    throw Error "Incomplete parse: '#{escape $.code.peek chars:50}'" if $.code.pos isnt $.code.text.length
    if returnContext
      return $
    else
      return $.result

  compile: () ->
    js = require('./joescript_grammar').NODES
    if not Node::Code
      @initNodeASTShortcuts()
    $ = CompileContext grammar:this
    code = @Block (o) => $.scope 'grammar code result', (grammar, code, result) =>
      for name, rule of @rules
        funcBlock = rule.compile $, result
        funcBlock = js.Block funcBlock if funcBlock not instanceof js.Block
        funcBlock.lines.push js.Statement 'return', result
        o @Assign @Index(grammar,name), @Func(null,'->',funcBlock)
      o @Assign result, @Null
      o @rank.compile $, result
    return code

  initNodeASTShortcuts: ->
    js = require('./joescript_grammar').NODES
    _.extend (Node::),
      Grammar:  js.Word('grammar0') # {"#{rulename}": <Function>}
      Code:
        pos:    js.Index(obj:js.Word('code0'), attr:'pos')
        match:  js.Index(obj:js.Word('code0'), attr:'match')
      _:
        extend: js.Index(obj:js.Word('_'),     attr:'extend')
      Null: js.Word 'null'
      Undefined: js.Word 'undefined'
      Func: (params,type,block) -> js.Func params:params,type:type,block:block
      If: (cond,block,elseBlock) -> js.If cond:cond,block:block,elseBlock:elseBlock
      Assign: (target,value) -> js.Assign target:target,type:'=',value:value
      Operation: (left,op,right) -> js.Operation left:left,op:op,right:right
      Statement: (type,expr) -> js.Statement type:type,expr:expr
      Invocation: (func,params...) -> js.Invocation func:func,params:params
      Index: (obj,attr) -> js.Index obj:obj,attr:attr
      Obj:  (items...) -> js.Obj (if items.length is 1 and items[0] instanceof Array then items[0] else items)
      Arr:  js.Arr
      Item: js.Item
      Word: js.Word
      Block: (fn) ->
        lines = []
        o = (line) ->
          if line instanceof js.Block
            _.extend lines, line.lines
          else
            lines.push line
        fn.call this, o
        js.Block lines
      Loop: (name, fn) -> js.Loop label:name,block:@Block(fn)
      Trail: (name, fn) ->
        block = @Block(fn)
        block.lines.push @Statement 'break', name
        js.Loop label:name,block:block

Line = clazz 'Line', ->
  init: (@args...) ->
  # name: The final and correct name for this rule
  # rule: A rule-like object
  # parentRule: The actual parent Rule instance
  # options: {cb,...}
  getRule: (name, rule, parentRule, options) ->
    if typeof rule is 'string'
      try
        rule = GRAMMAR.parse rule
      catch err
        console.log "Error in rule #{name}: #{rule}"
        GRAMMAR.parse rule, debug:yes
    else if rule instanceof Array
      rule = Rank.fromLines name, rule
    else if rule instanceof OLine
      rule = rule.toRule parentRule, name:name
    assert.ok not rule.rule? or rule.rule is rule
    rule.rule = rule
    assert.ok not rule.name? or rule.name is name
    rule.name = name
    _.extend rule, options if options?
    rule
  # returns {rule:rule, options:{cb,skipCache,skipLog,...}}
  getArgs: ->
    [rule, rest...] = @args
    result = rule:rule, options:{}
    for own key, value of rule
      if key in Node.optionKeys
        result.options[key] = value
        delete rule[key]
    for next in rest
      if next instanceof Function
        result.options.cb = next
      else
        _.extend result.options, next
    result
  toString: ->
    "#{@type} #{@args.join ','}"

ILine = clazz 'ILine', Line, ->
  type: 'i'
  toRules: (parentRule) ->
    {rule, options} = @getArgs()
    rules = {}
    # for an ILine, rule is an object of {"NAME":rule}
    for own name, _rule of rule
      rules[name] = @getRule name, _rule, parentRule, options
    rules

OLine = clazz 'OLine', Line, ->
  type: 'o'
  toRule: (parentRule, {index,name}) ->
    {rule, options} = @getArgs()
    # figure out the name for this rule
    if not name and
      typeof rule isnt 'string' and
      rule not instanceof Array and
      rule not instanceof Node
        # NAME: rule
        assert.ok _.keys(rule).length is 1, "Named rule should only have one key-value pair"
        name = _.keys(rule)[0]
        rule = rule[name]
    else if not name? and index? and parentRule?
      name = parentRule.name + "[#{index}]"
    else if not name?
      throw new Error "Name undefined for 'o' line"
    rule = @getRule name, rule, parentRule, options
    rule.parent = parentRule
    rule.index = index
    rule

@MACROS = MACROS =
  # Any rule node, possibly part of a Rank node
  o: OLine
  # Include line... Not included in the Rank order
  i: ILine
  # Helper for declaring tokens
  tokens: (tokens...) ->
    cb = tokens.pop() if typeof tokens[tokens.length-1] is 'function'
    rank = Rank()
    for token in tokens
      name = '_'+token.toUpperCase()
      rule = GRAMMAR.parse "_ &:'#{token}' <chars:1> !/[a-zA-Z\\$_0-9]/"
      rule.skipLog = yes
      rule.skipCache = yes
      rule.cb = cb if cb?
      rank.choices.push rule
      rank.include name, rule
    OLine rank

C  = -> Choice (x for x in arguments)
E  = -> Existential arguments...
L  = (label, node) -> node.label = label; node
La = -> Lookahead arguments...
N  = -> Not arguments...
P  = (value, join, min, max) -> Pattern value:value, join:join, min:min, max:max
R  = -> Ref arguments...
Re = -> Regex arguments...
S  = -> Sequence (x for x in arguments)
St = -> Str arguments...
{o, i, tokens}  = MACROS

@GRAMMAR = GRAMMAR = Grammar [
  o EXPR: [
    o S(R("CHOICE"), R("_"))
    o "CHOICE": [
      o S(P(R("_PIPE")), P(R("SEQUENCE"),R("_PIPE"),2), P(R("_PIPE"))), Choice
      o "SEQUENCE": [
        o P(R("UNIT"),null,2), Sequence
        o "UNIT": [
          o S(R("_"), R("LABELED"))
          o "LABELED": [
            o S(E(S(L("label",R("LABEL")), St(':'))), L('&',C(R("COMMAND"),R("DECORATED"),R("PRIMARY"))))
            o "COMMAND": [
              o S(St('<chars:'), L("chars",R("INT")), St('>')), Lookahead
              o S(St('<words:'), L("words",R("INT")), St('>')), Lookahead
            ]
            o "DECORATED": [
              o S(R("PRIMARY"), St('?')), Existential
              o S(L("value",R("PRIMARY")), St('*'), L("join",E(S(N(R("__")), R("PRIMARY")))), L("@",E(R("RANGE")))), Pattern
              o S(L("value",R("PRIMARY")), St('+'), L("join",E(S(N(R("__")), R("PRIMARY"))))), ({value,join}) -> Pattern value:value, join:join, min:1
              o S(L("value",R("PRIMARY")), L("@",R("RANGE"))), Pattern
              o S(St('!'), R("PRIMARY")), Not
              i "RANGE": o S(St('{'), R("_"), L("min",E(R("INT"))), R("_"), St(','), R("_"), L("max",E(R("INT"))), R("_"), St('}'))
            ]
            o "PRIMARY": [
              o R("WORD"), Ref
              o S(St('('), L("inlineLabel",E(S(R('WORD'), St(': ')))), L("&",R("EXPR")), St(')'))
              o S(St("'"), P(S(N(St("'")), C(R("ESC1"), R(".")))), St("'")), (it) -> Str       it.join ''
              o S(St("/"), P(S(N(St("/")), C(R("ESC2"), R(".")))), St("/")), (it) -> Regex     it.join ''
              o S(St("["), P(S(N(St("]")), C(R("ESC2"), R(".")))), St("]")), (it) -> Regex "[#{it.join ''}]"
            ]
          ]
        ]
      ]
    ]
  ]
  i LABEL:    C(St('&'), St('@'), R("WORD"))
  i WORD:     S(La(words:1), Re("[a-zA-Z\\._][a-zA-Z\\._0-9]*"))
  i INT:      S(La(words:1), Re("[0-9]+")), Number
  i _PIPE:    S(R("_"), St('|'))
  i _:        P(C(St(' '), St('\n')))
  i __:       P(C(St(' '), St('\n')), null, 1)
  i '.':      S(La(chars:1), Re("[\\s\\S]"))
  i ESC1:     S(St('\\'), R("."))
  i ESC2:     S(St('\\'), R(".")), (chr) -> '\\'+chr
]
