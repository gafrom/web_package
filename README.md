# web_package
Ruby implementation of Signed HTTP Exchange format, allowing a browser to trust that a HTTP request-response pair was generated by the origin it claims.


## Ever thought of saving the Internet on a flash?

Easily-peasily.

Let's sign a pair of request/response and serve the bundle as `application/signed-exchange` - Chromium browsers understand what it means and unpack them smoothly.

For that we need a certificate with a special "CanSignHttpExchanges" extension, but for the purpose of this guide we will use just a self-signed one. Please refer [here](https://github.com/WICG/webpackage/tree/master/go/signedexchange#creating-our-first-signed-exchange) to create such.

Also we need an `https` cdn serving static certificate in `application/cert-chain+cbor` format. We can use `gen-certurl` tool from [here](https://github.com/WICG/webpackage/tree/master/go/signedexchange#creating-our-first-signed-exchange) to convert PEM certificate into this format, so we could than serve it from a cdn.

### Required environment variables
Having done the above-said we are now ready to assign required env vars:
```bash
export SXG_CERT_URL='https://my.cdn.com/cert.cbor' \
       SXG_CERT_PATH='/local/path/to/cert.pem' \
       SXG_PRIV_PATH='/local/path/to/priv.key'
```
Please note, that the variables are fetched during class initialization. And failing to provide valid paths will result in an exception.

### Use it as a middleware

`WebPackage::Middleware` can handle `.sxg`-format requests by wrapping the respective HTML contents into signed exchange response. For example the route `https://my.app.com/abc.sxg` will respond with signed contents for `https://my.app.com/abc`.

If you already have a Rack-based application (like Rails or Sinatra), than it is easy incorporate an SXG proxy into its middleware stack.

#### Rails
Add the gem to your `Gemfile`:
```ruby
gem 'web_package'
```
And then add the middleware:
```ruby
# config/application.rb
config.middleware.insert 0, 'WebPackage::Middleware'
```

That is it. Now all successful `.sxg` requests will be wrapped into signed exchanges.

#### Pure Rack app
Imagine we have a simple web app:
```ruby
# config.ru
run ->(env) { [200, {}, ['<h1>Hello world!</h1>']] }
```
Add the gem and the middleware:
```ruby
# Gemfile
gem 'web_package'

# config.ru
use WebPackage::Middleware
```

We are done. Start your app by running a command `rackup config.ru`. Now all supplimentary `.sxg` routes will be available just out of the box.<br>
As expected, visiting `http://localhost:9292/hello` will produce:
```html
<h1>Hello world!</h1>
```
What's more, visiting `http://localhost:9292/hello.sxg` will spit signed http exchange, containing original `<h1>Hello world!</h1>` HTML:
```text
sxg1-b3\x00\x00\x1Chttps://localhost:9292/hello\x00\x019\x00\x00?label;cert-sha256=*+DoXYlCX+bFRyW65R3bFA2ICIz8Tyu54MLFUFo5tziA=*;cert-url=\"https://my.cdn.com/cert.cbor\";date=1557657274;expires=1558262074;integrity=\"digest/mi-sha256-03\";sig=*MEUCIAKKz+KSuhlzywfU12h3SkEq5ZuYYMxDZIgEDGYMd9sAAiEAj66Il48eb0CXFAnuZhnS+j6dqZVLJ6IwUVGWShhQu9g=*;validity-url=\"https://localhost/hello\"?FdigestX9mi-sha256-03=4QeUScOpSoJl7KJ47F11rSDHUTHZhDVwLiSLOWMcvqg=G:statusC200Pcontent-encodingLmi-sha256-03Vx-content-type-optionsGnosniff\x00\x00\x00\x00\x00\x00@\x00<h1>Hello world!</h1>
```

### Use it as it is
```ruby
require 'web_package'

# this is the request/response pair
request_url = 'https://my.app.com/abc'
response    = [200, {}, ['<h1>Hello world!</h1>']]

exchange = WebPackage::SignedHttpExchange.new(request_url, response)

exchange.headers
# => {"Content-Type"=>"application/signed-exchange;v=b3", "Cache-Control"=>"no-transform", "X-Content-Type-Options"=>"nosniff"}

exchange.body
# => "sxg1-b3\x00\x00\x16https://my.app.com/abc\x00\x018\x00\x00\x8Clabel;cert-sha256=*+DoXYlCX+bFRyW65R3bFA2ICIz8Tyu54MLFUFo5tziA=*;cert-url=\"https://my.cdn.com/cert.cbor\";date=1557648268;expires=1558253068;integrity=\"digest/mi-sha256-03\";sig=*MEYCIQDSH2F6E/naM/ul1iIMZMBd9VHnrbsxp+dKhYcxy9u1ewIhAIRIuHcTVPLS73q2ETLLGwY5Y7nR52bDG251uBBHxsBZ*;validity-url=\"https://my.app.com/abc\"\xA4FdigestX9mi-sha256-03=4QeUScOpSoJl7KJ47F11rSDHUTHZhDVwLiSLOWMcvqg=G:statusC200Pcontent-encodingLmi-sha256-03Vx-content-type-optionsGnosniff\x00\x00\x00\x00\x00\x00@\x00<h1>Hello world!</h1>"
```

The body can be stored on disk and served from any other server. That is, visiting e.g. `https://other.cdn.com/foo/bar.sxg` will result in <b>"Hello&nbsp;world!"</b> HTML with `https://my.app.com/abc` in a browser's address bar - with no requests sent to `https://my.app.com/abc` (until the page expired).

Successive reloads will force browser to factually send requests to `https://my.app.com/abc`.

Note also, that SXG is only supported by the anchor tag (`<a>`) and `link rel=prefetch`, so actually typing `https://other.cdn.com/foo/bar.sxg` into browser's address bar and hitting enter will just download an SXG file.

This all could be helpful to preload content or serve it from closer location. For details please refer to hands-on description of [Signed Http Exchanges](https://developers.google.com/web/updates/2018/11/signed-exchanges).

### Self-signed certificates in Chrome
Chrome will not proceed with a self-signed certificate - at least as long as its cbor representation is generated with dummy data for OCSP. To accomodate this, please launch the browser with the following flags:
```bash
chrome --user-data-dir=/tmp/udd\
       --ignore-certificate-errors-spki-list=`openssl x509 -noout -pubkey -in cert.pem | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`
```

Note, that the browser might spit a warning `You are using unsupported command-line flag: --ignore-certificate-errors-spki-list` - just ignore it - the browser does support this flag (tested in versions 73 and 74).

## Contributing
  - Fork it
  - Create your feature branch (git checkout -b my-new-feature)
  - Commit your changes (git commit -am 'Add some feature')
  - Push to the branch (git push origin my-new-feature)
  - Create new Pull Request

## License

Web package is released under the [MIT License](../master/LICENSE).
