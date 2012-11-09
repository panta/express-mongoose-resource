# express-mongoose-resource
# Copyright (C) 2012 Marco Pantaleoni.
#
# Distributed under the MIT License.

# Inspired by:
#   https://github.com/visionmedia/express/blob/master/examples/mvc/mvc.js
#   https://github.com/visionmedia/express-resource/
#   https://github.com/jsmarkus/colibri
#
# See also:
#   https://github.com/bebraw/rest-sugar
#   https://github.com/enyo/mongo-rest

#
# Usage:
#
# app.resource('forums', {model: Forum})
#   or
# app.resource({model: Forum})
#
# this will add automatically the following routes to the app:
#
# GET     /forums/schema       ->  return the model schema
# GET     /forums              ->  index
# GET     /forums/new          ->  new
# POST    /forums              ->  create
# GET     /forums/:forum       ->  show
# GET     /forums/:forum/edit  ->  edit
# PUT     /forums/:forum       ->  update
# DELETE  /forums/:forum       ->  destroy
#
# Note that if 'model' is not specified, app.resource falls back to
# express-resource implementation.

express = require('express')
Resource = exports.Resource = require('express-resource-middleware')

# Extend a source object with the properties of another object (shallow copy).
extend = (dst, src, overwrite=true) ->
  if src?
    for key, val of src
      if (key not of dst) or overwrite
        dst[key] = val
  dst

# Add missing properties from a `src` object.
defaults = (dst, src) ->
  for key, val of src
    if not (key of dst)
      dst[key] = val
  dst

invoke_callbacks = (context, callbacks, req, res) ->
  callback_invoke = (context, callbacks, i, err, req, res) ->
    l = callbacks.length
    if i >= l
      return
    next = (err) ->
      return callback_invoke(context, callbacks, i+1, err)
    cb = callbacks[i]
    if cb.length >= 4
      # error handler - (err, req, res, next)
      return callbacks[i].call(context, err, req, res, next)
    return callbacks[i].call(context, req, res, next)

  callback_invoke(context, callbacks, 0, null, req, res)

old_Resource_add = Resource::add
Resource::add = (resource, opts) ->
  if resource.controller? and opts.pivotField?
    resource.controller.trace("specifying pivot field '#{opts.pivotField}' and req field '#{@id}'")
    resource.controller.opts.pivot =
      modelField: opts.pivotField
      requestField: @id
  else
    console.log("no @controller or opts.pivotField")
  old_Resource_add.call(@, resource)

