http = require 'http'
connect = require 'connect'
{debug, info, warn, error:fatal} = (nogg=require('nogg')).logger 'server'
assert = require 'assert'


# logging
nogg.configure
  'default': [
    {file: 'logs/app.log',    level: 'debug'},
    {file: 'stdout',          level: 'debug'}]
  #'foo': [
  #  {file: 'foo.log',    level: 'debug'},
  #  {forward: 'default'}]
  'access': [
    {file: 'logs/access.log', formatter: null}]

# uncaught exceptions
process.on 'uncaughtException', (err) ->
  warn """\n
^^^^^^^^^^^^^^^^^
http://debuggable.com/posts/node-js-dealing-with-uncaught-exceptions:4c933d54-1428-443c-928d-4e1ecbdd56cb
#{err.message}
#{err.stack}
vvvvvvvvvvvvvvvvv
"""

# server
c = connect()
  .use(connect.logger())
  #.use(connect.staticCache())
  .use('/s', connect.static(__dirname + '/static'))
  .use(connect.favicon())
  .use(connect.cookieParser('TODO determine just how secret this is'))
  .use(connect.session({ cookie: { maxAge: 1000*60*60*24*30 }}))
  .use(connect.query())
  .use(connect.bodyParser())
c.use (req, res) ->
  res.writeHead 200, {'Content-Type': 'text/html'}
  res.end """
<html>
<link rel='stylesheet' type='text/css' href='http://fonts.googleapis.com/css?family=Anonymous+Pro'/>
<link rel='stylesheet' type='text/css' href='/s/style.css'/>
<script src='/s/jquery-1.7.2.js'></script>
<script src='/s/boot.js'></script>
<body>
  hello
</body>
</html>
"""

# server app
app = http.createServer(c)
io = require('socket.io').listen app
app.listen 8080

# kernel
{JKernel, GOD} = require 'joeson/src/interpreter'
kern = new JKernel
info "initialized kernel runloop"

# connect.io <-> kernel
io.sockets.on 'connection', (socket) ->

  # start code
  socket.on 'start', ({code,thread}) ->
    info "received code #{code}, thread id #{thread}"
    socket.get 'user', (err, user) ->
      # note: user may be null for new users.
      if err?
        fatal "Couldn't get the user of the socket", err, err.stack
        return
      kern.run
        user: user,
        code: code,
        stdout: (html) ->
          assert.ok typeof html is 'string', "stdout can only print html strings"
          info "stdout", html, thread
          socket.emit 'stdout', html:html, thread:thread
        stderr: (html) ->
          assert.ok typeof html is 'string', "stderr can only print html strings"
          info "stderr", html, thread
          socket.emit 'stderr', html:html, thread:thread
        stdin:  undefined # not implemented
