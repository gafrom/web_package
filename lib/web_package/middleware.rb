module WebPackage
  SXG_EXT = '.sxg'.freeze
  SXG_FLAG = 'web_package.sxg'.freeze

  # A Rack-compatible middleware.
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      env[SXG_FLAG] = true if sxg_delete!(env['PATH_INFO'])

      response = @app.call(env)
      return response unless response[0] == 200 && env[SXG_FLAG]

      # the original body must be closed first
      response[2].close if response[2].respond_to? :close

      # substituting the original response with SXG
      SignedHttpExchange.new(url(env), response).to_rack_response
    end

    private

    def sxg_delete!(path)
      return unless path.is_a?(String) && (i = path.rindex(SXG_EXT))

      path[i...i + SXG_EXT.size] = ''
    end

    def url(env)
      URI("https://#{env['HTTP_HOST'] || env['SERVER_NAME']}").tap do |u|
        path  = env['PATH_INFO']
        port  = env['SERVER_PORT']
        query = env['QUERY_STRING']

        u.path  = path
        u.port  = port if !u.port && port != '80'
        u.query = query if query && !query.empty?
      end.to_s
    end
  end
end
