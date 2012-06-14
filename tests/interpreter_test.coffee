{clazz, colors:{red, blue, cyan, magenta, green, normal, black, white, yellow}} = require('cardamom')
{inspect} = require 'util'
{equal, ok} = require 'assert'
_ = require 'underscore'
joe = require 'joeson/src/joescript'
{JRuntimeContext, SYSTEM} = require 'joeson/src/interpreter'

console.log blue "\n-= interpreter test =-"

counter = 0
test = (code, cb) ->
  console.log "#{red "test #{counter++}:"}\n#{normal code}"
  node = require('joeson/src/joescript').parse code
  node = node.toJSNode().installScope()
  #console.log node.serialize()
  $ = new JRuntimeContext SYSTEM.user
  try
    res = $.exec node
    cb.call context:$, it:res, node:node
  catch err
    console.log red "TEST ERROR:"
    console.log red err.stack
    process.exit(1)

test ' null ',                            -> equal @it, null
test ' undefined ',                       -> equal @it, undefined
test ' null * undefined ',                -> ok isNaN @it
test ' {} ',                              -> ok @it instanceof Object and _.keys(@it).length is 0
test ' {foo:1} ',                         -> ok @it instanceof Object and _.keys(@it).length is 1 and @it.foo is 1
test ' a = {foo:1}; a.foo ',              -> equal @it, 1
test ' if true then 1 else 2 ',           -> equal @it, 1
test ' if false then 1 else 2 ',          -> equal @it, 2
test ' a = "bar" ',                       -> equal @it, 'bar'
test ' a = "bar"; a ',                    -> equal @it, 'bar'
test '''
a = 'foo'
b = 'bar'
a + b
''',                                      -> equal @it, 'foobar'
test ' 1 + 2 * 3 + 4 ',                   -> equal @it, 11
test '''
foo = (bar) -> return bar + 1
foo(1)
''',                                      -> equal @it, 2

###
test "Array", Array
outer = (foo) ->
  inner = ->
    return foo + 1
func = outer(1)
func()
""", 2
test """
outer = (foo) ->
  bar = foo
  inner = ->
    bar = bar + 1
func = outer(1)
func()
func()
func()
func()
func()
""", 6
test """
outer = (foo) ->
  inner = ->
    bar = bar + 1
  bar = foo
  return inner
func = outer(1)
func()
func()
""", NaN
test """
outer = (foo) ->
  bar = foo
  inner = ->
    bar = bar + 1
func = outer(1)
a = func() for i in [1..5]
a
""", 6
test """
foo = ->
  1 + 1
foo()""", 2

# construction tests
test """
a = ->
new a""", (it) ->
  assert.ok it instanceof Object
  assert.ok _.keys(it).length is 0
  yes

test """
Foo = ->
  this.a = 'A'
  this.b = 'B'
f = new Foo()""", (it) ->
  assert.ok it instanceof Object
  assert.ok _.keys(it).length is 2
  assert.ok it.a is 'A' and it.b is 'B'
  yes

test """
p = {key:'value'}
Foo = ->
Foo.prototype = p
f = new Foo
f.key""", 'value'

test """
_ = require('underscore')
_.keys(foo:1, bar:2, baz:3).join(',')""", 'foo,bar,baz'
###