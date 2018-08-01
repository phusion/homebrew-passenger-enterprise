class PassengerEnterprise < Formula
  desc "Server for Ruby, Python, and Node.js apps via Apache/NGINX"
  homepage "https://www.phusionpassenger.com/"
  version "5.3.4"

  def self.token
    filepath = File.expand_path("~/.passenger-enterprise-download-token")
    if File.exist?(filepath)
      token = File.read(filepath)
    else
      token = ENV["HOMEBREW_PASSENGER_ENTERPRISE_TOKEN"]
    end
    while token.nil? || token.empty?
      puts "passenger enterprise token:"
      token = $stdin.gets
      ENV["HOMEBREW_PASSENGER_ENTERPRISE_TOKEN"] = token
    end
    token.chomp
  end

  url "https://www.phusionpassenger.com/orders/download?dir=#{version}&file=passenger-enterprise-server-#{version}.tar.gz", :user => "download:#{PassengerEnterprise.token}"
  sha256 "30e49dff83e9ed9ba0c52e00dbb0afd2a71b5d2c61ce9fa54f991da66ded3363"

  option "without-apache2-module", "Disable Apache2 module"

  depends_on :macos => :lion
  depends_on "pcre"
  depends_on "openssl"

  conflicts_with "passenger",
    :because => "passenger and passenger-enterprise install the same binaries."

  def install
    # https://github.com/Homebrew/homebrew-core/pull/1046
    ENV.delete("SDKROOT")

    inreplace "src/ruby_supportlib/phusion_passenger/platform_info/openssl.rb" do |s|
      s.gsub! "-I/usr/local/opt/openssl/include", "-I#{Formula["openssl"].opt_include}"
      s.gsub! "-L/usr/local/opt/openssl/lib", "-L#{Formula["openssl"].opt_lib}"
    end

    system "rake", "apache2" if build.with? "apache2-module"
    system "rake", "nginx"

    (libexec/"download_cache").mkpath

    # Fixes https://github.com/phusion/passenger/issues/1288
    rm_rf "buildout/libev"
    rm_rf "buildout/libuv"
    rm_rf "buildout/cache"

    necessary_files = %w[.editorconfig configure Rakefile README.md CONTRIBUTORS
                         CONTRIBUTING.md LICENSE CHANGELOG INSTALL.md
                         passenger-enterprise-server.gemspec build bin doc man dev src resources
                         buildout]
    libexec.mkpath
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

    nginx_addon_dir = `/usr/bin/ruby ./bin/passenger-config about nginx-addon-dir`.strip
    nginx_addon_dir.gsub!(/^#{Regexp.escape Dir.pwd}/, libexec)
    system "/usr/bin/ruby", "./dev/install_scripts_bootstrap_code.rb",
      "--nginx-module-config", libexec/"bin", "#{nginx_addon_dir}/config"

    mv libexec/"man", share
  end

  def caveats
    s = <<~EOS
      To activate Phusion Passenger for Nginx, run:
        brew install nginx-passenger-enterprise

      To avoid entering your download-token every time you install or update Passenger Enterprise,
      create a file at ~/.passenger-enterprise-download-token containing your download token, homebrew prevents us from creating it for you automatically.
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
