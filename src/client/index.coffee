@require = require

_scrollDown = (el) ->
  height = el.prop('scrollHeight')
  el.scrollTop(height)

# init. keep the DOM minimal so that this loads fast.
$(document).ready ->

  console.log "booting..."

  # configure logging
  {debug, info, warn, fatal} = require('nogg').logger __filename.split('/').last()
  domLog = window.domLog = $('#log')
  require('nogg').configure
    default:
      file:
        write: (line) ->
          domLog.append toHTML line
          _scrollDown $('#footer')
      level: 'debug'

  # UILayout
  $('body').layout
    defaults:
      applyDefaultStyles: no
    south:
      size:               500 # TODO
      applyDefaultStyles: yes
      initClosed:         yes
      onopen_end:         -> process.nextTick -> _scrollDown $('#main'); _scrollDown $('#footer')

  # load libraries
  {clazz} = require 'cardamom'
  {inspect} = require 'util'
  {randid} = require 'sembly/lib/helpers'
  {toHTML} = require 'sembly/src/parsers/ansi'
  {
    JKernel, JThread
    NODES:{JObject, JArray, JUser, JUndefined, JNull, JNaN, JBoundFunc, JStub}
    HELPERS:{isInteger,isObject}
  } = require 'sembly/src/interpreter'
  JSL = require 'sembly/src/parsers/jsl'
  require 'sembly/src/client/dom' # DOM plugin
  require 'sembly/src/client/misc' # DOM plugin
  {Editor} = require 'sembly/src/client/editor'

  # Can't use CACHE because that'll overwrite client state.
  # TODO reword. I don't know what ^^^ means.
  # Don't I want to overwrite the client state?
  cache = window.cache = {}

  # connect to server
  socket = window.socket = io.connect()

  # catch uncaught errors
  _err_ = (fn) ->
    wrapped = ->
      try
        fn.apply this, arguments
      catch err
        fatal "Uncaught error in socket callback: #{err.stack ? err}"
        console.log "Uncaught error in socket callback: #{err.stack ? err}"

  screen = undefined

  ## Send url to server.
  socket.emit 'load', window.location.pathname[1...]

  ## (re)initialize the screen.
  socket.on 'screen', _err_ (screenStr) ->
    console.log "received screen:", screenStr

    try
      screen = JSL.parse screenStr, env:{cache}
    catch err
      fatal "Error in parsing screenStr '#{screenStr}':\n#{err.stack ? err}"
      return

    # Attach screen JView
    try
      window.screenView = screen.newView()
      $('#screen').empty().append screenView.rootEl
    catch err
      fatal "Error in attaching screen view to DOM\n#{err.stack ? err}"

  # Attach listener for events
  socket.on 'event', _err_ (eventJSON) ->
    # console.log "eventJSON", eventJSON
    obj = cache[eventJSON.sourceId]
    info "new event #{inspect eventJSON} for obj ##{obj.id}"
    if not obj?
      fatal "Event for unknown object ##{eventJSON.sourceId}."
      return

    for key, value of eventJSON
      unless key in ['type', 'key', 'sourceId']
        try
          eventJSON[key] = valueObj = JSL.parse value, env:{cache} #, newCallback:(newObj) -> newObj.addListener screenView}
        catch err
          fatal "Error in parsing event item '#{key}':#{value} :\n#{err.stack ? err}"
          # XXX not sure what should go here.
    try
      obj.emit eventJSON
    catch err
      fatal "Error while emitting event to object ##{obj.id}:\n#{err.stack ? err}"

    # HACK to scroll down for screen.push
    _scrollDown $('#main') if obj is screen

  # Attach an editor now that screen is available.
  unless window.editor?
    editor = window.editor = new Editor el:$('#input_editor'), callback: (codeStr) ->
      console.log "sending code"
      socket.emit 'run', codeStr
      _scrollDown $('#main')

    # ipad hack, getting the touch keyboard to show up when tapping the page for the first time
    if navigator.userAgent.match(/(iPad)|(iPhone)|(iPod)/i)
      $('#screen').append($('<input id="ipadhack" type="text"></input>'))
      $('#ipadhack').focus().hide()
    else
      editor.focus()
    # ipad hack end
    $('#input_editor').click -> editor.focus()
    $(document.body).click -> editor.focus(); no
    $('#input_submit').click (e) ->
      editor.submit()
      no

  ## Server diagnostic info
  socket.on 'server_info.', _err_ (data) ->
    for key, value of data.memory
      data.memory[key] = (Math.floor(value/10000)/100.0)+"Mb"
    $('#server_info').text(inspect data)

  process.nextTick -> socket.emit 'server_info?'
  $('#server_info_refresh').click -> socket.emit 'server_info?'; no
