class UATokenizer
  VERSION = '1.0.0'

  TOKEN_MAPS = {
    'black_berry' => 'blackberry',
    'crios'       => 'chrome',
    'fb'          => 'facebook',
    'info_path'   => 'infopath',
    'lge'         => 'lg',
    'mot'         => 'motorolla',
    's40'         => 'series_40',
    's60'         => 'series_60',
    'sam'         => 'samsung',
    'symb'        => 'symbian'
  }

  COMMON_TOKENS = %w{
    mobile browser os cpu x like web phone like for
  }

  MAX_TOKEN_LENGTH = 25

  VERSION_MATCH = /^([a-z]?(\d+\.)+\d+[a-z]?|v\d+|\d)$/i

  TOKEN_MATCHERS = [
    # Non-lowercase first
    %r{([A-Z](?:[A-Z]+?|\d+))([a-z]{1,2}[A-Z0-9]|[A-Z][a-z]{2,}[^_\-]|[Ff]or)},
    # Lowercase or pre-underscored first
    /(_[A-Z][a-z]+|[a-z]{3,})\.?([\dA-Z])/,
    # Dots between words
    /([a-z]{3,})\.([a-z])/i,
    # Suffix identification
    /(\d)\.?([a-zA-Z]+\d|[a-zA-Z]{2,})/,
    # Nprefix identification
    /([A-Z]{3,})[^\w]?(\d[^_a-z])/
  ]

  URL_MATCHER = /^https?:\/\/|[^\s]+\.(com|net|us|net|org)$/
  SEC_MATCHER = /^([NUI])$/
  LAN_MATCHER = /^([a-z]{2})(?:[\-_]([a-z]{2,3}))?$/i
  SCR_MATCHER = /((\d{2,4})[xX*](\d{2,4}))/
  #SERIAL_MATCHER = /[A-Z0-9]{4,}/

  DATE_MATCHER          = %r{(^|\D)((?:19|20)\d{2})/?(0\d|1[0-2])/?([0-2]\d|3[01])(\D|$)}
  NOSPACE_MATCHER       = %r{\)/[a-zA-Z]|([^\s]+/){4,}}
  NOSPACE_DELIM_MATCHER = %r{([0-9A-Z])([A-Z][a-z])|\)/}
  UA_DELIM_MATCHER      = %r{(/(?:[^\s;])+|[\)\]]|^\w+)[\s;]+(\w)}
  UA_SPLIT_MATCHER      = /\s*[+;()\[\]]+\s*/

  ##
  # Parse the User-Agent String and return a UATokenizer instance.

  def self.parse ua
    data = {}
    meta = {}

    # Make YYYY/MM/DD into YYYY.MM.DD for easier parsing
    ua = ua.gsub(DATE_MATCHER, '\1\2.\3.\4\5')

    split(ua).each do |part|
      part.strip!

      case part
      when SCR_MATCHER
        meta[:screen] = [$2.to_i, $3.to_i]
        next

      when LAN_MATCHER
        if !meta[:localization] || meta[:localization] &&
        ($2 || $1.length < meta[:localization].length)
          meta[:localization] = ($2 ? "#{$1}-#{$2}" : $1).downcase
          next
        end

      when SEC_MATCHER
        meta[:security] = part
        next

      when URL_MATCHER
        meta[:url] = part
        next
      end

      parse_product(part) do |key, value|
        data[key] = get_version(data[key], value)
      end
    end

    new data, meta
  end


  ##
  # Compare string versions and return the largest one.

  def self.get_version v1, v2
    default = true
    return default unless v1 || v2

    return v1 || default unless v2 && v2 != default
    return v2 || default unless v1 && v1 != default

    if v1 =~ /^\d/ && v2 =~ /^\d/
      v1 < v2 ? v2 : v1
    elsif v1 =~ /^\d/
      v1
    elsif v2 =~ /^\d/
      v2
    else
      v1 < v2 ? v2 : v1
    end
  end


  ##
  # Splits the User-Agent String into meaningful pieces,
  # typically product-like sections.

  def self.split ua
    if ua =~ NOSPACE_MATCHER
      # Handle UAs without spaces. Split on 0|A HP|Compaq.
      ua.gsub!(NOSPACE_DELIM_MATCHER, '\1;\2')
    else
      # Add split markers to avoid needing to split on spaces.
      ua.gsub!(UA_DELIM_MATCHER, '\1;\2')
    end

    ua.sub(SCR_MATCHER, ';\1;').split(UA_SPLIT_MATCHER)
  end


  ##
  # Extracts a Product/Version pair from a given ProductToken.
  # Removes common tokens.
  #   UATokenizer.parse_product "Treo800w/v0100"
  #   #=> {"treo" => "v0100", "treo_800w" => "v0100", "800w" => "v0100"}
  #
  #   UATokenizer.parse_product "Vodafone/1.0/LG-KU990i/V10c"
  #   #=> {"vodafone" => "1.0", "lg" => "v10c", "lg_ku990i" => "v10c", "ku990i" => "v10c"}
  #
  #   UATokenizer.parse_product "Browser/Obigo-Q05A/3.6"
  #   #=> {"obigo" => "3.6", "obigo_q05a" => "3.6", "q05a" => "3.6"}

  def self.parse_product str
    parts = str.split("/")

    version     = nil
    tmp_version = nil

    out    = {}
    tokens = []

    parts.each_with_index do |part, i|
      last_of_many = parts.length > 1 && i+1 == parts.length

      if last_of_many
        version ||= part
        break if part =~ VERSION_MATCH
      end

      if version
        version = version.downcase

        tokens.each do |t|
          out[t] = version if !out[t] || out[t] == true
          yield t, version if block_given?
        end

        tokens  = []
        version = nil
      end

      last_token = nil

      tokenize(part) do |t|
        t = TOKEN_MAPS[t] || t

        next if t.length > MAX_TOKEN_LENGTH
        version = t and next if !version && t =~ VERSION_MATCH

        if last_token && last_token != version
          merge_token = [last_token, t].join("_")

          if TOKEN_MAPS[merge_token]
            t = TOKEN_MAPS[merge_token]
            tokens.pop
          else
            tokens << merge_token
          end
        end

        last_token = t

        tokens << t unless COMMON_TOKENS.include?(t) || t =~ /^\d+$/
      end
    end

    version &&= version.downcase
    version ||= true

    tokens.each do |t|
      out[t] = version if !out[t] || out[t] == true
      yield t, version if block_given?
    end

    out
  end


  ##
  # Normalizes and splits the String in potentially meaningful ways
  # and returns a hash map of :token => str.
  #   UATokenizer.tokenize("SAMSUNG-GT-S5620-ORANGE")
  #   #=> ["samsung", "gt", "s5620", "orange"]
  #
  #   UATokenizer.tokenize("SonyEricssonCK15i")
  #   #=> ["sony", "ericsson", "ck15i"]
  #
  #   UATokenizer.tokenize("Nokia2700c")
  #   #=> ["nokia", "2700c"]
  #
  #   UATokenizer.tokenize("iPhone")
  #   #=> ["iphone"]
  #
  #   UATokenizer.tokenize("HTC Desire HD A9191")
  #   #=> ["htc", "desire", "hd", "a9191"]
  #
  #   UATokenizer.tokenize("ZTE-Sydney-Orange")
  #   #=> ["zte", "sydney", "orange"]

  def self.tokenize str
    str = str.dup

    # Serialize versions
    2.times{ str.gsub!(/([^a-z]\d)[_,]\s?(\d)/i, '\1.\2') }

    TOKEN_MATCHERS.each{|regex| str.gsub!(regex, '\1_\2') }

    parts = str.downcase.split(/[_\s\-\/:;,]/)
    tokens = []

    parts.each do |t|
      next unless t && !t.empty?
      t.gsub!(/([a-z])\W([a-z])/, '\1_\2')
      yield(t) if block_given?
      tokens << t
    end

    tokens
  end


  attr_accessor :localization, :security, :screen, :url

  ##
  # Create a new UATokenizer instance from parsed User-Agent data.

  def initialize data, meta=nil
    meta        ||= {}
    @screen       = meta[:screen]
    @localization = meta[:localization]
    @security     = meta[:security]
    @url          = meta[:url]
    @tokens       = data
  end


  ##
  # Returns true-ish if the given key matches a User-Agent token.

  def [] key
    @tokens[key.to_s.downcase]
  end


  ##
  # Check if a given token is available with an optional version string.
  #   tokens.has?('mozilla', '>=5.0')
  #   tokens.has?('mozilla', '~>5.0')

  def has? name, version=nil
    token_version = self[name]

    return !!token_version unless version
    return false           unless String === token_version

    op = '=='
    version = version.strip

    if version =~ /^([><=]=?|~>)/
      op = $1
      version = version[op.length..-1].strip
    end

    op = '==' if op == '='

    if op == '~>'
      v_ary = version.split(".")
      return token_version >= version if v_ary.length < 2

      v_ary[-1] = '0'
      v_ary[-2] = v_ary[-2].next
      next_version = v_ary.join(".")
      token_version >= version && token_version < next_version

    else
      token_version.send(op, version)
    end
  end


  ##
  # Returns true if all given keys match a token.

  def all?(*keys)
    !keys.any?{|k| !@tokens[k] }
  end


  ##
  # Returns true if any given key matches a token.

  def any?(*keys)
    keys.any?{|k| @tokens[k] }
  end
end