class ModelController
  @TOOBJECT_DEFAULT_OPTS:
    getters: true

  constructor: (@app, @name, @model, @opts) ->
    @schema = @model.schema
    @modelName = @model.modelName
    @_trace = @opts.trace or true
    @_default_format = @opts.format or 'json'
    @_toObjectOpts = {}
    @_pre_serialize_cbs = []
    @_serialize_cb = null
    @_post_serialize_cbs = []
    @setSerializeCallback(@_default_serialize_cb)

    if @opts.pre_serialize
      for cb in @opts.pre_serialize
        @addPreSerializeCallback(cb)
    if @opts.serialize
      @setSerializeCallback(@opts.serialize)
    if @opts.post_serialize
      for cb in @opts.post_serialize
        @addPostSerializeCallback(cb)

    @_computeToObjectOpts()

    @trace(@schema)

    if @name is null
      @name = @modelName.toLowerCase()
    @singular = @name
    if 'plural' of @opts
      @plural = @opts.plural
    else
      @plural = @name
      if @plural[@plural.length-1] != 's'
        @plural += 's'
    @name = @plural

    # @base is the url base - without model name
    # (with leading slash and no trailing slash)
    if 'base' of opts
      @base = opts.base
    else
      @base = "/"
    if @base[0] != '/'
      @base = '/' + @base
    if @base[@base.length-1] == '/'
      @base = @base[0...@base.length-1]

    # @url_prefix is the url prefix complete with model name
    # (with leading slash and no trailing slash)
    @url_prefix = @base + "/" + @name
    if @url_prefix[0] != '/'
      @url_prefix = '/' + @url_prefix
    if @url_prefix[@url_prefix.length-1] == '/'
      @url_prefix = @url_prefix[0...@url_prefix.length-1]

  getSchema: ->
    schema = {}
    getPathInfo = (pathname, path) =>
      #path = @model.schema.path(pathname)
      # TODO: handle compound pathnames (like 'aaa.bbb')
      pathInfo =
        name: pathname
        kind: path.instance
        type: @model.schema.pathType(pathname)
      if path.instance is 'ObjectID'
        if 'ref' of path.options
          pathInfo.references = path.options.ref
        if 'auto' of path.options
          pathInfo.auto = path.options.auto
      pathInfo
    @model.schema.eachPath (pathname) =>
      path = @model.schema.path(pathname)
      pathInfo = getPathInfo(pathname, path)
      schema[pathname] = pathInfo
    for pathname, virtual of @model.schema.virtuals
      pathInfo = getPathInfo(pathname, virtual)
      schema[pathname] = pathInfo
    schema

  _register_schema_action: ->
    @app.get "#{@url_prefix}/schema", (req, res, next) =>
      res.send(@getSchema())

  # -- express-resource auto-loader ---------------------------------

  _auto_load: (req, id, fn) ->
    @trace("[auto-load] id:#{id} res.id:#{@resource.id}")
    @get id, fn

  # -- template rendering support -----------------------------------

  getTemplateContext: (req, res, extra) ->
    context =
      model: @model
      schema: @schema
      modelName: @modelName
      name: @name
      base: @base
      url_prefix: @url_prefix
      resource_id: @resource.id
    pivot = {}
    if @opts.pivot?
      @trace("we have a pivot model field: '#{@opts.pivot.modelField}' req field: '#{@opts.pivot.requestField}'")
      @trace("req.#{@opts.pivot.requestField} = #{req[@opts.pivot.requestField]}")
      if @opts.pivot.requestField of req
        pivot.pivot = @opts.pivot.requestField
        pivot.pivot_id = req[@opts.pivot.requestField].id
        pivot[@opts.pivot.requestField] = @preprocess_instance(req[@opts.pivot.requestField])
    defaults context, pivot
    return extend context, extra

  getInstanceTemplateContext: (req, res, instance, extra) ->
    serialized = @preprocess_instance(instance)
    context = @getTemplateContext req, res,
      instance: instance
      json: JSON.stringify(serialized)
      object: serialized
    return extend context, extra

  getSetTemplateContext: (req, res, instances, extra) ->
    serialized = @preprocess_instances(instances)
    context = @getTemplateContext req, res,
      instances: instances
      json: JSON.stringify(serialized)
      objects: serialized
    return extend context, extra

  _renderTemplate: (res, name, context) ->
    t_name = @url_prefix
    if t_name[0] == '/'
      t_name = t_name[1..]
    if t_name[t_name.length-1] != '/'
      t_name = t_name + '/'
    t_name += name
    return res.render t_name, context

  renderTemplate: (res, name, data, context) ->
    data.view ||= name
    data.name = name
    view = data.view
    if @opts.render_cb?[view]?
      @opts.render_cb[view].call @, data, context, (ctxt) =>
        return @_renderTemplate res, name, ctxt
    else
      return @_renderTemplate res, name, context

  # -- default actions ----------------------------------------------

  # GET /NAME
  _action_index: (req, res, next) ->
    format = req.format or @_default_format
    @traceAction(req, 'index', "#{@url_prefix} format:#{format}")
    subquery = false
    if @opts.pivot?
      @trace("we have a pivot model field: '#{@opts.pivot.modelField}' req field: '#{@opts.pivot.requestField}'")
      @trace("req.#{@opts.pivot.requestField} = #{req[@opts.pivot.requestField]}")
      if @opts.pivot.requestField of req
        @trace("subquery on #{@opts.pivot.modelField} = #{req[@opts.pivot.requestField].id}")
        subquery = true
      else
        @trace("NO SUBQUERY")
    conditions = null
    if subquery
      conditions = {}
      conditions[@opts.pivot.modelField] = req[@opts.pivot.requestField].id
      @trace("conditions:", conditions)
    @get_conditions conditions, (err, instances) =>
      return next(err)  if err
      if format == 'html'
        ctxt = @getSetTemplateContext req, res, instances,
          format: format
          view: 'index'
        return @renderTemplate res, "index", {instances: instances}, ctxt
      return res.send(@preprocess_instances(instances))

  # GET /NAME/new
  _action_new: (req, res, next) ->
    format = req.format or @_default_format
    @traceAction(req, 'new', "#{@url_prefix}/new format:#{format}")

    instance = new @model
    if @opts.pivot?
      @trace("we have a pivot model field: '#{@opts.pivot.modelField}' req field: '#{@opts.pivot.requestField}'")
      @trace("req.#{@opts.pivot.requestField} = #{req[@opts.pivot.requestField]}")
      if @opts.pivot.requestField of req
        if (not @opts.pivot.requestField of instance) or (not instance[@opts.pivot.requestField])
          instance[@opts.pivot.requestField] = req[@opts.pivot.requestField].id
    if format == 'html'
      ctxt = @getInstanceTemplateContext req, res, instance,
        format: format
        view: 'new'
        mode: 'new'
      return @renderTemplate res, "edit", {view: 'new', instance: instance}, ctxt
    return res.send(@preprocess_instance(instance))

  # POST /NAME
  _action_create: (req, res, next) ->
    format = req.format or @_default_format
    @traceAction(req, 'create', "#{@url_prefix} format:#{format}")
    # #console.log(req.body)
    # console.log("REQUEST files:")
    # console.log(req.files)
    # instanceValues = @get_body_instance_values(req)
    # instance = new @model(instanceValues)
    instance = new @model()
    @update_instance_from_body_values(req, instance)
    if @opts.pivot?
      @trace("we have a pivot model field: '#{@opts.pivot.modelField}' req field: '#{@opts.pivot.requestField}'")
      @trace("req.#{@opts.pivot.requestField} = #{req[@opts.pivot.requestField]}")
      if @opts.pivot.requestField of req
        if (not @opts.pivot.requestField of instance) or (not instance[@opts.pivot.requestField])
          instance[@opts.pivot.requestField] = req[@opts.pivot.requestField].id
    instance.save (err) =>
      return next(err)  if err
      console.log("created #{@modelName} with id:#{instance.id}")
      if (req.body._format? and req.body._format == 'html') or (format == 'html')
        return res.redirect @url_prefix + "/#{instance.id}" + ".html"
      else
        return res.send(@preprocess_instance(instance))

  # GET /NAME/:NAME
  _action_show: (req, res, next) ->
    format = req.format or @_default_format
    @traceAction(req, 'show', "#{@url_prefix}:#{@resource.id} format:#{format}")
    @get @getId(req), (err, instance) =>
      return next(err)  if err
      if format == 'html'
        ctxt = @getInstanceTemplateContext req, res, instance,
          format: format
          view: 'show'
        return @renderTemplate res, "show", {instance: instance}, ctxt
      else
        return res.send(@preprocess_instance(instance))

  # GET /NAME/:NAME/edit
  _action_edit: (req, res, next) ->
    format = req.format or @_default_format
    @traceAction(req, 'edit', "#{@url_prefix}:#{@resource.id}/edit format:#{format}")
    @get @getId(req), (err, instance) =>
      return next(err)  if err
      if format == 'html'
        ctxt = @getInstanceTemplateContext req, res, instance,
          format: format
          view: 'edit'
          mode: 'edit'
        return @renderTemplate res, "edit", {instance: instance}, ctxt
      res.send(@preprocess_instance(instance))

  # PUT /NAME/:NAME
  _action_update: (req, res, next) ->
    id = @getId(req)
    @traceAction(req, 'update', "#{@url_prefix}:#{@resource.id}")
    @get id, (err, instance) =>
      return next(err)  if err
      console.log("REQUEST files:")
      console.log(req.files)
      # instanceValues = @get_body_instance_values(req)
      # extend(instance, instanceValues, true)
      @update_instance_from_body_values(req, instance)
      return instance.save (err) =>
        return next(err)  if err
        console.log("updated #{@modelName} with id:#{id}")
        if req.body._format? and req.body._format == 'html'
          return res.redirect @url_prefix + "/#{instance.id}" + ".html"
        else
          return res.send(@preprocess_instance(instance))

  # DELETE /NAME/:NAME
  _action_destroy: (req, res, next) ->
    id = @getId(req)
    @traceAction(req, 'destroy', "#{@url_prefix}:#{@resource.id}")
    return @get id, (err, instance) =>
      return next(err)  if err
      return instance.remove (err) =>
        return next(err)  if err
        console.log("removed #{@modelName} with id:#{id}")
        return res.send('')

  # -- express-resource support ---------------------------------------

  getExpressResourceActions: (actions) ->
    actions = actions or {}
    controller = @
    extend actions,
      index: ->                         # GET /NAME
        controller._action_index.apply(controller, arguments)
      new: ->                           # GET /NAME/new
        controller._action_new.apply(controller, arguments)
      create: ->                        # POST /NAME
        controller._action_create.apply(controller, arguments)
      show: ->                          # GET /NAME/:NAME
        controller._action_show.apply(controller, arguments)
      edit: ->                          # GET /NAME/:NAME/edit
        controller._action_edit.apply(controller, arguments)
      update: ->                        # PUT /NAME/:NAME
        controller._action_update.apply(controller, arguments)
      destroy: ->                       # DELETE /NAME/:NAME
        controller._action_destroy.apply(controller, arguments)
      load: ->                          # express-resource auto-load
        controller._auto_load.apply(controller, arguments)
    actions

  # -- serialization --------------------------------------------------

  addPreSerializeCallback: (cb) ->
    @_pre_serialize_cbs.push cb
    @

  setSerializeCallback: (cb) ->
    @_serialize_cb = cb
    @

  addPostSerializeCallback: (cb) ->
    @_post_serialize_cbs.push cb
    @

  # -- helper methods -------------------------------------------------

  # trace
  trace: (args...) ->
    if @_trace
      args = args or []
      args.unshift("[#{@modelName}] ")
      console?.log?(args...)
    @

  traceAction: (req, actionName, url) ->
    if @_trace
      msg = "[#{@modelName}/#{actionName}] #{req.method} #{url}"
      if req.params? and (@resource.id or req.params)
        id = req.params[@resource.id]
        if id
          msg = msg + " id:#{id}"
      console?.log?(msg)
    @

  # return instance id value from req.params
  getId: (req) ->
    req.params[@resource.id]

  _computeToObjectOpts: ->
    @_toObjectOpts = {}
    if @opts.toObject? and @opts.toObject
      @_toObjectOpts = @opts.toObject
    @_toObjectOpts = defaults(@_toObjectOpts, ModelController.TOOBJECT_DEFAULT_OPTS)
    @

  _default_serialize_cb: (instance, toObjectOpts) ->
    instance.toObject(toObjectOpts)

  preprocess_instance: (instance) ->
    req =
      instance: instance
      toObject: @_toObjectOpts
    res = {}

    invoke_callbacks(@, @_pre_serialize_cbs, req, res)

    req.object = @_serialize_cb(req.instance, req.toObject)

    invoke_callbacks(@, @_post_serialize_cbs, req, res)
    return req.object

  preprocess_instances: (instances) ->
    instances.map (instance) => @preprocess_instance(instance)

  # views 'get' and 'get_all' helpers
  get: (id, fn) ->
    return @model.findById id, (err, item) =>
      if (not err) and item
        fn(null, item)
      else
        errtext = if err? then "\nError: #{err}" else ""
        fn(new Error("#{@modelName} with id:#{id} does not exist.#{errtext}"))

  get_conditions: (conditions, fn) ->
    cb = (err, items) =>
      if (not err) and items?
        fn(null, items)
      else
        errtext = if err? then "\nError: #{err}" else ""
        fn(new Error("Can't retrieve list of #{@modelName}.#{errtext}"))
    if conditions?
      return @model.find conditions, cb
    return @model.find cb

  get_all: (fn) ->
    return @get_conditions null, fn

  get_body_instance_values: (req, defaults) ->
    iv = extend({}, defaults, false)
    @model.schema.eachPath (pathname) =>
      path = @model.schema.path(pathname)
      # TODO: handle compound pathnames (like 'aaa.bbb')
      if pathname of req.body
        iv[pathname] = req.body[pathname]
      else if req.files? and (pathname of req.files)
        rf = req.files[pathname]
        @trace("getting file name:#{rf.name} length:#{rf.length} filename:#{rf.filename} mime:#{rf.mime}")
        # TODO: save also length, mime type, ... (provide a mongoose plugin?)
        #iv[pathname] = req.files[pathname].path
        iv[pathname] = {file: req.files[pathname]}
    iv

  update_instance_from_body_values: (req, instance) ->
    @model.schema.eachPath (pathname) =>
      path = @model.schema.path(pathname)
      # TODO: handle compound pathnames (like 'aaa.bbb')
      if pathname of req.body
        instance.set(pathname, req.body[pathname])
      else if req.files? and (pathname of req.files)
        rf = req.files[pathname]
        @trace("getting file name:#{rf.name} length:#{rf.length} filename:#{rf.filename} mime:#{rf.mime}")
        # TODO: save also length, mime type, ... (provide a mongoose plugin?)
        #instance[pathname] = req.files[pathname].path
        instance.set("#{pathname}.file", req.files[pathname])
    instance

exports.ModelController = ModelController

old_app_resource = express.HTTPServer::resource
express.HTTPServer::resource = express.HTTPSServer::resource = (name, actions, opts) ->

  o_name = name
  o_actions = actions
  o_opts = opts

  if "object" is typeof name
    opts = actions
    actions = name
    name = null
  opts = opts or {}
  actions = actions or {}

  if not (('model' of opts) or ('model' of actions))
    return old_app_resource.call(@, o_name, o_actions, o_opts)

  if 'model' of opts
    model = opts.model
  else if 'model' of actions
    model = actions.model
    delete actions['model']
  controller = opts.controller or new ModelController(@, name, model, opts)

  controller._register_schema_action()
  res = old_app_resource.call(@, controller.name, controller.getExpressResourceActions(), opts)
  controller.resource = res
  res.controller = controller
  res
