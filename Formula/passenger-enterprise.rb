class PassengerEnterprise < Formula
  version "6.0.1"
  sha256 "5b2491d39fa2e7406e87d85afcbbb942481473e6f2b05a0a0b697ae8ec91e000"

  def self.token
    filepath = File.expand_path("~/.passenger-enterprise-download-token")
    if File.exist?(filepath)
      token = File.read(filepath)
    else
      token = ENV["HOMEBREW_PASSENGER_ENTERPRISE_TOKEN"]
    end
    while token.nil? || token.empty?
      puts "Passenger Enterprise download token:"
      token = $stdin.gets
      abort "Unable to query for the download token" if token.nil?
      ENV["HOMEBREW_PASSENGER_ENTERPRISE_TOKEN"] = token
    end
    token.chomp
  end

  desc "Server for Ruby, Python, and Node.js apps via Apache/NGINX"
  homepage "https://www.phusionpassenger.com/"
  url "https://www.phusionpassenger.com/orders/download?dir=#{version}&file=passenger-enterprise-server-#{version}.tar.gz", :user => "download:#{PassengerEnterprise.token}"

  option "without-apache2-module", "Disable Apache2 module"
  depends_on "nginx" => :recommended
  depends_on "openssl"
  depends_on "pcre"

  conflicts_with "passenger",
    :because => "passenger and passenger-enterprise install the same binaries."

  resource "nginx" do
    url Formula["nginx"].stable.url
    sha256 Formula["nginx"].stable.checksum.hexdigest
  end

  def install
    # https://github.com/Homebrew/homebrew-core/pull/1046
    ENV.delete("SDKROOT")

    inreplace "src/ruby_supportlib/phusion_passenger/platform_info/openssl.rb" do |s|
      s.gsub! "-I/usr/local/opt/openssl/include", "-I#{Formula["openssl"].opt_include}"
      s.gsub! "-L/usr/local/opt/openssl/lib", "-L#{Formula["openssl"].opt_lib}"
    end

    system "rake", "apache2" if build.with? "apache2-module"

    if build.with?("nginx")
      system "rake", "nginx"
      nginx_addon_dir = `/usr/bin/ruby ./bin/passenger-config about nginx-addon-dir`.strip
      resource("nginx").stage do
        _, stderr, = Open3.capture3("nginx", "-V")
        args = stderr.split("configure arguments:").last.split(" --").reject(&:empty?).map { |s| "--#{s.strip}" }
        args << "--add-dynamic-module=#{nginx_addon_dir}"

        system "./configure", *args

        system "make"

        (libexec/"buildout/nginx_dynamic/").mkpath
        cp "objs/ngx_http_passenger_module.so", libexec/"buildout/nginx_dynamic/"
      end
    end

    (libexec/"download_cache").mkpath

    # Fixes https://github.com/phusion/passenger/issues/1288
    rm_rf "buildout/libev"
    rm_rf "buildout/libuv"
    rm_rf "buildout/cache"

    necessary_files = %w[configure Rakefile README.md CONTRIBUTORS
                         CONTRIBUTING.md LICENSE CHANGELOG package.json
                         passenger-enterprise-server.gemspec build bin doc images dev src
                         resources buildout]

    cp_r necessary_files, libexec, :preserve => true

    # Allow Homebrew to create symlinks for the Phusion Passenger commands.
    bin.install_symlink Dir["#{libexec}/bin/*"]

    # Ensure that the Phusion Passenger commands can always find their library
    # files.

    locations_ini = `/usr/bin/ruby ./bin/passenger-config --make-locations-ini --for-native-packaging-method=homebrew`
    locations_ini.gsub!(/=#{Regexp.escape Dir.pwd}/, "=#{libexec}")
    (libexec/"src/ruby_supportlib/phusion_passenger/locations.ini").write(locations_ini)

    ruby_libdir = `/usr/bin/ruby ./bin/passenger-config about ruby-libdir`.strip
    ruby_libdir.gsub!(/^#{Regexp.escape Dir.pwd}/, libexec)
    system "/usr/bin/ruby", "./dev/install_scripts_bootstrap_code.rb",
      "--ruby", ruby_libdir, *Dir[libexec/"bin/*"]

    system("/usr/bin/ruby ./bin/passenger-config compile-nginx-engine")
    cp Dir["buildout/support-binaries/nginx*"], libexec/"buildout/support-binaries", :preserve => true

    nginx_addon_dir.gsub!(/^#{Regexp.escape Dir.pwd}/, libexec)
    system "/usr/bin/ruby", "./dev/install_scripts_bootstrap_code.rb",
      "--nginx-module-config", libexec/"bin", "#{nginx_addon_dir}/config"

    man1.install Dir["man/*.1"]
    man8.install Dir["man/*.8"]
  end

  def caveats
    s = <<~EOS
      To avoid entering your download-token every time you install or update Passenger Enterprise, create a file at
      ~/.passenger-enterprise-download-token containing your download token, homebrew prevents us from creating it for you automatically.
    EOS

    s += <<~EOS if build.with? "nginx"

      To activate Phusion Passenger for Nginx, run:
        brew install nginx
      And add the following to #{etc}/nginx/nginx.conf at the top scope (outside http{}):
        load_module #{opt_libexec}/buildout/nginx_dynamic/ngx_http_passenger_module.so;
      And add the following to #{etc}/nginx/nginx.conf in the http scope:
        passenger_root #{opt_libexec}/src/ruby_supportlib/phusion_passenger/locations.ini;
        passenger_ruby /usr/bin/ruby;
    EOS

    s += <<~EOS if build.with? "apache2-module"

      To activate Phusion Passenger for Apache, create /etc/apache2/other/passenger.conf:
        LoadModule passenger_module #{opt_libexec}/buildout/apache2/mod_passenger.so
        PassengerRoot #{opt_libexec}/src/ruby_supportlib/phusion_passenger/locations.ini
        PassengerDefaultRuby /usr/bin/ruby

    EOS
    s
  end

  test do
    ruby_libdir = `#{HOMEBREW_PREFIX}/bin/passenger-config --ruby-libdir`.strip
    assert_equal "#{libexec}/src/ruby_supportlib", ruby_libdir
  end
end
