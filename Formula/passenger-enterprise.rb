class PassengerEnterprise < Formula
  desc "Server for Ruby, Python, and Node.js apps via Apache/NGINX"
  homepage "https://www.phusionpassenger.com/"
  version "5.1.1"
  url "https://www.phusionpassenger.com/orders/download?dir=#{version}&file=passenger-enterprise-server-#{version}.tar.gz", :user => "download:#{PassengerEnterprise.token}"
  sha256 "50e20618d7b48b80225c5676121a6408dd10e32e9875a66297bd7ea7727b27fe"
  head "https://github.com/phusion/passenger.git"

  def self.token
    filepath = "~/.passenger-enterprise-download-token"
    begin
      token = File.read(File.expand_path(filepath))
    rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR
      token = ENV["PASSENGER_ENTERPRISE_TOKEN"]
    ensure
      while token.nil? || token.empty?
        puts "passenger enterprise token:"
        token = $stdin.gets
      end
      File.write(File.expand_path(filepath), token)
    end
    token.chomp
  end

  option "without-apache2-module", "Disable Apache2 module"

  depends_on :macos => :lion
  depends_on "pcre"
  depends_on "openssl"
  if MacOS.version >= :sierra && (MacOS::Xcode.version.to_f >= 8.0 || MacOS::CLT.version.to_f >= 8.0)
    depends_on "apr-util" => :build
    depends_on "apr" => :build
  end

  conflicts_with "passenger",
    :because => "passenger and passenger-enterprise install the same binaries."

  def install
    # https://github.com/Homebrew/homebrew-core/pull/1046
    ENV.delete("SDKROOT")

    if MacOS.version >= :sierra && (MacOS::Xcode.version.to_f >= 8.0 || MacOS::CLT.version.to_f >= 8.0)
      ENV["APU_CONFIG"] = Formula["apr-util"].opt_bin/"apu-1-config"
      ENV["APR_CONFIG"] = Formula["apr"].opt_bin/"apr-1-config"
    end

    inreplace "src/ruby_supportlib/phusion_passenger/platform_info/openssl.rb" do |s|
      s.gsub! "-I/usr/local/opt/openssl/include", "-I#{Formula["openssl"].opt_include}"
      s.gsub! "-L/usr/local/opt/openssl/lib", "-L#{Formula["openssl"].opt_lib}"
    end
    inreplace "src/ruby_supportlib/phusion_passenger/config/nginx_engine_compiler.rb",
      "http://nginx.org",
      "https://nginx.org"

    rake "apache2" if build.with? "apache2-module"
    rake "nginx"

    system("/usr/bin/ruby ./bin/passenger-config compile-nginx-engine")

    (libexec/"download_cache").mkpath

    # Fixes https://github.com/phusion/passenger/issues/1288
    rm_rf "buildout/libev"
    rm_rf "buildout/libuv"
    rm_rf "buildout/cache"

    necessary_files = Dir[".editorconfig", "configure", "Rakefile", "README.md", "CONTRIBUTORS",
      "CONTRIBUTING.md", "LICENSE", "CHANGELOG", "INSTALL.md",
      "passenger.gemspec", "build", "bin", "doc", "man", "dev", "src",
      "resources", "buildout"]
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

    nginx_addon_dir = `/usr/bin/ruby ./bin/passenger-config about nginx-addon-dir`.strip
    nginx_addon_dir.gsub!(/^#{Regexp.escape Dir.pwd}/, libexec)
    system "/usr/bin/ruby", "./dev/install_scripts_bootstrap_code.rb",
      "--nginx-module-config", libexec/"bin", "#{nginx_addon_dir}/config"

    mv libexec/"man", share
  end

  def caveats
    s = <<-EOS.undent
      To activate Phusion Passenger for Nginx, run:
        brew install nginx-passenger-enterprise

      EOS

    s += <<-EOS.undent if build.with? "apache2-module"
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
