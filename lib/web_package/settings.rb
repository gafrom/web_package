module WebPackage
  OPTIONS = %i[headers expires_in sub_extension url_filter cert_url cert_path priv_path].freeze
  ENV_KEYS = Set.new(%w[SXG_CERT_URL SXG_CERT_PATH SXG_PRIV_PATH]).freeze
  DEFAULTS = {
    headers: { 'Content-Type'           => 'application/signed-exchange;v=b3',
               'Cache-Control'          => 'no-transform',
               'X-Content-Type-Options' => 'nosniff' },
    expires_in:    60 * 60 * 24 * 7, # 7.days
    sub_extension: nil, # proxy as default format (html)
    url_filter: ->(_uri) { true } # all paths are permitted
  }.freeze

  Settings = ConfigurationHash.new(OPTIONS) do |config, key|
    env_key = "SXG_#{key.upcase}"
    config[key] = ENV.fetch env_key if ENV_KEYS.include? env_key
  end.tap { |config| config.merge! DEFAULTS }
end
