module WebPackage
  SXG_FLAG = 'web_package.sxg'.freeze

  # A Rack-compatible middleware.
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      Settings.filter[env] ? process(env) : @app.call(env)
    end

    private

    def process(env)
      env[SXG_FLAG] = true
      response = @app.call(env)
      return response if response[0] != 200

      # the original body must be closed first
      response[2].close if response[2].respond_to? :close

      # substituting the original response with SXG
      SignedHttpExchange.new(uri(env), response).to_rack_response
    end

    def uri(env)
      URI("https://#{env['HTTP_HOST'] || env['SERVER_NAME']}").tap do |u|
        path  = env['PATH_INFO']
        port  = env['SERVER_PORT']
        query = env['QUERY_STRING']

        u.path  = path
        u.port  = port if !u.port && port != '80'
        u.query = query if query && !query.empty?
      end
    end
  end
end
