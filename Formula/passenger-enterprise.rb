class PassengerEnterprise < Formula
  version "6.0.23"
  sha256 "554ca6e4b7c9d9a203ec8d2d4f68a8732ef787150b7f5e732ff9a0e051d2a689"

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
  license "https://www.phusionpassenger.com/customers/account/read_latest_eula"

  revision Formula["passenger"].revision if Formula["passenger"].version >= version
  option "without-apache2-module", "Disable Apache2 module"

  # to build nginx module
  depends_on "nginx" => :recommended
  depends_on "openssl@3"
  depends_on "pcre"
  depends_on "pcre2"

  uses_from_macos "xz" => :build
  uses_from_macos "curl"
  uses_from_macos "libxcrypt"
  uses_from_macos "ruby"
  uses_from_macos "zlib"

  conflicts_with "passenger",
    :because => "passenger and passenger-enterprise install the same binaries"

  def install
    if OS.mac? && MacOS.version >= :mojave && MacOS::CLT.installed?
      ENV["SDKROOT"] = MacOS::CLT.sdk_path(MacOS.version)
    else
      ENV.delete("SDKROOT")
    end

    inreplace "src/ruby_supportlib/phusion_passenger/platform_info/openssl.rb" do |s|
      s.gsub! "-I/usr/local/opt/openssl/include", "-I#{Formula["openssl@3"].opt_include}"
      s.gsub! "-L/usr/local/opt/openssl/lib", "-L#{Formula["openssl@3"].opt_lib}"
    end

    system "rake", "apache2" if build.with? "apache2-module"
    if build.with?("nginx")
    system "rake", "nginx"
    nginx_addon_dir = `./bin/passenger-config about nginx-addon-dir`.strip

    mkdir "nginx" do
      system "tar", "-xf", "#{Formula["nginx"].opt_pkgshare}/src/src.tar.xz", "--strip-components", "1"
      args = (Formula["nginx"].opt_pkgshare/"src/configure_args.txt").read.split("\n")
      args << "--add-dynamic-module=#{nginx_addon_dir}"

      system "./configure", *args
      system "make"
      (libexec/"modules").install "objs/ngx_http_passenger_module.so"
    end
    end

    (libexec/"download_cache").mkpath

    # Fixes https://github.com/phusion/passenger/issues/1288
    rm_r("buildout/libev")
    rm_r("buildout/libuv")
    rm_r("buildout/cache")

    necessary_files = %w[configure Rakefile README.md CONTRIBUTORS
                         CONTRIBUTING.md LICENSE CHANGELOG package.json
                         passenger-enterprise-server.gemspec build bin doc images dev src
                         resources buildout]

    cp_r necessary_files, libexec, preserve: true

    # Allow Homebrew to create symlinks for the Phusion Passenger commands.
    bin.install_symlink Dir["#{libexec}/bin/*"]

    # Ensure that the Phusion Passenger commands can always find their library
    # files.

    locations_ini = `./bin/passenger-config --make-locations-ini --for-native-packaging-method=homebrew`
    locations_ini.gsub!(/=#{Regexp.escape Dir.pwd}/, "=#{libexec}")
    (libexec/"src/ruby_supportlib/phusion_passenger/locations.ini").write(locations_ini)

    ruby_libdir = `./bin/passenger-config about ruby-libdir`.strip
    ruby_libdir.gsub!(/^#{Regexp.escape Dir.pwd}/, libexec)
    system "./dev/install_scripts_bootstrap_code.rb",
      "--ruby", ruby_libdir, *Dir[libexec/"bin/*"]

    # Recreate the tarball with a top-level directory, and use Gzip compression.
    mkdir "nginx-#{Formula["nginx"].version}" do
      system "tar", "-xf", "#{Formula["nginx"].opt_pkgshare}/src/src.tar.xz", "--strip-components", "1"
    end
    system "tar", "-czf", buildpath/"nginx.tar.gz", "nginx-#{Formula["nginx"].version}"

    system "./bin/passenger-config", "compile-nginx-engine"
    cp Dir["buildout/support-binaries/nginx*"], libexec/"buildout/support-binaries", preserve: true

    nginx_addon_dir.gsub!(/^#{Regexp.escape Dir.pwd}/, libexec)
    system "./dev/install_scripts_bootstrap_code.rb",
      "--nginx-module-config", libexec/"bin", "#{nginx_addon_dir}/config"

    man1.install Dir["man/*.1"]
    man8.install Dir["man/*.8"]

    # See https://github.com/Homebrew/homebrew-core/pull/84379#issuecomment-910179525
    deuniversalize_machos
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
        load_module #{opt_libexec}/modules/ngx_http_passenger_module.so;
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

    (testpath/"nginx.conf").write <<~EOS
      load_module #{opt_libexec}/modules/ngx_http_passenger_module.so;
      worker_processes 4;
      error_log #{testpath}/error.log;
      pid #{testpath}/nginx.pid;

      events {
        worker_connections 1024;
      }

      http {
        passenger_root #{opt_libexec}/src/ruby_supportlib/phusion_passenger/locations.ini;
        passenger_ruby /usr/bin/ruby;
        client_body_temp_path #{testpath}/client_body_temp;
        fastcgi_temp_path #{testpath}/fastcgi_temp;
        proxy_temp_path #{testpath}/proxy_temp;
        scgi_temp_path #{testpath}/scgi_temp;
        uwsgi_temp_path #{testpath}/uwsgi_temp;
        passenger_temp_path #{testpath}/passenger_temp;

        server {
          passenger_enabled on;
          listen 8080;
          root #{testpath};
          access_log #{testpath}/access.log;
          error_log #{testpath}/error.log;
        }
      }
    EOS
    system "#{Formula["nginx"].opt_bin}/nginx", "-t", "-c", testpath/"nginx.conf"
  end
end
