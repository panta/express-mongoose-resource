fs     = require 'fs'
{exec} = require 'child_process'
util   = require 'util'
glob   = require 'glob'
muffin = require 'muffin'

option '-w', '--watch', 'continue to watch the files and rebuild them when they change'
option '-c', '--commit', 'operate on the git index instead of the working tree'
option '-m', '--compare', 'compare across git refs, stats task only.'

# Define a Cake task called build
task 'build', 'compile library', (options) ->
  # Run a map on all the files in the top directory
  muffin.run
    files: './src/**/*'
    options: options
    # For any file matching 'src/*.coffee', compile it to 'lib/*.js'
    map:
      'src/(.+).coffee' : (matches) -> muffin.compileScript(matches[0], "lib/#{matches[1]}.js", options)
   console.log "Watching src..." if options.watch

task 'stats', 'print source code stats', (options) ->
  muffin.statFiles(['lib/index.js'], options)

task 'doc', 'autogenerate docco anotated source and node IDL files', (options) ->
  muffin.run
    files: './src/**/*'
    options: options
    map:
      'src/index.coffee' : (matches) -> muffin.doccoFile(matches[0], options)

task 'test', ->