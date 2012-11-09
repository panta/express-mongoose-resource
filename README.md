# express-mongoose-resource

express-mongoose-resource provides resourceful routing for [mongoose][] models to [expressjs][].

The library uses and extends [express-resource][], remaining fully compatible with it.

Note: actually we now use [express-resource-middleware][], which adds route middleware support, remaining fully backward compatible with the original.

## Install

npm install express-mongoose-resource

## Usage

As with [express-resource][], simply `require('express-mongoose-resource')`, and resourceful routing will be available through the `app.resource()` method.
In addition to the usual [express-resource][] usage and semantics of `app.resource()`, it's now also possible to simply pass a [mongoose][] model to `app.resource()`, and
a new `Resource` object will be returned for the given model.
For instance, if we have a [mongoose][] `Forum` model, calling

```javascript
app.resource({model: Forum});
```

will estabilish the default [express-resource][] mapping (apart for the new `schema` action):

    GET     /forums/schema       ->  schema
    GET     /forums              ->  index
    GET     /forums/new          ->  new
    POST    /forums              ->  create
    GET     /forums/:forum       ->  show
    GET     /forums/:forum/edit  ->  edit
    PUT     /forums/:forum       ->  update
    DELETE  /forums/:forum       ->  destroy

where the `:forum` parameter is the [mongoose][] ObjectId for the model instance.
Note that when `model` is not specified, `app.resource()` falls back to the standard [express-resource][] implementation.

The format is determined using [express-resource][] content negotiation, and if not specified it's assumed to be `json`.
All actions are automatically available for the `json` format.

It's also possible to nest resources:

```javascript
var ForumSchema = new mongoose.Schema({
  ...
});
var Forum = db.model("Forum", ForumSchema);

var ThreadSchema = new mongoose.Schema({
  forum: { type: mongoose.ObjectId, ref: 'Forum' },
  ...
});
var Thread = db.model("Thread", ThreadSchema);

...

var r_forum = app.resource({model: Forum});
var r_thread = app.resource({model: Thread});

r_forum.add(r_thread, {pivotField: 'forum'});
```

which will a `Thread` resource nested under `Forum`:

    GET     /forums/:forum/threads/schema      ->  schema
    GET     /forums/:forum/threads             ->  index
    GET     /forums/:forum/threads/new         ->  new
    POST    /forums/:forum/threads             ->  create
    GET     /forums/:forum/threads/:forum      ->  show
    GET     /forums/:forum/threads/:forum/edit ->  edit
    PUT     /forums/:forum/threads/:forum      ->  update
    DELETE  /forums/:forum/threads/:forum      ->  destroy

### Content-Negotiation

The format is determined using [express-resource][] content negotiation, and if not specified it's assumed to be `json`.

### HTML resources

The `index`, `new`, `show` and `edit` actions also support the `html` format. In this case, an [expressjs][] template is rendered.
For the `Forum` example above, the templates would be:

- `forums/index` for the `index` action
- `forums/edit` for the `new` and `edit` actions
- `forums/show` for the `show` action

The context passed to the template contains the following keys:

- `view`, the view name (`index`, `new`, `show`, `edit`)
- `name`, the template name (`index`, `show`, `edit`) (by default, `edit` is used by `new` and `edit` views)
- `model`, the mongoose model
- `schema`, the mongoose schema
- `modelName`, the mongoose model name
- `resource_id`, the action name
- `instance`, the mongoose model instance (`new`, `show` and `edit` actions)
- `object`, a plain JavaScript object corresponding to the mongoose model instance, as returned by mongoose `toJSON()` (`new`, `show` and `edit` actions)
- `instances`, the mongoose result set (`index` action)
- `objects`, an array of plain JavaScript objects corresponding to the mongoose result set (`index` action)
- `json`, the JSON string representation of the model instance (`new`, `show` and `edit` actions) or of the result set  (`index` action)

When using nested resources, the context also contains the `pivot` field value, name and id. In the example above, the context variable `pivot` would contain `forum`, `pivot_id` would contain the forum id, and `forum` would contain the serialized forum model.

## Bugs and pull requests

Please use the github [repository][] to notify bugs and make pull requests.

## License

This software is © 2012 Marco Pantaleoni, released under the MIT licence. Use it, fork it.

See the LICENSE file for details.

[mongoose]: http://mongoosejs.com
[express-resource]: http://github.com/visionmedia/express-resource
[express-resource-middleware]: https://npmjs.org/package/express-resource-middleware
[CoffeeScript]: http://jashkenas.github.com/coffee-script/
[nodejs]: http://nodejs.org/
[expressjs]: http://expressjs.com
[Mocha]: http://visionmedia.github.com/mocha/
[Jade]: http://jade-lang.com
[repository]: http://github.com/panta/express-mongoose-resource
